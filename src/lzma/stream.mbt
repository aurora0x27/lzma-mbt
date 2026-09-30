///|
fn unpack_alone_props(props : Byte) -> (Int, Int, Int) raise @coder.CoderError {
  let n = props.to_int()
  if n >= 225 {
    raise @coder.Data
  }
  let lc = n % 9
  let t = n / 9
  let lp = t % 5
  let pb = t / 5
  if lc + lp > 4 {
    raise @coder.Data
  }
  (lc, lp, pb)
}

///|
/// Incremental LZMA_Alone (`.lzma`) decoder. The 13-byte header is parsed once
/// 13 bytes have arrived; the payload then advances one LZMA symbol at a time
/// through the shared `LzmaDec` state machine, so arbitrary input chunking
/// yields the same plaintext as the one-shot decoder. A known header
/// uncompressed size stops at that many bytes; the unknown size
/// (`0xFFFF_FFFF_FFFF_FFFF`) stops at the end marker.
pub struct StreamDecoder {
  mut buf : Array[Byte]
  mut pos : Int
  mut header_done : Bool
  mut dec : @coder.LzmaDec
  mut known : Bool
  mut expected : UInt64
  memlimit : UInt64
  mut ended : Bool
  prefix : Array[Byte]
  mut range : @rc.RangeDecoder?
}

///|
fn StreamDecoder::available(self : StreamDecoder) -> Int {
  self.buf.length() - self.pos
}

///|
fn StreamDecoder::compact(self : StreamDecoder) -> Unit {
  if self.pos > 0 && (self.pos >= 13 || self.pos * 2 >= self.buf.length()) {
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
pub fn StreamDecoder::new(memlimit : UInt64) -> StreamDecoder {
  {
    buf: [],
    pos: 0,
    header_done: false,
    dec: @coder.LzmaDec::new(3, 0, 2, 4096),
    known: false,
    expected: 0UL,
    memlimit,
    ended: false,
    prefix: [],
    range: None,
  }
}

///|
pub fn StreamDecoder::reset(self : StreamDecoder) -> Unit {
  self.buf.clear()
  self.pos = 0
  self.header_done = false
  self.dec = @coder.LzmaDec::new(3, 0, 2, 4096)
  self.known = false
  self.expected = 0UL
  self.ended = false
  self.prefix.clear()
  self.range = None
}

///|
pub fn StreamDecoder::parse_header(
  self : StreamDecoder,
) -> Unit raise @coder.CoderError {
  let props = self.buf[self.pos]
  let (lc, lp, pb) = unpack_alone_props(props)
  let dict_size = self.buf[self.pos + 1].to_int().reinterpret_as_uint() |
    (self.buf[self.pos + 2].to_int().reinterpret_as_uint() << 8) |
    (self.buf[self.pos + 3].to_int().reinterpret_as_uint() << 16) |
    (self.buf[self.pos + 4].to_int().reinterpret_as_uint() << 24)
  let mut unpacked = 0UL
  let mut k = 0
  while k < 8 {
    unpacked = unpacked |
      (
        self.buf[self.pos + 5 + k].to_int().reinterpret_as_uint().to_uint64() <<
        (8 * k)
      )
    k = k + 1
  }
  // liblzma rounds a too-small header dict up to 4096 rather than rejecting.
  let dict_int = if dict_size < 4096U {
    4096
  } else {
    dict_size.reinterpret_as_int()
  }
  if dict_int < 1 {
    raise @coder.Limit
  }
  if dict_int.reinterpret_as_uint().to_uint64() > self.memlimit {
    raise @coder.Limit
  }
  self.dec = @coder.LzmaDec::new(lc, lp, pb, dict_int)
  self.known = unpacked != 0xFFFF_FFFF_FFFF_FFFFUL
  self.expected = unpacked
  self.pos = self.pos + 13
  self.header_done = true
  self.compact()
}

///|
/// Feed arbitrary input. The boolean is true only after the complete `.lzma`
/// stream (known size or end marker) has been decoded.
pub fn StreamDecoder::feed(
  self : StreamDecoder,
  input : BytesView,
) -> (Bytes, Bool) raise @coder.CoderError {
  if self.ended && input.length() > 0 {
    raise @coder.Data
  }
  self.append(input)
  let out = @bit.Writer::new()
  if self.header_done == false {
    if self.available() < 13 {
      return (out.to_bytes(), false)
    }
    self.parse_header()
  }
  while true {
    if self.range is None {
      while self.prefix.length() < 5 && self.available() > 0 {
        self.prefix.push(self.buf[self.pos])
        self.pos = self.pos + 1
      }
      if self.prefix.length() < 5 {
        break
      }
      let first = Bytes::from_array(self.prefix[:5])
      let range = @rc.RangeDecoder::new(first[:]) catch {
        @rc.Eof => raise @coder.Eof
        @rc.Data => raise @coder.Data
      }
      if self.prefix.length() > 5 {
        let rest = Bytes::from_array(self.prefix[5:])
        range.append(rest[:])
      }
      self.prefix.clear()
      self.range = Some(range)
      self.compact()
    }
    // Hand all remaining bytes to the range decoder; it keeps its own read
    // position, so re-entering after more input arrives is safe.
    match self.range {
      None => break
      Some(range) => {
        if self.available() > 0 {
          let bytes = Bytes::from_array(self.buf[self.pos:])
          range.append(bytes[:])
          self.pos = self.buf.length()
          self.compact()
        }
        let mut keep_going = true
        while keep_going {
          // liblzma expects the end-of-stream marker even when the header
          // declares a known size; the declared size is then validated.
          let (piece, done) = self.dec.decode_symbol(
            range,
            0xFFFF_FFFF_FFFF_FFFFUL,
            allow_end_marker=true,
            transactional=range.remaining() < 16,
          ) catch {
            @coder.Eof => {
              keep_going = false
              (b"", false)
            }
            err => raise err
          }
          if done {
            if self.known && self.dec.position() != self.expected {
              raise @coder.Data
            }
            self.ended = true
            self.range = None
            keep_going = false
          } else {
            out.write_bytes(piece[:])
            if self.known && self.dec.position() > self.expected {
              raise @coder.Data
            }
          }
        }
      }
    }
    if self.ended {
      break
    }
    break
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
