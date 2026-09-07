///|
fn write_vli(w : @bit.Writer, v0 : UInt64) -> Unit {
  let mut v = v0
  while v >= 0x80UL {
    let b = ((v & 0x7FUL) | 0x80UL).reinterpret_as_int64().to_int()
    w.write_u8(b.to_byte())
    v = v >> 7
  }
  w.write_u8(v.reinterpret_as_int64().to_int().to_byte())
}

///|
fn vli_min_len(v : UInt64) -> Int {
  let mut n = 1
  let mut x = v
  while x >= 0x80UL {
    n = n + 1
    x = x >> 7
  }
  n
}

///|
fn read_vli(r : @bit.Reader) -> UInt64 raise @coder.CoderError {
  let mut result = 0UL
  let mut shift = 0
  let mut n = 0
  for _ in 0..<9 {
    let b = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
    n = n + 1
    let v = b.to_int().reinterpret_as_uint().to_uint64()
    result = result | ((v & 0x7FUL) << shift)
    if (v & 0x80UL) == 0UL {
      if n != vli_min_len(result) {
        raise @coder.Data
      }
      return result
    }
    shift = shift + 7
  }
  raise @coder.Data
}

///|
fn pad_to_4(w : @bit.Writer) -> Unit {
  while w.length() % 4 != 0 {
    w.write_u8(b'\x00')
  }
}

///|
fn check_field_size(check_id : Int) -> Int raise @coder.CoderError {
  match check_id {
    0 => 0
    1 => 4
    4 => 8
    10 => raise @coder.Unsupported
    _ => raise @coder.Unsupported
  }
}

///|
fn write_check(w : @bit.Writer, check_id : Int, data : BytesView) -> Unit {
  match check_id {
    1 => w.write_u32_le(@checksum.crc32(data))
    4 => w.write_u64_le(@checksum.crc64(data))
    _ => ()
  }
}

///|
fn bytes_to_u32_le(v : BytesView) -> UInt {
  v[0].to_int().reinterpret_as_uint() |
  (v[1].to_int().reinterpret_as_uint() << 8) |
  (v[2].to_int().reinterpret_as_uint() << 16) |
  (v[3].to_int().reinterpret_as_uint() << 24)
}

///|
fn bytes_to_u64_le(v : BytesView) -> UInt64 {
  bytes_to_u32_le(v[0:4]).to_uint64() |
  (bytes_to_u32_le(v[4:8]).to_uint64() << 32)
}

///|
fn parse_index_and_footer(
  data : BytesView,
  flags : Bytes,
  expect_nrec : UInt64,
  expect_unpadded : UInt64,
  expect_uncompressed : UInt64,
) -> Unit raise @coder.CoderError {
  let r = @bit.Reader::new(data)
  let ind = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  if ind != b'\x00' {
    raise @coder.Data
  }
  let nrec = read_vli(r)
  if nrec != expect_nrec {
    raise @coder.Data
  }
  let mut i = 0UL
  while i < nrec {
    let unpadded = read_vli(r)
    let uncompressed = read_vli(r)
    if unpadded != expect_unpadded || uncompressed != expect_uncompressed {
      raise @coder.Data
    }
    i = i + 1
  }
  while r.position() % 4 != 0 {
    let z = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
    if z != b'\x00' {
      raise @coder.Data
    }
  }
  let idx_len = r.position()
  let stored_crc = r.read_u32_le() catch { @bit.Eof => raise @coder.Eof }
  if @checksum.crc32(data[0:idx_len]) != stored_crc {
    raise @coder.Data
  }
  let fcrc = r.read_u32_le() catch { @bit.Eof => raise @coder.Eof }
  let backward = r.read_u32_le() catch { @bit.Eof => raise @coder.Eof }
  let g0 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let g1 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  if g0 != flags[0] || g1 != flags[1] {
    raise @coder.Data
  }
  let expected_back = ((idx_len + 4) / 4 - 1).reinterpret_as_uint()
  if backward != expected_back {
    raise @coder.Data
  }
  let foot = @bit.Writer::new()
  foot.write_u32_le(backward)
  foot.write_u8(g0)
  foot.write_u8(g1)
  if @checksum.crc32(foot.to_bytes()[:]) != fcrc {
    raise @coder.Data
  }
  let y = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let z = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  if y != b'\x59' || z != b'\x5A' {
    raise @coder.Data
  }
  if r.remaining() != 0 {
    raise @coder.Data
  }
}

///|
pub fn encode_xz(
  input : BytesView,
  lc : Int,
  lp : Int,
  pb : Int,
  dict_size : UInt,
  check_id? : Int = 4,
) -> Bytes raise @coder.CoderError {
  let check_n = check_field_size(check_id)
  let payload = @lzma2.encode_lzma2(input, lc, lp, pb, dict_size)
  let flags = Bytes::from_array([b'\x00', check_id.to_byte()][:])
  let w = @bit.Writer::new()
  w.write_bytes(b"\xFD\x37\x7A\x58\x5A\x00"[:])
  w.write_bytes(flags[:])
  w.write_u32_le(@checksum.crc32(flags[:]))
  let content = @bit.Writer::new()
  content.write_u8(b'\xC0')
  write_vli(content, payload.length().reinterpret_as_uint().to_uint64())
  write_vli(content, input.length().reinterpret_as_uint().to_uint64())
  content.write_u8(b'\x21')
  content.write_u8(b'\x01')
  content.write_u8(@lzma2.lzma2_dict_prop(dict_size))
  while (1 + content.length()) % 4 != 0 {
    content.write_u8(b'\x00')
  }
  let hdr = @bit.Writer::new()
  hdr.write_u8(((1 + content.length()) / 4).to_byte())
  hdr.write_bytes(content.to_bytes()[:])
  let hbytes = hdr.to_bytes()
  w.write_bytes(hbytes[:])
  w.write_u32_le(@checksum.crc32(hbytes[:]))
  w.write_bytes(payload[:])
  let pad = (4 - payload.length() % 4) % 4
  for _ in 0..<pad {
    w.write_u8(b'\x00')
  }
  write_check(w, check_id, input)
  let unpadded = hbytes.length() + 4 + payload.length() + check_n
  let index = @bit.Writer::new()
  index.write_u8(b'\x00')
  write_vli(index, 1UL)
  write_vli(index, unpadded.reinterpret_as_uint().to_uint64())
  write_vli(index, input.length().reinterpret_as_uint().to_uint64())
  pad_to_4(index)
  let ibytes = index.to_bytes()
  w.write_bytes(ibytes[:])
  w.write_u32_le(@checksum.crc32(ibytes[:]))
  let backward = ((ibytes.length() + 4) / 4 - 1).reinterpret_as_uint()
  let foot = @bit.Writer::new()
  foot.write_u32_le(backward)
  foot.write_bytes(flags[:])
  let fb = foot.to_bytes()
  w.write_u32_le(@checksum.crc32(fb[:]))
  w.write_bytes(fb[:])
  w.write_bytes(b"\x59\x5A"[:])
  w.to_bytes()
}

///|
pub fn decode_xz(
  input : BytesView,
  memlimit : UInt64,
  ignore_check : Bool,
) -> Bytes raise @coder.CoderError {
  let r = @bit.Reader::new(input)
  let m0 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let m1 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let m2 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let m3 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let m4 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let m5 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  if m0 != b'\xFD' ||
    m1 != b'\x37' ||
    m2 != b'\x7A' ||
    m3 != b'\x58' ||
    m4 != b'\x5A' ||
    m5 != b'\x00' {
    raise @coder.Data
  }
  let f0 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let f1 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  if f0 != b'\x00' {
    raise @coder.Data
  }
  let flags = Bytes::from_array([f0, f1][:])
  let fcrc = r.read_u32_le() catch { @bit.Eof => raise @coder.Eof }
  if @checksum.crc32(flags[:]) != fcrc {
    raise @coder.Data
  }
  let check_id = f1.to_int()
  let check_n = check_field_size(check_id)
  if r.remaining() == 0 {
    raise @coder.Eof
  }
  // A Block Header Size of 0 is invalid, so 0x00 here is the Index indicator
  // (a Stream with no Blocks), not a Block.
  if r.rest()[0] == b'\x00' {
    parse_index_and_footer(r.rest(), flags, 0UL, 0UL, 0UL)
    return b""
  }
  let hs = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let header_len = (hs.to_int() + 1) * 4
  let rest_hdr = r.read_exact(header_len - 5) catch {
    @bit.Eof => raise @coder.Eof
  }
  let hdr_arr : Array[Byte] = [hs]
  for b in rest_hdr {
    hdr_arr.push(b)
  }
  let hbytes = Bytes::from_array(hdr_arr[:])
  let hcrc = r.read_u32_le() catch { @bit.Eof => raise @coder.Eof }
  if @checksum.crc32(hbytes[:]) != hcrc {
    raise @coder.Data
  }
  let hr = @bit.Reader::new(hbytes[:])
  ignore(hr.read_u8() catch { @bit.Eof => raise @coder.Eof })
  let bflags = hr.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let bf = bflags.to_int()
  if (bf & 0x3C) != 0 {
    raise @coder.Data
  }
  if (bf & 0x03) != 0 {
    raise @coder.Unsupported
  }
  let has_comp_size = (bf & 0x40) != 0
  let mut declared_comp : UInt64? = None
  if has_comp_size {
    declared_comp = Some(read_vli(hr))
  }
  let mut declared_uncomp : UInt64? = None
  if (bf & 0x80) != 0 {
    declared_uncomp = Some(read_vli(hr))
  }
  let fid = hr.read_u8() catch { @bit.Eof => raise @coder.Eof }
  if fid != b'\x21' {
    raise @coder.Unsupported
  }
  let psz = hr.read_u8() catch { @bit.Eof => raise @coder.Eof }
  if psz != b'\x01' {
    raise @coder.Data
  }
  let dprop = hr.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let dict_size = @lzma2.lzma2_dict_size(dprop)
  while hr.remaining() > 0 {
    let z = hr.read_u8() catch { @bit.Eof => raise @coder.Eof }
    if z != b'\x00' {
      raise @coder.Data
    }
  }
  let rest = r.rest()
  let window = match declared_comp {
    Some(n) => {
      let cap = rest.length().reinterpret_as_uint().to_uint64()
      if n > cap {
        raise @coder.Eof
      }
      rest[0:n.reinterpret_as_int64().to_int()]
    }
    None => rest
  }
  let (plain, used) = @lzma2.decode_lzma2_consumed(window, memlimit, dict_size~)
  match declared_comp {
    Some(_) => if used != window.length() { raise @coder.Data }
    None => ()
  }
  match declared_uncomp {
    Some(n) =>
      if n != plain.length().reinterpret_as_uint().to_uint64() {
        raise @coder.Data
      }
    None => ()
  }
  ignore(r.read_exact(used) catch { @bit.Eof => raise @coder.Eof })
  let pad = (4 - used % 4) % 4
  for _ in 0..<pad {
    let z = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
    if z != b'\x00' {
      raise @coder.Data
    }
  }
  let stored = r.read_exact(check_n) catch { @bit.Eof => raise @coder.Eof }
  if ignore_check == false {
    let ok = match check_id {
      0 => true
      1 =>
        stored.length() == 4 &&
        @checksum.crc32(plain[:]) == bytes_to_u32_le(stored[:])
      4 =>
        stored.length() == 8 &&
        @checksum.crc64(plain[:]) == bytes_to_u64_le(stored[:])
      _ => false
    }
    if ok == false {
      raise @coder.Data
    }
  }
  parse_index_and_footer(
    r.rest(),
    flags,
    1UL,
    (hbytes.length() + 4 + used + check_n).reinterpret_as_uint().to_uint64(),
    plain.length().reinterpret_as_uint().to_uint64(),
  )
  plain
}
