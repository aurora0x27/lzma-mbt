///|
fn u8(v : Int) -> Byte {
  v.to_byte()
}

///|
fn dict_as_int(
  dict_size : UInt,
  memlimit : UInt64,
) -> Int raise @coder.CoderError {
  let d64 = dict_size.to_uint64()
  if d64 > memlimit {
    raise @coder.Limit
  }
  if d64 > 2147483647UL {
    raise @coder.Limit
  }
  let n = dict_size.reinterpret_as_int()
  if n < 1 {
    raise @coder.Limit
  }
  n
}

///|
pub fn lzma2_dict_prop(dict : UInt) -> Byte {
  if dict == 0xFFFFFFFFU {
    return u8(40)
  }
  let mut b = 0
  while b <= 40 {
    let decoded = (2U | (b.reinterpret_as_uint() & 1U)) << ((b >> 1) + 11)
    if decoded >= dict {
      return u8(b)
    }
    b = b + 1
  }
  u8(40)
}

///|
pub fn lzma2_dict_size(prop : Byte) -> UInt raise @coder.CoderError {
  let b = prop.to_int()
  if b > 40 {
    raise @coder.Data
  }
  if b == 40 {
    return 0xFFFFFFFFU
  }
  (2U | (b.reinterpret_as_uint() & 1U)) << ((b >> 1) + 11)
}

///|
fn write_uncompressed_chunk(w : @bit.Writer, chunk : BytesView) -> Unit {
  if chunk.length() < 1 {
    return
  }
  let m1 = chunk.length() - 1
  w.write_u8(b'\x01')
  w.write_u8(u8((m1 >> 8) & 0xFF))
  w.write_u8(u8(m1 & 0xFF))
  w.write_bytes(chunk)
}

///|
pub fn encode_lzma2(
  input : BytesView,
  lc : Int,
  lp : Int,
  pb : Int,
  dict_size : UInt,
) -> Bytes {
  let w = @bit.Writer::new()
  if input.length() == 0 {
    w.write_u8(b'\x00')
    return w.to_bytes()
  }
  let mut off = 0
  let n = input.length()
  while off < n {
    let chunk_n = if n - off > 65536 { 65536 } else { n - off }
    let chunk = input[off:off + chunk_n]
    let body = @coder.encode_lzma(
      chunk,
      lc,
      lp,
      pb,
      dict_size.reinterpret_as_int(),
      end_marker=false,
    )
    // Compressed size is a 16-bit field (max 65536). LZMA of incompressible
    // 64 KiB can exceed that; emit an uncompressed chunk instead of wrapping.
    if body.length() < 1 || body.length() > 65536 {
      write_uncompressed_chunk(w, chunk)
    } else {
      let uncomp_m1 = chunk_n - 1
      let comp_m1 = body.length() - 1
      let control = 0xE0 | (uncomp_m1 >> 16)
      w.write_u8(u8(control))
      w.write_u8(u8((uncomp_m1 >> 8) & 0xFF))
      w.write_u8(u8(uncomp_m1 & 0xFF))
      w.write_u8(u8((comp_m1 >> 8) & 0xFF))
      w.write_u8(u8(comp_m1 & 0xFF))
      w.write_u8(u8((pb * 5 + lp) * 9 + lc))
      w.write_bytes(body[:])
    }
    off = off + chunk_n
  }
  w.write_u8(b'\x00')
  w.to_bytes()
}

///|
pub fn decode_lzma2_consumed(
  input : BytesView,
  memlimit : UInt64,
  dict_size? : UInt = 65536U,
) -> (Bytes, Int) raise @coder.CoderError {
  let dict_int = dict_as_int(dict_size, memlimit)
  let r = @bit.Reader::new(input)
  let out = @bit.Writer::new()
  let mut produced = 0UL
  while true {
    let control = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
    let c = control.to_int()
    if c == 0 {
      break
    }
    if c < 0x80 {
      if c != 1 && c != 2 {
        raise @coder.Data
      }
      let hi = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
      let lo = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
      let size = ((hi.to_int() << 8) | lo.to_int()) + 1
      let data = r.read_exact(size) catch { @bit.Eof => raise @coder.Eof }
      let add = size.reinterpret_as_uint().to_uint64()
      if produced > 0xFFFF_FFFF_FFFF_FFFFUL - add {
        raise @coder.Data
      }
      produced = produced + add
      out.write_bytes(data)
    } else {
      // Only full dictionary + state + properties reset (0xE0..=0xFF).
      // 0x80/0xA0/0xC0 need a dictionary that survives across chunks.
      if (c & 0xE0) != 0xE0 {
        raise @coder.Unsupported
      }
      let u1 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
      let u0 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
      let c1 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
      let c0 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
      let props = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
      let pn = props.to_int()
      if pn >= 225 {
        raise @coder.Data
      }
      let lc = pn % 9
      let t = pn / 9
      let lp = t % 5
      let pb = t / 5
      if lc + lp > 4 {
        raise @coder.Data
      }
      let uncomp = (((c & 0x1F) << 16) | (u1.to_int() << 8) | u0.to_int()) + 1
      let comp = ((c1.to_int() << 8) | c0.to_int()) + 1
      let payload = r.read_exact(comp) catch { @bit.Eof => raise @coder.Eof }
      let add = uncomp.reinterpret_as_uint().to_uint64()
      if produced > 0xFFFF_FFFF_FFFF_FFFFUL - add {
        raise @coder.Data
      }
      produced = produced + add
      let plain = @coder.decode_lzma(
        payload,
        lc,
        lp,
        pb,
        dict_int,
        uncomp.reinterpret_as_uint().to_uint64(),
      )
      if plain.length() != uncomp {
        raise @coder.Data
      }
      out.write_bytes(plain[:])
    }
  }
  (out.to_bytes(), r.position())
}

///|
pub fn decode_lzma2(
  input : BytesView,
  memlimit : UInt64,
  dict_size? : UInt = 65536U,
) -> Bytes raise @coder.CoderError {
  let (plain, used) = decode_lzma2_consumed(input, memlimit, dict_size~)
  if used != input.length() {
    raise @coder.Data
  }
  plain
}
