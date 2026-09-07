///|
/// LZMA decoder session. The dictionary, probabilities, reps, and `pos`
/// survive across LZMA2 chunks; each compressed chunk still has its own
/// range decoder.
struct LzmaDec {
  mut probs : Probs
  dict : @lz.Dict
  mut state : Int
  mut r0 : UInt
  mut r1 : UInt
  mut r2 : UInt
  mut r3 : UInt
  mut pos : Int
  mut lc : Int
  mut lp : Int
  mut pb : Int
}

///|
pub fn LzmaDec::new(lc : Int, lp : Int, pb : Int, dict_size : Int) -> LzmaDec {
  {
    probs: Probs::new(lc, lp),
    dict: @lz.Dict::new(dict_size),
    state: 0,
    r0: 0U,
    r1: 0U,
    r2: 0U,
    r3: 0U,
    pos: 0,
    lc,
    lp,
    pb,
  }
}

///|
pub fn LzmaDec::reset_state(self : LzmaDec) -> Unit {
  self.probs = Probs::new(self.lc, self.lp)
  self.state = 0
  self.r0 = 0U
  self.r1 = 0U
  self.r2 = 0U
  self.r3 = 0U
}

///|
pub fn LzmaDec::reset_dict(self : LzmaDec) -> Unit {
  self.dict.reset()
  self.pos = 0
}

///|
pub fn LzmaDec::set_props(self : LzmaDec, lc : Int, lp : Int, pb : Int) -> Unit {
  self.lc = lc
  self.lp = lp
  self.pb = pb
  self.reset_state()
}

///|
pub fn LzmaDec::put_uncompressed(self : LzmaDec, data : BytesView) -> Unit {
  for b in data {
    self.dict.put(b)
    self.pos = self.pos + 1
  }
}

///|
pub fn LzmaDec::decode_payload(
  self : LzmaDec,
  src : BytesView,
  unpacked : UInt64,
  allow_end_marker? : Bool = false,
) -> Bytes raise CoderError {
  let dec = @rc.RangeDecoder::new(src) catch {
    @rc.Eof => raise Eof
    @rc.Data => raise Data
  }
  let start = self.pos.reinterpret_as_uint().to_uint64()
  let known = unpacked != 0xFFFF_FFFF_FFFF_FFFFUL
  let goal = if known { start + unpacked } else { 0xFFFF_FFFF_FFFF_FFFFUL }
  let out = @bit.Writer::new()
  while true {
    let cur = self.pos.reinterpret_as_uint().to_uint64()
    if known && cur >= goal {
      break
    }
    let ps = pos_state(self.pos, self.pb)
    if dec_bit(dec, self.probs.is_match, self.state * 16 + ps) == 0 {
      let prev = if self.pos == 0 {
        b'\x00'
      } else {
        self.dict.get(0) catch {
          @lz.InvalidDistance => raise Data
        }
      }
      let base = lit_index(self.pos, prev, self.lc, self.lp) * 0x300
      let match_b = if self.state < 7 {
        b'\x00'
      } else {
        self.dict.get(uint_as_int(self.r0)) catch {
          @lz.InvalidDistance => raise Data
        }
      }
      let b = decode_literal(dec, self.probs.lit, base, self.state, match_b)
      self.dict.put(b)
      out.write_u8(b)
      self.state = state_lit(self.state)
      self.pos = self.pos + 1
    } else {
      let mut dist = 0U
      let mut len = 0
      if dec_bit(dec, self.probs.is_rep, self.state) == 1 {
        if dec_bit(dec, self.probs.is_rep_g0, self.state) == 0 {
          if dec_bit(dec, self.probs.is_rep0_long, self.state * 16 + ps) == 0 {
            if self.pos == 0 {
              raise Data
            }
            let b = self.dict.output_byte(uint_as_int(self.r0)) catch {
              @lz.InvalidDistance => raise Data
            }
            out.write_u8(b)
            self.state = state_short_rep(self.state)
            self.pos = self.pos + 1
            continue
          }
        } else {
          if dec_bit(dec, self.probs.is_rep_g1, self.state) == 0 {
            dist = self.r1
          } else if dec_bit(dec, self.probs.is_rep_g2, self.state) == 0 {
            dist = self.r2
            self.r2 = self.r1
          } else {
            dist = self.r3
            self.r3 = self.r2
            self.r2 = self.r1
          }
          self.r1 = self.r0
          self.r0 = dist
        }
        len = decode_length(
          dec,
          self.probs.rep_len_choice,
          self.probs.rep_len_low,
          self.probs.rep_len_mid,
          self.probs.rep_len_high,
          ps,
        )
        self.state = state_rep(self.state)
      } else {
        self.r3 = self.r2
        self.r2 = self.r1
        self.r1 = self.r0
        len = decode_length(
          dec,
          self.probs.len_choice,
          self.probs.len_low,
          self.probs.len_mid,
          self.probs.len_high,
          ps,
        )
        dist = decode_distance(dec, self.probs, len)
        if dist == 0xFFFFFFFFU {
          if allow_end_marker {
            break
          }
          raise Data
        }
        self.r0 = dist
        self.state = state_match(self.state)
      }
      if dist > 0x7FFFFFFFU {
        raise Data
      }
      if known {
        let next = self.pos.reinterpret_as_uint().to_uint64() +
          len.reinterpret_as_uint().to_uint64()
        if next > goal {
          raise Data
        }
      }
      for _ in 0..<len {
        let b = self.dict.output_byte(uint_as_int(self.r0)) catch {
          @lz.InvalidDistance => raise Data
        }
        out.write_u8(b)
        self.pos = self.pos + 1
      }
    }
  }
  if known && self.pos.reinterpret_as_uint().to_uint64() != goal {
    raise Data
  }
  out.to_bytes()
}

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
  let dec = LzmaDec::new(lc, lp, pb, dict_size)
  dec.decode_payload(src, unpacked, allow_end_marker=true)
}
