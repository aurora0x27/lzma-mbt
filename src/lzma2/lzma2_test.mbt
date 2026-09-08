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
  let arr = Array(capacity=enc.length() + 1)
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
test "lzma2_leading_continuation_is_data" {
  let err = @test.expect_error(() => {
    decode_lzma2(b"\x80\x00\x00\x00\x00"[:], 1024UL * 1024UL) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "lzma2_leading_props_chunk_is_data" {
  let err = @test.expect_error(() => {
    decode_lzma2(b"\xC0\x00\x00\x00\x00\x5D"[:], 1024UL * 1024UL) |> ignore
  })
  assert_true(err is @coder.Data)
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
  assert_eq(enc[0], b'\xE0')
  let comp = ((enc[3].to_int() << 8) | enc[4].to_int()) + 1
  let second = 6 + comp
  assert_true(second < enc.length())
  assert_eq(enc[second].to_int() & 0xE0, 0x80)
  let dec = decode_lzma2(enc[:], 1024UL * 1024UL, dict_size=4096U)
  assert_eq(dec, src)
}

///|
test "lzma2_uncompressed_no_reset_after_dict_reset" {
  let enc = Bytes::from_array(
    [
      b'\x01', b'\x00', b'\x01', b'a', b'b', b'\x02', b'\x00', b'\x01', b'c', b'd',
      b'\x00',
    ][:],
  )
  let dec = decode_lzma2(enc[:], 1024UL * 1024UL)
  assert_eq(dec, b"abcd")
}

///|
test "lzma2_leading_uncompressed_no_reset_is_data" {
  let err = @test.expect_error(() => {
    decode_lzma2(
      Bytes::from_array(
        [b'\x02', b'\x00', b'\x02', b'a', b'b', b'c', b'\x00'][:],
      )[:],
      1024UL * 1024UL,
    )
    |> ignore
  })
  assert_true(err is @coder.Data)
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
test "lzma2_leading_state_reset_is_data" {
  let err = @test.expect_error(() => {
    decode_lzma2(b"\xA0\x00\x00\x00\x00"[:], 1024UL * 1024UL) |> ignore
  })
  assert_true(err is @coder.Data)
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
  let arr = Array(capacity=65536)
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
  let arr = Array(capacity=enc.length() + 2)
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

///|
fn concat_bytes(parts : Array[Bytes]) -> Bytes {
  let a = Array()
  for p in parts {
    for b in p[:] {
      a.push(b)
    }
  }
  Bytes::from_array(a[:])
}

///|
test "lzma2_liblzma_e0_then_80_run" {
  // liblzma FORMAT_RAW LZMA2, dict=4096, 2 MiB + 100 bytes of 'A'.
  // Chunks: 0xE0 (2096914) then 0x80 (338).
  let enc = concat_bytes([
    b"\xff\xff\x11\x01\x6c\x5d\x00\x20\xef\xfb\xbf\xfe\xa3\xb1\x5e\xe5\xf8\x3f\xb2\xaa\x26\x55\xf8\x68\x70\x41\x70\x15\x0f\x8d\xfd\x1e\x4c\x1b\x8a\x42\xb7\x19\xf4\x69",
    b"\x18\x71\xae\x66\x23\x8a\x8a\x4d\x2f\xa3\x0d\xd9\x7f\xa6\xe3\x8c\x23\x11\x53\xe0\x59\x18\xc5\x75\x8a\xe2\x77\xf8\xb6\x94\x7f\x0c\x6a\xc0\xde\x74\x49\x64\xe2\xe9",
    b"\x5c\x53\xb2\x04\xd8\xf7\x44\x0c\xab\x5f\x0d\x6d\x46\xe9\xe5\xc3\x76\x88\xb7\x96\x57\xac\xb6\x4d\xe1\x69\x1d\x6f\xfb\x4b\x88\x10\x6c\x42\xcb\x88\x3f\x5c\x00\x8f",
    b"\xd0\x4e\xaf\x26\x28\x94\x71\x1f\x3d\x8f\x24\xe1\x70\x9e\xa7\x23\x5f\xec\x28\xcb\x85\xd1\x95\x98\x8a\x7e\x2a\x91\xf2\x27\x75\xf7\x19\xc0\x06\x98\x4d\x98\xfd\xd8",
    b"\xaf\xd5\x90\x0f\xc4\x25\x53\xf8\xf5\x91\x36\x31\x05\xa5\xb0\xee\x6f\xc1\x70\x4d\x47\x0c\xd1\x91\x11\xaa\xad\x60\x1d\xba\xce\xb1\x27\x18\x5c\x59\x86\xe9\x66\x52",
    b"\x58\xbe\xe9\x76\xac\x59\xe4\xe5\x5b\x05\x08\xf9\xc7\xda\xad\xfc\xfb\x52\x2b\x74\xcd\x1e\x5b\x20\x42\xf9\xdd\x53\x3d\xf8\x29\x64\x09\x3b\x80\xcb\x2a\x6c\xdf\xb5",
    b"\x3b\xf0\xc4\xbd\x2e\x5f\xaa\x0f\x3e\x4b\x66\x42\x90\x13\x0e\xff\x10\x93\xf8\x71\x78\x59\xf8\x0b\xcd\xff\x95\x28\x46\x0f\xa9\xfc\x7c\xde\xfb\x9a\x30\x2e\x56\xc0",
    b"\x8f\x85\xf3\x83\x81\xc0\x65\xc4\x25\x53\xf8\xf5\x91\x36\x31\x05\xa5\xb0\xee\x6f\xc1\x70\x4d\x47\x0c\xd1\x91\x11\xaa\xad\x60\x1d\xba\xce\xb1\x27\x18\x5c\x59\x86",
    b"\xe9\x66\x52\x58\xbe\xe9\x76\xac\x59\xe4\xe5\x5b\x05\x08\xf9\xc7\xda\xad\xfc\xfb\x52\x2b\x74\xcd\x1e\x5b\x20\x42\xf9\xdd\x53\x3d\xf8\x29\x64\x09\x3b\x80\xcb\x2a",
    b"\x6c\xdf\xb5\x3b\xf0\xc4\xbc\x48\x27\xe6\x58\x80\x01\x51\x00\x05\x00\x3d\x8f\x56\x47\x00\x00",
  ])
  let dec = decode_lzma2(enc[:], 1024UL * 1024UL, dict_size=4096U)
  assert_eq(dec.length(), 2097252)
  assert_eq(dec[0], b'\x41')
  assert_eq(dec[2097251], b'\x41')
}

///|
test "lzma2_uncompressed_then_continuation_needs_props" {
  let err = @test.expect_error(() => {
    decode_lzma2(
      Bytes::from_array(
        [
          b'\x01', b'\x00', b'\x00', b'x', b'\x80', b'\x00', b'\x00', b'\x00', b'\x00',
        ][:],
      )[:],
      1024UL * 1024UL,
    )
    |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "lzma2_truncated_continuation_is_eof" {
  let src = Bytes::make(70000, b'\x33')
  let enc = encode_lzma2(src[:], 3, 0, 2, 4096U)
  let comp = ((enc[3].to_int() << 8) | enc[4].to_int()) + 1
  let second = 6 + comp
  let err = @test.expect_error(() => {
    decode_lzma2(enc[0:second + 1], 1024UL * 1024UL, dict_size=4096U) |> ignore
  })
  assert_true(err is @coder.Eof)
}
