///|
test "crc32_empty" {
  assert_eq(crc32(b""[:]), 0U)
}

///|
test "crc32_check_string" {
  assert_eq(crc32(b"123456789"[:]), 0xCBF43926U)
}

///|
test "crc32_chunked" {
  let a = b"12345"[:]
  let b = b"6789"[:]
  let all = b"123456789"[:]
  assert_eq(crc32(b, init=crc32(a)), crc32(all))
}

///|
test "crc64_empty" {
  assert_eq(crc64(b""[:]), 0UL)
}

///|
test "crc64_check_string" {
  assert_eq(crc64(b"123456789"[:]), 0x995DC9BBDF1939FAUL)
}

///|
test "crc64_chunked" {
  let a = b"12345"[:]
  let b = b"6789"[:]
  let all = b"123456789"[:]
  assert_eq(crc64(b, init=crc64(a)), crc64(all))
}

///|
test "crc32_zero_byte" {
  assert_eq(crc32(b"\x00"[:]), 0xD202EF8DU)
}

///|
test "crc64_zero_byte" {
  assert_eq(crc64(b"\x00"[:]), 0x1FADA17364673F59UL)
}
