///|
test "lzma2_c0_after_uncompressed" {
  let src = b"hello!!!!!"
  let enc = @coder.LzmaEnc::new(3, 0, 2, 4096)
  enc.reset_dict()
  enc.reset_state()
  enc.skip_uncompressed(5)
  let body = enc.encode_chunk(src[:], 5, 5)
  let w = @bit.Writer::new()
  write_uncompressed_chunk(w, src[0:5])
  write_compressed_chunk(w, 0xC0, 5, body, 3, 0, 2, true)
  w.write_u8(b'\x00')
  let dec = decode_lzma2(w.to_bytes()[:], 1024UL * 1024UL, dict_size=4096U)
  assert_eq(dec, src)
}

///|
test "lzma2_a0_resets_state_keeps_dict" {
  let src = b"AAAABBBB"
  let enc = @coder.LzmaEnc::new(3, 0, 2, 4096)
  let body1 = enc.encode_chunk(src[:], 0, 4)
  enc.reset_state()
  let body2 = enc.encode_chunk(src[:], 4, 4)
  let w = @bit.Writer::new()
  write_compressed_chunk(w, 0xE0, 4, body1, 3, 0, 2, true)
  write_compressed_chunk(w, 0xA0, 4, body2, 3, 0, 2, false)
  w.write_u8(b'\x00')
  let dec = decode_lzma2(w.to_bytes()[:], 1024UL * 1024UL, dict_size=4096U)
  assert_eq(dec, src)
}

///|
test "lzma2_80_after_e0_session" {
  let src = b"0123456789abcdefghij"
  let enc = @coder.LzmaEnc::new(3, 0, 2, 4096)
  let body1 = enc.encode_chunk(src[:], 0, 10)
  let body2 = enc.encode_chunk(src[:], 10, 10)
  let w = @bit.Writer::new()
  write_compressed_chunk(w, 0xE0, 10, body1, 3, 0, 2, true)
  write_compressed_chunk(w, 0x80, 10, body2, 3, 0, 2, false)
  w.write_u8(b'\x00')
  let dec = decode_lzma2(w.to_bytes()[:], 1024UL * 1024UL, dict_size=4096U)
  assert_eq(dec, src)
}
