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
test "lzma_payload_eof_does_not_poison_decoder_state" {
  let src = b"transactional lzma payload with enough symbols"
  let body = encode_lzma(src[:], 3, 0, 2, 4096, end_marker=true)
  let dec = LzmaDec::new(3, 0, 2, 4096)
  let truncated = body[:body.length() - 8]
  let err = @test.expect_error(() => {
    dec.decode_payload_resumable(
      truncated,
      src.length().reinterpret_as_uint().to_uint64(),
      allow_end_marker=true,
    )
    |> ignore
  })
  assert_true(err is Eof)
  assert_eq(
    dec.decode_payload_resumable(
      body[:],
      src.length().reinterpret_as_uint().to_uint64(),
      allow_end_marker=true,
    ),
    src,
  )
}

///|
test "lzma_payload_can_be_driven_symbol_by_symbol" {
  let src = b"symbol stepping keeps the decoder state coherent"
  let body = encode_lzma(src[:], 3, 0, 2, 4096, end_marker=true)
  let range = @rc.RangeDecoder::new(body[:])
  let dec = LzmaDec::new(3, 0, 2, 4096)
  let target = src.length().reinterpret_as_uint().to_uint64()
  let out = Array()
  let mut done = false
  while done == false {
    let (piece, end) = dec.decode_symbol(
      range,
      target,
      allow_end_marker=true,
      transactional=false,
    )
    for b in piece[:] {
      out.push(b)
    }
    done = end
  }
  assert_eq(Bytes::from_array(out[:]), src)
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
