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
test "xz_sha256_check_roundtrip" {
  let src = b"sha256 check"
  let enc = encode_xz(src[:], 3, 0, 2, 4096U, check_id=10)
  assert_eq(enc[7], b'\x0A')
  let dec = decode_xz(enc[:], 1024UL * 1024UL, false)
  assert_eq(dec, src)
}

///|
test "xz_sha256_empty_roundtrip" {
  let enc = encode_xz(b""[:], 3, 0, 2, 4096U, check_id=10)
  let dec = decode_xz(enc[:], 1024UL * 1024UL, false)
  assert_eq(dec, b"")
}

///|
test "xz_sha256_over_64k_roundtrip" {
  let src = Bytes::make(70000, b'\x5A')
  let enc = encode_xz(src[:], 3, 0, 2, 4096U, check_id=10)
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
  let arr = Array(capacity=enc.length())
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
fn liblzma_empty_xz() -> Bytes {
  b"\xFD\x37\x7A\x58\x5A\x00\x00\x04\xE6\xD6\xB4\x46\x00\x00\x00\x00\x1C\xDF\x44\x21\x1F\xB6\xF3\x7D\x01\x00\x00\x00\x00\x04\x59\x5A"
}

///|
fn liblzma_hello_xz() -> Bytes {
  b"\xFD\x37\x7A\x58\x5A\x00\x00\x04\xE6\xD6\xB4\x46\x02\x00\x21\x01\x16\x00\x00\x00\x74\x2F\xE5\xA3\x01\x00\x09\x68\x65\x6C\x6C\x6F\x20\x6C\x7A\x6D\x61\x00\x00\x00\xF7\x7B\xCD\xAC\x69\x58\xF9\xEB\x00\x01\x22\x0A\x15\x1A\xE1\x67\x1F\xB6\xF3\x7D\x01\x00\x00\x00\x00\x04\x59\x5A"
}

///|
test "decode_liblzma_empty_xz" {
  let enc = liblzma_empty_xz()
  let dec = decode_xz(enc[:], 128UL * 1024UL * 1024UL, false)
  assert_eq(dec, b"")
}

///|
test "decode_liblzma_hello_xz" {
  let enc = liblzma_hello_xz()
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
test "xz_stream_decoder_delta_payload_chunks" {
  let src = b"delta history crosses payload chunks"
  let enc = encode_xz(src[:], 3, 0, 2, 4096U, delta_distance=3)
  let dec = StreamDecoder::new(128UL * 1024UL * 1024UL, false)
  let got : Array[Byte] = []
  let mut i = 0
  while i < enc.length() {
    let (part, _) = dec.feed(enc[i:i + 1])
    for b in part[:] {
      got.push(b)
    }
    i = i + 1
  }
  assert_eq(Bytes::from_array(got[:]), src)
}

///|
test "xz_trailing_bytes_are_rejected" {
  let enc = encode_xz(b"x"[:], 3, 0, 2, 4096U)
  let arr = Array(capacity=enc.length() + 1)
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
  let arr = Array(capacity=enc.length())
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
  let arr = Array(capacity=enc.length())
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
  let arr = Array(capacity=enc.length())
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
  let arr = Array(capacity=enc.length())
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
test "xz_footer_crc_mismatch_is_data" {
  let enc = encode_xz(b"fcrc"[:], 3, 0, 2, 4096U)
  let arr = Array(capacity=enc.length())
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
  let arr = Array(capacity=enc.length())
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
  let arr = Array(capacity=enc.length())
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
  let arr = Array(capacity=enc.length())
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
  let arr = Array(capacity=enc.length())
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
  let arr = Array(capacity=enc.length())
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
  let arr = Array(capacity=enc.length())
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
  let arr = Array(capacity=enc.length())
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
    let buf = Array(capacity=n)
    for _ in 0..<n {
      buf.push(n.to_byte())
    }
    let enc = encode_xz(Bytes::from_array(buf[:])[:], 3, 0, 2, 4096U)
    let arr = Array(capacity=enc.length())
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
  let arr = Array(capacity=enc.length())
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
  let arr = Array(capacity=enc.length())
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

///|
/// `xz --block-size=2 --check=crc32 --lzma2=preset=0` of `"aabb"` (2 Blocks).
/// Block 2 starts at offset 36 (header 12, payload 6, pad 2, CRC32 4).
fn liblzma_two_block_xz() -> Bytes {
  b"\xFD\x37\x7A\x58\x5A\x00\x00\x01\x69\x22\xDE\x36\x02\xC0\x06\x02\x21\x01\x0C\x00\x82\x1A\x7A\xF2\x01\x00\x01\x61\x61\x00\x00\x00\xD7\x19\x8A\x07\x02\xC0\x06\x02\x21\x01\x0C\x00\x82\x1A\x7A\xF2\x01\x00\x01\x62\x62\x00\x00\x00\xAE\x1B\xAE\xB5\x00\x02\x16\x02\x16\x02\x00\x00\x8B\xA0\x04\x2B\x3E\x30\x0D\x8B\x02\x00\x00\x00\x00\x01\x59\x5A"
}

///|
/// Same encoder settings as `liblzma_two_block_xz`, plaintext `"aabbcc"` (3 Blocks).
fn liblzma_three_block_xz() -> Bytes {
  b"\xFD\x37\x7A\x58\x5A\x00\x00\x01\x69\x22\xDE\x36\x02\xC0\x06\x02\x21\x01\x0C\x00\x82\x1A\x7A\xF2\x01\x00\x01\x61\x61\x00\x00\x00\xD7\x19\x8A\x07\x02\xC0\x06\x02\x21\x01\x0C\x00\x82\x1A\x7A\xF2\x01\x00\x01\x62\x62\x00\x00\x00\xAE\x1B\xAE\xB5\x02\xC0\x06\x02\x21\x01\x0C\x00\x82\x1A\x7A\xF2\x01\x00\x01\x63\x63\x00\x00\x00\x79\x1A\xB2\xDB\x00\x03\x16\x02\x16\x02\x16\x02\xC4\x7F\xE5\x7F\x3E\x30\x0D\x8B\x02\x00\x00\x00\x00\x01\x59\x5A"
}

///|
/// `xz --check=sha256 --lzma2=preset=0` of `"sha256 reference"`.
fn liblzma_sha256_xz() -> Bytes {
  b"\xFD\x37\x7A\x58\x5A\x00\x00\x0A\xE1\xFB\x0C\xA1\x03\xC0\x14\x10\x21\x01\x0C\x00\x00\x00\x00\x00\x0B\xF2\x0E\xCB\x01\x00\x0F\x73\x68\x61\x32\x35\x36\x20\x72\x65\x66\x65\x72\x65\x6E\x63\x65\x00\x2A\x3E\xEB\xBA\x6D\xE2\x16\x82\xED\x96\xFD\x93\xE5\x83\x19\xF7\x85\xFD\xBC\xCF\xC0\xBE\xE5\x7C\xCA\x82\x95\x68\x6C\x6A\xC7\xC2\x00\x01\x44\x10\x4E\x2F\x24\xA9\x18\x9B\x4B\x9A\x01\x00\x00\x00\x00\x0A\x59\x5A"
}

///|
/// `xz --check=crc32 --delta=dist=1 --lzma2=preset=0` of `"abcdefabcdef"`.
fn liblzma_delta_dist1_xz() -> Bytes {
  b"\xFD\x37\x7A\x58\x5A\x00\x00\x01\x69\x22\xDE\x36\x04\xC1\x12\x0C\x03\x01\x00\x21\x01\x0C\x00\x00\x00\x00\x00\x00\xFC\xE7\xFB\x30\xE0\x00\x0B\x00\x0A\x5D\x00\x30\x80\x70\x9F\x60\x1D\x21\x00\x00\x00\x00\x00\x00\x66\xE9\xE4\x71\x00\x01\x2A\x0C\x28\x35\x5B\x46\x90\x42\x99\x0D\x01\x00\x00\x00\x00\x01\x59\x5A"
}

///|
/// `xz --check=crc32 --delta=dist=4 --lzma2=preset=0` of `"abcdefabcdef"`.
fn liblzma_delta_dist4_xz() -> Bytes {
  b"\xFD\x37\x7A\x58\x5A\x00\x00\x01\x69\x22\xDE\x36\x04\xC1\x10\x0C\x03\x01\x03\x21\x01\x0C\x00\x00\x00\x00\x00\x00\x52\x98\xA2\x3A\x01\x00\x0B\x61\x62\x63\x64\x04\x04\xFE\xFE\xFE\xFE\x04\x04\x00\x66\xE9\xE4\x71\x00\x01\x28\x0C\xAA\x57\x6D\x74\x90\x42\x99\x0D\x01\x00\x00\x00\x00\x01\x59\x5A"
}

///|
/// `xz --check=crc32 --delta=dist=256 --lzma2=preset=0` of `"abcdefabcdef"`.
fn liblzma_delta_dist256_xz() -> Bytes {
  b"\xFD\x37\x7A\x58\x5A\x00\x00\x01\x69\x22\xDE\x36\x04\xC1\x10\x0C\x03\x01\xFF\x21\x01\x0C\x00\x00\x00\x00\x00\x00\x45\xF4\xD2\x30\x01\x00\x0B\x61\x62\x63\x64\x65\x66\x61\x62\x63\x64\x65\x66\x00\x66\xE9\xE4\x71\x00\x01\x28\x0C\xAA\x57\x6D\x74\x90\x42\x99\x0D\x01\x00\x00\x00\x00\x01\x59\x5A"
}

///|
fn copy_bytes(enc : Bytes) -> Array[Byte] {
  let arr = Array(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  arr
}

///|
fn xz_index_start(arr : Array[Byte]) -> Int {
  let n = arr.length()
  let backward = arr[n - 8].to_int().reinterpret_as_uint() |
    (arr[n - 7].to_int().reinterpret_as_uint() << 8) |
    (arr[n - 6].to_int().reinterpret_as_uint() << 16) |
    (arr[n - 5].to_int().reinterpret_as_uint() << 24)
  let index_total = (backward.reinterpret_as_int() + 1) * 4
  n - 12 - index_total
}

///|
fn concat_views(a : BytesView, b : BytesView) -> Bytes {
  let arr = Array(capacity=a.length() + b.length())
  for x in a {
    arr.push(x)
  }
  for x in b {
    arr.push(x)
  }
  Bytes::from_array(arr[:])
}

///|
fn concat3_views(a : BytesView, b : BytesView, c : BytesView) -> Bytes {
  concat_views(concat_views(a, b)[:], c)
}

///|
fn padding(n : Int) -> Bytes {
  Bytes::make(n, b'\x00')
}

///|
fn rewrite_block_header_crc(arr : Array[Byte]) -> Unit {
  let hs = arr[12].to_int()
  let header_len = (hs + 1) * 4
  let hdr_end = 12 + header_len - 4
  let hdr = Bytes::from_array(arr[12:hdr_end])
  let crc = @checksum.crc32(hdr[:])
  arr[hdr_end] = (crc & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 1] = ((crc >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 2] = ((crc >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  arr[hdr_end + 3] = ((crc >> 24) & 0xFFU).reinterpret_as_int().to_byte()
}

///|
fn find_filter(arr : Array[Byte], id : Byte) -> Int {
  let hs = arr[12].to_int()
  let header_len = (hs + 1) * 4
  let hdr_end = 12 + header_len - 4
  let mut pos = -1
  let mut i = 14
  while i + 1 < hdr_end && pos < 0 {
    if arr[i] == id && arr[i + 1] == b'\x01' {
      pos = i
    }
    i = i + 1
  }
  pos
}

///|
fn rewrite_index_crc(arr : Array[Byte]) -> Unit {
  let n = arr.length()
  let backward = arr[n - 8].to_int().reinterpret_as_uint() |
    (arr[n - 7].to_int().reinterpret_as_uint() << 8) |
    (arr[n - 6].to_int().reinterpret_as_uint() << 16) |
    (arr[n - 5].to_int().reinterpret_as_uint() << 24)
  let index_total = (backward.reinterpret_as_int() + 1) * 4
  let index_start = n - 12 - index_total
  let crc_off = n - 16
  let body = Bytes::from_array(arr[index_start:crc_off])
  let crc = @checksum.crc32(body[:])
  arr[crc_off] = (crc & 0xFFU).reinterpret_as_int().to_byte()
  arr[crc_off + 1] = ((crc >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  arr[crc_off + 2] = ((crc >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  arr[crc_off + 3] = ((crc >> 24) & 0xFFU).reinterpret_as_int().to_byte()
}

///|
test "decode_liblzma_two_block_xz" {
  let enc = liblzma_two_block_xz()
  assert_eq(enc[60], b'\x00')
  assert_eq(enc[61], b'\x02')
  assert_eq(enc[62], b'\x16')
  assert_eq(enc[63], b'\x02')
  assert_eq(enc[64], b'\x16')
  assert_eq(enc[65], b'\x02')
  let dec = decode_xz(enc[:], 128UL * 1024UL * 1024UL, false)
  assert_eq(dec, b"aabb")
}

///|
test "decode_liblzma_three_block_xz" {
  let enc = liblzma_three_block_xz()
  assert_eq(enc[84], b'\x00')
  assert_eq(enc[85], b'\x03')
  let dec = decode_xz(enc[:], 128UL * 1024UL * 1024UL, false)
  assert_eq(dec, b"aabbcc")
}

///|
test "xz_encoder_writes_one_index_record" {
  let enc = encode_xz(Bytes::make(80, b'a')[:], 3, 0, 2, 4096U)
  let arr = copy_bytes(enc)
  let n = arr.length()
  let backward = arr[n - 8].to_int().reinterpret_as_uint() |
    (arr[n - 7].to_int().reinterpret_as_uint() << 8) |
    (arr[n - 6].to_int().reinterpret_as_uint() << 16) |
    (arr[n - 5].to_int().reinterpret_as_uint() << 24)
  let index_total = (backward.reinterpret_as_int() + 1) * 4
  let index_start = n - 12 - index_total
  assert_eq(arr[index_start], b'\x00')
  assert_eq(arr[index_start + 1], b'\x01')
}

///|
test "xz_multi_block_index_nrec_mismatch" {
  let arr = copy_bytes(liblzma_two_block_xz())
  assert_eq(arr[61], b'\x02')
  arr[61] = b'\x01'
  rewrite_index_crc(arr)
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_multi_block_index_size_mismatch" {
  let arr = copy_bytes(liblzma_two_block_xz())
  assert_eq(arr[65], b'\x02')
  arr[65] = b'\x03'
  rewrite_index_crc(arr)
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_second_block_header_truncated" {
  let enc = liblzma_two_block_xz()
  let err = @test.expect_error(() => {
    decode_xz(enc[0:37], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Eof)
}

///|
test "xz_second_block_data_truncated" {
  let enc = liblzma_two_block_xz()
  let err = @test.expect_error(() => {
    decode_xz(enc[0:51], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Eof)
}

///|
test "xz_second_block_check_truncated" {
  let enc = liblzma_two_block_xz()
  let err = @test.expect_error(() => {
    decode_xz(enc[0:57], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Eof)
}

///|
test "xz_concatenated_two_streams" {
  let a = encode_xz(b"alpha"[:], 3, 0, 2, 4096U)
  let b = encode_xz(b"beta"[:], 3, 0, 2, 4096U)
  let enc = concat_views(a[:], b[:])
  let dec = decode_xz(enc[:], 128UL * 1024UL * 1024UL, false, concatenated=true)
  assert_eq(dec, b"alphabeta")
}

///|
test "xz_concatenated_padding_between_streams" {
  let a = encode_xz(b"a"[:], 3, 0, 2, 4096U)
  let b = encode_xz(b"b"[:], 3, 0, 2, 4096U)
  let four = concat3_views(a[:], padding(4)[:], b[:])
  let eight = concat3_views(a[:], padding(8)[:], b[:])
  assert_eq(
    decode_xz(four[:], 128UL * 1024UL * 1024UL, false, concatenated=true),
    b"ab",
  )
  assert_eq(
    decode_xz(eight[:], 128UL * 1024UL * 1024UL, false, concatenated=true),
    b"ab",
  )
}

///|
test "xz_concatenated_three_streams_and_empty_stream" {
  let empty = encode_xz(b""[:], 3, 0, 2, 4096U)
  let a = encode_xz(b"A"[:], 3, 0, 2, 4096U)
  let b = encode_xz(b"B"[:], 3, 0, 2, 4096U)
  let enc = concat3_views(empty[:], a[:], b[:])
  let dec = decode_xz(enc[:], 128UL * 1024UL * 1024UL, false, concatenated=true)
  assert_eq(dec, b"AB")
}

///|
test "xz_concatenated_liblzma_streams" {
  let enc = concat3_views(
    liblzma_empty_xz()[:],
    padding(4)[:],
    liblzma_hello_xz()[:],
  )
  let dec = decode_xz(enc[:], 128UL * 1024UL * 1024UL, false, concatenated=true)
  assert_eq(dec, b"hello lzma")
}

///|
test "xz_concatenated_false_rejects_next_stream" {
  let a = encode_xz(b"a"[:], 3, 0, 2, 4096U)
  let b = encode_xz(b"b"[:], 3, 0, 2, 4096U)
  let enc = concat_views(a[:], b[:])
  let err = @test.expect_error(() => {
    decode_xz(enc[:], 128UL * 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_concatenated_rejects_bad_padding" {
  let a = encode_xz(b"a"[:], 3, 0, 2, 4096U)
  let b = encode_xz(b"b"[:], 3, 0, 2, 4096U)
  let bad = concat3_views(a[:], b"\x00\x00\x00\x01"[:], b[:])
  let err = @test.expect_error(() => {
    decode_xz(bad[:], 128UL * 1024UL * 1024UL, false, concatenated=true)
    |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_concatenated_rejects_padding_not_multiple_of_four" {
  let a = encode_xz(b"a"[:], 3, 0, 2, 4096U)
  let b = encode_xz(b"b"[:], 3, 0, 2, 4096U)
  for n in 1..<=5 {
    if n != 4 {
      let enc = concat3_views(a[:], padding(n)[:], b[:])
      let err = @test.expect_error(() => {
        decode_xz(enc[:], 128UL * 1024UL * 1024UL, false, concatenated=true)
        |> ignore
      })
      assert_true(err is @coder.Data)
    }
  }
}

///|
test "xz_concatenated_next_stream_header_truncated" {
  let a = encode_xz(b"a"[:], 3, 0, 2, 4096U)
  let magic = b"\xFD\x37\x7A\x58\x5A\x00"
  for n in 1..<=5 {
    let enc = concat_views(a[:], magic[0:n])
    let err = @test.expect_error(() => {
      decode_xz(enc[:], 128UL * 1024UL * 1024UL, false, concatenated=true)
      |> ignore
    })
    assert_true(err is @coder.Eof)
  }
}

///|
test "decode_liblzma_sha256_xz" {
  let dec = decode_xz(liblzma_sha256_xz()[:], 128UL * 1024UL * 1024UL, false)
  assert_eq(dec, b"sha256 reference")
}

///|
test "xz_sha256_check_field_is_32_bytes" {
  let src = b"sha256 field"
  let arr = copy_bytes(encode_xz(src[:], 3, 0, 2, 4096U, check_id=10))
  let index_start = xz_index_start(arr)
  let check_start = index_start - 32
  assert_eq(
    Bytes::from_array(arr[check_start:index_start]),
    @checksum.sha256(src[:]),
  )
}

///|
test "xz_sha256_check_mismatch_is_data" {
  let arr = copy_bytes(encode_xz(b"sha256 bad"[:], 3, 0, 2, 4096U, check_id=10))
  let index_start = xz_index_start(arr)
  arr[index_start - 1] = (arr[index_start - 1].to_int() ^ 1).to_byte()
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_ignore_check_accepts_bad_sha256" {
  let src = b"sha256 ignore"
  let arr = copy_bytes(encode_xz(src[:], 3, 0, 2, 4096U, check_id=10))
  let index_start = xz_index_start(arr)
  arr[index_start - 1] = (arr[index_start - 1].to_int() ^ 1).to_byte()
  let dec = decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, true)
  assert_eq(dec, src)
}

///|
test "xz_sha256_check_truncated" {
  let arr = copy_bytes(
    encode_xz(b"sha256 trunc"[:], 3, 0, 2, 4096U, check_id=10),
  )
  let index_start = xz_index_start(arr)
  let err = @test.expect_error(() => {
    decode_xz(
      Bytes::from_array(arr[0:index_start - 1])[:],
      1024UL * 1024UL,
      false,
    )
    |> ignore
  })
  assert_true(err is @coder.Eof)
}

///|
test "xz_delta_filter_roundtrip_distances" {
  let src = b"abcdefabcdef"
  for distance in [1, 4, 256] {
    let enc = encode_xz(
      src[:],
      3,
      0,
      2,
      4096U,
      check_id=1,
      delta_distance=distance,
    )
    let dec = decode_xz(enc[:], 1024UL * 1024UL, false)
    assert_eq(dec, src)
    let arr = copy_bytes(enc)
    let delta = find_filter(arr, b'\x03')
    assert_true(delta >= 0)
    assert_eq(arr[delta + 2], (distance - 1).to_byte())
  }
}

///|
test "decode_liblzma_delta_xz_distances" {
  let src = b"abcdefabcdef"
  assert_eq(decode_xz(liblzma_delta_dist1_xz()[:], 1024UL * 1024UL, false), src)
  assert_eq(decode_xz(liblzma_delta_dist4_xz()[:], 1024UL * 1024UL, false), src)
  assert_eq(
    decode_xz(liblzma_delta_dist256_xz()[:], 1024UL * 1024UL, false),
    src,
  )
}

///|
test "xz_delta_distance_property_256_is_ff" {
  let enc = encode_xz(
    b"abcdefabcdef"[:],
    3,
    0,
    2,
    4096U,
    check_id=1,
    delta_distance=256,
  )
  let arr = copy_bytes(enc)
  let delta = find_filter(arr, b'\x03')
  assert_true(delta >= 0)
  assert_eq(arr[delta + 2], b'\xFF')
}

///|
test "xz_delta_encode_rejects_invalid_distance" {
  let high = @test.expect_error(() => {
    encode_xz(b"x"[:], 3, 0, 2, 4096U, check_id=1, delta_distance=257) |> ignore
  })
  assert_true(high is @coder.Data)
  let neg = @test.expect_error(() => {
    encode_xz(b"x"[:], 3, 0, 2, 4096U, check_id=1, delta_distance=-1) |> ignore
  })
  assert_true(neg is @coder.Data)
}

///|
test "xz_delta_property_size_must_be_one" {
  let enc = encode_xz(
    b"abcdefabcdef"[:],
    3,
    0,
    2,
    4096U,
    check_id=1,
    delta_distance=4,
  )
  let arr = copy_bytes(enc)
  let delta = find_filter(arr, b'\x03')
  assert_true(delta >= 0)
  arr[delta + 1] = b'\x00'
  rewrite_block_header_crc(arr)
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_delta_must_not_be_last_filter" {
  let enc = encode_xz(b"tail"[:], 3, 0, 2, 4096U, check_id=1)
  let arr = copy_bytes(enc)
  let lzma2 = find_filter(arr, b'\x21')
  assert_true(lzma2 >= 0)
  arr[lzma2] = b'\x03'
  rewrite_block_header_crc(arr)
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_three_filter_chains_are_unsupported" {
  let enc = encode_xz(
    b"abcdefabcdef"[:],
    3,
    0,
    2,
    4096U,
    check_id=1,
    delta_distance=4,
  )
  let arr = copy_bytes(enc)
  arr[13] = b'\xC2'
  rewrite_block_header_crc(arr)
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Unsupported)
}
