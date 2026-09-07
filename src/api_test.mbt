///|
test "preset_rejects_out_of_range" {
  let err = @test.expect_error(() => Preset::new(10) |> ignore)
  assert_true(err is InvalidConfiguration(_))
}

///|
test "encode_rejects_auto_format" {
  let err = @test.expect_error(() => {
    encode(b"x"[:], options={
      ..EncodeOptions::default(),
      format: Format::Auto,
    })
    |> ignore
  })
  assert_true(err is InvalidConfiguration(_))
}

///|
test "invalid_lc_lp_is_rejected" {
  let err = @test.expect_error(() => {
    encode(b""[:], options={
      ..EncodeOptions::default(),
      format: Format::Lzma,
      props: Some({ lc: 3, lp: 2, pb: 2, dict_size: MIN_DICT_SIZE, }),
    })
    |> ignore
  })
  assert_true(err is InvalidConfiguration(_))
}

///|
test "encode_decode_xz_roundtrip" {
  let src = b"hello xz"
  let enc = encode(src[:])
  let dec = decode(enc[:])
  assert_eq(dec, src)
}

///|
test "encode_decode_lzma_roundtrip" {
  let src = b"hello lzma alone"
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let dec = decode(enc[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  assert_eq(dec, src)
}

///|
test "stream_chunked_decode" {
  let src = b"chunked streaming"
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let dec = Decoder::new(options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  let mut i = 0
  while i < enc.length() {
    dec.write(enc[i:i + 1]) |> ignore
    i = i + 1
  }
  assert_eq(dec.finish(), src)
}

///|
test "stream_chunked_xz_decode" {
  let src = b"chunked xz stream"
  let enc = encode(src[:])
  let dec = Decoder::new()
  let mut i = 0
  while i < enc.length() {
    dec.write(enc[i:i + 1]) |> ignore
    i = i + 1
  }
  assert_eq(dec.finish(), src)
}

///|
test "stream_chunked_lzma2_decode" {
  let src = b"chunked lzma2"
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma2,
  })
  let dec = Decoder::new(options={
    ..DecodeOptions::default(),
    format: Format::Lzma2,
  })
  let mut i = 0
  while i < enc.length() {
    dec.write(enc[i:i + 1]) |> ignore
    i = i + 1
  }
  assert_eq(dec.finish(), src)
}

///|
test "pack_unpack_props_roundtrip" {
  let b = pack_props(3, 0, 2)
  let (lc, lp, pb) = unpack_props(b)
  assert_eq(lc, 3)
  assert_eq(lp, 0)
  assert_eq(pb, 2)
}

///|
test "default_encode_options_are_xz_preset6_crc64" {
  let o = EncodeOptions::default()
  assert_eq(o.format, Format::Xz)
  assert_eq(o.preset.level, 6)
  assert_eq(o.check, Check::Crc64)
}

///|
test "effective_memlimit_default_is_128mib" {
  assert_eq(effective_memlimit(None), DEFAULT_MEMLIMIT)
}

///|
test "filter_spec_variants_exist" {
  let props : LzmaProps = { lc: 3, lp: 0, pb: 2, dict_size: MIN_DICT_SIZE, }
  ignore(FilterSpec::Lzma1(props))
  ignore(FilterSpec::Lzma2(props))
  ignore(FilterSpec::Delta(distance=1))
  ignore(FilterSpec::BcjX86(start_offset=0U))
}

///|
test "root_reexports_crc32" {
  assert_eq(crc32(b"123456789"[:]), 0xCBF43926U)
}

///|
test "encode_decode_lzma2_roundtrip" {
  let src = b"hello lzma2 root"
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma2,
  })
  let dec = decode(enc[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma2,
  })
  assert_eq(dec, src)
}

///|
test "auto_detects_lzma_alone" {
  let src = b"auto lzma"
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  assert_eq(decode(enc[:]), src)
}

///|
test "encode_is_deterministic" {
  let src = b"same in same out"
  let a = encode(src[:])
  let b = encode(src[:])
  assert_eq(a, b)
}

///|
test "sha256_check_is_unsupported" {
  let err = @test.expect_error(() => {
    encode(b"x"[:], options={
      ..EncodeOptions::default(),
      check: Check::Sha256,
    })
    |> ignore
  })
  assert_true(err is UnsupportedFeature(_))
}

///|
test "concatenated_is_unsupported" {
  let enc = encode(b"x"[:])
  let err = @test.expect_error(() => {
    decode(enc[:], options={ ..DecodeOptions::default(), concatenated: true, })
    |> ignore
  })
  assert_true(err is UnsupportedFeature(_))
}

///|
test "memlimit_rejects_small_budget" {
  let enc = encode(b"x"[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
    props: Some({ lc: 3, lp: 0, pb: 2, dict_size: MIN_DICT_SIZE, }),
  })
  let err = @test.expect_error(() => {
    decode(enc[:], options={
      ..DecodeOptions::default(),
      format: Format::Lzma,
      memlimit: Some(100UL),
    })
    |> ignore
  })
  assert_true(err is MemoryLimit)
}

///|
test "delta_filter_lzma_roundtrip" {
  let src = b"\x01\x02\x03\x04\x05\x06"
  let filters = [FilterSpec::Delta(distance=1)]
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
    filters,
  })
  let dec = decode(enc[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
    filters,
  })
  assert_eq(dec, src)
}

///|
test "stream_code_one_byte_output" {
  let src = b"outbuf"
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let dec = Decoder::new(options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  let slot = Array::make(1, b'\x00')
  let out : OutputBuf = { data: slot, start: 0, }
  let first = dec.code(enc[:], out, Action::Finish)
  assert_eq(first.produced, 1)
  assert_eq(first.status, NeedOutput)
  let collected = Array::new()
  collected.push(slot[0])
  while true {
    out.start = 0
    let step = dec.code(b""[:], out, Action::Run)
    if step.produced > 0 {
      collected.push(slot[0])
    }
    if step.status is StreamEnd {
      break
    }
    assert_eq(step.status, NeedOutput)
  }
  assert_eq(Bytes::from_array(collected[:]), src)
}

///|
test "encoder_code_finish_roundtrip" {
  let src = b"encoder code"
  let encoder = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let buf = Array::make(4096, b'\x00')
  let out : OutputBuf = { data: buf, start: 0, }
  let r = encoder.code(src[:], out, Action::Finish)
  assert_true(r.status is StreamEnd || r.status is NeedOutput)
  let compressed = out.written()
  let dec = decode(compressed[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  assert_eq(dec, src)
}

///|
test "mixed_bytes_lzma_roundtrip" {
  let arr = Array::new(capacity=256)
  let mut x = 1
  for _ in 0..<256 {
    x = (x * 1103515245 + 12345) & 0x7FFFFFFF
    arr.push((x & 0xFF).to_byte())
  }
  let src = Bytes::from_array(arr[:])
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let dec = decode(enc[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  assert_eq(dec, src)
}

///|
test "xz_format_mismatch_is_format_error" {
  let err = @test.expect_error(() => {
    decode(b"notxz!"[:], options={
      ..DecodeOptions::default(),
      format: Format::Xz,
    })
    |> ignore
  })
  assert_true(err is FormatError)
}

///|
test "lzma_format_rejects_xz_magic" {
  let enc = encode(b"x"[:])
  let err = @test.expect_error(() => {
    decode(enc[:], options={ ..DecodeOptions::default(), format: Format::Lzma, })
    |> ignore
  })
  assert_true(err is FormatError)
}

///|
test "empty_input_is_eof" {
  let err = @test.expect_error(() => decode(b""[:]) |> ignore)
  assert_true(err is UnexpectedEof)
}

///|
test "sync_flush_is_rejected" {
  let enc = Encoder::new()
  let out = OutputBuf::new(size=16)
  let err = @test.expect_error(() => {
    enc.code(b"x"[:], out, Action::SyncFlush) |> ignore
  })
  assert_true(err is InvalidConfiguration(_))
}

///|
test "full_flush_is_rejected" {
  let enc = Encoder::new()
  let out = OutputBuf::new(size=16)
  let err = @test.expect_error(() => {
    enc.code(b"x"[:], out, Action::FullFlush) |> ignore
  })
  assert_true(err is InvalidConfiguration(_))
}

///|
test "decoder_full_flush_is_rejected" {
  let dec = Decoder::new()
  let out = OutputBuf::new(size=16)
  let err = @test.expect_error(() => {
    dec.code(b"x"[:], out, Action::FullFlush) |> ignore
  })
  assert_true(err is InvalidConfiguration(_))
}

///|
test "empty_output_buf_is_too_small" {
  let src = b"hello"
  let encoder = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let out = OutputBuf::new()
  let err = @test.expect_error(() => {
    encoder.code(src[:], out, Action::Finish) |> ignore
  })
  assert_true(err is BufferTooSmall)
  assert_eq(encoder.total_in(), 0UL)
  let retry = OutputBuf::new(size=4096)
  let r = encoder.code(src[:], retry, Action::Finish)
  assert_eq(r.status, StreamEnd)
  let back = decode(retry.written()[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  assert_eq(back, src)
}

///|
test "output_buf_new_has_writable_slots" {
  let out = OutputBuf::new(size=8)
  assert_eq(out.remaining(), 8)
}

///|
test "check_none_xz_roundtrip" {
  let src = b"no check"
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    check: Check::None,
  })
  let dec = decode(enc[:])
  assert_eq(dec, src)
}

///|
test "check_crc32_xz_roundtrip" {
  let src = b"crc32 root"
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    check: Check::Crc32,
  })
  let dec = decode(enc[:])
  assert_eq(dec, src)
}

///|
test "ignore_check_still_decodes_valid" {
  let src = b"ignore me"
  let enc = encode(src[:])
  let ok = decode(enc[:], options={
    ..DecodeOptions::default(),
    ignore_check: true,
  })
  assert_eq(ok, src)
}

///|
test "finish_twice_is_rejected" {
  let enc = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  enc.write(b"x"[:])
  ignore(enc.finish())
  let err = @test.expect_error(() => enc.finish() |> ignore)
  assert_true(err is InvalidConfiguration(_))
}

///|
test "decoder_new_rejects_zero_memlimit" {
  let err = @test.expect_error(() => {
    Decoder::new(options={ ..DecodeOptions::default(), memlimit: Some(0UL), })
    |> ignore
  })
  assert_true(err is InvalidConfiguration(_))
}

///|
test "corrupt_xz_header_crc" {
  let enc = encode(b"x"[:])
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  arr[8] = (arr[8].to_int() ^ 1).to_byte()
  let err = @test.expect_error(() => {
    decode(Bytes::from_array(arr[:])[:]) |> ignore
  })
  assert_true(err is DataError)
}

///|
test "extreme_preset_is_unsupported" {
  let err = @test.expect_error(() => Preset::new(6, extreme=true) |> ignore)
  assert_true(err is UnsupportedFeature(_))
}

///|
test "unpack_props_rejects_out_of_range" {
  let err = @test.expect_error(() => unpack_props(b'\xE1') |> ignore)
  assert_true(err is InvalidInput(_))
}

///|
test "unpack_props_rejects_lc_lp" {
  let err = @test.expect_error(() => unpack_props(b'\xE0') |> ignore)
  assert_true(err is InvalidInput(_))
}

///|
test "lzma2_format_rejects_xz_magic" {
  let enc = encode(b"x"[:])
  let err = @test.expect_error(() => {
    decode(enc[:], options={
      ..DecodeOptions::default(),
      format: Format::Lzma2,
    })
    |> ignore
  })
  assert_true(err is FormatError)
}

///|
test "bcj_filter_lzma_roundtrip" {
  let src = b"\xE8\x10\x00\x00\x00\x90\x90\x90"
  let filters = [FilterSpec::BcjX86(start_offset=0U)]
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
    filters,
  })
  let dec = decode(enc[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
    filters,
  })
  assert_eq(dec, src)
}

///|
test "truncated_xz_is_eof" {
  let enc = encode(b"hello"[:])
  let err = @test.expect_error(() => decode(enc[0:8]) |> ignore)
  assert_true(err is UnexpectedEof || err is FormatError || err is DataError)
}

///|
test "xz_trailing_garbage_is_data_error" {
  let enc = encode(b"x"[:])
  let arr = Array::new(capacity=enc.length() + 1)
  for b in enc[:] {
    arr.push(b)
  }
  arr.push(b'\x00')
  let err = @test.expect_error(() => {
    decode(Bytes::from_array(arr[:])[:]) |> ignore
  })
  assert_true(err is DataError)
}

///|
test "invalid_delta_distance_is_rejected" {
  let err = @test.expect_error(() => {
    encode(b"x"[:], options={
      ..EncodeOptions::default(),
      format: Format::Lzma,
      filters: [FilterSpec::Delta(distance=0)],
    })
    |> ignore
  })
  assert_true(err is InvalidConfiguration(_))
}

///|
test "codec_filter_in_chain_is_rejected" {
  let props : LzmaProps = { lc: 3, lp: 0, pb: 2, dict_size: MIN_DICT_SIZE, }
  let err = @test.expect_error(() => {
    encode(b"x"[:], options={
      ..EncodeOptions::default(),
      filters: [FilterSpec::Lzma2(props)],
    })
    |> ignore
  })
  assert_true(err is InvalidConfiguration(_))
}

///|
test "encoder_reset_allows_reuse" {
  let enc = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  enc.write(b"first"[:])
  ignore(enc.finish())
  enc.reset()
  enc.write(b"second"[:])
  let compressed = enc.finish()
  let dec = decode(compressed[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  assert_eq(dec, b"second")
}

///|
test "run_before_finish_returns_ok" {
  let enc = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let out = OutputBuf::new(size=16)
  let r = enc.code(b"x"[:], out, Action::Run)
  assert_eq(r.status, Ok)
  assert_eq(r.consumed, 1)
  assert_eq(r.produced, 0)
}

///|
test "decoder_new_rejects_concatenated" {
  let err = @test.expect_error(() => {
    Decoder::new(options={ ..DecodeOptions::default(), concatenated: true, })
    |> ignore
  })
  assert_true(err is UnsupportedFeature(_))
}

///|
test "ignore_check_accepts_bad_crc64" {
  let src = b"badcrc"
  let enc = encode(src[:])
  let want = crc64(src[:])
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  let mut i = 0
  let mut flipped = false
  while i + 8 <= arr.length() {
    let mut v = 0UL
    let mut s = 0
    while s < 8 {
      v = v | (arr[i + s].to_int().reinterpret_as_uint().to_uint64() << (s * 8))
      s = s + 1
    }
    if v == want {
      arr[i] = (arr[i].to_int() ^ 1).to_byte()
      flipped = true
      break
    }
    i = i + 1
  }
  assert_true(flipped)
  let mutated = Bytes::from_array(arr[:])
  let err = @test.expect_error(() => decode(mutated[:]) |> ignore)
  assert_true(err is DataError)
  let ok = decode(mutated[:], options={
    ..DecodeOptions::default(),
    ignore_check: true,
  })
  assert_eq(ok, src)
}

///|
test "stream_write_finish_delta" {
  let src = b"\x01\x02\x03\x04"
  let filters = [FilterSpec::Delta(distance=1)]
  let enc = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
    filters,
  })
  enc.write(src[:])
  let compressed = enc.finish()
  let dec = Decoder::new(options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
    filters,
  })
  dec.write(compressed[:])
  assert_eq(dec.finish(), src)
}

///|
test "auto_rejects_raw_lzma2" {
  let enc = encode(b"not alone"[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma2,
  })
  let err = @test.expect_error(() => decode(enc[:]) |> ignore)
  assert_true(err is FormatError)
}

///|
test "code_after_stream_end_is_rejected" {
  let encoder = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let out = OutputBuf::new(size=4096)
  let r = encoder.code(b"x"[:], out, Action::Finish)
  assert_eq(r.status, StreamEnd)
  let err = @test.expect_error(() => {
    encoder.code(b""[:], out, Action::Run) |> ignore
  })
  assert_true(err is InvalidConfiguration(_))
}

///|
test "decoder_code_one_byte_run_then_finish" {
  let src = b"code run chunks"
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let dec = Decoder::new(options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  let out = OutputBuf::new(size=64)
  let mut i = 0
  while i < enc.length() {
    let step = dec.code(enc[i:i + 1], out, Action::Run)
    assert_eq(step.status, Ok)
    assert_eq(step.consumed, 1)
    assert_eq(step.produced, 0)
    i = i + 1
  }
  let last = dec.code(b""[:], out, Action::Finish)
  assert_eq(last.status, StreamEnd)
  assert_eq(out.written(), src)
}

///|
test "xz_output_can_exceed_dict_memlimit" {
  let src = Bytes::make(8000, b'\x62')
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Xz,
    props: Some({ lc: 3, lp: 0, pb: 2, dict_size: MIN_DICT_SIZE, }),
  })
  let dec = decode(enc[:], options={
    ..DecodeOptions::default(),
    memlimit: Some(MIN_DICT_SIZE.to_uint64()),
  })
  assert_eq(dec, src)
}

///|
test "write_after_finish_is_rejected" {
  let enc = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  ignore(enc.finish())
  let err = @test.expect_error(() => enc.write(b"x"[:]))
  assert_true(err is InvalidConfiguration(_))
}

///|
test "finish_after_code_run" {
  let src = b"run then finish"
  let encoder = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let out = OutputBuf::new(size=16)
  ignore(encoder.code(src[:], out, Action::Run))
  let compressed = encoder.finish()
  let dec = decode(compressed[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  assert_eq(dec, src)
}

///|
test "delta_distance_256_roundtrip" {
  let src = Bytes::make(300, b'\x11')
  let filters = [FilterSpec::Delta(distance=256)]
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
    filters,
  })
  let dec = decode(enc[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
    filters,
  })
  assert_eq(dec, src)
}

///|
test "bcj_nonzero_start_offset_roundtrip" {
  let src = b"\xE8\x10\x00\x00\x00\x90\x90\x90"
  let filters = [FilterSpec::BcjX86(start_offset=0x1000U)]
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
    filters,
  })
  let dec = decode(enc[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
    filters,
  })
  assert_eq(dec, src)
}

///|
test "ignore_check_accepts_bad_crc32" {
  let src = b"crc32bad"
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    check: Check::Crc32,
  })
  let want = crc32(src[:])
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  let mut i = 0
  let mut flipped = false
  while i + 4 <= arr.length() {
    let v = arr[i].to_int().reinterpret_as_uint() |
      (arr[i + 1].to_int().reinterpret_as_uint() << 8) |
      (arr[i + 2].to_int().reinterpret_as_uint() << 16) |
      (arr[i + 3].to_int().reinterpret_as_uint() << 24)
    if v == want {
      arr[i] = (arr[i].to_int() ^ 1).to_byte()
      flipped = true
      break
    }
    i = i + 1
  }
  assert_true(flipped)
  let mutated = Bytes::from_array(arr[:])
  let err = @test.expect_error(() => decode(mutated[:]) |> ignore)
  assert_true(err is DataError)
  let ok = decode(mutated[:], options={
    ..DecodeOptions::default(),
    ignore_check: true,
  })
  assert_eq(ok, src)
}

///|
test "delta_then_bcj_roundtrip" {
  let src = b"\xE8\x01\x02\x03\x04\x90\x90\x90"
  let filters = [
    FilterSpec::Delta(distance=1),
    FilterSpec::BcjX86(start_offset=0U),
  ]
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
    filters,
  })
  let dec = decode(enc[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
    filters,
  })
  assert_eq(dec, src)
}

///|
test "xz_delta_filter_roundtrip" {
  let src = b"\x10\x11\x12\x13\x14"
  let filters = [FilterSpec::Delta(distance=1)]
  let enc = encode(src[:], options={ ..EncodeOptions::default(), filters, })
  let dec = decode(enc[:], options={ ..DecodeOptions::default(), filters, })
  assert_eq(dec, src)
}

///|
test "no_input_after_finish_while_draining" {
  let src = b"drain"
  let encoder = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let out = OutputBuf::new(size=1)
  let first = encoder.code(src[:], out, Action::Finish)
  assert_eq(first.status, NeedOutput)
  let err = @test.expect_error(() => {
    encoder.code(b"x"[:], out, Action::Run) |> ignore
  })
  assert_true(err is InvalidConfiguration(_))
}

///|
test "encode_rejects_preset_level_in_struct" {
  let err = @test.expect_error(() => {
    encode(b"x"[:], options={
      ..EncodeOptions::default(),
      preset: { level: 10, extreme: false, },
    })
    |> ignore
  })
  assert_true(err is InvalidConfiguration(_))
}

///|
test "decoder_no_input_after_finish_while_draining" {
  let src = b"drain2"
  let compressed = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let dec = Decoder::new(options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  let out = OutputBuf::new(size=1)
  let first = dec.code(compressed[:], out, Action::Finish)
  assert_eq(first.status, NeedOutput)
  let err = @test.expect_error(() => {
    dec.code(b"x"[:], out, Action::Run) |> ignore
  })
  assert_true(err is InvalidConfiguration(_))
}

///|
test "write_then_code_finish" {
  let src = b"written"
  let encoder = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  encoder.write(src[:])
  let out = OutputBuf::new(size=4096)
  let r = encoder.code(b""[:], out, Action::Finish)
  assert_eq(r.status, StreamEnd)
  let dec = decode(out.written()[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  assert_eq(dec, src)
}

///|
test "encoder_total_in_out" {
  let src = b"ab"
  let enc = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  enc.write(src[:])
  let compressed = enc.finish()
  assert_eq(enc.total_in(), 2UL)
  assert_eq(
    enc.total_out(),
    compressed.length().reinterpret_as_uint().to_uint64(),
  )
}

///|
test "output_buf_invalid_start" {
  let enc = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let out : OutputBuf = { data: Array::make(4, b'\x00'), start: -1, }
  let err = @test.expect_error(() => {
    enc.code(b"x"[:], out, Action::Finish) |> ignore
  })
  assert_true(err is BufferTooSmall)
}

///|
test "output_buf_start_past_end" {
  let enc = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let out : OutputBuf = { data: Array::make(4, b'\x00'), start: 5, }
  let err = @test.expect_error(() => {
    enc.code(b"x"[:], out, Action::Finish) |> ignore
  })
  assert_true(err is BufferTooSmall)
}

///|
test "lzma_invalid_props_is_format_error" {
  let err = @test.expect_error(() => {
    decode(b"\xE1\x00\x00\x10\x00\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF"[:], options={
      ..DecodeOptions::default(),
      format: Format::Lzma,
    })
    |> ignore
  })
  assert_true(err is FormatError)
}

///|
test "finish_returns_remaining_after_need_output" {
  let src = b"need output rest"
  let encoder = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let out = OutputBuf::new(size=1)
  let first = encoder.code(src[:], out, Action::Finish)
  assert_eq(first.status, NeedOutput)
  let rest = encoder.finish()
  let head = out.written()
  let arr = Array::new(capacity=head.length() + rest.length())
  for b in head[:] {
    arr.push(b)
  }
  for b in rest[:] {
    arr.push(b)
  }
  let compressed = Bytes::from_array(arr[:])
  let dec = decode(compressed[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  assert_eq(dec, src)
  assert_eq(
    encoder.total_out(),
    compressed.length().reinterpret_as_uint().to_uint64(),
  )
}

///|
test "finish_after_stream_end_is_rejected" {
  let encoder = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let out = OutputBuf::new(size=4096)
  let r = encoder.code(b"x"[:], out, Action::Finish)
  assert_eq(r.status, StreamEnd)
  let err = @test.expect_error(() => encoder.finish() |> ignore)
  assert_true(err is InvalidConfiguration(_))
}

///|
test "decoder_finish_returns_remaining" {
  let src = b"dec rest"
  let compressed = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let dec = Decoder::new(options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  let out = OutputBuf::new(size=1)
  let first = dec.code(compressed[:], out, Action::Finish)
  assert_eq(first.status, NeedOutput)
  let rest = dec.finish()
  let head = out.written()
  let arr = Array::new(capacity=head.length() + rest.length())
  for b in head[:] {
    arr.push(b)
  }
  for b in rest[:] {
    arr.push(b)
  }
  assert_eq(Bytes::from_array(arr[:]), src)
}

///|
test "decoder_total_in_out" {
  let src = b"xy"
  let compressed = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let dec = Decoder::new(options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  dec.write(compressed[:])
  let plain = dec.finish()
  assert_eq(plain, src)
  assert_eq(
    dec.total_in(),
    compressed.length().reinterpret_as_uint().to_uint64(),
  )
  assert_eq(dec.total_out(), 2UL)
}

///|
test "empty_xz_roundtrip" {
  let enc = encode(b""[:])
  assert_eq(decode(enc[:]), b"")
}

///|
test "lzma_truncated_header_is_eof" {
  let err = @test.expect_error(() => {
    decode(b"\x5D\x00"[:], options={
      ..DecodeOptions::default(),
      format: Format::Lzma,
    })
    |> ignore
  })
  assert_true(err is UnexpectedEof)
}

///|
test "decoder_reset_allows_reuse" {
  let a = encode(b"first"[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let b = encode(b"second"[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let dec = Decoder::new(options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  dec.write(a[:])
  assert_eq(dec.finish(), b"first")
  dec.reset()
  dec.write(b[:])
  assert_eq(dec.finish(), b"second")
}

///|
test "from_preset_level_6_dict" {
  let p = LzmaProps::from_preset(Preset::default())
  assert_eq(p.lc, 3)
  assert_eq(p.lp, 0)
  assert_eq(p.pb, 2)
  assert_eq(p.dict_size, 8388608U)
}

///|
test "from_preset_rejects_bad_level" {
  let err = @test.expect_error(() => {
    LzmaProps::from_preset({ level: 10, extreme: false, }) |> ignore
  })
  assert_true(err is InvalidConfiguration(_))
}

///|
test "from_preset_rejects_extreme" {
  let err = @test.expect_error(() => {
    LzmaProps::from_preset({ level: 6, extreme: true, }) |> ignore
  })
  assert_true(err is UnsupportedFeature(_))
}

///|
test "xz_truncated_is_eof" {
  let err = @test.expect_error(() => {
    decode(b"\xFD\x37\x7A"[:], options={
      ..DecodeOptions::default(),
      format: Format::Xz,
    })
    |> ignore
  })
  assert_true(err is UnexpectedEof)
}

///|
test "xz_empty_explicit_is_eof" {
  let err = @test.expect_error(() => {
    decode(b""[:], options={ ..DecodeOptions::default(), format: Format::Xz, })
    |> ignore
  })
  assert_true(err is UnexpectedEof)
}

///|
test "auto_truncated_xz_prefix_is_eof" {
  let err = @test.expect_error(() => {
    decode(b"\xFD\x37\x7A\x58\x5A"[:]) |> ignore
  })
  assert_true(err is UnexpectedEof)
}

///|
test "auto_xz_magic_only_is_eof" {
  let err = @test.expect_error(() => {
    decode(b"\xFD\x37\x7A\x58\x5A\x00"[:]) |> ignore
  })
  assert_true(err is UnexpectedEof)
}

///|
test "xz_magic_only_is_eof" {
  let err = @test.expect_error(() => {
    decode(b"\xFD\x37\x7A\x58\x5A\x00"[:], options={
      ..DecodeOptions::default(),
      format: Format::Xz,
    })
    |> ignore
  })
  assert_true(err is UnexpectedEof)
}

///|
test "auto_truncated_lzma_header_is_eof" {
  let err = @test.expect_error(() => decode(b"\x5D\x00\x10"[:]) |> ignore)
  assert_true(err is UnexpectedEof)
}

///|
test "lzma_header_size_too_large_is_data" {
  let src = b"hello"
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let arr = Array::new(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  arr[5] = b'\x64'
  arr[6] = b'\x00'
  arr[7] = b'\x00'
  arr[8] = b'\x00'
  arr[9] = b'\x00'
  arr[10] = b'\x00'
  arr[11] = b'\x00'
  arr[12] = b'\x00'
  let err = @test.expect_error(() => {
    decode(Bytes::from_array(arr[:])[:], options={
      ..DecodeOptions::default(),
      format: Format::Lzma,
    })
    |> ignore
  })
  assert_true(err is DataError)
}

///|
test "pack_props_rejects_invalid" {
  let err = @test.expect_error(() => pack_props(3, 2, 2) |> ignore)
  assert_true(err is InvalidConfiguration(_))
}

///|
test "unknown_size_constant" {
  assert_eq(UNKNOWN_SIZE, 0xFFFF_FFFF_FFFF_FFFFUL)
}

///|
test "output_buf_negative_size_is_empty" {
  let out = OutputBuf::new(size=-3)
  assert_eq(out.remaining(), 0)
}

///|
test "preset_0_dict_size" {
  let p = LzmaProps::from_preset(Preset::new(0))
  assert_eq(p.dict_size, 262144U)
}

///|
test "encoder_finish_twice_is_rejected" {
  let enc = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  ignore(enc.finish())
  let err = @test.expect_error(() => enc.finish() |> ignore)
  assert_true(err is InvalidConfiguration(_))
}

///|
test "decoder_finish_twice_is_rejected" {
  let compressed = encode(b"x"[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let dec = Decoder::new(options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  dec.write(compressed[:])
  ignore(dec.finish())
  let err = @test.expect_error(() => dec.finish() |> ignore)
  assert_true(err is InvalidConfiguration(_))
}

///|
test "xz_header_dict_over_memlimit" {
  let enc = encode(b"x"[:])
  let err = @test.expect_error(() => {
    decode(enc[:], options={
      ..DecodeOptions::default(),
      memlimit: Some(MIN_DICT_SIZE.to_uint64()),
    })
    |> ignore
  })
  assert_true(err is MemoryLimit)
}

///|
test "lzma2_empty_input_is_eof" {
  let err = @test.expect_error(() => {
    decode(b""[:], options={
      ..DecodeOptions::default(),
      format: Format::Lzma2,
    })
    |> ignore
  })
  assert_true(err is UnexpectedEof)
}

///|
test "lzma2_end_marker_only_is_empty" {
  let dec = decode(b"\x00"[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma2,
  })
  assert_eq(dec, b"")
}

///|
test "reset_after_need_output" {
  let src = b"after reset"
  let encoder = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let out = OutputBuf::new(size=1)
  let first = encoder.code(src[:], out, Action::Finish)
  assert_eq(first.status, NeedOutput)
  encoder.reset()
  encoder.write(src[:])
  let compressed = encoder.finish()
  let back = decode(compressed[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  assert_eq(back, src)
}

///|
test "decoder_sync_flush_is_rejected" {
  let dec = Decoder::new()
  let out = OutputBuf::new(size=16)
  let err = @test.expect_error(() => {
    dec.code(b"x"[:], out, Action::SyncFlush) |> ignore
  })
  assert_true(err is InvalidConfiguration(_))
}

///|
test "decoder_write_after_finish_is_rejected" {
  let compressed = encode(b"x"[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let dec = Decoder::new(options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  dec.write(compressed[:])
  ignore(dec.finish())
  let err = @test.expect_error(() => dec.write(b"y"[:]))
  assert_true(err is InvalidConfiguration(_))
}

///|
test "lzma_encode_ignores_check_field" {
  let src = b"check ignored"
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
    check: Check::Crc32,
  })
  let back = decode(enc[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  assert_eq(back, src)
}

///|
test "decode_rejects_zero_memlimit" {
  let err = @test.expect_error(() => {
    decode(b""[:], options={ ..DecodeOptions::default(), memlimit: Some(0UL), })
    |> ignore
  })
  assert_true(err is InvalidConfiguration(_))
}

///|
test "lzma_empty_input_is_eof" {
  let err = @test.expect_error(() => {
    decode(b""[:], options={ ..DecodeOptions::default(), format: Format::Lzma, })
    |> ignore
  })
  assert_true(err is UnexpectedEof)
}

///|
test "xz_bcj_filter_roundtrip" {
  let src = b"\xE8\x10\x00\x00\x00\x90\x90\x90"
  let filters = [FilterSpec::BcjX86(start_offset=0U)]
  let enc = encode(src[:], options={ ..EncodeOptions::default(), filters, })
  let back = decode(enc[:], options={ ..DecodeOptions::default(), filters, })
  assert_eq(back, src)
}

///|
test "preset_dict_sizes" {
  let shifts = [18, 20, 21, 22, 22, 23, 23, 24, 25, 26]
  let mut level = 0
  while level <= 9 {
    let p = LzmaProps::from_preset(Preset::new(level))
    assert_eq(p.dict_size, 1U << shifts[level])
    level = level + 1
  }
}

///|
test "decoder_empty_output_retries" {
  let src = b"retry"
  let compressed = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let dec = Decoder::new(options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  let empty = OutputBuf::new()
  let err = @test.expect_error(() => {
    dec.code(compressed[:], empty, Action::Finish) |> ignore
  })
  assert_true(err is BufferTooSmall)
  assert_eq(dec.total_in(), 0UL)
  let out = OutputBuf::new(size=4096)
  let r = dec.code(compressed[:], out, Action::Finish)
  assert_eq(r.status, StreamEnd)
  assert_eq(out.written(), src)
}

///|
test "auto_decodes_liblzma_empty_xz" {
  let enc = b"\xFD\x37\x7A\x58\x5A\x00\x00\x04\xE6\xD6\xB4\x46\x00\x00\x00\x00\x1C\xDF\x44\x21\x1F\xB6\xF3\x7D\x01\x00\x00\x00\x00\x04\x59\x5A"
  assert_eq(decode(enc[:]), b"")
}

///|
test "encoder_finish_empty_xz" {
  let enc = Encoder::new()
  let out = enc.finish()
  assert_eq(decode(out[:]), b"")
}

///|
test "lzma2_encode_ignores_check_field" {
  let src = b"lzma2 check"
  let enc = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Lzma2,
    check: Check::Crc32,
  })
  let back = decode(enc[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma2,
  })
  assert_eq(back, src)
}

///|
test "finish_full_output_returns_need_output" {
  let src = b"hello"
  let encoder = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let out = OutputBuf::new(size=4)
  out.start = 4
  let r = encoder.code(src[:], out, Action::Finish)
  assert_eq(r.status, NeedOutput)
  assert_eq(r.consumed, src.length())
  assert_eq(r.produced, 0)
  let drain = OutputBuf::new(size=4096)
  let r2 = encoder.code(b""[:], drain, Action::Finish)
  assert_eq(r2.status, StreamEnd)
  let back = decode(drain.written()[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  assert_eq(back, src)
}

///|
test "run_drains_after_need_output" {
  let src = b"drain-run"
  let encoder = Encoder::new(options={
    ..EncodeOptions::default(),
    format: Format::Lzma,
  })
  let head = OutputBuf::new(size=1)
  let first = encoder.code(src[:], head, Action::Finish)
  assert_eq(first.status, NeedOutput)
  let tail = OutputBuf::new(size=4096)
  let second = encoder.code(b""[:], tail, Action::Run)
  assert_eq(second.status, StreamEnd)
  let arr = Array::new()
  for b in head.written()[:] {
    arr.push(b)
  }
  for b in tail.written()[:] {
    arr.push(b)
  }
  let back = decode(Bytes::from_array(arr[:])[:], options={
    ..DecodeOptions::default(),
    format: Format::Lzma,
  })
  assert_eq(back, src)
}
