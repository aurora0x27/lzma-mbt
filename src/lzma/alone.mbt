///|
pub fn encode_alone(
  input : BytesView,
  lc : Int,
  lp : Int,
  pb : Int,
  dict_size : UInt,
) -> Bytes {
  let w = @bit.Writer::new()
  let packed = (pb * 5 + lp) * 9 + lc
  w.write_u8(packed.to_byte())
  w.write_u32_le(dict_size)
  w.write_u64_le(input.length().reinterpret_as_uint().to_uint64())
  let body = @coder.encode_lzma(
    input,
    lc,
    lp,
    pb,
    dict_size.reinterpret_as_int(),
    end_marker=true,
  )
  w.write_bytes(body[:])
  w.to_bytes()
}

///|
pub fn decode_alone(
  input : BytesView,
  memlimit : UInt64,
) -> Bytes raise @coder.CoderError {
  let r = @bit.Reader::new(input)
  let props = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let n = props.to_int()
  if n >= 225 {
    raise @coder.Data
  }
  let lc = n % 9
  let t = n / 9
  let lp = t % 5
  let pb = t / 5
  if lc + lp > 4 {
    raise @coder.Data
  }
  let dict_size = r.read_u32_le() catch { @bit.Eof => raise @coder.Eof }
  let unpacked = r.read_u64_le() catch { @bit.Eof => raise @coder.Eof }
  // liblzma rounds a too-small header dict up to 4096 rather than rejecting the stream.
  let dict_int = if dict_size < 4096U {
    4096
  } else {
    dict_size.reinterpret_as_int()
  }
  if dict_int < 1 {
    raise @coder.Limit
  }
  if dict_int.reinterpret_as_uint().to_uint64() > memlimit {
    raise @coder.Limit
  }
  let rest = r.read_exact(r.remaining()) catch { @bit.Eof => raise @coder.Eof }
  @coder.decode_lzma(rest, lc, lp, pb, dict_int, unpacked)
}
