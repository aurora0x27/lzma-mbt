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

///|
test "bcj_arm_roundtrip" {
  let src = b"\x00\x00\x00\xEB\x02\x00\x00\xEB\x78\x56\x34\x12\x90\x90\x90\x90"
  let e = bcj_arm(src[:], 0U, true)
  let d = bcj_arm(e[:], 0U, false)
  assert_eq(d, src)
}

///|
test "bcj_arm_known_transform" {
  // A single B/BL word `00 00 00 EB` (LE) at offset 0 encodes to field 2
  // (`(0 + 0 + 8) >> 2`); decoding restores the original.
  assert_eq(bcj_arm(b"\x00\x00\x00\xEB"[:], 0U, true), b"\x02\x00\x00\xEB")
  assert_eq(bcj_arm(b"\x02\x00\x00\xEB"[:], 0U, false), b"\x00\x00\x00\xEB")
  // Second word of two, 4 bytes in: base = start_offset + 4 + 8.
  let two = b"\x90\x90\x90\x90\x00\x00\x00\xEB"
  assert_eq(bcj_arm(two[:], 0U, true), b"\x90\x90\x90\x90\x03\x00\x00\xEB")
  // Non-zero, 32-bit wrapping start offset.
  let wrap = b"\x00\x00\x00\xEB"
  assert_eq(bcj_arm(wrap[:], 0xFFFFFFF8U, true), b"\x00\x00\x00\xEB")
  let base = b"\x00\x00\x00\xEB"
  assert_eq(bcj_arm(base[:], 4096U, true), b"\x02\x04\x00\xEB")
  // A trailing partial word is never rewritten.
  assert_eq(bcj_arm(b"\x00\x00\x00"[:], 0U, true), b"\x00\x00\x00")
  assert_eq(
    bcj_arm(b"\x00\x00\x00\xEB\x01"[:], 0U, true),
    b"\x02\x00\x00\xEB\x01",
  )
}

///|
test "bcj_arm64_roundtrip" {
  let src = b"\x00\x00\x00\x94\xFF\xFF\xFF\x97\x00\x00\x08\x91\xF0\x03\x00\x91\xC0\x03\x5F\xD6"
  let e = bcj_arm64(src[:], 0U, true)
  let d = bcj_arm64(e[:], 0U, false)
  assert_eq(d, src)
}

///|
test "bcj_arm64_matches_liblzma" {
  // Exact outputs of `lzma_bcj_arm64_encode/decode` (xz 5.8).
  // BL word at a 4096-byte offset: immediate gains pc >> 2 = 0x400.
  let bl = b"\x00\x00\x00\x94"
  assert_eq(bcj_arm64(bl[:], 4096U, true), b"\x00\x04\x00\x94")
  // A BL followed by an in-range ADRP at the same offset.
  let two = b"\x00\x00\x00\x94\x00\xF0\x07\x90"
  assert_eq(bcj_arm64(two[:], 4096U, true), b"\x00\x04\x00\x94\x00\xF0\x07\xB0")
  assert_eq(
    bcj_arm64(b"\x00\x04\x00\x94\x00\xF0\x07\xB0"[:], 4096U, false),
    two,
  )
  // Out-of-range ADRP is left untouched.
  assert_eq(bcj_arm64(b"\x00\x00\x08\x91"[:], 0U, true), b"\x00\x00\x08\x91")
  // A trailing partial word is never rewritten.
  assert_eq(
    bcj_arm64(b"\x00\x00\x00\x94\x01"[:], 0U, true),
    b"\x00\x00\x00\x94\x01",
  )
}

///|
test "bcj_armthumb_roundtrip" {
  let src = b"\x00\xF0\x00\xF8\x11\xF8\x22\xF0\x33\x00\x44\xFF\x10\xF3\x20\xFB"
  let e = bcj_armthumb(src[:], 0U, true)
  let d = bcj_armthumb(e[:], 0U, false)
  assert_eq(d, src)
}

///|
test "bcj_armthumb_transform" {
  // A Thumb BL pair `00 F0 00 F8` at offset 0: base = 0 + 0 + 4, field 0.
  assert_eq(bcj_armthumb(b"\x00\xF0\x00\xF8"[:], 0U, true), b"\x00\xF0\x02\xF8")
  assert_eq(
    bcj_armthumb(b"\x00\xF0\x02\xF8"[:], 0U, false),
    b"\x00\xF0\x00\xF8",
  )
  // The same pair at a 4096-byte start offset.
  assert_eq(
    bcj_armthumb(b"\x00\xF0\x00\xF8"[:], 4096U, true),
    b"\x01\xF0\x02\xF8",
  )
  // Non-matching halfwords are untouched; fewer than 4 bytes is untouched.
  assert_eq(bcj_armthumb(b"\x00\xF8\x00\xF0"[:], 0U, true), b"\x00\xF8\x00\xF0")
  assert_eq(bcj_armthumb(b"\x00\xF0\x00"[:], 0U, true), b"\x00\xF0\x00")
  assert_eq(
    bcj_armthumb(b"\x00\xF0\x00\xF8\x01"[:], 0U, true),
    b"\x00\xF0\x02\xF8\x01",
  )
}

///|
test "bcj_powerpc_roundtrip" {
  let src = b"\x48\x00\x00\x01\x4B\xFF\xFF\x01\x4C\x11\x22\x01\x48\x11\x22\x00"
  let e = bcj_powerpc(src[:], 0U, true)
  let d = bcj_powerpc(e[:], 0U, false)
  assert_eq(d, src)
}

///|
test "bcj_powerpc_transform" {
  // A branch word `48 00 00 01` (field 0) at offset 0 is unchanged.
  assert_eq(bcj_powerpc(b"\x48\x00\x00\x01"[:], 0U, true), b"\x48\x00\x00\x01")
  // At a 4096-byte start offset the field gains 0x1000.
  assert_eq(
    bcj_powerpc(b"\x48\x00\x00\x01"[:], 4096U, true),
    b"\x48\x00\x10\x01",
  )
  assert_eq(
    bcj_powerpc(b"\x48\x00\x10\x01"[:], 4096U, false),
    b"\x48\x00\x00\x01",
  )
  // Near-miss words are untouched; fewer than 4 bytes is untouched.
  assert_eq(bcj_powerpc(b"\x48\x11\x22\x00"[:], 0U, true), b"\x48\x11\x22\x00")
  assert_eq(bcj_powerpc(b"\x4C\x11\x22\x01"[:], 0U, true), b"\x4C\x11\x22\x01")
  assert_eq(bcj_powerpc(b"\x48\x00\x00"[:], 0U, true), b"\x48\x00\x00")
}
