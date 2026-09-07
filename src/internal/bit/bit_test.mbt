///|
test "read_u32_le" {
  let r = Reader::new(b"\x01\x02\x03\x04"[:])
  assert_eq(r.read_u32_le(), 0x04030201U)
  assert_eq(r.remaining(), 0)
}

///|
test "truncated_read_is_eof" {
  let r = Reader::new(b"\x01\x02"[:])
  let err = @test.expect_error(() => r.read_u32_le() |> ignore)
  assert_true(err is Eof)
}

///|
test "u32_roundtrip" {
  let w = Writer::new()
  w.write_u32_le(0x04030201U)
  let r = Reader::new(w.to_bytes()[:])
  assert_eq(r.read_u32_le(), 0x04030201U)
}

///|
test "u64_roundtrip" {
  let w = Writer::new()
  w.write_u64_le(0x0807060504030201UL)
  let r = Reader::new(w.to_bytes()[:])
  assert_eq(r.read_u64_le(), 0x0807060504030201UL)
}

///|
test "empty_eof" {
  let r = Reader::new(b""[:])
  let err = @test.expect_error(() => r.read_u8() |> ignore)
  assert_true(err is Eof)
}

///|
test "u32_high_bit_roundtrip" {
  let w = Writer::new()
  w.write_u32_le(0xCBF43926U)
  let r = Reader::new(w.to_bytes()[:])
  assert_eq(r.read_u32_le(), 0xCBF43926U)
}

///|
test "read_exact_zero_is_empty" {
  let r = Reader::new(b"\x01"[:])
  assert_eq(r.read_exact(0), b""[:])
  assert_eq(r.read_u8(), b'\x01')
}

///|
test "u64_high_bit_roundtrip" {
  let w = Writer::new()
  w.write_u64_le(0x8000000000000001UL)
  let r = Reader::new(w.to_bytes()[:])
  assert_eq(r.read_u64_le(), 0x8000000000000001UL)
}

///|
test "read_exact_negative_is_eof" {
  let r = Reader::new(b"\x01"[:])
  let err = @test.expect_error(() => r.read_exact(-1) |> ignore)
  assert_true(err is Eof)
}
