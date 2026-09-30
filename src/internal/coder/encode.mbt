///|
fn match_len_at(
  input : BytesView,
  pos : Int,
  dist0 : Int,
  max_len : Int,
  window : Int,
) -> Int {
  if dist0 < 0 || dist0 >= window {
    return 0
  }
  let start = pos - dist0 - 1
  if start < 0 {
    return 0
  }
  let mut l = 0
  while l < max_len && input[start + l] == input[pos + l] {
    l = l + 1
  }
  l
}

///|
/// LZMA encoder session. Probability tables and reps persist across LZMA2
/// chunks; each chunk still gets a fresh range encoder.
struct LzmaEnc {
  mut probs : Probs
  mut state : Int
  mut r0 : UInt
  mut r1 : UInt
  mut r2 : UInt
  mut r3 : UInt
  mut pos : Int
  lc : Int
  lp : Int
  pb : Int
  dict_size : Int
}

///|
pub fn LzmaEnc::new(lc : Int, lp : Int, pb : Int, dict_size : Int) -> LzmaEnc {
  {
    probs: Probs::new(lc, lp),
    state: 0,
    r0: 0U,
    r1: 0U,
    r2: 0U,
    r3: 0U,
    pos: 0,
    lc,
    lp,
    pb,
    dict_size,
  }
}

///|
pub fn LzmaEnc::clone(self : LzmaEnc) -> LzmaEnc {
  {
    probs: copy_probs(self.probs),
    state: self.state,
    r0: self.r0,
    r1: self.r1,
    r2: self.r2,
    r3: self.r3,
    pos: self.pos,
    lc: self.lc,
    lp: self.lp,
    pb: self.pb,
    dict_size: self.dict_size,
  }
}

///|
pub fn LzmaEnc::reset_state(self : LzmaEnc) -> Unit {
  self.probs = Probs::new(self.lc, self.lp)
  self.state = 0
  self.r0 = 0U
  self.r1 = 0U
  self.r2 = 0U
  self.r3 = 0U
}

///|
pub fn LzmaEnc::reset_dict(self : LzmaEnc) -> Unit {
  self.pos = 0
}

///|
pub fn LzmaEnc::skip_uncompressed(self : LzmaEnc, n : Int) -> Unit {
  self.pos = self.pos + n
}

///|
/// Candidate: kind 0=none, 1=short-rep, 2=rep0, 3=rep1, 4=rep2, 5=rep3, 6=new.
priv struct EncChoice {
  kind : Int
  len : Int
  dist : UInt
  price : Int
}

///|
fn no_choice() -> EncChoice {
  { kind: 0, len: 1, dist: 0U, price: 0x7FFFFFFF, }
}

///|
fn LzmaEnc::price_short_rep(self : LzmaEnc, ps : Int) -> Int {
  bit_price(self.probs.is_match[self.state * 16 + ps], 1) +
  bit_price(self.probs.is_rep[self.state], 1) +
  bit_price(self.probs.is_rep_g0[self.state], 0) +
  bit_price(self.probs.is_rep0_long[self.state * 16 + ps], 0)
}

///|
fn LzmaEnc::price_rep0(self : LzmaEnc, ps : Int, len : Int) -> Int {
  bit_price(self.probs.is_match[self.state * 16 + ps], 1) +
  bit_price(self.probs.is_rep[self.state], 1) +
  bit_price(self.probs.is_rep_g0[self.state], 0) +
  bit_price(self.probs.is_rep0_long[self.state * 16 + ps], 1) +
  length_price(
    self.probs.rep_len_choice,
    self.probs.rep_len_low,
    self.probs.rep_len_mid,
    self.probs.rep_len_high,
    ps,
    len,
  )
}

///|
fn LzmaEnc::price_rep1(self : LzmaEnc, ps : Int, len : Int) -> Int {
  bit_price(self.probs.is_match[self.state * 16 + ps], 1) +
  bit_price(self.probs.is_rep[self.state], 1) +
  bit_price(self.probs.is_rep_g0[self.state], 1) +
  bit_price(self.probs.is_rep_g1[self.state], 0) +
  length_price(
    self.probs.rep_len_choice,
    self.probs.rep_len_low,
    self.probs.rep_len_mid,
    self.probs.rep_len_high,
    ps,
    len,
  )
}

///|
fn LzmaEnc::price_rep2(self : LzmaEnc, ps : Int, len : Int) -> Int {
  bit_price(self.probs.is_match[self.state * 16 + ps], 1) +
  bit_price(self.probs.is_rep[self.state], 1) +
  bit_price(self.probs.is_rep_g0[self.state], 1) +
  bit_price(self.probs.is_rep_g1[self.state], 1) +
  bit_price(self.probs.is_rep_g2[self.state], 0) +
  length_price(
    self.probs.rep_len_choice,
    self.probs.rep_len_low,
    self.probs.rep_len_mid,
    self.probs.rep_len_high,
    ps,
    len,
  )
}

///|
fn LzmaEnc::price_rep3(self : LzmaEnc, ps : Int, len : Int) -> Int {
  bit_price(self.probs.is_match[self.state * 16 + ps], 1) +
  bit_price(self.probs.is_rep[self.state], 1) +
  bit_price(self.probs.is_rep_g0[self.state], 1) +
  bit_price(self.probs.is_rep_g1[self.state], 1) +
  bit_price(self.probs.is_rep_g2[self.state], 1) +
  length_price(
    self.probs.rep_len_choice,
    self.probs.rep_len_low,
    self.probs.rep_len_mid,
    self.probs.rep_len_high,
    ps,
    len,
  )
}

///|
fn LzmaEnc::price_new_match(
  self : LzmaEnc,
  ps : Int,
  len : Int,
  dist : UInt,
) -> Int {
  bit_price(self.probs.is_match[self.state * 16 + ps], 1) +
  bit_price(self.probs.is_rep[self.state], 0) +
  length_price(
    self.probs.len_choice,
    self.probs.len_low,
    self.probs.len_mid,
    self.probs.len_high,
    ps,
    len,
  ) +
  distance_price(self.probs, len, dist)
}

///|
fn consider(
  cur : EncChoice,
  kind : Int,
  len : Int,
  dist : UInt,
  price : Int,
) -> EncChoice {
  // Prefer longer matches (greedy length); use price only to break ties,
  // then lower kind (reps before new match).
  if cur.kind == 0 {
    return { kind, len, dist, price, }
  }
  if len > cur.len ||
    (
      len == cur.len &&
      (price < cur.price || (price == cur.price && kind < cur.kind))
    ) {
    { kind, len, dist, price, }
  } else {
    cur
  }
}

///|
fn LzmaEnc::find_best_at(
  self : LzmaEnc,
  input : BytesView,
  abs : Int,
  avail : Int,
  mf : MatchFinder,
  /// Filled dictionary size at this absolute position.
  window : Int,
) -> EncChoice {
  let ps = pos_state(window, self.pb)
  let mut best = no_choice()
  if avail < 2 || window <= 0 {
    return best
  }
  let max_len = min_int(273, avail)
  let max_dist = min_int(window, self.dict_size)

  let l0 = match_len_at(input, abs, uint_as_int(self.r0), max_len, window)
  if l0 == 1 {
    best = consider(best, 1, 1, self.r0, self.price_short_rep(ps))
  }
  if l0 >= 2 {
    best = consider(best, 2, l0, self.r0, self.price_rep0(ps, l0))
  }
  let l1 = match_len_at(input, abs, uint_as_int(self.r1), max_len, window)
  if l1 >= 2 {
    best = consider(best, 3, l1, self.r1, self.price_rep1(ps, l1))
  }
  let l2 = match_len_at(input, abs, uint_as_int(self.r2), max_len, window)
  if l2 >= 2 {
    best = consider(best, 4, l2, self.r2, self.price_rep2(ps, l2))
  }
  let l3 = match_len_at(input, abs, uint_as_int(self.r3), max_len, window)
  if l3 >= 2 {
    best = consider(best, 5, l3, self.r3, self.price_rep3(ps, l3))
  }
  match mf.find(input, abs, window, avail, max_dist) {
    Some((nl, nd)) =>
      if nl >= 2 {
        best = consider(best, 6, nl, nd, self.price_new_match(ps, nl, nd))
      }
    None => ()
  }
  best
}

///|
fn LzmaEnc::emit_choice(
  self : LzmaEnc,
  enc : @rc.RangeEncoder,
  choice : EncChoice,
  input : BytesView,
  abs : Int,
) -> Int {
  let ps = pos_state(self.pos, self.pb)
  if choice.kind == 1 {
    enc.encode_bit(self.probs.is_match, self.state * 16 + ps, 1)
    enc.encode_bit(self.probs.is_rep, self.state, 1)
    enc.encode_bit(self.probs.is_rep_g0, self.state, 0)
    enc.encode_bit(self.probs.is_rep0_long, self.state * 16 + ps, 0)
    self.state = state_short_rep(self.state)
    return 1
  }
  if choice.kind >= 2 && choice.len >= 2 {
    enc.encode_bit(self.probs.is_match, self.state * 16 + ps, 1)
    if choice.kind == 6 {
      enc.encode_bit(self.probs.is_rep, self.state, 0)
      self.r3 = self.r2
      self.r2 = self.r1
      self.r1 = self.r0
      self.r0 = choice.dist
      encode_length(
        enc,
        self.probs.len_choice,
        self.probs.len_low,
        self.probs.len_mid,
        self.probs.len_high,
        ps,
        choice.len,
      )
      encode_distance(enc, self.probs, choice.len, choice.dist)
      self.state = state_match(self.state)
    } else {
      enc.encode_bit(self.probs.is_rep, self.state, 1)
      if choice.kind == 2 {
        enc.encode_bit(self.probs.is_rep_g0, self.state, 0)
        enc.encode_bit(self.probs.is_rep0_long, self.state * 16 + ps, 1)
      } else {
        enc.encode_bit(self.probs.is_rep_g0, self.state, 1)
        if choice.kind == 3 {
          enc.encode_bit(self.probs.is_rep_g1, self.state, 0)
        } else if choice.kind == 4 {
          enc.encode_bit(self.probs.is_rep_g1, self.state, 1)
          enc.encode_bit(self.probs.is_rep_g2, self.state, 0)
          self.r2 = self.r1
        } else {
          enc.encode_bit(self.probs.is_rep_g1, self.state, 1)
          enc.encode_bit(self.probs.is_rep_g2, self.state, 1)
          self.r3 = self.r2
          self.r2 = self.r1
        }
        self.r1 = self.r0
        self.r0 = choice.dist
      }
      encode_length(
        enc,
        self.probs.rep_len_choice,
        self.probs.rep_len_low,
        self.probs.rep_len_mid,
        self.probs.rep_len_high,
        ps,
        choice.len,
      )
      self.state = state_rep(self.state)
    }
    return choice.len
  }
  // Literal
  enc.encode_bit(self.probs.is_match, self.state * 16 + ps, 0)
  let prev = if self.pos == 0 { b'\x00' } else { input[abs - 1] }
  let match_b = if self.state < 7 || self.pos == 0 {
    b'\x00'
  } else {
    let back = uint_as_int(self.r0)
    if back < 0 || back >= self.pos {
      b'\x00'
    } else {
      input[abs - 1 - back]
    }
  }
  let base = lit_index(self.pos, prev, self.lc, self.lp) * 0x300
  encode_literal(enc, self.probs.lit, base, self.state, match_b, input[abs])
  self.state = state_lit(self.state)
  1
}

///|
/// Encode `n` input bytes into an existing range encoder without flushing it.
/// Used by both the one-shot path and the streaming encoder.
pub fn LzmaEnc::encode_stream(
  self : LzmaEnc,
  enc : @rc.RangeEncoder,
  input : BytesView,
  from : Int,
  n : Int,
) -> Unit {
  let to = from + n
  let seed_back = min_int(self.dict_size, MatchSeedCap)
  let seed_from = if from > seed_back { from - seed_back } else { 0 }
  let mf = MatchFinder::new(seed_from)
  mf.seed(input, seed_from, from)
  let nice = nice_len_for_dict(self.dict_size)
  let mut abs = from
  while abs < to {
    let avail = to - abs
    let cur = self.find_best_at(input, abs, avail, mf, self.pos)
    let mut take = no_choice()
    if cur.kind != 0 && cur.len >= 2 {
      if cur.len >= nice {
        take = cur
      } else if abs + 1 < to {
        // Lazy: peek at next position after a hypothetical literal.
        let prev = if self.pos == 0 { b'\x00' } else { input[abs - 1] }
        let match_b = if self.state < 7 || self.pos == 0 {
          b'\x00'
        } else {
          let back = uint_as_int(self.r0)
          if back < 0 || back >= self.pos {
            b'\x00'
          } else {
            input[abs - 1 - back]
          }
        }
        let lit_base = lit_index(self.pos, prev, self.lc, self.lp) * 0x300
        let ps = pos_state(self.pos, self.pb)
        let lit_p = literal_price(
          self.probs,
          self.state,
          ps,
          lit_base,
          match_b,
          input[abs],
        )
        let next = self.find_best_at(
          input,
          abs + 1,
          avail - 1,
          mf,
          self.pos + 1,
        )
        if next.kind != 0 &&
          next.len >= 2 &&
          (
            next.len > cur.len ||
            (next.len == cur.len && lit_p + next.price < cur.price)
          ) {
          take = no_choice() // emit literal this step
        } else {
          take = cur
        }
      } else {
        take = cur
      }
    } else if cur.kind == 1 {
      // Short rep is always cheap enough to take immediately.
      take = cur
    }

    let step = self.emit_choice(enc, take, input, abs)
    let mut i = 0
    while i < step {
      mf.insert(input, abs + i)
      i = i + 1
    }
    abs = abs + step
    self.pos = self.pos + step
  }
}

///|
/// Write the LZMA end-of-stream marker into an existing range encoder.
pub fn LzmaEnc::write_end_marker(
  self : LzmaEnc,
  enc : @rc.RangeEncoder,
) -> Unit {
  let ps = pos_state(self.pos, self.pb)
  enc.encode_bit(self.probs.is_match, self.state * 16 + ps, 1)
  enc.encode_bit(self.probs.is_rep, self.state, 0)
  encode_length(
    enc,
    self.probs.len_choice,
    self.probs.len_low,
    self.probs.len_mid,
    self.probs.len_high,
    ps,
    2,
  )
  encode_distance(enc, self.probs, 2, 0xFFFFFFFFU)
}

///|
pub fn LzmaEnc::encode_chunk(
  self : LzmaEnc,
  input : BytesView,
  from : Int,
  n : Int,
  end_marker? : Bool = false,
) -> Bytes {
  let enc = @rc.RangeEncoder::new()
  self.encode_stream(enc, input, from, n)
  if end_marker {
    self.write_end_marker(enc)
  }
  enc.flush()
}

///|
pub fn encode_lzma(
  input : BytesView,
  lc : Int,
  lp : Int,
  pb : Int,
  dict_size : Int,
  end_marker? : Bool = true,
) -> Bytes {
  let enc = LzmaEnc::new(lc, lp, pb, dict_size)
  enc.encode_chunk(input, 0, input.length(), end_marker~)
}
