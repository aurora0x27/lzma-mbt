///|
fn match_len_at(
  input : BytesView,
  pos : Int,
  dist0 : Int,
  max_len : Int,
) -> Int {
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
) -> (Int, UInt)? {
  let avail = input.length() - pos
  if avail < 2 {
    return None
  }
  let max_len = min_int(273, avail)
  // Cap lookback at 4096: greedy search is O(window), not the full dict_size.
  let max_dist = min_int(pos, min_int(dict_size, 4096))
  let mut best_len = 1
  let mut best_dist = 0U
  let mut d = 1
  while d <= max_dist {
    let len = match_len_at(input, pos, d - 1, max_len)
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
pub fn encode_lzma(
  input : BytesView,
  lc : Int,
  lp : Int,
  pb : Int,
  dict_size : Int,
  end_marker? : Bool = true,
) -> Bytes {
  let enc = @rc.RangeEncoder::new()
  let probs = Probs::new(lc, lp)
  let mut state = 0
  let mut r0 = 0U
  let mut r1 = 0U
  let mut r2 = 0U
  let mut r3 = 0U
  let mut pos = 0
  let n = input.length()
  while pos < n {
    let ps = pos_state(pos, pb)
    let prev = if pos == 0 { b'\x00' } else { input[pos - 1] }
    let avail = n - pos
    let mut used_match = false
    if avail >= 2 && pos > 0 {
      let max_len = min_int(273, avail)
      let mut best_kind = 0
      let mut best_len = 1
      let mut best_dist = r0
      let l0 = match_len_at(input, pos, uint_as_int(r0), max_len)
      if l0 >= 1 {
        if l0 == 1 {
          best_kind = 1
          best_len = 1
        }
        if l0 >= 2 {
          best_kind = 2
          best_len = l0
          best_dist = r0
        }
      }
      let l1 = match_len_at(input, pos, uint_as_int(r1), max_len)
      if l1 > best_len {
        best_kind = 3
        best_len = l1
        best_dist = r1
      }
      let l2 = match_len_at(input, pos, uint_as_int(r2), max_len)
      if l2 > best_len {
        best_kind = 4
        best_len = l2
        best_dist = r2
      }
      let l3 = match_len_at(input, pos, uint_as_int(r3), max_len)
      if l3 > best_len {
        best_kind = 5
        best_len = l3
        best_dist = r3
      }
      match find_new_match(input, pos, dict_size) {
        Some((nl, nd)) =>
          if nl > best_len {
            best_kind = 6
            best_len = nl
            best_dist = nd
          }
        None => ()
      }
      if best_kind == 1 {
        enc.encode_bit(probs.is_match, state * 16 + ps, 1)
        enc.encode_bit(probs.is_rep, state, 1)
        enc.encode_bit(probs.is_rep_g0, state, 0)
        enc.encode_bit(probs.is_rep0_long, state * 16 + ps, 0)
        state = state_short_rep(state)
        pos = pos + 1
        used_match = true
      } else if best_kind >= 2 && best_len >= 2 {
        enc.encode_bit(probs.is_match, state * 16 + ps, 1)
        if best_kind == 6 {
          enc.encode_bit(probs.is_rep, state, 0)
          r3 = r2
          r2 = r1
          r1 = r0
          r0 = best_dist
          encode_length(
            enc,
            probs.len_choice,
            probs.len_low,
            probs.len_mid,
            probs.len_high,
            ps,
            best_len,
          )
          encode_distance(enc, probs, best_len, best_dist)
          state = state_match(state)
        } else {
          enc.encode_bit(probs.is_rep, state, 1)
          if best_kind == 2 {
            enc.encode_bit(probs.is_rep_g0, state, 0)
            enc.encode_bit(probs.is_rep0_long, state * 16 + ps, 1)
          } else {
            enc.encode_bit(probs.is_rep_g0, state, 1)
            if best_kind == 3 {
              enc.encode_bit(probs.is_rep_g1, state, 0)
            } else if best_kind == 4 {
              enc.encode_bit(probs.is_rep_g1, state, 1)
              enc.encode_bit(probs.is_rep_g2, state, 0)
              r2 = r1
            } else {
              enc.encode_bit(probs.is_rep_g1, state, 1)
              enc.encode_bit(probs.is_rep_g2, state, 1)
              r3 = r2
              r2 = r1
            }
            r1 = r0
            r0 = best_dist
          }
          encode_length(
            enc,
            probs.rep_len_choice,
            probs.rep_len_low,
            probs.rep_len_mid,
            probs.rep_len_high,
            ps,
            best_len,
          )
          state = state_rep(state)
        }
        pos = pos + best_len
        used_match = true
      }
    }
    if used_match == false {
      enc.encode_bit(probs.is_match, state * 16 + ps, 0)
      let match_b = if state < 7 || pos == 0 {
        b'\x00'
      } else {
        let back = uint_as_int(r0)
        if back < 0 || back >= pos {
          b'\x00'
        } else {
          input[pos - 1 - back]
        }
      }
      let base = lit_index(pos, prev, lc, lp) * 0x300
      encode_literal(enc, probs.lit, base, state, match_b, input[pos])
      state = state_lit(state)
      pos = pos + 1
    }
  }
  if end_marker {
    let ps = pos_state(pos, pb)
    enc.encode_bit(probs.is_match, state * 16 + ps, 1)
    enc.encode_bit(probs.is_rep, state, 0)
    encode_length(
      enc,
      probs.len_choice,
      probs.len_low,
      probs.len_mid,
      probs.len_high,
      ps,
      2,
    )
    encode_distance(enc, probs, 2, 0xFFFFFFFFU)
  }
  enc.flush()
}
