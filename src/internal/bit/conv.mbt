///|
pub fn byte_to_uint(b : Byte) -> UInt {
  b.to_int().reinterpret_as_uint()
}

///|
pub fn uint_to_byte(v : UInt) -> Byte {
  (v & 0xFFU).reinterpret_as_int().to_byte()
}

///|
pub fn uint_lo32(v : UInt64) -> UInt {
  (v & 0xFFFFFFFFUL).reinterpret_as_int64().to_int().reinterpret_as_uint()
}
