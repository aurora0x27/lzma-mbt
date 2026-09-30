///|
fn se_write_vli(w : @bit.Writer, v0 : UInt64) -> Unit {
  let mut v = v0
  while v >= 0x80UL {
    let b = ((v & 0x7FUL) | 0x80UL).reinterpret_as_int64().to_int()
    w.write_u8(b.to_byte())
    v = v >> 7
  }
  w.write_u8(v.reinterpret_as_int64().to_int().to_byte())
}

///|
fn se_pad_to_4(w : @bit.Writer) -> Unit {
  while w.length() % 4 != 0 {
    w.write_u8(b'\x00')
  }
}

///|
/// Incremental single-Stream `.xz` encoder. It writes the Stream Header and a
/// Block Header without compressed/uncompressed sizes (their size is unknown
/// while streaming), forwards LZMA2 chunks as they complete, then writes the
/// Block Padding, Check, Index, and Footer at `finish`. Output bytes differ
/// from the one-shot encoder (which records both sizes) but are a valid `.xz`
/// Stream with the same plaintext.
pub struct StreamEncoder {
  lzma2 : @lzma2.StreamEncoder
  check_id : Int
  check_n : Int
  flags : Bytes
  hbytes : Bytes
  hbytes_len : Int
  mut payload_len : Int
  mut plain_len : UInt64
  mut crc32_acc : UInt
  mut crc64_acc : UInt64
  mut started : Bool
  mut ended : Bool
}

///|
pub fn StreamEncoder::new(
  lc : Int,
  lp : Int,
  pb : Int,
  dict_size : UInt,
  check_id : Int,
) -> StreamEncoder raise @coder.CoderError {
  let check_n = match check_id {
    0 => 0
    1 => 4
    4 => 8
    _ => raise @coder.Unsupported
  }
  let props = @lzma2.lzma2_dict_prop(dict_size)
  let content = @bit.Writer::new()
  content.write_u8(b'\x00')
  content.write_u8(b'\x21')
  content.write_u8(b'\x01')
  content.write_u8(props)
  while (1 + content.length()) % 4 != 0 {
    content.write_u8(b'\x00')
  }
  let hdr = @bit.Writer::new()
  hdr.write_u8(((1 + content.length()) / 4).to_byte())
  hdr.write_bytes(content.to_bytes()[:])
  let hbytes = hdr.to_bytes()
  {
    lzma2: @lzma2.StreamEncoder::new(lc, lp, pb, dict_size),
    check_id,
    check_n,
    flags: Bytes::from_array([b'\x00', check_id.to_byte()][:]),
    hbytes,
    hbytes_len: hbytes.length(),
    payload_len: 0,
    plain_len: 0UL,
    crc32_acc: 0U,
    crc64_acc: 0UL,
    started: false,
    ended: false,
  }
}

///|
pub fn StreamEncoder::reset(self : StreamEncoder) -> Unit {
  self.lzma2.reset()
  self.payload_len = 0
  self.plain_len = 0UL
  self.crc32_acc = 0U
  self.crc64_acc = 0UL
  self.started = false
  self.ended = false
}

///|
fn StreamEncoder::stream_header(
  self : StreamEncoder,
  out : @bit.Writer,
) -> Unit {
  out.write_bytes(b"\xFD\x37\x7A\x58\x5A\x00"[:])
  out.write_bytes(self.flags[:])
  out.write_u32_le(@checksum.crc32(self.flags[:]))
}

///|
fn StreamEncoder::block_header(self : StreamEncoder, out : @bit.Writer) -> Unit {
  out.write_bytes(self.hbytes[:])
  out.write_u32_le(@checksum.crc32(self.hbytes[:]))
}

///|
/// Feed input; `finish` terminates the LZMA2 payload and writes Index/Footer.
pub fn StreamEncoder::feed(
  self : StreamEncoder,
  input : BytesView,
  finish : Bool,
) -> Bytes raise @coder.CoderError {
  if self.ended && input.length() > 0 {
    raise @coder.Data
  }
  let out = @bit.Writer::new()
  if self.started == false {
    self.stream_header(out)
    self.block_header(out)
    self.started = true
  }
  if input.length() > 0 {
    self.plain_len = self.plain_len +
      input.length().reinterpret_as_uint().to_uint64()
    match self.check_id {
      1 => self.crc32_acc = @checksum.crc32(input, init=self.crc32_acc)
      4 => self.crc64_acc = @checksum.crc64(input, init=self.crc64_acc)
      _ => ()
    }
  }
  let body = self.lzma2.feed(input, finish)
  self.payload_len = self.payload_len + body.length()
  out.write_bytes(body[:])
  if finish && self.ended == false {
    let pad = (4 - self.payload_len % 4) % 4
    for _ in 0..<pad {
      out.write_u8(b'\x00')
    }
    match self.check_id {
      1 => out.write_u32_le(self.crc32_acc)
      4 => out.write_u64_le(self.crc64_acc)
      _ => ()
    }
    let unpadded = (self.hbytes_len + 4 + self.payload_len + self.check_n)
      .reinterpret_as_uint()
      .to_uint64()
    let index = @bit.Writer::new()
    index.write_u8(b'\x00')
    se_write_vli(index, 1UL)
    se_write_vli(index, unpadded)
    se_write_vli(index, self.plain_len)
    se_pad_to_4(index)
    let ibytes = index.to_bytes()
    out.write_bytes(ibytes[:])
    out.write_u32_le(@checksum.crc32(ibytes[:]))
    let backward = ((ibytes.length() + 4) / 4 - 1).reinterpret_as_uint()
    let foot = @bit.Writer::new()
    foot.write_u32_le(backward)
    foot.write_bytes(self.flags[:])
    let fb = foot.to_bytes()
    out.write_u32_le(@checksum.crc32(fb[:]))
    out.write_bytes(fb[:])
    out.write_bytes(b"\x59\x5A"[:])
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
