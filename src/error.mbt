///|
/// Public error type. `Error` is a MoonBit reserved name.
/// Match on the tag (`err is DataError`); string payloads are not a stable API.
pub suberror LzmaError {
  /// Properties byte or similar field that cannot be a valid encoding.
  InvalidInput(String)
  /// Stream ended before a legal terminator.
  UnexpectedEof
  /// Caller options (lc/lp/pb, dict, preset, memlimit, filters).
  InvalidConfiguration(String)
  /// Allowed by the spec but not implemented in this version.
  UnsupportedFeature(String)
  /// Dictionary would exceed `DecodeOptions.memlimit`.
  MemoryLimit
  /// Corrupt bitstream, CRC, Index, or padding.
  DataError
  /// Streaming `code` only: output buffer cannot accept the Finish payload.
  BufferTooSmall
  /// Magic / flags do not match the requested `Format`.
  FormatError
} derive(Debug, Eq)

///|
/// Default decoder memory limit when `DecodeOptions.memlimit` is `None`.
pub const DEFAULT_MEMLIMIT : UInt64 = 134217728UL

///|
pub fn effective_memlimit(limit : UInt64?) -> UInt64 {
  match limit {
    None => DEFAULT_MEMLIMIT
    Some(n) => n
  }
}
