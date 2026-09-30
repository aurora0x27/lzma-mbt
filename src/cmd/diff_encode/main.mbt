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
fn push_u32_le(a : Array[Byte], v : UInt) -> Unit {
  a.push((v & 0xFFU).reinterpret_as_int().to_byte())
  a.push(((v >> 8) & 0xFFU).reinterpret_as_int().to_byte())
  a.push(((v >> 16) & 0xFFU).reinterpret_as_int().to_byte())
  a.push(((v >> 24) & 0xFFU).reinterpret_as_int().to_byte())
}

///|
/// Deterministic x86-laden payload (adjacent/overlapping E8/E9 with 0x00/0xFF
/// top-byte immediates) for the container x86 BCJ encode differential.
fn bcj_payload() -> Bytes {
  let a = Array()
  let vals = [
    0U, 1U, 0xFFFFFFFFU, 5U, 0xFFFFFFFBU, 0x7FFFFFFFU, 0x80000000U, 100U, 0xFFFFFF9CU,
    0x10U, 0xFFFFFFF0U, 0x4000U,
  ]
  for i in 0..<40 {
    let op = if i % 2 == 0 { b'\xE8' } else { b'\xE9' }
    a.push(op)
    push_u32_le(a, vals[i % 12])
    for _ in 0..<(i % 3) {
      a.push(b'\x90')
    }
  }
  let seg = b"\xE8\xE8\x00\x00\x00\xE8\xE9\x00\x00\x00\xE9\xE8\xFF\xFF\xFF\x90\x90"
  for _ in 0..<30 {
    for b in seg[:] {
      a.push(b)
    }
  }
  for n in 0..<256 {
    a.push(n.to_byte())
  }
  Bytes::from_array(a[:])
}

///|
/// Deterministic ARM-laden payload (32-bit words with a `0xEB` top byte).
fn arm_payload() -> Bytes {
  let a = Array()
  for k in 0..<300 {
    let off = (k.reinterpret_as_uint() * 0xABCDU) & 0xFFFFFFU
    push_u32_le(a, 0xEB000000U | off)
  }
  for _ in 0..<30 {
    push_u32_le(a, 0xEBFFFFFFU)
    push_u32_le(a, 0x12345678U)
  }
  a.push(b'\xEB')
  a.push(b'\x01')
  Bytes::from_array(a[:])
}

///|
/// Deterministic ARM64-laden payload (BL and ADRP instructions) plus a
/// trailing partial word.
fn arm64_payload() -> Bytes {
  b"\x00\x00\x00\x94\xCD\xAB\x00\x94\x9A\x57\x01\x94\x67\x03\x02\x94\x34\xAF\x02\x94\x01\x5B\x03\x94\xCE\x06\x04\x94\x9B\xB2\x04\x94\x68\x5E\x05\x94\x35\x0A\x06\x94\x02\xB6\x06\x94\xCF\x61\x07\x94\x9C\x0D\x08\x94\x69\xB9\x08\x94\x36\x65\x09\x94\x03\x11\x0A\x94\xD0\xBC\x0A\x94\x9D\x68\x0B\x94\x6A\x14\x0C\x94\x37\xC0\x0C\x94\x04\x6C\x0D\x94\xD1\x17\x0E\x94\x9E\xC3\x0E\x94\x6B\x6F\x0F\x94\x38\x1B\x10\x94\x05\xC7\x10\x94\xD2\x72\x11\x94\x9F\x1E\x12\x94\x6C\xCA\x12\x94\x39\x76\x13\x94\x06\x22\x14\x94\xD3\xCD\x14\x94\xA0\x79\x15\x94\x6D\x25\x16\x94\x3A\xD1\x16\x94\x07\x7D\x17\x94\xD4\x28\x18\x94\xA1\xD4\x18\x94\x6E\x80\x19\x94\x3B\x2C\x1A\x94\x00\x00\x00\x90\x81\x28\x00\xB0\x02\x51\x00\xD0\x83\x79\x00\xF0\x24\xA2\x00\x90\xA5\xCA\x00\xB0\x26\xF3\x00\xD0\xA7\x1B\x01\xF0\x48\x44\x01\x90\xC9\x6C\x01\xB0\x4A\x95\x01\xD0\xCB\xBD\x01\xF0\x6C\xE6\x01\x90\xED\x0E\x02\xB0\x6E\x37\x02\xD0\xEF\x5F\x02\xF0\x90\x88\x02\x90\x11\xB1\x02\xB0\x92\xD9\x02\xD0\x13\x02\x03\xF0\xC0\x03\x5F\xD6\x94"
}

///|
/// Deterministic ARM-Thumb-laden payload (Thumb BL pairs plus a trailing
/// partial pair).
fn armthumb_payload() -> Bytes {
  b"\x00\xF0\x00\xF8\x37\xF1\x5B\xF8\x6E\xF2\xB6\xF8\xA5\xF3\x11\xF8\xDC\xF4\x6C\xF8\x13\xF5\xC7\xF8\x4A\xF6\x22\xF8\x81\xF7\x7D\xF8\xB8\xF0\xD8\xF9\xEF\xF1\x33\xF9\x26\xF2\x8E\xF9\x5D\xF3\xE9\xF9\x94\xF4\x44\xF9\xCB\xF5\x9F\xF9\x02\xF6\xFA\xF9\x39\xF7\x55\xF9\x70\xF0\xB0\xFA\xA7\xF1\x0B\xFA\xDE\xF2\x66\xFA\x15\xF3\xC1\xFA\x4C\xF4\x1C\xFA\x83\xF5\x77\xFA\xBA\xF6\xD2\xFA\xF1\xF7\x2D\xFA\x28\xF0\x88\xFB\x5F\xF1\xE3\xFB\x96\xF2\x3E\xFB\xCD\xF3\x99\xFB\x04\xF4\xF4\xFB\x3B\xF5\x4F\xFB\x72\xF6\xAA\xFB\xA9\xF7\x05\xFB\xE0\xF0\x60\xFC\x17\xF1\xBB\xFC\x4E\xF2\x16\xFC\x85\xF3\x71\xFC\xBC\xF4\xCC\xFC\xF3\xF5\x27\xFC\x2A\xF6\x82\xFC\x61\xF7\xDD\xFC\x98\xF0\x38\xFD\xCF\xF1\x93\xFD\x06\xF2\xEE\xFD\x3D\xF3\x49\xFD\x74\xF4\xA4\xFD\xAB\xF5\xFF\xFD\xE2\xF6\x5A\xFD\x19\xF7\xB5\xFD\x50\xF0\x10\xFE\x87\xF1\x6B\xFE\x11\xF8\x22\xF0\xF0\x01\xF8"
}

///|
/// Deterministic PowerPC-laden payload (big-endian branch words plus
/// near-miss words).
fn powerpc_payload() -> Bytes {
  b"\x48\x00\x00\x01\x49\x37\x5B\x9D\x4A\x6E\xB6\x39\x4B\xA5\x11\xD5\x48\xDC\x6C\x75\x49\x13\xC7\x11\x4A\x4A\x22\xAD\x4B\x81\x7D\x49\x48\xB8\xD8\xE9\x49\xEF\x33\x85\x4A\x26\x8E\x21\x4B\x5D\xE9\xBD\x48\x94\x44\x5D\x49\xCB\x9F\xF9\x4A\x02\xFA\x95\x4B\x39\x55\x31\x48\x70\xB0\xD1\x49\xA7\x0B\x6D\x4A\xDE\x66\x09\x4B\x15\xC1\xA5\x48\x4C\x1C\x45\x49\x83\x77\xE1\x4A\xBA\xD2\x7D\x4B\xF1\x2D\x19\x48\x28\x88\xB9\x49\x5F\xE3\x55\x4A\x96\x3E\xF1\x4B\xCD\x99\x8D\x48\x04\xF4\x2D\x49\x3B\x4F\xC9\x4A\x72\xAA\x65\x4B\xA9\x05\x01\x48\xE0\x60\xA1\x49\x17\xBB\x3D\x4A\x4E\x16\xD9\x4B\x85\x71\x75\x48\xBC\xCC\x15\x49\xF3\x27\xB1\x4A\x2A\x82\x4D\x4B\x61\xDD\xE9\x48\x98\x38\x89\x49\xCF\x93\x25\x4A\x06\xEE\xC1\x4B\x3D\x49\x5D\x48\x74\xA4\xFD\x49\xAB\xFF\x99\x4A\xE2\x5A\x35\x4B\x19\xB5\xD1\x48\x50\x10\x71\x49\x87\x6B\x0D\x48\x11\x22\x00\x4C\x11\x22\x01\x48\x01"
}

///|
/// Deterministic IA-64-laden payload (bundles exercising all three branch
/// slots plus a trailing partial bundle).
fn ia64_payload() -> Bytes {
  b"\x16\x00\x00\x00\x00\x14\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x12\x00\x00\x00\x00\x00\x00\x28\x1A\x01\x28\x00\x00\x00\x00\x00\x10\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xC0\x8A\x06\x50\x16\x00\x70\xDA\x00\x16\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x12\x00\x00\x00\x00\x00\x00\xA0\x68\x04\x28\x00\x00\x00\x00\x00\x10\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xE0\x5A\x10\x58\x16\x00\xE0\xB4\x01\x14\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x12\x00\x00\x00\x00\x00\x00\x18\xB7\x07\x2C\x00\x00\x00\x00\x00\x16\x01\x02"
}

///|
/// Deterministic SPARC-laden payload (big-endian call words plus near-miss
/// words).
fn sparc_payload() -> Bytes {
  b"\x40\x00\x00\x00\x7F\xFD\x5B\x9D\x40\x2E\xB6\x3A\x7F\xF7\x11\xD7\x40\x1C\x6C\x74\x7F\xF1\xC7\x11\x40\x0A\x22\xAE\x7F\xEB\x7D\x4B\x40\x38\xD8\xE8\x7F\xE5\x33\x85\x40\x26\x8E\x22\x7F\xDF\xE9\xBF\x40\x14\x44\x5C\x7F\xD9\x9F\xF9\x40\x02\xFA\x96\x7F\xD3\x55\x33\x40\x30\xB0\xD0\x7F\xCD\x0B\x6D\x40\x1E\x66\x0A\x7F\xC7\xC1\xA7\x40\x0C\x1C\x44\x7F\xC1\x77\xE1\x40\x3A\xD2\x7E\x7F\xFB\x2D\x1B\x40\x28\x88\xB8\x7F\xF5\xE3\x55\x40\x16\x3E\xF2\x7F\xEF\x99\x8F\x40\x04\xF4\x2C\x7F\xE9\x4F\xC9\x40\x32\xAA\x66\x7F\xE3\x05\x03\x40\x20\x60\xA0\x7F\xDD\xBB\x3D\x40\x0E\x16\xDA\x7F\xD7\x71\x77\x40\x3C\xCC\x14\x7F\xD1\x27\xB1\x40\x2A\x82\x4E\x7F\xCB\xDD\xEB\x40\x18\x38\x88\x7F\xC5\x93\x25\x40\x06\xEE\xC2\x7F\xFF\x49\x5F\x40\x34\xA4\xFC\x7F\xF9\xFF\x99\x40\x22\x5A\x36\x7F\xF3\xB5\xD3\x40\x10\x10\x70\x7F\xED\x6B\x0D\x40\xC0\x11\x22\x7F\x00\x33\x44\x40\x00\x11"
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
fn emit_xz_bcj_case(
  name : String,
  payload : Bytes,
  preset : Int,
  check : @lzma.Check,
  bcj : String,
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
    bcj_x86=bcj == "x86",
    bcj_arm=bcj == "arm",
    bcj_arm64=bcj == "arm64",
    bcj_armthumb=bcj == "armthumb",
    bcj_powerpc=bcj == "powerpc",
    bcj_ia64=bcj == "ia64",
    bcj_sparc=bcj == "sparc",
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
/// Encode via the incremental `Encoder::code(..., Run)` path (1-byte output
/// slots, draining `NeedOutput`) and emit the result for the reference
/// decoder, proving streaming output is a valid Stream.
fn emit_stream_case(
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
  let enc = @lzma.Encoder::new(options~)
  let arr = Array()
  let mut pos = 0
  while pos < payload.length() {
    let n = if payload.length() - pos > 4096 {
      4096
    } else {
      payload.length() - pos
    }
    let out = @lzma.OutputBuf::new(size=1)
    let r = enc.code(payload[pos:pos + n], out, @lzma.Action::Run)
    for b in out.written()[:] {
      arr.push(b)
    }
    let mut draining = r.status is @lzma.NeedOutput
    while draining {
      let tail = @lzma.OutputBuf::new(size=1)
      let more = enc.code(b""[:], tail, @lzma.Action::Run)
      for b in tail.written()[:] {
        arr.push(b)
      }
      draining = more.status is @lzma.NeedOutput
    }
    pos = pos + n
  }
  let rest = enc.finish()
  for b in rest[:] {
    arr.push(b)
  }
  let encoded = Bytes::from_array(arr[:])
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
    emit_xz_bcj_case(
      "short_xz_bcj_p6_crc64",
      bcj_payload(),
      6,
      @lzma.Check::Crc64,
      "x86",
    )
    emit_xz_bcj_case(
      "short_xz_arm_p6_crc64",
      arm_payload(),
      6,
      @lzma.Check::Crc64,
      "arm",
    )
    emit_xz_bcj_case(
      "short_xz_arm64_p6_crc64",
      arm64_payload(),
      6,
      @lzma.Check::Crc64,
      "arm64",
    )
    emit_xz_bcj_case(
      "short_xz_armthumb_p6_crc64",
      armthumb_payload(),
      6,
      @lzma.Check::Crc64,
      "armthumb",
    )
    emit_xz_bcj_case(
      "short_xz_powerpc_p6_crc64",
      powerpc_payload(),
      6,
      @lzma.Check::Crc64,
      "powerpc",
    )
    emit_xz_bcj_case(
      "short_xz_ia64_p6_crc64",
      ia64_payload(),
      6,
      @lzma.Check::Crc64,
      "ia64",
    )
    emit_xz_bcj_case(
      "short_xz_sparc_p6_crc64",
      sparc_payload(),
      6,
      @lzma.Check::Crc64,
      "sparc",
    )
    emit_stream_case(
      "stream_xz_p6_crc64",
      mixed_bytes(3000),
      @lzma.Format::Xz,
      6,
      @lzma.Check::Crc64,
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
