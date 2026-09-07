///|
pub suberror BitError {
  Eof
} derive(Debug, Eq)

///|
pub struct Reader {
  data : BytesView
  mut pos : Int
}

///|
pub fn Reader::new(data : BytesView) -> Reader {
  { data, pos: 0, }
}

///|
pub fn Reader::remaining(self : Reader) -> Int {
  self.data.length() - self.pos
}

///|
pub fn Reader::rest(self : Reader) -> BytesView {
  self.data[self.pos:]
}

///|
pub fn Reader::position(self : Reader) -> Int {
  self.pos
}

///|
pub fn Reader::read_u8(self : Reader) -> Byte raise BitError {
  if self.pos >= self.data.length() {
    raise Eof
  }
  let b = self.data[self.pos]
  self.pos = self.pos + 1
  b
}

///|
pub fn Reader::read_exact(self : Reader, n : Int) -> BytesView raise BitError {
  if n < 0 || self.remaining() < n {
    raise Eof
  }
  let start = self.pos
  self.pos = self.pos + n
  self.data[start:self.pos]
}

///|
pub fn Reader::read_u32_le(self : Reader) -> UInt raise BitError {
  let b0 = byte_to_uint(self.read_u8())
  let b1 = byte_to_uint(self.read_u8())
  let b2 = byte_to_uint(self.read_u8())
  let b3 = byte_to_uint(self.read_u8())
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
pub fn Reader::read_u64_le(self : Reader) -> UInt64 raise BitError {
  let lo = self.read_u32_le().to_uint64()
  let hi = self.read_u32_le().to_uint64()
  lo | (hi << 32)
}

///|
pub struct Writer {
  data : Array[Byte]
}

///|
pub fn Writer::new() -> Writer {
  { data: [], }
}

///|
pub fn Writer::write_u8(self : Writer, b : Byte) -> Unit {
  self.data.push(b)
}

///|
pub fn Writer::write_u32_le(self : Writer, v : UInt) -> Unit {
  self.write_u8(uint_to_byte(v))
  self.write_u8(uint_to_byte(v >> 8))
  self.write_u8(uint_to_byte(v >> 16))
  self.write_u8(uint_to_byte(v >> 24))
}

///|
pub fn Writer::write_u64_le(self : Writer, v : UInt64) -> Unit {
  self.write_u32_le(uint_lo32(v))
  self.write_u32_le(uint_lo32(v >> 32))
}

///|
pub fn Writer::write_bytes(self : Writer, bytes : BytesView) -> Unit {
  for b in bytes {
    self.data.push(b)
  }
}

///|
pub fn Writer::to_bytes(self : Writer) -> Bytes {
  Bytes::from_array(self.data[:])
}

///|
pub fn Writer::length(self : Writer) -> Int {
  self.data.length()
}
