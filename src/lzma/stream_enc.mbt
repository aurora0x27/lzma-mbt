///|
/// Incremental LZMA_Alone encoder. It keeps a persistent range encoder and
/// encodes only a "safe" prefix (input minus a 273-byte lookahead window), so
/// the symbol choices and emitted bytes match the one-shot encoder; the final
/// bytes are produced at `finish`. The header uses the unknown-size marker
/// plus an end marker because the size is not known while streaming.
pub struct StreamEncoder {
  mut rc : @rc.RangeEncoder
  mut enc : @coder.LzmaEnc
  mut window : Array[Byte]
  mut start : Int
  lc : Int
  lp : Int
  pb : Int
  dict_size : UInt
  mut started : Bool
  mut ended : Bool
}

///|
pub fn StreamEncoder::new(
  lc : Int,
  lp : Int,
  pb : Int,
  dict_size : UInt,
) -> StreamEncoder {
  let dict_int = if dict_size.reinterpret_as_int() < 1 {
    1
  } else {
    dict_size.reinterpret_as_int()
  }
  {
    rc: @rc.RangeEncoder::new(),
    enc: @coder.LzmaEnc::new(lc, lp, pb, dict_int),
    window: [],
    start: 0,
    lc,
    lp,
    pb,
    dict_size,
    started: false,
    ended: false,
  }
}

///|
pub fn StreamEncoder::reset(self : StreamEncoder) -> Unit {
  self.rc = @rc.RangeEncoder::new()
  self.enc = @coder.LzmaEnc::new(
    self.lc,
    self.lp,
    self.pb,
    self.dict_size.reinterpret_as_int(),
  )
  self.window.clear()
  self.start = 0
  self.started = false
  self.ended = false
}

///|
fn StreamEncoder::header(self : StreamEncoder, out : @bit.Writer) -> Unit {
  let packed = (self.pb * 5 + self.lp) * 9 + self.lc
  out.write_u8(packed.to_byte())
  out.write_u32_le(self.dict_size)
  out.write_u64_le(0xFFFF_FFFF_FFFF_FFFFUL)
}

///|
fn StreamEncoder::append(self : StreamEncoder, input : BytesView) -> Unit {
  for b in input {
    self.window.push(b)
  }
}

///|
fn StreamEncoder::trim(self : StreamEncoder) -> Unit {
  // Keep at least 4096 bytes of history for back-references (the match finder
  // caps lookback at 4096) plus any not-yet-encoded bytes.
  if self.start > 4096 {
    let drop = self.start - 4096
    let next = Array(capacity=self.window.length() - drop)
    for b in self.window[drop:] {
      next.push(b)
    }
    self.window = next
    self.start = self.start - drop
  }
}

///|
/// Feed input. `finish` encodes the remaining pending bytes, writes the end
/// marker, and flushes. Returns the bytes produced by this call.
pub fn StreamEncoder::feed(
  self : StreamEncoder,
  input : BytesView,
  finish : Bool,
) -> Bytes raise @coder.CoderError {
  if self.ended && input.length() > 0 {
    raise @coder.Data
  }
  self.append(input)
  let out = @bit.Writer::new()
  if self.started == false {
    self.header(out)
    self.started = true
  }
  let avail = self.window.length() - self.start
  let mut encode_n = avail
  if finish == false {
    let safe = avail - 273
    encode_n = if safe > 0 { safe } else { 0 }
  }
  if encode_n > 0 {
    let src = Bytes::from_array(self.window[:])
    self.enc.encode_stream(self.rc, src[:], self.start, encode_n)
    self.start = self.start + encode_n
    self.trim()
    out.write_bytes(self.rc.drain()[:])
  }
  if finish && self.ended == false {
    self.enc.write_end_marker(self.rc)
    self.ended = true
    out.write_bytes(self.rc.flush()[:])
  }
  out.to_bytes()
}

///|
pub fn StreamEncoder::finish(
  self : StreamEncoder,
) -> Bytes raise @coder.CoderError {
  if self.ended == false {
    raise @coder.Eof
  }
  b""
}
