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
fn write_compressed_chunk(
  w : @bit.Writer,
  control_base : Int,
  chunk_n : Int,
  body : Bytes,
  lc : Int,
  lp : Int,
  pb : Int,
  with_props : Bool,
) -> Unit {
  let uncomp_m1 = chunk_n - 1
  let comp_m1 = body.length() - 1
  w.write_u8(u8(control_base | (uncomp_m1 >> 16)))
  w.write_u8(u8((uncomp_m1 >> 8) & 0xFF))
  w.write_u8(u8(uncomp_m1 & 0xFF))
  w.write_u8(u8((comp_m1 >> 8) & 0xFF))
  w.write_u8(u8(comp_m1 & 0xFF))
  if with_props {
    w.write_u8(u8((pb * 5 + lp) * 9 + lc))
  }
  w.write_bytes(body[:])
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
  let mut enc = @coder.LzmaEnc::new(lc, lp, pb, dict_size.reinterpret_as_int())
  let mut off = 0
  let n = input.length()
  let mut need_dict_reset = true
  let mut need_props = true
  while off < n {
    let chunk_n = if n - off > 65536 { 65536 } else { n - off }
    if need_dict_reset {
      enc.reset_dict()
      enc.reset_state()
    } else if need_props {
      enc.reset_state()
    }
    let trial = enc.clone()
    let body = trial.encode_chunk(input, off, chunk_n)
    if body.length() < 1 || body.length() > 65536 {
      write_uncompressed_chunk(w, input[off:off + chunk_n])
      enc.reset_dict()
      enc.reset_state()
      enc.skip_uncompressed(chunk_n)
      need_dict_reset = false
      need_props = true
    } else {
      enc = trial
      if need_dict_reset {
        write_compressed_chunk(w, 0xE0, chunk_n, body, lc, lp, pb, true)
      } else if need_props {
        write_compressed_chunk(w, 0xC0, chunk_n, body, lc, lp, pb, true)
      } else {
        write_compressed_chunk(w, 0x80, chunk_n, body, lc, lp, pb, false)
      }
      need_dict_reset = false
      need_props = false
    }
    off = off + chunk_n
  }
  w.write_u8(b'\x00')
  w.to_bytes()
}

///|
fn unpack_lzma_props(props : Byte) -> (Int, Int, Int) raise @coder.CoderError {
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
  (lc, lp, pb)
}

///|
fn add_produced(produced : UInt64, n : Int) -> UInt64 raise @coder.CoderError {
  let add = n.reinterpret_as_uint().to_uint64()
  if produced > 0xFFFF_FFFF_FFFF_FFFFUL - add {
    raise @coder.Data
  }
  produced + add
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
  // Dummy lc/lp/pb until the first properties byte. A new stream must
  // start with dictionary reset (`0x01` or `0xE0..=0xFF`).
  let dec = @coder.LzmaDec::new(3, 0, 2, dict_int)
  let mut produced = 0UL
  let mut need_dict_reset = true
  let mut need_props = true
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
      if c == 1 {
        dec.reset_dict()
        need_props = true
        need_dict_reset = false
      } else if need_dict_reset {
        raise @coder.Data
      }
      let hi = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
      let lo = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
      let size = ((hi.to_int() << 8) | lo.to_int()) + 1
      let data = r.read_exact(size) catch { @bit.Eof => raise @coder.Eof }
      produced = add_produced(produced, size)
      dec.put_uncompressed(data)
      out.write_bytes(data)
    } else {
      if c >= 0xE0 {
        dec.reset_dict()
        need_dict_reset = false
        need_props = true
      } else if need_dict_reset {
        raise @coder.Data
      }
      let u1 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
      let u0 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
      let c1 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
      let c0 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
      let uncomp = (((c & 0x1F) << 16) | (u1.to_int() << 8) | u0.to_int()) + 1
      let comp = ((c1.to_int() << 8) | c0.to_int()) + 1
      if c >= 0xC0 {
        let props = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
        let (lc, lp, pb) = unpack_lzma_props(props)
        dec.set_props(lc, lp, pb)
        need_props = false
      } else if need_props {
        raise @coder.Data
      } else if c >= 0xA0 {
        dec.reset_state()
      }
      let payload = r.read_exact(comp) catch { @bit.Eof => raise @coder.Eof }
      produced = add_produced(produced, uncomp)
      let plain = dec.decode_payload(
        payload,
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
