///|
/// Incremental raw LZMA2 encoder. Chunks are emitted as soon as 65536 pending
/// bytes are available (the same chunk boundaries as the one-shot encoder), so
/// the produced bytes are identical to `encode_lzma2` for the same input.
pub struct StreamEncoder {
  mut enc : @coder.LzmaEnc
  mut window : Array[Byte]
  mut start : Int
  lc : Int
  lp : Int
  pb : Int
  dict_size : UInt
  mut need_dict_reset : Bool
  mut need_props : Bool
  mut ended : Bool
}

///|
pub fn StreamEncoder::new(
  lc : Int,
  lp : Int,
  pb : Int,
  dict_size : UInt,
) -> StreamEncoder {
  {
    enc: @coder.LzmaEnc::new(lc, lp, pb, dict_size.reinterpret_as_int()),
    window: [],
    start: 0,
    lc,
    lp,
    pb,
    dict_size,
    need_dict_reset: true,
    need_props: true,
    ended: false,
  }
}

///|
pub fn StreamEncoder::reset(self : StreamEncoder) -> Unit {
  self.enc = @coder.LzmaEnc::new(
    self.lc,
    self.lp,
    self.pb,
    self.dict_size.reinterpret_as_int(),
  )
  self.window.clear()
  self.start = 0
  self.need_dict_reset = true
  self.need_props = true
  self.ended = false
}

///|
fn StreamEncoder::append(self : StreamEncoder, input : BytesView) -> Unit {
  for b in input {
    self.window.push(b)
  }
}

///|
fn StreamEncoder::trim(self : StreamEncoder) -> Unit {
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
fn StreamEncoder::emit_chunk(
  self : StreamEncoder,
  out : @bit.Writer,
  n : Int,
) -> Unit {
  let src = Bytes::from_array(self.window[:])
  if self.need_dict_reset {
    self.enc.reset_dict()
    self.enc.reset_state()
  } else if self.need_props {
    self.enc.reset_state()
  }
  let trial = self.enc.clone()
  let body = trial.encode_chunk(src[:], self.start, n)
  if body.length() < 1 || body.length() > 65536 {
    write_uncompressed_chunk(out, src[self.start:self.start + n])
    self.enc.reset_dict()
    self.enc.reset_state()
    self.enc.skip_uncompressed(n)
    self.need_dict_reset = false
    self.need_props = true
  } else {
    self.enc = trial
    if self.need_dict_reset {
      write_compressed_chunk(
        out,
        0xE0,
        n,
        body,
        self.lc,
        self.lp,
        self.pb,
        true,
      )
    } else if self.need_props {
      write_compressed_chunk(
        out,
        0xC0,
        n,
        body,
        self.lc,
        self.lp,
        self.pb,
        true,
      )
    } else {
      write_compressed_chunk(
        out,
        0x80,
        n,
        body,
        self.lc,
        self.lp,
        self.pb,
        false,
      )
    }
    self.need_dict_reset = false
    self.need_props = false
  }
  self.start = self.start + n
  self.trim()
}

///|
/// Feed input; `finish` encodes the remaining pending bytes and writes the
/// LZMA2 end marker. Returns the bytes produced by this call.
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
  while self.window.length() - self.start >= 65536 {
    self.emit_chunk(out, 65536)
  }
  if finish && self.ended == false {
    let avail = self.window.length() - self.start
    if avail > 0 {
      self.emit_chunk(out, avail)
    }
    out.write_u8(b'\x00')
    self.ended = true
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
