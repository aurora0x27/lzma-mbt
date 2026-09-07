///|
/// Compressed container / filter format. `Auto` is decode-only.
pub(all) enum Format {
  /// `.xz` magic vs LZMA_Alone properties byte. Encode is rejected.
  Auto
  /// LZMA_Alone (`.lzma`).
  Lzma
  /// Raw LZMA2 (no `.xz` container).
  Lzma2
  /// `.xz` Stream.
  Xz
} derive(Debug, Eq)

///|
pub(all) enum Check {
  None
  Crc32
  Crc64
  /// Enum member only; encode/decode raise `UnsupportedFeature`.
  Sha256
} derive(Debug, Eq)

///|
pub(all) enum Action {
  /// Buffers input. Compress/decompress runs at `Finish`.
  Run
  /// Unsupported; `code` raises `InvalidConfiguration`.
  SyncFlush
  /// Unsupported; `code` raises `InvalidConfiguration`.
  FullFlush
  /// Ends input and drains through `encode` / `decode`.
  Finish
} derive(Debug, Eq)

///|
pub(all) enum Status {
  /// `Run` buffered input; no codec output yet.
  Ok
  /// `Finish` completed and pending output is fully drained.
  StreamEnd
  /// Reserved for a future incremental state machine. `Run` currently returns `Ok`.
  NeedInput
  /// Output buffer is full; take `written()` and continue `code` or `finish()`.
  NeedOutput
} derive(Debug, Eq)

///|
pub(all) struct Preset {
  level : Int
  extreme : Bool
} derive(Debug, Eq)

///|
pub fn Preset::default() -> Preset {
  { level: 6, extreme: false, }
}

///|
pub fn Preset::new(
  level : Int,
  extreme? : Bool = false,
) -> Preset raise LzmaError {
  if level < 0 || level > 9 {
    raise InvalidConfiguration("preset level must be 0..=9")
  }
  if extreme {
    raise UnsupportedFeature("extreme preset")
  }
  { level, extreme, }
}

///|
/// LZMA1 properties. All fields are required; `lc + lp` must be at most 4.
pub(all) struct LzmaProps {
  lc : Int
  lp : Int
  pb : Int
  dict_size : UInt
} derive(Debug, Eq)

///|
pub const MIN_DICT_SIZE : UInt = 4096U

///|
pub const MAX_DICT_SIZE : UInt = 1610612736U

///|
pub fn LzmaProps::validate(self : LzmaProps) -> Unit raise LzmaError {
  if self.lc < 0 || self.lc > 8 {
    raise InvalidConfiguration("lc must be 0..=8")
  }
  if self.lp < 0 || self.lp > 4 {
    raise InvalidConfiguration("lp must be 0..=4")
  }
  if self.pb < 0 || self.pb > 4 {
    raise InvalidConfiguration("pb must be 0..=4")
  }
  if self.lc + self.lp > 4 {
    raise InvalidConfiguration("lc + lp must be <= 4")
  }
  if self.dict_size < MIN_DICT_SIZE || self.dict_size > MAX_DICT_SIZE {
    raise InvalidConfiguration("dict_size out of range")
  }
}

///|
/// liblzma preset dictionary sizes: 1 << [18,20,21,22,22,23,23,24,25,26].
pub fn LzmaProps::from_preset(preset : Preset) -> LzmaProps raise LzmaError {
  Preset::new(preset.level, extreme=preset.extreme) |> ignore
  let shifts = [18, 20, 21, 22, 22, 23, 23, 24, 25, 26]
  let dict_size = 1U << shifts[preset.level]
  let props = { lc: 3, lp: 0, pb: 2, dict_size, }
  props.validate()
  props
}

///|
pub fn pack_props(lc : Int, lp : Int, pb : Int) -> Byte raise LzmaError {
  if lc < 0 || lc > 8 || lp < 0 || lp > 4 || pb < 0 || pb > 4 || lc + lp > 4 {
    raise InvalidConfiguration("invalid lc/lp/pb")
  }
  ((pb * 5 + lp) * 9 + lc).to_byte()
}

///|
pub fn unpack_props(props : Byte) -> (Int, Int, Int) raise LzmaError {
  let n = props.to_int()
  if n >= 225 {
    raise InvalidInput("LZMA properties byte")
  }
  let lc = n % 9
  let t = n / 9
  let lp = t % 5
  let pb = t / 5
  if lc + lp > 4 {
    raise InvalidInput("LZMA properties byte")
  }
  (lc, lp, pb)
}

///|
/// Extra pre/post filters around the codec. `Lzma1`/`Lzma2` here are configuration errors.
pub(all) enum FilterSpec {
  Lzma1(LzmaProps)
  Lzma2(LzmaProps)
  Delta(distance~ : Int)
  BcjX86(start_offset~ : UInt)
} derive(Debug, Eq)

///|
pub(all) struct EncodeOptions {
  format : Format
  preset : Preset
  check : Check
  props : LzmaProps?
  filters : Array[FilterSpec]
} derive(Debug, Eq)

///|
pub fn EncodeOptions::default() -> EncodeOptions {
  {
    format: Format::Xz,
    preset: Preset::default(),
    check: Check::Crc64,
    props: None,
    filters: [],
  }
}

///|
pub fn EncodeOptions::resolved_props(
  self : EncodeOptions,
) -> LzmaProps raise LzmaError {
  match self.props {
    Some(p) => {
      p.validate()
      p
    }
    None => LzmaProps::from_preset(self.preset)
  }
}

///|
pub fn EncodeOptions::validate(self : EncodeOptions) -> Unit raise LzmaError {
  match self.format {
    Auto =>
      raise InvalidConfiguration("Format::Auto cannot be used for encoding")
    Lzma | Lzma2 | Xz => ()
  }
  Preset::new(self.preset.level, extreme=self.preset.extreme) |> ignore
  self.resolved_props() |> ignore
  if self.check is Check::Sha256 {
    raise UnsupportedFeature("SHA-256 check")
  }
  validate_extra_filters(self.filters)
}

///|
pub(all) struct DecodeOptions {
  format : Format
  memlimit : UInt64?
  concatenated : Bool
  ignore_check : Bool
  filters : Array[FilterSpec]
} derive(Debug, Eq)

///|
pub fn DecodeOptions::default() -> DecodeOptions {
  {
    format: Format::Auto,
    memlimit: None,
    concatenated: false,
    ignore_check: false,
    filters: [],
  }
}

///|
pub fn DecodeOptions::validate(self : DecodeOptions) -> Unit raise LzmaError {
  if self.concatenated {
    raise UnsupportedFeature("concatenated xz streams")
  }
  if effective_memlimit(self.memlimit) == 0UL {
    raise InvalidConfiguration("memlimit must be > 0")
  }
  validate_extra_filters(self.filters)
}

///|
fn validate_extra_filters(filters : Array[FilterSpec]) -> Unit raise LzmaError {
  for f in filters {
    match f {
      Lzma1(_) | Lzma2(_) => raise InvalidConfiguration("codec filter in chain")
      Delta(distance~) =>
        if distance < 1 || distance > 256 {
          raise InvalidConfiguration("delta distance")
        }
      BcjX86(_) => ()
    }
  }
}

///|
pub const UNKNOWN_SIZE : UInt64 = 0xFFFF_FFFF_FFFF_FFFFUL
