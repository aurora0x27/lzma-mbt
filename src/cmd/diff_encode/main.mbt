// Encoder dump for scripts/diff_encode.py (not a public API).
// stdout records: LZMA_MBT_DIFF_V1, CASE…END, DONE.

///|
fn hex_digit(n : Int) -> Char {
  if n < 10 {
    (48 + n).unsafe_to_char()
  } else {
    (87 + n).unsafe_to_char()
  }
}

///|
fn to_hex(data : Bytes) -> String {
  let sb = StringBuilder(size_hint=data.length() * 2)
  for b in data {
    let v = b.to_int()
    sb.write_char(hex_digit(v >> 4))
    sb.write_char(hex_digit(v & 15))
  }
  sb.to_string()
}

///|
fn mix_byte(i : Int) -> Byte {
  let n = i.reinterpret_as_uint()
  (((n * 13U) ^ (n >> 3)) & 0xFFU).reinterpret_as_int().to_byte()
}

///|
fn mixed_bytes(n : Int) -> Bytes {
  let arr = Array(capacity=n)
  for i in 0..<n {
    arr.push(mix_byte(i))
  }
  Bytes::from_array(arr[:])
}

///|
fn check_name(c : @lzma.Check) -> String {
  match c {
    None => "none"
    Crc32 => "crc32"
    Crc64 => "crc64"
    Sha256 => "sha256"
  }
}

///|
fn format_name(f : @lzma.Format) -> String {
  match f {
    Auto => "auto"
    Lzma => "lzma"
    Lzma2 => "lzma2"
    Xz => "xz"
  }
}

///|
fn emit_case(
  name : String,
  payload : Bytes,
  format : @lzma.Format,
  preset : Int,
  check : @lzma.Check,
) -> Unit raise @lzma.LzmaError {
  let options : @lzma.EncodeOptions = {
    format,
    preset: { level: preset, extreme: false, },
    check,
    props: None,
    filters: [],
  }
  let props = options.resolved_props()
  let encoded = @lzma.encode(payload[:], options~)
  println("CASE \{name}")
  println("format=\{format_name(format)}")
  println("preset=\{preset}")
  println("check=\{check_name(check)}")
  println("dict=\{props.dict_size}")
  println("plain_len=\{payload.length()}")
  println("plain_hex=\{to_hex(payload)}")
  println("comp_hex=\{to_hex(encoded)}")
  println("END")
}

///|
fn emit_xz_delta_case(
  name : String,
  payload : Bytes,
  preset : Int,
  check : @lzma.Check,
  delta_distance : Int,
) -> Unit raise @lzma.LzmaError {
  let options : @lzma.EncodeOptions = {
    format: Xz,
    preset: { level: preset, extreme: false, },
    check,
    props: None,
    filters: [],
  }
  let props = options.resolved_props()
  let check_id = match check {
    None => 0
    Crc32 => 1
    Crc64 => 4
    Sha256 => 10
  }
  let encoded = @xz.encode_xz(
    payload[:],
    props.lc,
    props.lp,
    props.pb,
    props.dict_size,
    check_id~,
    delta_distance~,
  ) catch {
    @coder.Data => {
      println("ERROR DataError")
      return
    }
    @coder.Eof => {
      println("ERROR UnexpectedEof")
      return
    }
    @coder.Limit => {
      println("ERROR MemoryLimit")
      return
    }
    @coder.Unsupported => {
      println("ERROR UnsupportedFeature")
      return
    }
  }
  println("CASE \{name}")
  println("format=xz")
  println("preset=\{preset}")
  println("check=\{check_name(check)}")
  println("dict=\{props.dict_size}")
  println("plain_len=\{payload.length()}")
  println("plain_hex=\{to_hex(payload)}")
  println("comp_hex=\{to_hex(encoded)}")
  println("END")
}

///|
fn main {
  println("LZMA_MBT_DIFF_V1")
  try {
    let empty = b""
    let short = b"hello lzma"
    let run64 = Bytes::make(64, b'\xAA')
    let incomp256 = mixed_bytes(256)
    let incomp64k = mixed_bytes(65536)
    let over64k = Bytes::make(70000, b'\x33')
    emit_case(
      "empty_xz_p6_crc64",
      empty,
      @lzma.Format::Xz,
      6,
      @lzma.Check::Crc64,
    )
    emit_case("empty_lzma_p6", empty, @lzma.Format::Lzma, 6, @lzma.Check::Crc64)
    emit_case(
      "empty_lzma2_p6",
      empty,
      @lzma.Format::Lzma2,
      6,
      @lzma.Check::Crc64,
    )
    emit_case(
      "short_xz_p6_crc64",
      short,
      @lzma.Format::Xz,
      6,
      @lzma.Check::Crc64,
    )
    emit_case("short_lzma_p6", short, @lzma.Format::Lzma, 6, @lzma.Check::Crc64)
    emit_case(
      "short_lzma2_p6",
      short,
      @lzma.Format::Lzma2,
      6,
      @lzma.Check::Crc64,
    )
    emit_case(
      "short_xz_p0_crc64",
      short,
      @lzma.Format::Xz,
      0,
      @lzma.Check::Crc64,
    )
    emit_case("short_lzma_p0", short, @lzma.Format::Lzma, 0, @lzma.Check::Crc64)
    emit_case(
      "short_lzma2_p0",
      short,
      @lzma.Format::Lzma2,
      0,
      @lzma.Check::Crc64,
    )
    emit_case(
      "short_xz_p6_crc32",
      short,
      @lzma.Format::Xz,
      6,
      @lzma.Check::Crc32,
    )
    emit_case("short_xz_p6_none", short, @lzma.Format::Xz, 6, @lzma.Check::None)
    emit_case(
      "short_xz_p6_sha256",
      short,
      @lzma.Format::Xz,
      6,
      @lzma.Check::Sha256,
    )
    emit_xz_delta_case(
      "short_xz_delta_d1_p6_crc64",
      short,
      6,
      @lzma.Check::Crc64,
      1,
    )
    emit_case(
      "empty_xz_p6_crc32",
      empty,
      @lzma.Format::Xz,
      6,
      @lzma.Check::Crc32,
    )
    emit_case("empty_xz_p6_none", empty, @lzma.Format::Xz, 6, @lzma.Check::None)
    emit_case(
      "run64_xz_p6_crc64",
      run64,
      @lzma.Format::Xz,
      6,
      @lzma.Check::Crc64,
    )
    emit_case("run64_lzma_p6", run64, @lzma.Format::Lzma, 6, @lzma.Check::Crc64)
    emit_case(
      "run64_lzma2_p6",
      run64,
      @lzma.Format::Lzma2,
      6,
      @lzma.Check::Crc64,
    )
    emit_case(
      "incomp256_xz_p6_crc64",
      incomp256,
      @lzma.Format::Xz,
      6,
      @lzma.Check::Crc64,
    )
    emit_case(
      "incomp256_lzma_p6",
      incomp256,
      @lzma.Format::Lzma,
      6,
      @lzma.Check::Crc64,
    )
    emit_case(
      "incomp256_lzma2_p6",
      incomp256,
      @lzma.Format::Lzma2,
      6,
      @lzma.Check::Crc64,
    )
    emit_case(
      "over64k_xz_p6_crc64",
      over64k,
      @lzma.Format::Xz,
      6,
      @lzma.Check::Crc64,
    )
    emit_case(
      "over64k_lzma_p6",
      over64k,
      @lzma.Format::Lzma,
      6,
      @lzma.Check::Crc64,
    )
    emit_case(
      "over64k_lzma2_p6",
      over64k,
      @lzma.Format::Lzma2,
      6,
      @lzma.Check::Crc64,
    )
    emit_case(
      "over64k_xz_p0_crc64",
      over64k,
      @lzma.Format::Xz,
      0,
      @lzma.Check::Crc64,
    )
    emit_case(
      "incomp64k_lzma2_p6",
      incomp64k,
      @lzma.Format::Lzma2,
      6,
      @lzma.Check::Crc64,
    )
    emit_case(
      "incomp64k_xz_p6_crc64",
      incomp64k,
      @lzma.Format::Xz,
      6,
      @lzma.Check::Crc64,
    )
    emit_case(
      "incomp64k_lzma_p6",
      incomp64k,
      @lzma.Format::Lzma,
      6,
      @lzma.Check::Crc64,
    )
    println("DONE")
  } catch {
    err => {
      let tag = match err {
        InvalidInput(_) => "InvalidInput"
        UnexpectedEof => "UnexpectedEof"
        InvalidConfiguration(_) => "InvalidConfiguration"
        UnsupportedFeature(_) => "UnsupportedFeature"
        MemoryLimit => "MemoryLimit"
        DataError => "DataError"
        BufferTooSmall => "BufferTooSmall"
        FormatError => "FormatError"
      }
      println("ERROR \{tag}")
    }
  }
}
