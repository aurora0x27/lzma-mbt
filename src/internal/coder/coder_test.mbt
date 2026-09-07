///|
test "lzma_payload_roundtrip" {
  let src = b"coder layer"
  let body = encode_lzma(src[:], 3, 0, 2, 4096, end_marker=true)
  let dec = decode_lzma(
    body[:],
    3,
    0,
    2,
    4096,
    src.length().reinterpret_as_uint().to_uint64(),
  )
  assert_eq(dec, src)
}

///|
test "lzma_payload_unknown_size" {
  let src = b"xyz"
  let body = encode_lzma(src[:], 3, 0, 2, 4096, end_marker=true)
  let dec = decode_lzma(body[:], 3, 0, 2, 4096, 0xFFFF_FFFF_FFFF_FFFFUL)
  assert_eq(dec, src)
}

///|
test "lzma_payload_empty" {
  let body = encode_lzma(b""[:], 3, 0, 2, 4096, end_marker=true)
  let dec = decode_lzma(body[:], 3, 0, 2, 4096, 0UL)
  assert_eq(dec, b"")
}

///|
test "range_first_byte_must_be_zero" {
  let err = @test.expect_error(() => {
    decode_lzma(b"\x01\x00\x00\x00\x00"[:], 3, 0, 2, 4096, 0UL) |> ignore
  })
  assert_true(err is Data)
}

///|
test "lzma_dict_size_zero_is_limit" {
  let err = @test.expect_error(() => {
    decode_lzma(b"\x00\x00\x00\x00\x00"[:], 3, 0, 2, 0, 0UL) |> ignore
  })
  assert_true(err is Limit)
}
