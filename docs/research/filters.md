# Filters (Delta, BCJ x86)

## Scope

Standalone Delta and a simplified x86 BCJ (E8/E9 relative-offset rewrite). These can wrap LZMA/LZMA2/XZ payloads via `EncodeOptions.filters` / `DecodeOptions.filters`. Container-native filter chains inside `.xz` Block Headers other than LZMA2 are not encoded in this version; unknown XZ filter IDs decode as `UnsupportedFeature`.

## Specification

XZ Utils filter documentation:

- **Delta**: distance `1..=256`. Encode `out[i] = in[i] - hist[i % distance]`; decode adds. History starts at zeros. Distance 256 is encoded as 0 in some headers; this API uses 256 directly.
- **x86 BCJ**: convert relative `E8`/`E9` 32-bit offsets to/from absolute using unsigned wrapping `now_pos + i + 5` (`uint32_t` IP). Full liblzma BCJ also tracks MSByte status for overlapping instructions; this pass is the reversible subset used for round-trip tests.

Filter IDs (for `.xz` headers, not this API enum): Delta `0x03`, x86 `0x04`, LZMA2 `0x21`.

## Reference implementation

`src/liblzma/simple/x86.c`, `src/liblzma/delta/delta_*.c`.

## Data model

`FilterSpec::{ Delta(distance), BcjX86(start_offset), Lzma1, Lzma2 }`. LZMA1/LZMA2 in the extra chain are configuration errors (the format already has a codec).

## Algorithm

Encode applies filters in array order, then the container codec. Decode runs the codec, then filters in reverse order.

Delta distance outside `1..=256` raises `FilterError::InvalidDistance` (mapped to `InvalidConfiguration` at the root).

## Invariants

- `delta_decode(delta_encode(x, d), d) == x`
- `bcj_x86(bcj_x86(x, off, true), off, false) == x` for the implemented E8/E9 rewrite
- Unknown `.xz` filter ID does not silently skip

## Edge cases

Distance 1 and 256; empty input; `E8` near the last four bytes (must not rewrite a truncated immediate); high-bit immediates; non-zero `start_offset`.

## Error cases

Distance 0 or > 256; putting `Lzma1`/`Lzma2` in the extra filter chain.

## Test vectors

Delta `"\x01\x02\x03\x04\x05"` distance 1; 300-byte run distance 256; BCJ `E8 10 00 00 00 90 90`; high-bit immediates with non-zero `start_offset`; truncated `E8` (no 4-byte immediate); invalid distance 0.

## Compatibility notes

Delta matches liblzma for the distance used as a raw filter. x86 BCJ is a simplified reversible transform, not claimed equal to `lzma_simple_x86_*` on arbitrary binaries. No differential column.

## Open questions

ARM/ARM64/PowerPC/IA64/SPARC BCJ, and embedding Delta/BCJ as `.xz` Block filters, are later work.
