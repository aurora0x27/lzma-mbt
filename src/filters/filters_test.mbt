///|
test "delta_roundtrip" {
  let src = b"\x01\x02\x03\x04\x05"
  let e = delta_encode(src[:], 1)
  let d = delta_decode(e[:], 1)
  assert_eq(d, src)
}

///|
test "delta_distance_256" {
  let src = Bytes::make(300, b'\x7F')
  let e = delta_encode(src[:], 256)
  let d = delta_decode(e[:], 256)
  assert_eq(d, src)
}

///|
test "delta_invalid_distance" {
  let err = @test.expect_error(() => delta_encode(b"x"[:], 0) |> ignore)
  assert_true(err is InvalidDistance)
  let err2 = @test.expect_error(() => delta_decode(b"x"[:], 257) |> ignore)
  assert_true(err2 is InvalidDistance)
}

///|
test "bcj_roundtrip" {
  let src = b"\xE8\x10\x00\x00\x00\x90\x90"
  let e = bcj_x86(src[:], 0U, true)
  let d = bcj_x86(e[:], 0U, false)
  assert_eq(d, src)
}

///|
test "bcj_negative_disp_and_start_offset" {
  let src = b"\xE8\xFF\xFF\xFF\x7F\xE9\x00\x00\x00\x80"
  let e = bcj_x86(src[:], 0x1000U, true)
  let d = bcj_x86(e[:], 0x1000U, false)
  assert_eq(d, src)
}

///|
test "bcj_truncated_immediate_untouched" {
  let src = b"\xE8\x01\x02\x03"
  let e = bcj_x86(src[:], 0U, true)
  assert_eq(e, src)
}

///|
test "bcj_wraparound_start_offset" {
  let src = b"\xE8\x10\x00\x00\x00\x90"
  let e = bcj_x86(src[:], 0xFFFFFFFFU, true)
  let d = bcj_x86(e[:], 0xFFFFFFFFU, false)
  assert_eq(d, src)
}

///|
test "delta_empty_roundtrip" {
  assert_eq(delta_decode(delta_encode(b""[:], 1)[:], 1), b"")
}

///|
test "bcj_empty_is_empty" {
  assert_eq(bcj_x86(b""[:], 0U, true), b"")
}

///|
/// Exact outputs of liblzma `lzma_bcj_x86_encode/decode` (xz 5.8), locking the
/// full MSByte / `prev_mask` transform rather than a reversible E8/E9 subset.
test "bcj_x86_matches_liblzma_encode" {
  let v1 = b"\xE8\x00\x00\x00\xFF\x90"
  assert_eq(bcj_x86(v1[:], 0U, true), b"\xE8\x05\x00\x00\xFF\x90")
  let top = b"\xE8\x01\x02\x03\xFF\xE9\x04\x05\x06\x00"
  assert_eq(
    bcj_x86(top[:], 0U, true),
    b"\xE8\x06\x02\x03\xFF\xE9\x0E\x05\x06\x00",
  )
  // Adjacent/overlapping E8/E9 candidates exercise the prev_mask state.
  let seg = b"\xE8\xE8\x00\x00\x00\xE8\xE9\x00\x00\x00\xE9\xE8\xFF\xFF\xFF\x90\x90"
  assert_eq(
    bcj_x86(seg[:], 0U, true),
    b"\xE8\xED\x00\x00\x00\xE8\xF3\x00\x00\x00\xE9\xF7\xFF\xFF\xFF\x90\x90",
  )
  assert_eq(
    bcj_x86(seg[:], 4096U, true),
    b"\xE8\xED\x10\x00\x00\xE8\xF3\x10\x00\x00\xE9\xF7\x0F\x00\x00\x90\x90",
  )
}

///|
test "bcj_x86_matches_liblzma_decode" {
  let encoded = b"\xE8\xED\x00\x00\x00\xE8\xF3\x00\x00\x00\xE9\xF7\xFF\xFF\xFF\x90\x90"
  assert_eq(
    bcj_x86(encoded[:], 0U, false),
    b"\xE8\xE8\x00\x00\x00\xE8\xE9\x00\x00\x00\xE9\xE8\xFF\xFF\xFF\x90\x90",
  )
  assert_eq(
    bcj_x86(b"\xE8\x05\x00\x00\xFF\x90"[:], 0U, false),
    b"\xE8\x00\x00\x00\xFF\x90",
  )
}
