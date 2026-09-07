///|
fn fill_probs(n : Int) -> Array[UInt] {
  Array::make(n, PROB_INIT)
}

///|
test "prob_update_moves_toward_bit" {
  let p0 = prob_update_0(PROB_INIT)
  let p1 = prob_update_1(PROB_INIT)
  assert_true(p0 > PROB_INIT)
  assert_true(p1 < PROB_INIT)
}

///|
test "encode_decode_bits_roundtrip" {
  let bits = [0, 1, 1, 0, 0, 0, 1, 1, 0, 1, 0, 0, 1, 1, 1, 0]
  let enc = RangeEncoder::new()
  let probs = fill_probs(1)
  for b in bits {
    enc.encode_bit(probs, 0, b)
  }
  let bytes = enc.flush()
  let dec = RangeDecoder::new(bytes[:])
  let dprobs = fill_probs(1)
  for b in bits {
    assert_eq(dec.decode_bit(dprobs, 0), b)
  }
}

///|
test "encode_decode_direct_bits" {
  let enc = RangeEncoder::new()
  enc.encode_direct_bits(0b10110U, 5)
  let bytes = enc.flush()
  let dec = RangeDecoder::new(bytes[:])
  assert_eq(dec.decode_direct_bits(5), 0b10110U)
}

///|
test "truncated_init_is_eof" {
  let err = @test.expect_error(() => RangeDecoder::new(b"\x00\x01"[:]) |> ignore)
  assert_true(err is Eof)
}

///|
test "nonzero_first_byte_is_data" {
  let err = @test.expect_error(() => {
    RangeDecoder::new(b"\x01\x00\x00\x00\x00"[:]) |> ignore
  })
  assert_true(err is Data)
}
