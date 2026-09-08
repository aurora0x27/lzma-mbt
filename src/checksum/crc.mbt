///|
fn make_crc32_table() -> Array[UInt] {
  let table = Array::make(256, 0U)
  for i in 0..<256 {
    let mut crc = i.reinterpret_as_uint()
    for _ in 0..<8 {
      if (crc & 1U) != 0U {
        crc = (crc >> 1) ^ 0xEDB88320U
      } else {
        crc = crc >> 1
      }
    }
    table[i] = crc
  }
  table
}

///|
fn make_crc64_table() -> Array[UInt64] {
  let table = Array::make(256, 0UL)
  let poly : UInt64 = 0xC96C5795D7870F42UL
  for i in 0..<256 {
    let mut crc = i.reinterpret_as_uint().to_uint64()
    for _ in 0..<8 {
      if (crc & 1UL) != 0UL {
        crc = (crc >> 1) ^ poly
      } else {
        crc = crc >> 1
      }
    }
    table[i] = crc
  }
  table
}

///|
let crc32_table : Array[UInt] = make_crc32_table()

///|
let crc64_table : Array[UInt64] = make_crc64_table()

///|
fn byte_as_uint(b : Byte) -> UInt {
  b.to_int().reinterpret_as_uint()
}

///|
pub fn crc32(data : BytesView, init? : UInt = 0U) -> UInt {
  let mut crc = init ^ 0xFFFFFFFFU
  for b in data {
    let idx = ((crc ^ byte_as_uint(b)) & 0xFFU).reinterpret_as_int()
    crc = crc32_table[idx] ^ (crc >> 8)
  }
  crc ^ 0xFFFFFFFFU
}

///|
pub fn crc64(data : BytesView, init? : UInt64 = 0UL) -> UInt64 {
  let mut crc = init ^ 0xFFFFFFFF_FFFFFFFFUL
  for b in data {
    let idx = ((crc ^ byte_as_uint(b).to_uint64()) & 0xFFUL)
      .reinterpret_as_int64()
      .to_int()
    crc = crc64_table[idx] ^ (crc >> 8)
  }
  crc ^ 0xFFFFFFFF_FFFFFFFFUL
}

///|
let sha256_k : Array[UInt] = [
  0x428A2F98U, 0x71374491U, 0xB5C0FBCFU, 0xE9B5DBA5U, 0x3956C25BU, 0x59F111F1U, 0x923F82A4U,
  0xAB1C5ED5U, 0xD807AA98U, 0x12835B01U, 0x243185BEU, 0x550C7DC3U, 0x72BE5D74U, 0x80DEB1FEU,
  0x9BDC06A7U, 0xC19BF174U, 0xE49B69C1U, 0xEFBE4786U, 0x0FC19DC6U, 0x240CA1CCU, 0x2DE92C6FU,
  0x4A7484AAU, 0x5CB0A9DCU, 0x76F988DAU, 0x983E5152U, 0xA831C66DU, 0xB00327C8U, 0xBF597FC7U,
  0xC6E00BF3U, 0xD5A79147U, 0x06CA6351U, 0x14292967U, 0x27B70A85U, 0x2E1B2138U, 0x4D2C6DFCU,
  0x53380D13U, 0x650A7354U, 0x766A0ABBU, 0x81C2C92EU, 0x92722C85U, 0xA2BFE8A1U, 0xA81A664BU,
  0xC24B8B70U, 0xC76C51A3U, 0xD192E819U, 0xD6990624U, 0xF40E3585U, 0x106AA070U, 0x19A4C116U,
  0x1E376C08U, 0x2748774CU, 0x34B0BCB5U, 0x391C0CB3U, 0x4ED8AA4AU, 0x5B9CCA4FU, 0x682E6FF3U,
  0x748F82EEU, 0x78A5636FU, 0x84C87814U, 0x8CC70208U, 0x90BEFFFAU, 0xA4506CEBU, 0xBEF9A3F7U,
  0xC67178F2U,
]

///|
struct Sha256State {
  h : Array[UInt]
  buf : Array[Byte]
  mut total_len : UInt64
}

///|
fn rotr32(x : UInt, n : Int) -> UInt {
  (x >> n) | (x << (32 - n))
}

///|
fn read_u32_be(block : BytesView, off : Int) -> UInt {
  (byte_as_uint(block[off]) << 24) |
  (byte_as_uint(block[off + 1]) << 16) |
  (byte_as_uint(block[off + 2]) << 8) |
  byte_as_uint(block[off + 3])
}

///|
fn write_u32_be(out : Array[Byte], v : UInt) -> Unit {
  out.push(((v >> 24) & 0xFFU).reinterpret_as_int().to_byte())
  out.push(((v >> 16) & 0xFFU).reinterpret_as_int().to_byte())
  out.push(((v >> 8) & 0xFFU).reinterpret_as_int().to_byte())
  out.push((v & 0xFFU).reinterpret_as_int().to_byte())
}

///|
pub fn Sha256State::new() -> Sha256State {
  {
    h: [
      0x6A09E667U, 0xBB67AE85U, 0x3C6EF372U, 0xA54FF53AU, 0x510E527FU, 0x9B05688CU,
      0x1F83D9ABU, 0x5BE0CD19U,
    ],
    buf: [],
    total_len: 0UL,
  }
}

///|
fn Sha256State::process_block(self : Sha256State, block : BytesView) -> Unit {
  let w = Array::make(64, 0U)
  for i in 0..<16 {
    w[i] = read_u32_be(block, i * 4)
  }
  for i in 16..<64 {
    let s0 = rotr32(w[i - 15], 7) ^ rotr32(w[i - 15], 18) ^ (w[i - 15] >> 3)
    let s1 = rotr32(w[i - 2], 17) ^ rotr32(w[i - 2], 19) ^ (w[i - 2] >> 10)
    w[i] = w[i - 16] + s0 + w[i - 7] + s1
  }
  let mut a = self.h[0]
  let mut b = self.h[1]
  let mut c = self.h[2]
  let mut d = self.h[3]
  let mut e = self.h[4]
  let mut f = self.h[5]
  let mut g = self.h[6]
  let mut h = self.h[7]
  for i in 0..<64 {
    let s1 = rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25)
    let ch = (e & f) ^ (e.lnot() & g)
    let temp1 = h + s1 + ch + sha256_k[i] + w[i]
    let s0 = rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22)
    let maj = (a & b) ^ (a & c) ^ (b & c)
    let temp2 = s0 + maj
    h = g
    g = f
    f = e
    e = d + temp1
    d = c
    c = b
    b = a
    a = temp1 + temp2
  }
  self.h[0] = self.h[0] + a
  self.h[1] = self.h[1] + b
  self.h[2] = self.h[2] + c
  self.h[3] = self.h[3] + d
  self.h[4] = self.h[4] + e
  self.h[5] = self.h[5] + f
  self.h[6] = self.h[6] + g
  self.h[7] = self.h[7] + h
}

///|
pub fn Sha256State::update(self : Sha256State, data : BytesView) -> Unit {
  self.total_len = self.total_len +
    data.length().reinterpret_as_uint().to_uint64()
  for b in data {
    self.buf.push(b)
    if self.buf.length() == 64 {
      self.process_block(Bytes::from_array(self.buf[:])[:])
      self.buf.clear()
    }
  }
}

///|
pub fn Sha256State::finish(self : Sha256State) -> Bytes {
  let bit_len = self.total_len << 3
  self.buf.push(b'\x80')
  while self.buf.length() % 64 != 56 {
    self.buf.push(b'\x00')
  }
  for shift in [56, 48, 40, 32, 24, 16, 8, 0] {
    self.buf.push(
      ((bit_len >> shift) & 0xFFUL).reinterpret_as_int64().to_int().to_byte(),
    )
  }
  if self.buf.length() == 64 {
    self.process_block(Bytes::from_array(self.buf[0:64])[:])
  } else {
    self.process_block(Bytes::from_array(self.buf[0:64])[:])
    self.process_block(Bytes::from_array(self.buf[64:128])[:])
  }
  let out = Array(capacity=32)
  for v in self.h {
    write_u32_be(out, v)
  }
  Bytes::from_array(out[:])
}

///|
pub fn sha256(data : BytesView) -> Bytes {
  let st = Sha256State::new()
  st.update(data)
  st.finish()
}
