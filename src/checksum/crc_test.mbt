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

///|
fn concat_views(a : BytesView, b : BytesView) -> Bytes {
  let out = Array(capacity=a.length() + b.length())
  for x in a {
    out.push(x)
  }
  for x in b {
    out.push(x)
  }
  Bytes::from_array(out[:])
}

///|
test "sha256_empty" {
  assert_eq(
    sha256(b""[:]),
    b"\xE3\xB0\xC4\x42\x98\xFC\x1C\x14\x9A\xFB\xF4\xC8\x99\x6F\xB9\x24\x27\xAE\x41\xE4\x64\x9B\x93\x4C\xA4\x95\x99\x1B\x78\x52\xB8\x55",
  )
}

///|
test "sha256_abc" {
  assert_eq(
    sha256(b"abc"[:]),
    b"\xBA\x78\x16\xBF\x8F\x01\xCF\xEA\x41\x41\x40\xDE\x5D\xAE\x22\x23\xB0\x03\x61\xA3\x96\x17\x7A\x9C\xB4\x10\xFF\x61\xF2\x00\x15\xAD",
  )
}

///|
test "sha256_multi_block_vector" {
  let src = b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
  assert_eq(
    sha256(src[:]),
    b"\x24\x8D\x6A\x61\xD2\x06\x38\xB8\xE5\xC0\x26\x93\x0C\x3E\x60\x39\xA3\x3C\xE4\x59\x64\xFF\x21\x67\xF6\xEC\xED\xD4\x19\xDB\x06\xC1",
  )
}

///|
test "sha256_chunked" {
  let a = b"abcdbcdecdefdefg"
  let b = b"efghfghighijhijkijkljklmklmnlmnomnopnopq"
  let all = concat_views(a[:], b[:])
  let st = Sha256State::new()
  st.update(a[:])
  st.update(b[:])
  assert_eq(st.finish(), sha256(all[:]))
}
