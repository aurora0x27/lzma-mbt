///|
pub fn decode_lzma(
  src : BytesView,
  lc : Int,
  lp : Int,
  pb : Int,
  dict_size : Int,
  unpacked : UInt64,
) -> Bytes raise CoderError {
  if dict_size < 1 {
    raise Limit
  }
  let dec = @rc.RangeDecoder::new(src) catch {
    @rc.Eof => raise Eof
    @rc.Data => raise Data
  }
  let probs = Probs::new(lc, lp)
  let dict = @lz.Dict::new(dict_size)
  let mut state = 0
  let mut r0 = 0U
  let mut r1 = 0U
  let mut r2 = 0U
  let mut r3 = 0U
  let mut pos = 0
  let out = @bit.Writer::new()
  while true {
    if unpacked != 0xFFFF_FFFF_FFFF_FFFFUL &&
      pos.reinterpret_as_uint().to_uint64() >= unpacked {
      break
    }
    let ps = pos_state(pos, pb)
    if dec_bit(dec, probs.is_match, state * 16 + ps) == 0 {
      let prev = if pos == 0 {
        b'\x00'
      } else {
        dict.get(0) catch {
          @lz.InvalidDistance => raise Data
        }
      }
      let base = lit_index(pos, prev, lc, lp) * 0x300
      let match_b = if state < 7 {
        b'\x00'
      } else {
        dict.get(uint_as_int(r0)) catch {
          @lz.InvalidDistance => raise Data
        }
      }
      let b = decode_literal(dec, probs.lit, base, state, match_b)
      dict.put(b)
      out.write_u8(b)
      state = state_lit(state)
      pos = pos + 1
    } else {
      let mut dist = 0U
      let mut len = 0
      if dec_bit(dec, probs.is_rep, state) == 1 {
        if dec_bit(dec, probs.is_rep_g0, state) == 0 {
          if dec_bit(dec, probs.is_rep0_long, state * 16 + ps) == 0 {
            if pos == 0 {
              raise Data
            }
            let b = dict.output_byte(uint_as_int(r0)) catch {
              @lz.InvalidDistance => raise Data
            }
            out.write_u8(b)
            state = state_short_rep(state)
            pos = pos + 1
            continue
          }
        } else {
          if dec_bit(dec, probs.is_rep_g1, state) == 0 {
            dist = r1
          } else if dec_bit(dec, probs.is_rep_g2, state) == 0 {
            dist = r2
            r2 = r1
          } else {
            dist = r3
            r3 = r2
            r2 = r1
          }
          r1 = r0
          r0 = dist
        }
        len = decode_length(
          dec,
          probs.rep_len_choice,
          probs.rep_len_low,
          probs.rep_len_mid,
          probs.rep_len_high,
          ps,
        )
        state = state_rep(state)
      } else {
        r3 = r2
        r2 = r1
        r1 = r0
        len = decode_length(
          dec,
          probs.len_choice,
          probs.len_low,
          probs.len_mid,
          probs.len_high,
          ps,
        )
        dist = decode_distance(dec, probs, len)
        if dist == 0xFFFFFFFFU {
          break
        }
        r0 = dist
        state = state_match(state)
      }
      if dist > 0x7FFFFFFFU {
        raise Data
      }
      if unpacked != 0xFFFF_FFFF_FFFF_FFFFUL {
        let next = pos.reinterpret_as_uint().to_uint64() +
          len.reinterpret_as_uint().to_uint64()
        if next > unpacked {
          raise Data
        }
      }
      for _ in 0..<len {
        let b = dict.output_byte(uint_as_int(r0)) catch {
          @lz.InvalidDistance => raise Data
        }
        out.write_u8(b)
        pos = pos + 1
      }
    }
  }
  if unpacked != 0xFFFF_FFFF_FFFF_FFFFUL &&
    pos.reinterpret_as_uint().to_uint64() != unpacked {
    raise Data
  }
  out.to_bytes()
}
