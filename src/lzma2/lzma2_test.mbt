///|
test "lzma2_roundtrip" {
  let src = b"hello lzma2 stream"
  let enc = encode_lzma2(src[:], 3, 0, 2, 65536U)
  let dec = decode_lzma2(enc[:], 128UL * 1024UL * 1024UL, dict_size=65536U)
  assert_eq(dec, src)
}

///|
test "lzma2_empty" {
  let enc = encode_lzma2(b""[:], 3, 0, 2, 4096U)
  let dec = decode_lzma2(enc[:], 1024UL * 1024UL, dict_size=4096U)
  assert_eq(dec, b"")
}

///|
test "lzma2_uncompressed_chunk" {
  let enc = Bytes::from_array(
    [b'\x01', b'\x00', b'\x04', b'h', b'e', b'l', b'l', b'o', b'\x00'][:],
  )
  let dec = decode_lzma2(enc[:], 1024UL * 1024UL)
  assert_eq(dec, b"hello")
}

///|
test "lzma2_bad_control" {
  let err = @test.expect_error(() => {
    decode_lzma2(b"\x03"[:], 1024UL * 1024UL) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "lzma2_truncated" {
  let err = @test.expect_error(() => {
    decode_lzma2(b"\x01"[:], 1024UL * 1024UL) |> ignore
  })
  assert_true(err is @coder.Eof)
}

///|
test "lzma2_trailing_bytes_are_rejected" {
  let enc = encode_lzma2(b"x"[:], 3, 0, 2, 4096U)
  let arr = Array::new(capacity=enc.length() + 1)
  for b in enc[:] {
    arr.push(b)
  }
  arr.push(b'\x00')
  let err = @test.expect_error(() => {
    decode_lzma2(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, dict_size=4096U)
    |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "lzma2_state_chunk_is_unsupported" {
  let err = @test.expect_error(() => {
    decode_lzma2(b"\x80\x00\x00\x00\x00"[:], 1024UL * 1024UL) |> ignore
  })
  assert_true(err is @coder.Unsupported)
}

///|
test "lzma2_props_without_dict_reset_is_unsupported" {
  let err = @test.expect_error(() => {
    decode_lzma2(b"\xC0\x00\x00\x00\x00\x5D"[:], 1024UL * 1024UL) |> ignore
  })
  assert_true(err is @coder.Unsupported)
}

///|
test "lzma2_memlimit_is_dictionary_not_output" {
  let src = Bytes::make(8000, b'\x61')
  let enc = encode_lzma2(src[:], 3, 0, 2, 4096U)
  let dec = decode_lzma2(enc[:], 4096UL, dict_size=4096U)
  assert_eq(dec, src)
}

///|
test "lzma2_crosses_64kib_chunk" {
  let src = Bytes::make(70000, b'\x33')
  let enc = encode_lzma2(src[:], 3, 0, 2, 4096U)
  let dec = decode_lzma2(enc[:], 1024UL * 1024UL, dict_size=4096U)
  assert_eq(dec, src)
}

///|
test "lzma2_uncompressed_no_reset" {
  let enc = Bytes::from_array(
    [b'\x02', b'\x00', b'\x02', b'a', b'b', b'c', b'\x00'][:],
  )
  let dec = decode_lzma2(enc[:], 1024UL * 1024UL)
  assert_eq(dec, b"abc")
}

///|
test "lzma2_dict_prop_roundtrip" {
  assert_eq(lzma2_dict_size(lzma2_dict_prop(4096U)), 4096U)
  assert_eq(lzma2_dict_size(lzma2_dict_prop(8388608U)), 8388608U)
  assert_eq(lzma2_dict_prop(4096U).to_int(), 0)
}

///|
test "lzma2_dict_prop_byte_too_large" {
  let err = @test.expect_error(() => lzma2_dict_size(b'\x29') |> ignore)
  assert_true(err is @coder.Data)
}

///|
test "lzma2_max_dict_prop_hits_memlimit" {
  let huge = lzma2_dict_size(b'\x28')
  let err = @test.expect_error(() => {
    decode_lzma2(b"\x00"[:], 1024UL * 1024UL, dict_size=huge) |> ignore
  })
  assert_true(err is @coder.Limit)
}

///|
test "lzma2_compressed_chunk_rejects_lc_lp" {
  let err = @test.expect_error(() => {
    decode_lzma2(b"\xE0\x00\x00\x00\x00\x0D"[:], 1024UL * 1024UL) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "lzma2_compressed_chunk_rejects_props_byte" {
  let err = @test.expect_error(() => {
    decode_lzma2(b"\xE0\x00\x00\x00\x00\xE1"[:], 1024UL * 1024UL) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "lzma2_zero_dict_is_limit" {
  let err = @test.expect_error(() => {
    decode_lzma2(b"\x00"[:], 1024UL * 1024UL, dict_size=0U) |> ignore
  })
  assert_true(err is @coder.Limit)
}

///|
test "lzma2_state_reset_chunk_is_unsupported" {
  let err = @test.expect_error(() => {
    decode_lzma2(b"\xA0\x00\x00\x00\x00"[:], 1024UL * 1024UL) |> ignore
  })
  assert_true(err is @coder.Unsupported)
}

///|
test "lzma2_one_byte_roundtrip" {
  let enc = encode_lzma2(b"a"[:], 3, 0, 2, 4096U)
  assert_eq(decode_lzma2(enc[:], 1024UL * 1024UL, dict_size=4096U), b"a")
}

///|
test "lzma2_repetitive_stays_compressed" {
  let src = Bytes::make(1000, b'\x33')
  let enc = encode_lzma2(src[:], 3, 0, 2, 4096U)
  assert_eq(enc[0], b'\xE0')
  assert_eq(decode_lzma2(enc[:], 1024UL * 1024UL, dict_size=4096U), src)
}

///|
test "lzma2_incompressible_roundtrip" {
  let arr = Array::new(capacity=65536)
  for i in 0..<65536 {
    let n = i.reinterpret_as_uint()
    arr.push((((n * 13U) ^ (n >> 3)) & 0xFFU).reinterpret_as_int().to_byte())
  }
  let src = Bytes::from_array(arr[:])
  let enc = encode_lzma2(src[:], 3, 0, 2, 4096U)
  assert_true(enc[0] == b'\x01' || enc[0] == b'\xE0')
  if enc[0] == b'\xE0' {
    let comp = ((enc[3].to_int() << 8) | enc[4].to_int()) + 1
    assert_true(comp <= 65536)
  }
  let dec = decode_lzma2(enc[:], 1024UL * 1024UL, dict_size=4096U)
  assert_eq(dec, src)
}

///|
test "lzma2_consumed_stops_at_end_marker" {
  let enc = encode_lzma2(b"x"[:], 3, 0, 2, 4096U)
  let arr = Array::new(capacity=enc.length() + 2)
  for b in enc[:] {
    arr.push(b)
  }
  arr.push(b'\xAA')
  arr.push(b'\xBB')
  let (plain, used) = decode_lzma2_consumed(
    Bytes::from_array(arr[:])[:],
    1024UL * 1024UL,
    dict_size=4096U,
  )
  assert_eq(plain, b"x")
  assert_eq(used, enc.length())
}
