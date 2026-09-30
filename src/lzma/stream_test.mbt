///|
fn lzma_stream_decode_chunks(
  chunks : Array[BytesView],
) -> Bytes raise @coder.CoderError {
  let dec = StreamDecoder::new(128UL * 1024UL * 1024UL)
  let out = Array()
  for c in chunks {
    let (part, _) = dec.feed(c[:])
    for b in part[:] {
      out.push(b)
    }
  }
  let rest = dec.finish()
  for b in rest[:] {
    out.push(b)
  }
  Bytes::from_array(out[:])
}

///|
fn lzma_split_every(data : Bytes, n : Int) -> Array[BytesView] {
  let parts = Array()
  let mut i = 0
  while i < data.length() {
    let end = if i + n > data.length() { data.length() } else { i + n }
    parts.push(data[i:end])
    i = i + n
  }
  parts
}

///|
test "lzma_stream_one_byte_chunks" {
  let src = b"lzma stream chunking"
  let enc = encode_alone(src[:], 3, 0, 2, 4096U)
  let got = lzma_stream_decode_chunks(lzma_split_every(enc, 1))
  assert_eq(got, src)
}

///|
test "lzma_stream_one_byte_chunks_over_64k" {
  let src = Bytes::make(70000, b'\x5A')
  let enc = encode_alone(src[:], 3, 0, 2, 4096U)
  let got = lzma_stream_decode_chunks(lzma_split_every(enc, 1))
  assert_eq(got, src)
}

///|
test "lzma_stream_header_split_everywhere" {
  let src = b"header boundaries"
  let enc = encode_alone(src[:], 3, 0, 2, 4096U)
  let mut n = 1
  while n <= 14 {
    let got = lzma_stream_decode_chunks(lzma_split_every(enc, n))
    assert_eq(got, src)
    n = n + 1
  }
}

///|
test "lzma_stream_unknown_size_uses_end_marker" {
  let src = b"unknown size stream"
  let enc = encode_alone(src[:], 3, 0, 2, 4096U)
  let arr = Array(capacity=enc.length())
  for b in enc[:] {
    arr.push(b)
  }
  // Zero the 8-byte uncompressed size field (offset 5) to the unknown marker.
  let mut k = 0
  while k < 8 {
    arr[5 + k] = b'\xFF'
    k = k + 1
  }
  let patched = Bytes::from_array(arr[:])
  assert_eq(decode_alone(patched[:], 128UL * 1024UL * 1024UL), src)
  let got = lzma_stream_decode_chunks(lzma_split_every(patched, 3))
  assert_eq(got, src)
}

///|
test "lzma_stream_random_chunks_equivalence" {
  let src = Bytes::make(2000, b'\x37')
  let enc = encode_alone(src[:], 3, 0, 2, 4096U)
  let mut seed = 12345U
  let mut iter = 0
  while iter < 60 {
    let parts = Array()
    let mut i = 0
    while i < enc.length() {
      seed = (seed * 1103515245U + 12345U) & 0x7FFFFFFFU
      let n = (seed % 7U).reinterpret_as_int() + 1
      let end = if i + n > enc.length() { enc.length() } else { i + n }
      parts.push(enc[i:end])
      i = end
    }
    assert_eq(lzma_stream_decode_chunks(parts), src)
    iter = iter + 1
  }
}

///|
test "lzma_stream_truncated_is_eof" {
  let src = b"truncated stream"
  let enc = encode_alone(src[:], 3, 0, 2, 4096U)
  let dec = StreamDecoder::new(128UL * 1024UL * 1024UL)
  let (_, _) = dec.feed(enc[0:10])
  let err = @test.expect_error(() => dec.finish() |> ignore)
  assert_true(err is @coder.Eof)
}

///|
test "lzma_stream_bad_props_is_data" {
  let dec = StreamDecoder::new(128UL * 1024UL * 1024UL)
  let header = b"\xE1\x00\x00\x10\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  let err = @test.expect_error(() => dec.feed(header[:]) |> ignore)
  assert_true(err is @coder.Data)
}

///|
test "lzma_stream_memlimit_is_limit" {
  let dec = StreamDecoder::new(100UL)
  let header = b"\x5D\x00\x00\x10\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  let err = @test.expect_error(() => dec.feed(header[:]) |> ignore)
  assert_true(err is @coder.Limit)
}

///|
test "lzma_stream_extra_after_end_is_data" {
  let src = b"end then extra"
  let enc = encode_alone(src[:], 3, 0, 2, 4096U)
  let got = lzma_stream_decode_chunks(lzma_split_every(enc, 4))
  assert_eq(got, src)
  let dec = StreamDecoder::new(128UL * 1024UL * 1024UL)
  let (_, done) = dec.feed(enc[:])
  assert_true(done)
  let err = @test.expect_error(() => dec.feed(b"\x00"[:]) |> ignore)
  assert_true(err is @coder.Data)
}
