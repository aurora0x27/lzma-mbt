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

///|
fn push_u32_le(a : Array[Byte], v : UInt) -> Unit {
  a.push((v & 0xFFU).reinterpret_as_int().to_byte())
  a.push(((v >> 8) & 0xFFU).reinterpret_as_int().to_byte())
  a.push(((v >> 16) & 0xFFU).reinterpret_as_int().to_byte())
  a.push(((v >> 24) & 0xFFU).reinterpret_as_int().to_byte())
}

///|
/// Deterministic x86-laden payload exercising adjacent/overlapping E8/E9 with
/// 0x00/0xFF immediate top bytes (the MSByte / `prev_mask` state machine).
fn x86_bcj_plain() -> Bytes {
  let a = Array()
  let vals = [
    0U, 1U, 0xFFFFFFFFU, 5U, 0xFFFFFFFBU, 0x7FFFFFFFU, 0x80000000U, 100U, 0xFFFFFF9CU,
    0x10U, 0xFFFFFFF0U, 0x4000U,
  ]
  for i in 0..<60 {
    let op = if i % 2 == 0 { b'\xE8' } else { b'\xE9' }
    a.push(op)
    push_u32_le(a, vals[i % 12])
    for _ in 0..<(i % 3) {
      a.push(b'\x90')
    }
  }
  let seg = b"\xE8\xE8\x00\x00\x00\xE8\xE9\x00\x00\x00\xE9\xE8\xFF\xFF\xFF\x90\x90"
  for _ in 0..<40 {
    for b in seg[:] {
      a.push(b)
    }
  }
  for _ in 0..<3 {
    for n in 0..<256 {
      a.push(n.to_byte())
    }
  }
  Bytes::from_array(a[:])
}

///|
/// `xz --x86 --lzma2=preset=6 --check=crc64` of `x86_bcj_plain()`.
fn liblzma_x86_xz() -> Bytes {
  b"\xFD\x37\x7A\x58\x5A\x00\x00\x04\xE6\xD6\xB4\x46\x04\xC1\xBA\x04\x90\x0E\x04\x00\x21\x01\x16\x00\x00\x00\x00\x00\x3D\xCD\x40\x4E\xE0\x07\x0F\x02\x32\x5D\x00\x74\x01\x3C\x19\x3E\x07\xF0\xDD\xC3\x74\x0E\xEB\x71\x1F\xFC\x93\x7B\x44\x00\xBC\x62\x07\x0D\x5A\x11\x7B\x3F\xB4\xCC\x47\xA5\x06\x4B\x73\x52\x82\xC0\x73\xEE\x56\xAC\xA2\x25\x0C\x5E\xD8\xD2\xA6\xEB\xB1\x86\x3A\xB6\x3E\x77\x80\xB4\x2A\xD5\x2C\xB8\x7B\x07\x10\x2F\xA2\x92\x0F\xEE\x8D\x8E\xB7\x91\xDB\xC0\xDF\xC4\xB4\x7B\xEE\xEB\xFC\x97\x6C\xF7\xE7\xFD\x2E\xA7\xDB\x9F\x1B\xCC\x9A\x01\x23\x84\xC4\x03\x8D\x3F\xE3\xDF\x49\xAA\xDA\x07\x09\xB3\x29\x69\x5E\x64\xCB\xC5\x8A\x18\x8D\x42\xA2\x3E\xB2\x6C\xD8\x2D\xCD\x48\x43\xAB\x49\x03\x62\x8F\x88\xD3\x0A\x5A\x12\x2F\xC2\xDA\x62\x35\x0F\xAF\xBF\xD5\x37\xD3\xAB\x5E\x85\xBA\xB2\x00\xF6\xF7\x73\x60\xD0\x43\x90\x4A\x23\x61\x71\x93\x80\x13\x30\xF7\x31\x72\x81\x21\xBF\x46\x43\x97\x62\xD1\x38\xE7\xF9\x8F\xB1\x1E\x69\xE1\xFE\x60\x02\xAD\x4B\xD8\xF7\xBC\x09\xE3\x7B\x01\x47\xED\x3B\x55\xBA\x00\x2C\x9E\xDC\xBD\xA7\xCB\x83\x64\x54\xBD\x32\x63\x49\x3C\x80\xDF\xE6\x83\xB8\x0F\x04\x09\xDB\x9E\x2F\xBD\x4B\x1B\x89\x43\xF7\xAB\x7F\x88\x19\x08\x97\xA9\x44\x8D\x42\x11\xD1\x06\xFC\xAC\x20\xF8\x16\x35\x3E\x98\x33\x01\xB2\xBC\x53\xB3\x97\x7B\x4C\xE2\xC4\x26\x4D\x8C\xFC\xC5\x4E\xA9\x2F\x0D\xF5\xCC\x91\x88\x10\x2A\x37\x5E\xC0\xEF\x4C\x5B\x49\x1B\xE5\xBB\x74\x03\x47\x7C\xD3\xA7\x65\x80\xE2\xD2\xC9\x3A\xB1\x8A\x08\xF7\xAA\xF5\x28\xBF\xB2\xE0\x5A\xA3\x94\xD0\x91\x9E\xD9\xA0\x04\xAA\x7C\xBE\xF3\xC4\x35\x46\x58\xA3\x71\xB7\xA9\x04\x04\x96\x40\x6F\xD6\xFD\x31\x55\x5B\x06\x75\x33\xA6\x7F\xDE\xF9\x6D\xE6\x14\xFD\xDC\xB7\x06\x94\x27\x12\xE9\xAA\x8B\x89\x77\x74\xEA\x11\x2D\xAE\x46\xFF\x26\xB7\x46\x26\xA8\xAE\x37\x1A\x46\x19\x93\x67\xAE\xA4\xC5\x41\x9D\x2D\x73\xB4\x38\x8C\x13\xF0\x8F\x67\xA3\x22\x6A\xC0\xCA\x0C\x3F\xA3\x84\x79\x2F\x8A\xC2\xE8\x45\x00\xC8\x2F\x9A\x29\xBC\x5D\xAC\x97\x5F\xA3\xD7\x92\x1A\x5D\x59\xDA\xC2\xD7\x10\x44\xB6\x65\x12\xC8\xB7\xB5\x4E\x8F\x38\x6D\xA4\x96\x2C\x12\x5A\x7C\x1A\x18\xE5\x81\x54\x68\xEE\xB4\x48\xA2\xBF\xA4\x2A\x17\xA8\x91\x6A\xFA\xEF\x4E\x01\xA9\xD6\x53\xBA\xE5\xAC\xD5\x30\x3B\x92\xED\x61\x67\x6C\x52\x41\x05\x92\xA0\x47\x0B\xC9\x74\x6C\x4F\xC9\x63\x85\xCC\x9D\xD3\xCC\x85\x65\xE8\x63\xDC\x99\xEF\xF2\x9B\x6A\xF7\x8D\x8A\x8B\x91\xD0\x3E\xF7\x87\x89\xD4\x97\x24\xC0\xFB\x6F\x74\x77\x27\xD7\x2D\xA1\x6C\xA4\xB1\x3F\x06\xBF\x0B\x25\x4E\xEE\x4B\x21\x01\xE0\x5F\x84\xAC\x21\x02\xBF\x90\x00\x00\x00\x00\xBA\xFC\x5C\x30\xBE\x13\x9A\xE0\x00\x01\xD6\x04\x90\x0E\x00\x00\x81\x41\x6C\x45\xB1\xC4\x67\xFB\x02\x00\x00\x00\x00\x04\x59\x5A"
}

///|
test "decode_liblzma_x86_bcj_xz" {
  let src = x86_bcj_plain()
  assert_eq(src.length(), 1808)
  let enc = liblzma_x86_xz()
  assert_eq(decode_xz(enc[:], 128UL * 1024UL * 1024UL, false), src)
}

///|
test "xz_x86_bcj_self_roundtrip" {
  let src = x86_bcj_plain()
  let enc = encode_xz(src[:], 3, 0, 2, 65536U, check_id=4, bcj_x86=true)
  assert_eq(decode_xz(enc[:], 128UL * 1024UL * 1024UL, false), src)
  let arr = copy_bytes(enc)
  assert_eq(arr[13], b'\xC1')
  let x86 = find_x86_record(arr)
  assert_true(x86 >= 0)
  assert_eq(arr[x86 + 1], b'\x00')
  assert_eq(arr[find_filter_id(arr, b'\x21') + 1], b'\x01')
}

///|
test "xz_stream_decoder_x86_bcj_block" {
  let src = x86_bcj_plain()
  let enc = encode_xz(src[:], 3, 0, 2, 65536U, check_id=4, bcj_x86=true)
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
test "xz_stream_decoder_x86_reference_chunked" {
  let src = x86_bcj_plain()
  let enc = liblzma_x86_xz()
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
fn find_filter_id(arr : Array[Byte], id : Byte) -> Int {
  let hs = arr[12].to_int()
  let header_len = (hs + 1) * 4
  let hdr_end = 12 + header_len - 4
  let mut pos = -1
  let mut i = 14
  while i + 1 < hdr_end && pos < 0 {
    if arr[i] == id {
      pos = i
    }
    i = i + 1
  }
  pos
}

///|
/// x86 BCJ filter record in the Block Header is ID 0x04 with a zero-size
/// property, so locate the `04 00` pair rather than a bare 0x04 (the block's
/// VLI size fields can also contain the byte 0x04).
fn find_x86_record(arr : Array[Byte]) -> Int {
  let hs = arr[12].to_int()
  let header_len = (hs + 1) * 4
  let hdr_end = 12 + header_len - 4
  let mut pos = -1
  let mut i = 14
  while i + 1 < hdr_end && pos < 0 {
    if arr[i] == b'\x04' && arr[i + 1] == b'\x00' {
      pos = i
    }
    i = i + 1
  }
  pos
}

///|
/// Find a zero-property filter record (`<id> 00`) in the Block Header.
fn find_no_props_record(arr : Array[Byte], id : Byte) -> Int {
  let hs = arr[12].to_int()
  let header_len = (hs + 1) * 4
  let hdr_end = 12 + header_len - 4
  let mut pos = -1
  let mut i = 14
  while i + 1 < hdr_end && pos < 0 {
    if arr[i] == id && arr[i + 1] == b'\x00' {
      pos = i
    }
    i = i + 1
  }
  pos
}

///|
test "xz_x86_property_size_must_be_zero" {
  let enc = encode_xz(
    x86_bcj_plain()[:],
    3,
    0,
    2,
    4096U,
    check_id=1,
    bcj_x86=true,
  )
  let arr = copy_bytes(enc)
  let x86 = find_x86_record(arr)
  assert_true(x86 >= 0)
  assert_eq(arr[x86 + 1], b'\x00')
  arr[x86 + 1] = b'\x01'
  rewrite_block_header_crc(arr)
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_x86_must_not_be_last_filter" {
  let enc = encode_xz(b"tail"[:], 3, 0, 2, 4096U, check_id=1)
  let arr = copy_bytes(enc)
  let lzma2 = find_filter_id(arr, b'\x21')
  assert_true(lzma2 >= 0)
  arr[lzma2] = b'\x04'
  rewrite_block_header_crc(arr)
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_unknown_prefilter_is_unsupported" {
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
  let delta = find_filter_id(arr, b'\x03')
  assert_true(delta >= 0)
  arr[delta] = b'\x05'
  rewrite_block_header_crc(arr)
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Unsupported)
}

///|
/// Deterministic ARM-laden payload (32-bit words whose top byte is `0xEB`,
/// i.e. B/BL) with a trailing partial word.
fn arm_bcj_plain() -> Bytes {
  let a = Array()
  for k in 0..<300 {
    let off = (k.reinterpret_as_uint() * 0xABCDU) & 0xFFFFFFU
    push_u32_le(a, 0xEB000000U | off)
  }
  for k in 0..<60 {
    push_u32_le(a, 0xEBFFFFFFU)
    push_u32_le(a, 0x12345678U)
    push_u32_le(a, 0xE1A00000U + ((k.reinterpret_as_uint() * 7U) & 0xFFU))
  }
  a.push(b'\xEB')
  a.push(b'\x01')
  Bytes::from_array(a[:])
}

///|
/// `xz --arm --lzma2=preset=6 --check=crc64` of `arm_bcj_plain()`.
fn liblzma_arm_xz() -> Bytes {
  b"\xFD\x37\x7A\x58\x5A\x00\x00\x04\xE6\xD6\xB4\x46\x04\xC1\xA4\x08\x82\x0F\x07\x00\x21\x01\x16\x00\x00\x00\x00\x00\x8A\x0A\x49\xB3\xE0\x07\x81\x04\x1C\x5D\x00\x01\x00\x36\x12\x36\xEE\x67\x68\x3F\xA6\xC8\x9D\x70\x55\x79\xB2\xC5\x04\xE8\x63\x67\x92\x70\xAE\x6B\xF2\xBB\x96\xA9\x5C\xF2\xE5\x97\xCB\x08\xD8\xFD\x46\x6E\xF4\x0D\x12\x82\x3F\x0F\xB7\x37\x59\xB3\x9C\xD7\xAE\x7A\x84\x15\x35\x15\x3C\x7B\x85\xD5\xE1\x1C\x23\xD2\x4A\x37\x0C\x67\x8A\x08\x31\xBE\x58\xA6\xCC\x6C\x53\xB2\x42\x36\x31\xCE\x13\x7A\xF8\xB3\x73\xB9\x5B\xAA\x77\x48\x03\x86\xDA\x7A\xCB\x22\x7C\x67\x26\x55\xF0\x65\x31\xA6\x45\x10\xDD\xD5\xF5\x30\x86\xE1\x8E\x5D\x79\xAA\x0E\xBA\x52\xCB\xD2\x40\xC5\x32\x75\x2F\xBE\x8F\x1C\xC2\x00\x6A\x60\x1B\xE6\xF4\x8E\xC2\x87\x44\xA0\x51\xA6\x9A\x95\x52\x53\xB0\xF7\xD5\x86\x05\x01\x06\x9B\xA8\x7F\xFE\x0B\x78\x06\x67\xA0\xF8\x52\x59\x71\x0F\x65\xB4\xEB\xCB\x88\x78\xF8\xEC\x0E\xC3\xE4\xBD\x46\x30\x61\x4D\x6D\x9C\xE4\x38\xD7\x6D\xD1\x71\xB2\xA9\x1B\x68\x20\x04\xFA\x0A\x92\x0E\xE2\x1A\x87\x81\x20\x88\xF5\xE1\x89\x7F\xA1\x86\x71\x67\x15\xBC\x35\x8C\xC7\x46\x0D\x6D\x54\xB4\x6C\x59\x6A\xAB\x1E\xE0\xDB\x3C\xBF\xD0\x40\x32\x36\x25\x0E\x39\xA6\xC5\x01\xF2\x70\xC3\x6F\x24\x5F\x06\xFB\xBB\x0B\x30\x13\x74\x0A\xAD\x8D\xD6\xB2\x62\x91\x08\x33\x65\xA4\x73\x32\x73\x29\xFB\x8F\x11\x93\xCC\x7A\x0D\x6D\xE4\x71\xD2\xDA\xDE\x88\x24\xED\xF6\xF6\xE6\x18\x30\x5E\x61\xF1\x0C\x5C\x81\xA9\xB0\xD6\xEC\x11\x33\x89\xFF\x1E\x30\xA0\x14\xAC\xFF\x98\x15\x7B\x4A\x0A\x18\x64\xCF\x7B\x82\xDC\xF0\x0B\x9F\x85\x9C\xBE\x23\x68\xFF\xCE\x86\x9F\xF5\x2F\x22\x31\xD4\x2C\x55\x95\x60\x20\x8E\xB9\xB3\x1F\xE5\x61\x80\x6F\x10\x6B\x8B\x61\x2A\xA1\xAE\xB5\x71\x34\xD3\x12\x7F\x86\xC0\x89\x29\x33\x75\x11\x42\xCF\xBF\xBA\x18\xCF\x82\x3E\xB2\x8A\x9B\x55\xA2\xB2\x14\x2F\x6B\x9D\xDE\x1B\x10\x06\x4D\xB0\xDF\xB6\xF9\x4B\x38\x21\xBE\x97\x5E\xB9\x9C\xB0\xB7\x0A\xBE\x32\x60\x13\x3E\x65\x51\x23\x0D\xCC\x93\x45\xD9\x92\xA4\xF4\xFB\xA7\xD2\xAA\x8D\x96\x0F\x11\xD6\xE4\x37\x01\xB6\x1B\x2B\x73\x8C\xD2\x4C\xB2\x27\xDF\x38\xDD\x41\xE1\xC9\x58\xD3\x0F\xD4\x68\xE0\x6E\x83\x2F\x74\xDA\x0B\xCA\x85\xFE\x93\xA3\x28\xA6\x1F\xF7\x35\xE1\x72\xDA\xB3\xFD\x89\x34\x77\x0A\xD9\x9E\x00\xBE\x68\xB8\xED\xBC\x00\xB0\x1A\xC0\x45\x1E\xEC\x3A\xF9\x44\x01\x8C\xFF\xC8\x6B\x05\xE5\x44\xB8\x79\xCD\xAB\x43\x5B\xF9\x0D\xE9\x85\x40\xCE\xC9\xC7\xDF\x73\xCE\xA7\x7D\x7E\x7B\x76\xEE\x28\x76\x42\x0F\xBF\x4D\x23\x73\xB4\x64\xC2\xDA\x6A\xF7\x1D\xFE\x0E\x8F\x8E\xA3\xF5\x04\xEA\xB9\xEC\x6A\xE7\xE3\xDA\xFB\x75\xDB\xB6\x85\x2F\x60\xB5\xC8\x12\xE5\x86\x73\xF9\xA1\xC3\x06\x04\x73\xE6\x28\xE7\x6E\x91\xBF\x58\xAD\xF9\xCD\x6E\x57\xFE\xD8\x5A\x68\x88\x2F\xFD\xA7\x97\x7A\x12\xC8\x12\x06\x3F\xF1\x2F\x7E\xF2\x0C\x90\xAC\x6D\xB6\x40\xCF\xE0\x28\xFF\x27\x11\xD4\x45\x42\x28\x27\x7B\xBF\xCE\x42\x1A\x4C\x5E\x00\x81\xAD\xE1\x07\x12\xD3\xE4\xF4\x99\x9C\x9B\x7A\x67\xBA\x1D\x52\x26\xB1\xC2\x99\xD3\x12\x98\x76\x06\xB2\x66\x87\xA4\x97\xA1\xB6\x9E\x47\x28\xD7\x12\x09\x3C\xDC\x85\x3C\x23\x0F\xF1\xE7\x0C\x38\x10\x45\xCA\x2F\x59\xE3\x4E\xE6\xB8\x67\x9A\x69\x5A\x79\xB5\x31\x8E\x95\xB2\x8E\xB0\xFA\x19\xB1\x0A\x03\x35\x92\x78\x2B\x9B\xC1\xD2\x96\x58\x3B\x9F\x01\x92\x57\x03\x77\xD9\xFA\xAD\xE4\x0A\x20\xE4\x01\x8D\xAB\x8A\xCD\xED\x03\x4D\x19\x55\xC6\x38\xB6\x27\x44\x45\x3D\xF9\xA4\xCA\x82\x70\x62\x0E\x4B\xBE\xA6\xBB\x12\x2B\xB2\x09\x93\x1C\xC6\x1E\xFE\xC0\x48\xCA\xB8\x45\x74\x6B\x99\x0D\x68\x0B\x3C\xD4\xD2\x20\x6E\x04\x51\xA5\xDD\x58\x86\xAA\xCB\x96\x36\x37\xAF\x36\xF3\x9D\xD7\xC9\x48\xA9\xAA\x3D\x85\xF0\x34\x64\x17\x73\x51\xF4\xA4\x8C\x13\x8E\x2D\x6F\xC8\xA6\xED\x2D\x50\x1C\x84\x79\xC0\x63\xAE\x38\x26\x28\xA0\xC5\xA4\x1F\x5F\x83\x0B\x50\x9A\x5D\x27\x3C\x13\x2C\xAA\x81\x4C\x4D\xDF\xB0\xCD\xD9\xB6\x02\x54\xE1\x1A\x60\xCD\xF0\x9A\xA5\x5E\x34\x1D\x11\xBB\x2A\xC6\xC4\x27\x1D\x9E\x0E\xB6\xE0\x28\xC5\xCE\xB5\xA4\xAB\x6F\xEC\xDE\xB0\x48\x45\x03\x62\xC1\xCB\xA1\xA8\xE4\x02\x6A\xF5\x86\xEE\xCE\x2C\xD7\x55\xD0\xFE\xE3\x21\xAD\xDD\xCF\x51\x91\x96\xAF\x17\x8F\x6A\x55\x6E\xD4\x33\x70\xF6\x9D\x8E\xB3\x89\x09\xDB\xD3\xBE\x49\xC1\xB0\xAB\x2E\xA9\xB4\x3F\xED\xB6\xF3\x44\x64\xD4\x74\x7C\xB2\xE6\x1C\xD0\x52\x04\x37\xEC\x77\x7D\xDB\x1B\x53\x33\x7E\x21\x92\x4A\xB5\xA5\x15\xEF\x49\x79\x0E\x22\xB5\x79\xBA\x0D\x6A\x53\x4D\xA9\x48\x49\x9F\xBD\xF6\xC1\xD9\x6D\x68\x06\xFB\xCC\xC9\x39\xD2\x2E\xB4\xDE\xEB\xDE\xEA\x35\x85\x0F\x61\x37\x5F\x4A\xD4\xD7\x41\x47\xD6\xB7\xD0\x64\xC7\x09\xE0\x24\x9B\x82\x20\xC8\xCF\x4B\x47\x51\x05\x92\x6F\x27\x0A\xBF\x53\x8F\xAE\x14\x00\xFA\x5B\x06\x3F\x3A\x6E\xB1\x53\x00\x01\xC0\x08\x82\x0F\x00\x00\x25\xB8\xC1\xAE\xB1\xC4\x67\xFB\x02\x00\x00\x00\x00\x04\x59\x5A"
}

///|
test "decode_liblzma_arm_bcj_xz" {
  let src = arm_bcj_plain()
  assert_eq(src.length(), 1922)
  assert_eq(decode_xz(liblzma_arm_xz()[:], 128UL * 1024UL * 1024UL, false), src)
}

///|
test "xz_arm_bcj_self_roundtrip" {
  let src = arm_bcj_plain()
  let enc = encode_xz(src[:], 3, 0, 2, 65536U, check_id=4, bcj_arm=true)
  assert_eq(decode_xz(enc[:], 128UL * 1024UL * 1024UL, false), src)
  let arr = copy_bytes(enc)
  assert_eq(arr[13], b'\xC1')
  let arm = find_no_props_record(arr, b'\x07')
  assert_true(arm >= 0)
  assert_eq(arr[arm + 1], b'\x00')
}

///|
test "xz_stream_decoder_arm_bcj_block" {
  let src = arm_bcj_plain()
  let enc = encode_xz(src[:], 3, 0, 2, 65536U, check_id=4, bcj_arm=true)
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
test "xz_arm_property_size_must_be_zero" {
  let enc = encode_xz(
    arm_bcj_plain()[:],
    3,
    0,
    2,
    4096U,
    check_id=1,
    bcj_arm=true,
  )
  let arr = copy_bytes(enc)
  let arm = find_no_props_record(arr, b'\x07')
  assert_true(arm >= 0)
  assert_eq(arr[arm + 1], b'\x00')
  arr[arm + 1] = b'\x01'
  rewrite_block_header_crc(arr)
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_arm_must_not_be_last_filter" {
  let enc = encode_xz(b"tail"[:], 3, 0, 2, 4096U, check_id=1)
  let arr = copy_bytes(enc)
  let lzma2 = find_filter_id(arr, b'\x21')
  assert_true(lzma2 >= 0)
  arr[lzma2] = b'\x07'
  rewrite_block_header_crc(arr)
  let err = @test.expect_error(() => {
    decode_xz(Bytes::from_array(arr[:])[:], 1024UL * 1024UL, false) |> ignore
  })
  assert_true(err is @coder.Data)
}

///|
test "xz_encoder_rejects_multiple_prefilters" {
  let enc = @test.expect_error(() => {
    encode_xz(
      b"x"[:],
      3,
      0,
      2,
      4096U,
      check_id=1,
      delta_distance=1,
      bcj_arm=true,
    )
    |> ignore
  })
  assert_true(enc is @coder.Data)
  let enc2 = @test.expect_error(() => {
    encode_xz(b"x"[:], 3, 0, 2, 4096U, check_id=1, bcj_x86=true, bcj_arm=true)
    |> ignore
  })
  assert_true(enc2 is @coder.Data)
}
