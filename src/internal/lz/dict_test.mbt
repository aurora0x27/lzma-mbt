///|
test "put_get_last_byte" {
  let d = Dict::new(8)
  d.put(b'\x11')
  d.put(b'\x22')
  assert_eq(d.get(0), b'\x22')
  assert_eq(d.get(1), b'\x11')
}

///|
test "overlap_copy" {
  let d = Dict::new(16)
  d.put(b'\xAB')
  d.copy_match(0, 3)
  assert_eq(d.get(0), b'\xAB')
  assert_eq(d.get(1), b'\xAB')
  assert_eq(d.get(2), b'\xAB')
  assert_eq(d.get(3), b'\xAB')
}

///|
test "invalid_distance_is_error" {
  let d = Dict::new(8)
  d.put(b'\x01')
  let err = @test.expect_error(() => d.get(1) |> ignore)
  assert_true(err is InvalidDistance)
}

///|
test "dict_wraps_and_keeps_filled_cap" {
  let d = Dict::new(2)
  d.put(b'\x01')
  d.put(b'\x02')
  d.put(b'\x03')
  assert_eq(d.get(0), b'\x03')
  assert_eq(d.get(1), b'\x02')
  let err = @test.expect_error(() => d.get(2) |> ignore)
  assert_true(err is InvalidDistance)
}
