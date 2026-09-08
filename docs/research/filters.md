# Filters (Delta, BCJ x86)

## Scope

Standalone Delta and a simplified x86 BCJ (E8/E9 relative-offset rewrite). These can wrap LZMA/LZMA2/XZ payloads via `EncodeOptions.filters` / `DecodeOptions.filters`. XZ Block Headers also support the container-native Delta filter followed by LZMA2. XZ BCJ and other ISA filters remain unsupported as container filters; unknown XZ filter IDs decode as `UnsupportedFeature`.

## Specification

XZ Utils filter documentation:

- **Delta**: distance `1..=256`. Encode `out[i] = in[i] - hist[i % distance]`; decode adds. History starts at zeros. In an XZ Block Header, Delta properties are one byte with value `distance - 1`, so distance 1 is `0x00`, 4 is `0x03`, and 256 is `0xFF`. The task note that said `256 -> 0` was checked against `xz --delta=dist=256` and is not the XZ container encoding used by liblzma.
- **x86 BCJ**: convert relative `E8`/`E9` 32-bit offsets to/from absolute using unsigned wrapping `now_pos + i + 5` (`uint32_t` IP). Full liblzma BCJ also tracks MSByte status for overlapping instructions; this pass is the reversible subset used for round-trip tests.

Filter IDs (for `.xz` headers, not this API enum): Delta `0x03`, x86 `0x04`, LZMA2 `0x21`.

## Reference implementation

`src/liblzma/simple/x86.c`, `src/liblzma/delta/delta_*.c`.

## Data model

`FilterSpec::{ Delta(distance), BcjX86(start_offset), Lzma1, Lzma2 }`. LZMA1/LZMA2 in the extra chain are configuration errors (the format already has a codec).

## Algorithm

Root-package `EncodeOptions.filters` applies extra filters in array order, then the selected codec/container. Root-package decode runs the codec/container, then extra filters in reverse order.

XZ container-native Delta is separate from root-package extra filters: `xz` decodes a Block filter chain of `Delta -> LZMA2` by LZMA2-decoding the filtered bytes, then applying Delta decode before Block Check verification. `xz.encode_xz(..., delta_distance=n)` applies Delta encode before LZMA2 and writes two filter records (`0x03` then `0x21`) into the Block Header. Distance `0` means no container Delta filter.

Delta distance outside `1..=256` raises `FilterError::InvalidDistance` (mapped to `InvalidConfiguration` at the root).

## Invariants

- `delta_decode(delta_encode(x, d), d) == x`
- `decode_xz(encode_xz(x, delta_distance=d)) == x` for `d in {1, 4, 256}`
- `bcj_x86(bcj_x86(x, off, true), off, false) == x` for the implemented E8/E9 rewrite
- Unknown `.xz` filter ID does not silently skip
- XZ Delta may appear only before the final LZMA2 filter; Delta as the last filter is `Data`

## Edge cases

Distance 1, 4, and 256; empty input; `E8` near the last four bytes (must not rewrite a truncated immediate); high-bit immediates; non-zero `start_offset`.

## Error cases

Distance 0 or > 256 in root-package extra filters; `xz.encode_xz` treats `delta_distance=0` as no Delta filter and rejects negative or >256 distances as `Data`. Putting `Lzma1`/`Lzma2` in the extra filter chain is invalid configuration. In XZ Block Headers, Delta property size other than one byte, Delta as the final filter, and filter chains longer than two filters are rejected.

## Test vectors

Delta `"\x01\x02\x03\x04\x05"` distance 1; 300-byte run distance 256; BCJ `E8 10 00 00 00 90 90`; high-bit immediates with non-zero `start_offset`; truncated `E8` (no 4-byte immediate); invalid distance 0. XZ container Delta tests cover self-encoded distances 1 / 4 / 256, embedded `xz --delta=dist=1/4/256 --lzma2=preset=0 --check=crc32` reference files for `"abcdefabcdef"`, property byte `0xFF` for distance 256, malformed Delta property length, Delta as final filter, and three-filter chains.

## Compatibility notes

Delta matches liblzma as both a standalone transform and an XZ container filter for the tested distances. XZ Delta encoder output is accepted by Python `lzma` and `xz -d` through `scripts/diff_encode.py`. x86 BCJ is a simplified reversible transform, not claimed equal to `lzma_simple_x86_*` on arbitrary binaries.

## Open questions

Full XZ x86 BCJ (including MSByte / `prev_mask`) and ARM/ARM64/PowerPC/IA64/SPARC BCJ container filters are later work.
