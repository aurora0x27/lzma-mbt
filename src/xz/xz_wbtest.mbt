///|
test "vli_minimal_zero" {
  let r = @bit.Reader::new(b"\x00"[:])
  assert_eq(read_vli(r), 0UL)
}

///|
test "vli_two_byte_128" {
  let r = @bit.Reader::new(b"\x80\x01"[:])
  assert_eq(read_vli(r), 128UL)
}

///|
test "vli_overlong_zero_is_data" {
  let r = @bit.Reader::new(b"\x80\x00"[:])
  let raised = try {
    read_vli(r) |> ignore
    false
  } catch {
    @coder.Data => true
    _ => false
  }
  assert_true(raised)
}

///|
test "vli_nine_continuation_bytes_is_data" {
  let r = @bit.Reader::new(b"\x80\x80\x80\x80\x80\x80\x80\x80\x80"[:])
  let raised = try {
    read_vli(r) |> ignore
    false
  } catch {
    @coder.Data => true
    _ => false
  }
  assert_true(raised)
}
