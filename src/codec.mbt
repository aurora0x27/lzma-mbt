///|
fn append_bytes(buf : Array[Byte], view : BytesView) -> Unit {
  for b in view {
    buf.push(b)
  }
}

///|
fn view_to_bytes(view : BytesView) -> Bytes {
  let a = Array(capacity=view.length())
  append_bytes(a, view)
  Bytes::from_array(a[:])
}

///|
fn apply_encode_filters(
  input : BytesView,
  filters : Array[FilterSpec],
) -> Bytes raise LzmaError {
  let mut cur = view_to_bytes(input)
  for f in filters {
    match f {
      Lzma1(_) | Lzma2(_) => raise InvalidConfiguration("codec filter in chain")
      Delta(distance~) =>
        cur = @filters.delta_encode(cur[:], distance) catch {
          _ => raise InvalidConfiguration("delta distance")
        }
      BcjX86(start_offset~) =>
        cur = @filters.bcj_x86(cur[:], start_offset, true)
    }
  }
  cur
}

///|
fn apply_decode_filters(
  input : Bytes,
  filters : Array[FilterSpec],
) -> Bytes raise LzmaError {
  let mut cur = input
  let mut i = filters.length() - 1
  while i >= 0 {
    match filters[i] {
      Lzma1(_) | Lzma2(_) => raise InvalidConfiguration("codec filter in chain")
      Delta(distance~) =>
        cur = @filters.delta_decode(cur[:], distance) catch {
          _ => raise InvalidConfiguration("delta distance")
        }
      BcjX86(start_offset~) =>
        cur = @filters.bcj_x86(cur[:], start_offset, false)
    }
    i = i - 1
  }
  cur
}

///|
fn encode_format(
  input : BytesView,
  options : EncodeOptions,
  props : LzmaProps,
) -> Bytes raise LzmaError {
  match options.format {
    Auto =>
      raise InvalidConfiguration("Format::Auto cannot be used for encoding")
    Lzma =>
      @lzma.encode_alone(input, props.lc, props.lp, props.pb, props.dict_size)
    Lzma2 =>
      @lzma2.encode_lzma2(input, props.lc, props.lp, props.pb, props.dict_size)
    Xz => {
      let check_id = match options.check {
        None => 0
        Crc32 => 1
        Crc64 => 4
        Sha256 => 10
      }
      @xz.encode_xz(
        input,
        props.lc,
        props.lp,
        props.pb,
        props.dict_size,
        check_id~,
      ) catch {
        @coder.Unsupported => raise UnsupportedFeature("xz check")
        @coder.Eof => raise UnexpectedEof
        @coder.Data => raise DataError
        @coder.Limit => raise MemoryLimit
      }
    }
  }
}

///|
fn encode_body(
  input : BytesView,
  options : EncodeOptions,
) -> Bytes raise LzmaError {
  let props = options.resolved_props()
  if options.filters.length() == 0 {
    encode_format(input, options, props)
  } else {
    let filtered = apply_encode_filters(input, options.filters)
    encode_format(filtered[:], options, props)
  }
}

///|
fn dict_cap_from_memlimit(limit : UInt64) -> UInt {
  let maxd = MAX_DICT_SIZE.to_uint64()
  let n = if limit > maxd { maxd } else { limit }
  if n == 0UL {
    1U
  } else {
    n.reinterpret_as_int64().to_int().reinterpret_as_uint()
  }
}

///|
fn looks_like_xz(input : BytesView) -> Bool {
  input.length() >= 6 &&
  input[0] == b'\xFD' &&
  input[1] == b'\x37' &&
  input[2] == b'\x7A' &&
  input[3] == b'\x58' &&
  input[4] == b'\x5A' &&
  input[5] == b'\x00'
}

///|
fn lzma_props_byte_ok(b : Byte) -> Bool {
  try {
    unpack_props(b) |> ignore
    true
  } catch {
    _ => false
  }
}

///|
fn looks_like_lzma(input : BytesView) -> Bool {
  input.length() >= 13 && lzma_props_byte_ok(input[0])
}

///|
fn xz_magic_prefix(input : BytesView) -> Bool {
  let magic = b"\xFD\x37\x7A\x58\x5A\x00"
  if input.length() == 0 || input.length() >= 6 {
    return false
  }
  let mut i = 0
  while i < input.length() {
    if input[i] != magic[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
fn looks_like_truncated_lzma(input : BytesView) -> Bool {
  input.length() > 0 && input.length() < 13 && lzma_props_byte_ok(input[0])
}

///|
fn decode_body(
  input : BytesView,
  options : DecodeOptions,
) -> Bytes raise LzmaError {
  options.validate()
  let limit = effective_memlimit(options.memlimit)
  let fmt = match options.format {
    Auto =>
      if looks_like_xz(input) {
        Format::Xz
      } else if looks_like_lzma(input) {
        Format::Lzma
      } else if input.length() == 0 ||
        xz_magic_prefix(input) ||
        looks_like_truncated_lzma(input) {
        raise UnexpectedEof
      } else {
        raise FormatError
      }
    Xz => {
      if input.length() < 6 {
        raise UnexpectedEof
      }
      if looks_like_xz(input) == false {
        raise FormatError
      }
      Format::Xz
    }
    Lzma => {
      if looks_like_xz(input) {
        raise FormatError
      }
      if input.length() >= 13 && looks_like_lzma(input) == false {
        raise FormatError
      }
      Format::Lzma
    }
    Lzma2 => {
      if looks_like_xz(input) {
        raise FormatError
      }
      Format::Lzma2
    }
  }
  let raw = try {
    match fmt {
      Auto | Lzma => @lzma.decode_alone(input, limit)
      Lzma2 =>
        @lzma2.decode_lzma2(
          input,
          limit,
          dict_size=dict_cap_from_memlimit(limit),
        )
      Xz =>
        @xz.decode_xz(
          input,
          limit,
          options.ignore_check,
          concatenated=options.concatenated,
        )
    }
  } catch {
    @coder.Eof => raise UnexpectedEof
    @coder.Data => raise DataError
    @coder.Limit => raise MemoryLimit
    @coder.Unsupported => raise UnsupportedFeature("lzma2/xz feature")
  }
  apply_decode_filters(raw, options.filters)
}

///|
pub fn encode(
  input : BytesView,
  options? : EncodeOptions = EncodeOptions::default(),
) -> Bytes raise LzmaError {
  options.validate()
  encode_body(input, options)
}

///|
pub fn decode(
  input : BytesView,
  options? : DecodeOptions = DecodeOptions::default(),
) -> Bytes raise LzmaError {
  decode_body(input, options)
}
