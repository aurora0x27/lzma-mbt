///|
pub suberror FilterError {
  InvalidDistance
} derive(Debug, Eq)

///|
pub fn delta_encode(
  input : BytesView,
  distance : Int,
) -> Bytes raise FilterError {
  if distance < 1 || distance > 256 {
    raise InvalidDistance
  }
  let hist = Array::make(distance, b'\x00')
  let out = Array(capacity=input.length())
  let mut i = 0
  for b in input {
    let p = i % distance
    let prev = hist[p].to_int()
    let cur = b.to_int()
    out.push(((cur - prev) & 0xFF).to_byte())
    hist[p] = b
    i = i + 1
  }
  Bytes::from_array(out[:])
}

///|
pub fn delta_decode(
  input : BytesView,
  distance : Int,
) -> Bytes raise FilterError {
  if distance < 1 || distance > 256 {
    raise InvalidDistance
  }
  let hist = Array::make(distance, b'\x00')
  let out = Array(capacity=input.length())
  let mut i = 0
  for b in input {
    let p = i % distance
    let prev = hist[p].to_int()
    let cur = (b.to_int() + prev) & 0xFF
    let nb = cur.to_byte()
    out.push(nb)
    hist[p] = nb
    i = i + 1
  }
  Bytes::from_array(out[:])
}

///|
/// Reversible x86 E8/E9 relative-offset conversion (XZ BCJ subset).
/// Offsets are 32-bit wrapping, matching the C `uint32_t` instruction pointer.
pub fn bcj_x86(input : BytesView, start_offset : UInt, encode : Bool) -> Bytes {
  let data = Array(capacity=input.length())
  for b in input {
    data.push(b)
  }
  let mut i = 0
  let n = data.length()
  while i + 4 < n {
    let b = data[i]
    if b == b'\xE8' || b == b'\xE9' {
      let rel = data[i + 1].to_int().reinterpret_as_uint() |
        (data[i + 2].to_int().reinterpret_as_uint() << 8) |
        (data[i + 3].to_int().reinterpret_as_uint() << 16) |
        (data[i + 4].to_int().reinterpret_as_uint() << 24)
      let ip = start_offset + i.reinterpret_as_uint() + 5U
      let dest = if encode { rel + ip } else { rel - ip }
      data[i + 1] = (dest & 0xFFU).reinterpret_as_int().to_byte()
      data[i + 2] = ((dest >> 8) & 0xFFU).reinterpret_as_int().to_byte()
      data[i + 3] = ((dest >> 16) & 0xFFU).reinterpret_as_int().to_byte()
      data[i + 4] = ((dest >> 24) & 0xFFU).reinterpret_as_int().to_byte()
      i = i + 5
    } else {
      i = i + 1
    }
  }
  Bytes::from_array(data[:])
}
