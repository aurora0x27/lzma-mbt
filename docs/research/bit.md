# Bit / byte utilities

## Scope

Little-endian byte reading and writing used by LZMA headers, checksum framing, and related on-disk integers. XZ VLIs live in the `xz` package. Not a bitstream for the range coder (that lives in `range_coder`).

## Specification

- Unsigned integers are packed little-endian unless a format says otherwise (XZ Stream Header flags are raw bytes; LZMA_Alone dict size is LE u32; uncompressed size is LE u64).
- Reading past the end of a view is a recoverable error, not a panic.

## Reference implementation

`liblzma` uses pointer + remaining size. MoonBit uses `BytesView` + cursor.

## Data model

- `Reader`: view + `pos`
- `Writer`: growable `Array[Byte]`

## Algorithm

Sequential cursor. `read_*` requires enough remaining bytes. `write_*` appends.

## Invariants

- `0 <= pos <= data.length()`
- A successful `read_u32_le` advances `pos` by 4
- Writer output concatenates in call order

## Edge cases

Empty view; exact-length read; 1-byte short read; `UInt`/`UInt64` max values.

## Error cases

Truncated input → `BitError::Eof` (mapped to `LzmaError::UnexpectedEof` by higher layers).

## Test vectors

- `u32` `0x04030201` as bytes `01 02 03 04`
- `u64` `0x0807060504030201`

## Compatibility notes

Byte order must match `liblzma` on-disk formats.

## Open questions

None. VLI encoding lives in the `xz` package.
