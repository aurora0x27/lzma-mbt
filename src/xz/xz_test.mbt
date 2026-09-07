///|
test "xz_roundtrip" {
  let src = b"xz container roundtrip"
  let enc = encode_xz(src[:], 3, 0, 2, 65536U)
  let dec = decode_xz(enc[:], 128UL * 1024UL * 1024UL, false)
  assert_eq(dec, src)
}

///|
test "xz_empty_roundtrip" {
  let enc = encode_xz(b""[:], 3, 0, 2, 4096U)
  let dec = decode_xz(enc[:], 1024UL * 1024UL, false)
  assert_eq(dec, b"")
}

///|
test "xz_crc32_check_roundtrip" {
  let src = b"crc32 check"
  let enc = encode_xz(src[:], 3, 0, 2, 4096U, check_id=1)
  let dec = decode_xz(enc[:], 1024UL * 1024UL, false)
  assert_eq(dec, src)
}

///|
test "xz_none_check_roundtrip" {
  let src = b"no check field"
  let enc = encode_xz(src[:], 3, 0, 2, 4096U, check_id=0)
  let dec = decode_xz(enc[:], 1024UL * 1024UL, false)
  assert_eq(dec, src)
}

///|
test "xz_magic_and_footer" {
  let enc = encode_xz(b"yz"[:], 3, 0, 2, 4096U)
  assert_eq(enc[0], b'\xFD')
  assert_eq(enc[1], b'\x37')
  assert_eq(enc[2], b'\x7A')
  assert_eq(enc[3], b'\x58')
  assert_eq(enc[4], b'\x5A')
  assert_eq(enc[5], b'\x00')
  assert_eq(enc[enc.length() - 2], b'\x59')
  assert_eq(enc[enc.length() - 1], b'\x5A')
}

///|
test "xz_bad_magic" {
  let err = @test.expect_error(() => {
    decode_xz(b"notxz!"[:], 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_unknown_filter_id" {
  let enc = encode_xz(b"x"[:], 3, 0, 2, 4096U)
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  let hs = arr[12].to_int()
  let header_len = (hs + 1) * 4
  let hdr_end = 12 + header_len - 4
  let mut i = 12
  while i + 1 < hdr_end {
    if arr[i] == b'\x21' && arr[i + 1] == b'\x01' {
      arr[i] = b'\x06'
      break
    }
    i = i + 1
  }
  let hdr = Bytes::from_array(arr[12:hdr_end])
  let crc = @checksum.crc32(hdr[:])
  arr[hdr_end] = (crc & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 1] = ((crc >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 2] = ((crc >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 3] = ((crc >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  let mutated = Bytes::from_array(arr[:])
  let err = @test.expect_error(() => {
    decode_xz(mutated[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Unsupported)
}

///|
test "decode_liblzma_empty_xz" {
  let enc = b"\xFD\x37\x7A\x58\x5A\x00\x00\x04\xE6\xD6\xB4\x46\x00\x00\x00\x00\x1C\xDF\x44\x21\x1F\xB6\xF3\x7D\x01\x00\x00\x00\x00\x04\x59\x5A"
  let dec = decode_xz(enc[:], 128UL * 1024UL * 1024UL, false)
  assert_eq(dec, b"")
}

///|
test "decode_liblzma_hello_xz" {
  let enc = b"\xFD\x37\x7A\x58\x5A\x00\x00\x04\xE6\xD6\xB4\x46\x02\x00\x21\x01\x16\x00\x00\x00\x74\x2F\xE5\xA3\x01\x00\x09\x68\x65\x6C\x6C\x6F\x20\x6C\x7A\x6D\x61\x00\x00\x00\xF7\x7B\xCD\xAC\x69\x58\xF9\xEB\x00\x01\x22\x0A\x15\x1A\xE1\x67\x1F\xB6\xF3\x7D\x01\x00\x00\x00\x00\x04\x59\x5A"
  let dec = decode_xz(enc[:], 128UL * 1024UL * 1024UL, false)
  assert_eq(dec, b"hello lzma")
}

///|
test "decode_liblzma_one_byte_xz" {
  let enc = b"\xFD\x37\x7A\x58\x5A\x00\x00\x04\xE6\xD6\xB4\x46\x02\x00\x21\x01\x16\x00\x00\x00\x74\x2F\xE5\xA3\x01\x00\x00\x61\x00\x00\x00\x00\x05\x2B\x65\x2E\x77\x84\x02\x33\x00\x01\x19\x01\xA5\x2C\x81\xCC\x1F\xB6\xF3\x7D\x01\x00\x00\x00\x00\x04\x59\x5A"
  let dec = decode_xz(enc[:], 128UL * 1024UL * 1024UL, false)
  assert_eq(dec, b"a")
}

///|
test "decode_liblzma_run_xz" {
  let enc = b"\xFD\x37\x7A\x58\x5A\x00\x00\x04\xE6\xD6\xB4\x46\x02\x00\x21\x01\x16\x00\x00\x00\x74\x2F\xE5\xA3\xE0\x00\x3F\x00\x06\x5D\x00\x55\x6E\x56\x00\x00\x00\x00\x00\x00\xB7\xF7\x11\x92\xE3\x9F\xF8\x9F\x00\x01\x22\x40\x9B\xB2\xE8\xF1\x1F\xB6\xF3\x7D\x01\x00\x00\x00\x00\x04\x59\x5A"
  let dec = decode_xz(enc[:], 128UL * 1024UL * 1024UL, false)
  assert_eq(dec, Bytes::make(64, b'\xAA'))
}

///|
test "xz_trailing_bytes_are_rejected" {
  let enc = encode_xz(b"x"[:], 3, 0, 2, 4096U)
  let arr = Array::new(capacity=enc.length() + 1)
  for b in enc[:] {
    arr.push(b)
  }
  arr.push(b'\x00')
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_unknown_check_id_is_rejected" {
  let err = @test.expect_error(() => {
    encode_xz(b"x"[:], 3, 0, 2, 4096U, check_id=2) |> ignore
  })
  assert_true(err is @coder.Unsupported)
}

///|
test "xz_index_record_must_match_block" {
  let enc = encode_xz(b"idx"[:], 3, 0, 2, 4096U)
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  let n = arr.length()
  let backward = arr[n - 8].to_int().reinterpret_as_uint() |
    (arr[n - 7].to_int().reinterpret_as_uint() << 8) |
    (arr[n - 6].to_int().reinterpret_as_uint() << 16) |
    (arr[n - 5].to_int().reinterpret_as_uint() << 24)
  let index_total = (backward.reinterpret_as_int() + 1) * 4
  let index_start = n - 12 - index_total
  let crc_off = n - 16
  arr[index_start + 2] = (arr[index_start + 2].to_int() ^ 1).to_byte()
  let body = Bytes::from_array(arr[index_start:crc_off])
  let crc = @checksum.crc32(body[:])
  arr[crc_off] = (crc & 0xFFU).reinterpret_as_int().to_byte()
  arr[crc_off + 1] = ((crc >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  arr[crc_off + 2] = ((crc >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  arr[crc_off + 3] = ((crc >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_compressed_size_must_match_payload" {
  let enc = encode_xz(b"csz"[:], 3, 0, 2, 4096U)
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  let hs = arr[12].to_int()
  let header_len = (hs + 1) * 4
  let hdr_end = 12 + header_len - 4
  assert_eq(arr[13], b'\xC0')
  assert_true(arr[14].to_int() < 0x80)
  arr[14] = (arr[14].to_int() + 1).to_byte()
  let hdr = Bytes::from_array(arr[12:hdr_end])
  let crc = @checksum.crc32(hdr[:])
  arr[hdr_end] = (crc & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 1] = ((crc >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 2] = ((crc >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 3] = ((crc >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_uncompressed_size_must_match_plain" {
  let enc = encode_xz(b"usz"[:], 3, 0, 2, 4096U)
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  let hs = arr[12].to_int()
  let header_len = (hs + 1) * 4
  let hdr_end = 12 + header_len - 4
  assert_eq(arr[13], b'\xC0')
  assert_true(arr[14].to_int() < 0x80)
  assert_true(arr[15].to_int() < 0x80)
  arr[15] = (arr[15].to_int() + 1).to_byte()
  let hdr = Bytes::from_array(arr[12:hdr_end])
  let crc = @checksum.crc32(hdr[:])
  arr[hdr_end] = (crc & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 1] = ((crc >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 2] = ((crc >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 3] = ((crc >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_block_header_padding_must_be_zero" {
  let enc = encode_xz(b"pad"[:], 3, 0, 2, 4096U)
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  let hs = arr[12].to_int()
  let header_len = (hs + 1) * 4
  let hdr_end = 12 + header_len - 4
  assert_true(hdr_end > 18)
  assert_eq(arr[hdr_end - 1], b'\x00')
  arr[hdr_end - 1] = b'\x01'
  let hdr = Bytes::from_array(arr[12:hdr_end])
  let crc = @checksum.crc32(hdr[:])
  arr[hdr_end] = (crc & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 1] = ((crc >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 2] = ((crc >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 3] = ((crc >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_sha256_check_flag_is_unsupported" {
  let enc = encode_xz(b"x"[:], 3, 0, 2, 4096U)
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  arr[7] = b'\x0A'
  let flags = Bytes::from_array([arr[6], arr[7]][:])
  let crc = @checksum.crc32(flags[:])
  arr[8] = (crc & 0xFFU).reinterpret_as_int().to_byte()
  arr[9] = ((crc >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  arr[10] = ((crc >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  arr[11] = ((crc >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Unsupported)
}

///|
test "xz_footer_crc_mismatch_is_data" {
  let enc = encode_xz(b"fcrc"[:], 3, 0, 2, 4096U)
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  let n = arr.length()
  arr[n - 12] = (arr[n - 12].to_int() ^ 1).to_byte()
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_backward_size_mismatch_is_data" {
  let enc = encode_xz(b"bwd"[:], 3, 0, 2, 4096U)
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  let n = arr.length()
  arr[n - 8] = (arr[n - 8].to_int() ^ 1).to_byte()
  let fb = Bytes::from_array(arr[n - 8:n - 2])
  let crc = @checksum.crc32(fb[:])
  arr[n - 12] = (crc & 0xFFU).reinterpret_as_int().to_byte()
  arr[n - 11] = ((crc >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  arr[n - 10] = ((crc >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  arr[n - 9] = ((crc >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_stream_flags_reserved_is_data" {
  let enc = encode_xz(b"flg"[:], 3, 0, 2, 4096U)
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  arr[6] = b'\x01'
  let flags = Bytes::from_array([arr[6], arr[7]][:])
  let crc = @checksum.crc32(flags[:])
  arr[8] = (crc & 0xFFU).reinterpret_as_int().to_byte()
  arr[9] = ((crc >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  arr[10] = ((crc >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  arr[11] = ((crc >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_two_filters_are_unsupported" {
  let enc = encode_xz(b"flt"[:], 3, 0, 2, 4096U)
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  let hs = arr[12].to_int()
  let header_len = (hs + 1) * 4
  let hdr_end = 12 + header_len - 4
  assert_eq(arr[13], b'\xC0')
  arr[13] = b'\xC1'
  let hdr = Bytes::from_array(arr[12:hdr_end])
  let crc = @checksum.crc32(hdr[:])
  arr[hdr_end] = (crc & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 1] = ((crc >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 2] = ((crc >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 3] = ((crc >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Unsupported)
}

///|
test "xz_block_flags_reserved_is_data" {
  let enc = encode_xz(b"rsv"[:], 3, 0, 2, 4096U)
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  let hs = arr[12].to_int()
  let header_len = (hs + 1) * 4
  let hdr_end = 12 + header_len - 4
  arr[13] = b'\xC4'
  let hdr = Bytes::from_array(arr[12:hdr_end])
  let crc = @checksum.crc32(hdr[:])
  arr[hdr_end] = (crc & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 1] = ((crc >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 2] = ((crc >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 3] = ((crc >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_footer_flags_must_match_header" {
  let enc = encode_xz(b"ff"[:], 3, 0, 2, 4096U)
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  let n = arr.length()
  arr[n - 3] = (arr[n - 3].to_int() ^ 1).to_byte()
  let fb = Bytes::from_array(arr[n - 8:n - 2])
  let crc = @checksum.crc32(fb[:])
  arr[n - 12] = (crc & 0xFFU).reinterpret_as_int().to_byte()
  arr[n - 11] = ((crc >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  arr[n - 10] = ((crc >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  arr[n - 9] = ((crc >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_index_padding_must_be_zero" {
  let enc = encode_xz(Bytes::make(200, b'\x01')[:], 3, 0, 2, 4096U)
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  let n = arr.length()
  let backward = arr[n - 8].to_int().reinterpret_as_uint() |
    (arr[n - 7].to_int().reinterpret_as_uint() << 8) |
    (arr[n - 6].to_int().reinterpret_as_uint() << 16) |
    (arr[n - 5].to_int().reinterpret_as_uint() << 24)
  let index_total = (backward.reinterpret_as_int() + 1) * 4
  let index_start = n - 12 - index_total
  let crc_off = n - 16
  assert_eq(arr[crc_off - 1], b'\x00')
  arr[crc_off - 1] = b'\x01'
  let body = Bytes::from_array(arr[index_start:crc_off])
  let crc = @checksum.crc32(body[:])
  arr[crc_off] = (crc & 0xFFU).reinterpret_as_int().to_byte()
  arr[crc_off + 1] = ((crc >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  arr[crc_off + 2] = ((crc >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  arr[crc_off + 3] = ((crc >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_footer_magic_must_be_yz" {
  let enc = encode_xz(b"yz2"[:], 3, 0, 2, 4096U)
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  let n = arr.length()
  arr[n - 1] = (arr[n - 1].to_int() ^ 1).to_byte()
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_block_padding_must_be_zero" {
  let mut found = false
  let mut n = 1
  while n <= 48 && found == false {
    let buf = Array::new(capacity=n)
    for _ in 0..<n {
      buf.push(n.to_byte())
    }
    let enc = encode_xz(Bytes::from_array(buf[:])[:], 3, 0, 2, 4096U)
    let arr = Array::new(capacity=enc.length())
    for b in enc[:] {
      arr.push(b)
    }
    let mut i = 14
    let mut payload_len = 0
    let mut shift = 0
    for _ in 0..<9 {
      let b = arr[i].to_int()
      i = i + 1
      payload_len = payload_len | ((b & 0x7F) << shift)
      if (b & 0x80) == 0 {
        break
      }
      shift = shift + 7
    }
    let pad = (4 - payload_len % 4) % 4
    if pad > 0 {
      let hs = arr[12].to_int()
      let header_len = (hs + 1) * 4
      let payload_start = 12 + header_len + 4
      arr[payload_start + payload_len] = b'\x01'
      let err = @test.expect_error(() => {
        decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false)
        |> ignore
      })
      assert_true(err is @coder.Data)
      found = true
    }
    n = n + 1
  }
  assert_true(found)
}

///|
test "xz_index_record_count_must_be_one" {
  let enc = encode_xz(b"nrec"[:], 3, 0, 2, 4096U)
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  let n = arr.length()
  let backward = arr[n - 8].to_int().reinterpret_as_uint() |
    (arr[n - 7].to_int().reinterpret_as_uint() << 8) |
    (arr[n - 6].to_int().reinterpret_as_uint() << 16) |
    (arr[n - 5].to_int().reinterpret_as_uint() << 24)
  let index_total = (backward.reinterpret_as_int() + 1) * 4
  let index_start = n - 12 - index_total
  let crc_off = n - 16
  assert_eq(arr[index_start], b'\x00')
  assert_eq(arr[index_start + 1], b'\x01')
  arr[index_start + 1] = b'\x02'
  let body = Bytes::from_array(arr[index_start:crc_off])
  let crc = @checksum.crc32(body[:])
  arr[crc_off] = (crc & 0xFFU).reinterpret_as_int().to_byte()
  arr[crc_off + 1] = ((crc >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  arr[crc_off + 2] = ((crc >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  arr[crc_off + 3] = ((crc >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_unknown_check_id_on_decode_is_unsupported" {
  let enc = encode_xz(b"cid"[:], 3, 0, 2, 4096U)
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  arr[7] = b'\x02'
  let flags = Bytes::from_array([arr[6], arr[7]][:])
  let crc = @checksum.crc32(flags[:])
  arr[8] = (crc & 0xFFU).reinterpret_as_int().to_byte()
  arr[9] = ((crc >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  arr[10] = ((crc >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  arr[11] = ((crc >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Unsupported)
}
