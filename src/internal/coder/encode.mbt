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
fn find_new_match(
  input : BytesView,
  pos : Int,
  dict_size : Int,
  window : Int,
  avail : Int,
) -> (Int, UInt)? {
  if avail < 2 {
    return None
  }
  let max_len = min_int(273, avail)
  // Cap lookback at 4096: greedy search is O(window), not the full dict_size.
  let max_dist = min_int(window, min_int(dict_size, 4096))
  let mut best_len = 1
  let mut best_dist = 0U
  let mut d = 1
  while d <= max_dist {
    let len = match_len_at(input, pos, d - 1, max_len, window)
    if len > best_len {
      best_len = len
      best_dist = int_as_uint(d - 1)
      if len == max_len {
        break
      }
    }
    d = d + 1
  }
  if best_len >= 2 {
    Some((best_len, best_dist))
  } else {
    None
  }
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
pub fn LzmaEnc::encode_chunk(
  self : LzmaEnc,
  input : BytesView,
  from : Int,
  n : Int,
  end_marker? : Bool = false,
) -> Bytes {
  let enc = @rc.RangeEncoder::new()
  let to = from + n
  let mut abs = from
  while abs < to {
    let ps = pos_state(self.pos, self.pb)
    let prev = if self.pos == 0 { b'\x00' } else { input[abs - 1] }
    let avail = to - abs
    let mut used_match = false
    if avail >= 2 && self.pos > 0 {
      let max_len = min_int(273, avail)
      let mut best_kind = 0
      let mut best_len = 1
      let mut best_dist = self.r0
      let l0 = match_len_at(input, abs, uint_as_int(self.r0), max_len, self.pos)
      if l0 >= 1 {
        if l0 == 1 {
          best_kind = 1
          best_len = 1
        }
        if l0 >= 2 {
          best_kind = 2
          best_len = l0
          best_dist = self.r0
        }
      }
      let l1 = match_len_at(input, abs, uint_as_int(self.r1), max_len, self.pos)
      if l1 > best_len {
        best_kind = 3
        best_len = l1
        best_dist = self.r1
      }
      let l2 = match_len_at(input, abs, uint_as_int(self.r2), max_len, self.pos)
      if l2 > best_len {
        best_kind = 4
        best_len = l2
        best_dist = self.r2
      }
      let l3 = match_len_at(input, abs, uint_as_int(self.r3), max_len, self.pos)
      if l3 > best_len {
        best_kind = 5
        best_len = l3
        best_dist = self.r3
      }
      match find_new_match(input, abs, self.dict_size, self.pos, avail) {
        Some((nl, nd)) =>
          if nl > best_len {
            best_kind = 6
            best_len = nl
            best_dist = nd
          }
        None => ()
      }
      if best_kind == 1 {
        enc.encode_bit(self.probs.is_match, self.state * 16 + ps, 1)
        enc.encode_bit(self.probs.is_rep, self.state, 1)
        enc.encode_bit(self.probs.is_rep_g0, self.state, 0)
        enc.encode_bit(self.probs.is_rep0_long, self.state * 16 + ps, 0)
        self.state = state_short_rep(self.state)
        abs = abs + 1
        self.pos = self.pos + 1
        used_match = true
      } else if best_kind >= 2 && best_len >= 2 {
        enc.encode_bit(self.probs.is_match, self.state * 16 + ps, 1)
        if best_kind == 6 {
          enc.encode_bit(self.probs.is_rep, self.state, 0)
          self.r3 = self.r2
          self.r2 = self.r1
          self.r1 = self.r0
          self.r0 = best_dist
          encode_length(
            enc,
            self.probs.len_choice,
            self.probs.len_low,
            self.probs.len_mid,
            self.probs.len_high,
            ps,
            best_len,
          )
          encode_distance(enc, self.probs, best_len, best_dist)
          self.state = state_match(self.state)
        } else {
          enc.encode_bit(self.probs.is_rep, self.state, 1)
          if best_kind == 2 {
            enc.encode_bit(self.probs.is_rep_g0, self.state, 0)
            enc.encode_bit(self.probs.is_rep0_long, self.state * 16 + ps, 1)
          } else {
            enc.encode_bit(self.probs.is_rep_g0, self.state, 1)
            if best_kind == 3 {
              enc.encode_bit(self.probs.is_rep_g1, self.state, 0)
            } else if best_kind == 4 {
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
            self.r0 = best_dist
          }
          encode_length(
            enc,
            self.probs.rep_len_choice,
            self.probs.rep_len_low,
            self.probs.rep_len_mid,
            self.probs.rep_len_high,
            ps,
            best_len,
          )
          self.state = state_rep(self.state)
        }
        abs = abs + best_len
        self.pos = self.pos + best_len
        used_match = true
      }
    }
    if used_match == false {
      enc.encode_bit(self.probs.is_match, self.state * 16 + ps, 0)
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
      abs = abs + 1
      self.pos = self.pos + 1
    }
  }
  if end_marker {
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
