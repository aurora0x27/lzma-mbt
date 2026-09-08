///|
fn u8(v : Int) -> Byte {
  v.to_byte()
}

///|
fn dict_as_int(
  dict_size : UInt,
  memlimit : UInt64,
) -> Int raise @coder.CoderError {
  let d64 = dict_size.to_uint64()
  if d64 > memlimit {
    raise @coder.Limit
  }
  if d64 > 2147483647UL {
    raise @coder.Limit
  }
  let n = dict_size.reinterpret_as_int()
  if n < 1 {
    raise @coder.Limit
  }
  n
}

///|
pub fn lzma2_dict_prop(dict : UInt) -> Byte {
  if dict == 0xFFFFFFFFU {
    return u8(40)
  }
  let mut b = 0
  while b <= 40 {
    let decoded = (2U | (b.reinterpret_as_uint() & 1U)) << ((b >> 1) + 11)
    if decoded >= dict {
      return u8(b)
    }
    b = b + 1
  }
  u8(40)
}

///|
pub fn lzma2_dict_size(prop : Byte) -> UInt raise @coder.CoderError {
  let b = prop.to_int()
  if b > 40 {
    raise @coder.Data
  }
  if b == 40 {
    return 0xFFFFFFFFU
  }
  (2U | (b.reinterpret_as_uint() & 1U)) << ((b >> 1) + 11)
}

///|
fn write_uncompressed_chunk(w : @bit.Writer, chunk : BytesView) -> Unit {
  if chunk.length() < 1 {
    return
  }
  let m1 = chunk.length() - 1
  w.write_u8(b'\x01')
  w.write_u8(u8((m1 >> 8) & 0xFF))
  w.write_u8(u8(m1 & 0xFF))
  w.write_bytes(chunk)
}

///|
fn write_compressed_chunk(
  w : @bit.Writer,
  control_base : Int,
  chunk_n : Int,
  body : Bytes,
  lc : Int,
  lp : Int,
  pb : Int,
  with_props : Bool,
) -> Unit {
  let uncomp_m1 = chunk_n - 1
  let comp_m1 = body.length() - 1
  w.write_u8(u8(control_base | (uncomp_m1 >> 16)))
  w.write_u8(u8((uncomp_m1 >> 8) & 0xFF))
  w.write_u8(u8(uncomp_m1 & 0xFF))
  w.write_u8(u8((comp_m1 >> 8) & 0xFF))
  w.write_u8(u8(comp_m1 & 0xFF))
  if with_props {
    w.write_u8(u8((pb * 5 + lp) * 9 + lc))
  }
  w.write_bytes(body[:])
}

///|
pub fn encode_lzma2(
  input : BytesView,
  lc : Int,
  lp : Int,
  pb : Int,
  dict_size : UInt,
) -> Bytes {
  let w = @bit.Writer::new()
  if input.length() == 0 {
    w.write_u8(b'\x00')
    return w.to_bytes()
  }
  let mut enc = @coder.LzmaEnc::new(lc, lp, pb, dict_size.reinterpret_as_int())
  let mut off = 0
  let n = input.length()
  let mut need_dict_reset = true
  let mut need_props = true
  while off < n {
    let chunk_n = if n - off > 65536 { 65536 } else { n - off }
    if need_dict_reset {
      enc.reset_dict()
      enc.reset_state()
    } else if need_props {
      enc.reset_state()
    }
    let trial = enc.clone()
    let body = trial.encode_chunk(input, off, chunk_n)
    if body.length() < 1 || body.length() > 65536 {
      write_uncompressed_chunk(w, input[off:off + chunk_n])
      enc.reset_dict()
      enc.reset_state()
      enc.skip_uncompressed(chunk_n)
      need_dict_reset = false
      need_props = true
    } else {
      enc = trial
      if need_dict_reset {
        write_compressed_chunk(w, 0xE0, chunk_n, body, lc, lp, pb, true)
      } else if need_props {
        write_compressed_chunk(w, 0xC0, chunk_n, body, lc, lp, pb, true)
      } else {
        write_compressed_chunk(w, 0x80, chunk_n, body, lc, lp, pb, false)
      }
      need_dict_reset = false
      need_props = false
    }
    off = off + chunk_n
  }
  w.write_u8(b'\x00')
  w.to_bytes()
}

///|
fn unpack_lzma_props(props : Byte) -> (Int, Int, Int) raise @coder.CoderError {
  let pn = props.to_int()
  if pn >= 225 {
    raise @coder.Data
  }
  let lc = pn % 9
  let t = pn / 9
  let lp = t % 5
  let pb = t / 5
  if lc + lp > 4 {
    raise @coder.Data
  }
  (lc, lp, pb)
}

///|
fn add_produced(produced : UInt64, n : Int) -> UInt64 raise @coder.CoderError {
  let add = n.reinterpret_as_uint().to_uint64()
  if produced > 0xFFFF_FFFF_FFFF_FFFFUL - add {
    raise @coder.Data
  }
  produced + add
}

///|
/// Incremental raw-LZMA2 parser. The LZMA dictionary and probability state
/// survive calls; a compressed payload is committed only after its declared
/// byte window has arrived.
pub struct StreamDecoder {
  mut buf : Array[Byte]
  mut pos : Int
  dec : @coder.LzmaDec
  mut need_dict_reset : Bool
  mut need_props : Bool
  mut ended : Bool
  payload_prefix : Array[Byte]
  mut payload_range : @rc.RangeDecoder?
  mut payload_remaining : Int
  mut payload_goal : UInt64
  mut payload_output_done : Bool
}

///|
pub fn StreamDecoder::reset(self : StreamDecoder) -> Unit {
  self.buf.clear()
  self.pos = 0
  self.dec.reset_dict()
  self.dec.set_props(3, 0, 2)
  self.need_dict_reset = true
  self.need_props = true
  self.ended = false
  self.payload_prefix.clear()
  self.payload_range = None
  self.payload_remaining = 0
  self.payload_goal = 0UL
  self.payload_output_done = false
}

///|
pub fn StreamDecoder::new(
  memlimit : UInt64,
  dict_size? : UInt = 65536U,
) -> StreamDecoder raise @coder.CoderError {
  let dict_int = dict_as_int(dict_size, memlimit)
  {
    buf: [],
    pos: 0,
    dec: @coder.LzmaDec::new(3, 0, 2, dict_int),
    need_dict_reset: true,
    need_props: true,
    ended: false,
    payload_prefix: [],
    payload_range: None,
    payload_remaining: 0,
    payload_goal: 0UL,
    payload_output_done: false,
  }
}

///|
fn StreamDecoder::available(self : StreamDecoder) -> Int {
  self.buf.length() - self.pos
}

///|
fn StreamDecoder::compact(self : StreamDecoder) -> Unit {
  if self.pos > 0 && (self.pos >= 4096 || self.pos * 2 >= self.buf.length()) {
    let next = Array(capacity=self.buf.length() - self.pos)
    for b in self.buf[self.pos:] {
      next.push(b)
    }
    self.buf = next
    self.pos = 0
  }
}

///|
fn StreamDecoder::append(self : StreamDecoder, input : BytesView) -> Unit {
  for b in input {
    self.buf.push(b)
  }
}

///|
/// Feed arbitrary input. The boolean is true only after the LZMA2 end marker
/// has been consumed. Incomplete headers and payloads are reported as false.
pub fn StreamDecoder::feed(
  self : StreamDecoder,
  input : BytesView,
) -> (Bytes, Bool) raise @coder.CoderError {
  if self.ended && input.length() > 0 {
    raise @coder.Data
  }
  self.append(input)
  let out = @bit.Writer::new()
  while true {
    let avail = self.available()
    if avail < 1 {
      break
    }
    if self.payload_remaining > 0 ||
      self.payload_prefix.length() > 0 ||
      self.payload_range is Some(_) ||
      self.payload_output_done {
      if self.payload_remaining > 0 {
        let take = if avail < self.payload_remaining {
          avail
        } else {
          self.payload_remaining
        }
        let chunk = Array(capacity=take)
        for b in self.buf[self.pos:self.pos + take] {
          chunk.push(b)
        }
        self.pos = self.pos + take
        self.payload_remaining = self.payload_remaining - take
        match self.payload_range {
          None => {
            for b in chunk[:] {
              self.payload_prefix.push(b)
            }
            if self.payload_prefix.length() >= 5 {
              let first = Bytes::from_array(self.payload_prefix[:5])
              let range = @rc.RangeDecoder::new(first[:]) catch {
                @rc.Eof => raise @coder.Eof
                @rc.Data => raise @coder.Data
              }
              if self.payload_prefix.length() > 5 {
                let rest = Bytes::from_array(self.payload_prefix[5:])
                range.append(rest[:])
              }
              self.payload_range = Some(range)
              self.payload_prefix.clear()
            }
          }
          Some(range) => {
            let bytes = Bytes::from_array(chunk[:])
            range.append(bytes[:])
          }
        }
      }
      match self.payload_range {
        None => ()
        Some(range) =>
          if self.payload_output_done == false {
            let mut keep_going = true
            while keep_going {
              let (piece, done) = self.dec.decode_symbol(
                range,
                self.payload_goal,
                transactional=range.remaining() < 16,
              ) catch {
                @coder.Eof => {
                  keep_going = false
                  (b"", false)
                }
                err => raise err
              }
              if done {
                self.payload_output_done = true
                keep_going = false
              } else {
                out.write_bytes(piece[:])
              }
            }
          }
      }
      if self.payload_output_done && self.payload_remaining == 0 {
        self.payload_prefix.clear()
        self.payload_range = None
        self.payload_goal = 0UL
        self.payload_output_done = false
        continue
      }
      if self.payload_remaining == 0 && self.payload_output_done == false {
        raise @coder.Eof
      }
      break
    }
    let c = self.buf[self.pos].to_int()
    if c == 0 {
      self.pos = self.pos + 1
      self.ended = true
      if self.available() > 0 {
        raise @coder.Data
      }
      break
    }
    if c < 0x80 {
      if c != 1 && c != 2 {
        raise @coder.Data
      }
      if self.need_dict_reset && c != 1 {
        raise @coder.Data
      }
      if c == 1 {
        self.dec.reset_dict()
        self.need_props = true
      }
      if avail < 3 {
        break
      }
      let size = (
          (self.buf[self.pos + 1].to_int() << 8) |
          self.buf[self.pos + 2].to_int()
        ) +
        1
      if avail < 3 + size {
        break
      }
      let data = Array(capacity=size)
      for b in self.buf[self.pos + 3:self.pos + 3 + size] {
        data.push(b)
      }
      let bytes = Bytes::from_array(data[:])
      self.dec.put_uncompressed(bytes[:])
      out.write_bytes(bytes[:])
      self.pos = self.pos + 3 + size
      self.need_dict_reset = false
      self.compact()
      continue
    }
    if self.need_dict_reset && c < 0xE0 {
      raise @coder.Data
    }
    let header = if c >= 0xC0 { 6 } else { 5 }
    if avail < header {
      break
    }
    let uncomp = (
        ((c & 0x1F) << 16) |
        (self.buf[self.pos + 1].to_int() << 8) |
        self.buf[self.pos + 2].to_int()
      ) +
      1
    let comp = (
        (self.buf[self.pos + 3].to_int() << 8) | self.buf[self.pos + 4].to_int()
      ) +
      1
    if avail < header + comp {
      break
    }
    if c >= 0xE0 {
      self.dec.reset_dict()
      self.need_props = true
    } else if c >= 0xA0 {
      self.dec.reset_state()
    }
    if c >= 0xC0 {
      let props = unpack_lzma_props(self.buf[self.pos + 5])
      let (lc, lp, pb) = props
      self.dec.set_props(lc, lp, pb)
      self.need_props = false
    } else if self.need_props {
      raise @coder.Data
    }
    self.pos = self.pos + header
    self.payload_prefix.clear()
    self.payload_range = None
    self.payload_remaining = comp
    self.payload_goal = self.dec.position() +
      uncomp.reinterpret_as_uint().to_uint64()
    self.payload_output_done = false
    self.need_dict_reset = false
  }
  (out.to_bytes(), self.ended)
}

///|
pub fn StreamDecoder::finish(
  self : StreamDecoder,
) -> Bytes raise @coder.CoderError {
  if self.ended == false {
    raise @coder.Eof
  }
  b""
}

///|
pub fn decode_lzma2_consumed(
  input : BytesView,
  memlimit : UInt64,
  dict_size? : UInt = 65536U,
) -> (Bytes, Int) raise @coder.CoderError {
  let dict_int = dict_as_int(dict_size, memlimit)
  let r = @bit.Reader::new(input)
  let out = @bit.Writer::new()
  // Dummy lc/lp/pb until the first properties byte. A new stream must
  // start with dictionary reset (`0x01` or `0xE0..=0xFF`).
  let dec = @coder.LzmaDec::new(3, 0, 2, dict_int)
  let mut produced = 0UL
  let mut need_dict_reset = true
  let mut need_props = true
  while true {
    let control = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
    let c = control.to_int()
    if c == 0 {
      break
    }
    if c < 0x80 {
      if c != 1 && c != 2 {
        raise @coder.Data
      }
      if c == 1 {
        dec.reset_dict()
        need_props = true
        need_dict_reset = false
      } else if need_dict_reset {
        raise @coder.Data
      }
      let hi = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
      let lo = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
      let size = ((hi.to_int() << 8) | lo.to_int()) + 1
      let data = r.read_exact(size) catch { @bit.Eof => raise @coder.Eof }
      produced = add_produced(produced, size)
      dec.put_uncompressed(data)
      out.write_bytes(data)
    } else {
      if c >= 0xE0 {
        dec.reset_dict()
        need_dict_reset = false
        need_props = true
      } else if need_dict_reset {
        raise @coder.Data
      }
      let u1 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
      let u0 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
      let c1 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
      let c0 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
      let uncomp = (((c & 0x1F) << 16) | (u1.to_int() << 8) | u0.to_int()) + 1
      let comp = ((c1.to_int() << 8) | c0.to_int()) + 1
      if c >= 0xC0 {
        let props = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
        let (lc, lp, pb) = unpack_lzma_props(props)
        dec.set_props(lc, lp, pb)
        need_props = false
      } else if need_props {
        raise @coder.Data
      } else if c >= 0xA0 {
        dec.reset_state()
      }
      let payload = r.read_exact(comp) catch { @bit.Eof => raise @coder.Eof }
      produced = add_produced(produced, uncomp)
      let plain = dec.decode_payload(
        payload,
        uncomp.reinterpret_as_uint().to_uint64(),
      )
      if plain.length() != uncomp {
        raise @coder.Data
      }
      out.write_bytes(plain[:])
    }
  }
  (out.to_bytes(), r.position())
}

///|
pub fn decode_lzma2(
  input : BytesView,
  memlimit : UInt64,
  dict_size? : UInt = 65536U,
) -> Bytes raise @coder.CoderError {
  let (plain, used) = decode_lzma2_consumed(input, memlimit, dict_size~)
  if used != input.length() {
    raise @coder.Data
  }
  plain
}
