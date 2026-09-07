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
