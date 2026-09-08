///|
test "alone_roundtrip_empty" {
  let enc = encode_alone(b""[:], 3, 0, 2, 4096U)
  let dec = decode_alone(enc[:], 128UL * 1024UL * 1024UL)
  assert_eq(dec, b"")
}

///|
test "alone_roundtrip_one_byte" {
  let src = b"a"
  let enc = encode_alone(src[:], 3, 0, 2, 4096U)
  let dec = decode_alone(enc[:], 128UL * 1024UL * 1024UL)
  assert_eq(dec, src)
}

///|
test "alone_roundtrip_hello" {
  let src = b"hello lzma"
  let enc = encode_alone(src[:], 3, 0, 2, 4096U)
  let dec = decode_alone(enc[:], 128UL * 1024UL * 1024UL)
  assert_eq(dec, src)
}

///|
test "alone_roundtrip_run" {
  let src = Bytes::make(64, b'\xAA')
  let enc = encode_alone(src[:], 3, 0, 2, 4096U)
  let dec = decode_alone(enc[:], 128UL * 1024UL * 1024UL)
  assert_eq(dec, src)
}

///|
test "alone_encode_is_deterministic" {
  let src = b"deterministic"
  let a = encode_alone(src[:], 3, 0, 2, 4096U)
  let b = encode_alone(src[:], 3, 0, 2, 4096U)
  assert_eq(a, b)
}

///|
test "truncated_header" {
  @test.assert_raise(() => {
    decode_alone(b"\x5D\x00"[:], 1024UL * 1024UL) |> ignore
  })
}

///|
test "invalid_props_byte" {
  let err = @test.expect_error(() => {
    decode_alone(
      b"\xE1\x00\x00\x10\x00\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF"[:],
      1024UL * 1024UL,
    )
    |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "dict_over_memlimit" {
  let enc = encode_alone(b"x"[:], 3, 0, 2, 4096U)
  let err = @test.expect_error(() => decode_alone(enc[:], 100UL) |> ignore)
  assert_true(err is @coder.Limit)
}

///|
test "decode_liblzma_hello_alone" {
  // liblzma FORMAT_ALONE, lc=3,lp=0,pb=2, dict=4096, unknown size
  let enc = b"\x5D\x00\x10\x00\x00\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x00\x34\x19\x49\xEE\x8D\xE9\x14\x8A\x6A\xA5\xDF\xA3\x91\x7F\xFF\xFB\x7F\x40\x00"
  let dec = decode_alone(enc[:], 128UL * 1024UL * 1024UL)
  assert_eq(dec, b"hello lzma")
}

///|
test "decode_liblzma_empty_alone" {
  let enc = b"\x5D\x00\x10\x00\x00\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x00\x83\xFF\xFB\xFF\xFF\xC0\x00\x00\x00"
  let dec = decode_alone(enc[:], 128UL * 1024UL * 1024UL)
  assert_eq(dec, b"")
}

///|
test "decode_liblzma_one_byte_alone" {
  let enc = b"\x5D\x00\x10\x00\x00\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x00\x30\xC1\xFB\xFF\xFF\xFF\xE0\x00\x00\x00"
  let dec = decode_alone(enc[:], 128UL * 1024UL * 1024UL)
  assert_eq(dec, b"a")
}

///|
test "decode_liblzma_run_alone" {
  let enc = b"\x5D\x00\x10\x00\x00\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x00\x55\x6E\x57\x07\xFF\xFF\xFF\xFF\x80\x00\x00\x00"
  let dec = decode_alone(enc[:], 128UL * 1024UL * 1024UL)
  assert_eq(dec, Bytes::make(64, b'\xAA'))
}

///|
test "small_header_dict_is_rounded_up" {
  let src = b"hello lzma"
  let enc = encode_alone(src[:], 3, 0, 2, 4096U)
  let arr = Array(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  arr[1] = b'\x01'
  arr[2] = b'\x00'
  arr[3] = b'\x00'
  arr[4] = b'\x00'
  let patched = Bytes::from_array(arr[:])
  let dec = decode_alone(patched[:], 128UL * 1024UL * 1024UL)
  assert_eq(dec, src)
}

///|
test "rounded_dict_is_checked_against_memlimit" {
  let src = b"hello lzma"
  let enc = encode_alone(src[:], 3, 0, 2, 4096U)
  let arr = Array(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  arr[1] = b'\x01'
  arr[2] = b'\x00'
  arr[3] = b'\x00'
  arr[4] = b'\x00'
  let patched = Bytes::from_array(arr[:])
  let err = @test.expect_error(() => decode_alone(patched[:], 100UL) |> ignore)
  assert_true(err is @coder.Limit)
}

///|
test "zero_header_dict_is_rounded_up" {
  let src = b"hello lzma"
  let enc = encode_alone(src[:], 3, 0, 2, 4096U)
  let arr = Array(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  arr[1] = b'\x00'
  arr[2] = b'\x00'
  arr[3] = b'\x00'
  arr[4] = b'\x00'
  let patched = Bytes::from_array(arr[:])
  let dec = decode_alone(patched[:], 128UL * 1024UL * 1024UL)
  assert_eq(dec, src)
}
