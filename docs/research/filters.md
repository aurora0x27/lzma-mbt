# Filters (Delta, BCJ x86)

## Scope

Standalone Delta and the full x86 BCJ (`simple/x86.c`) transform, plus XZ Block-Header chains `Delta -> LZMA2` and `x86 -> LZMA2`. Root-package extra filters wrap LZMA/LZMA2/XZ payloads via `EncodeOptions.filters` / `DecodeOptions.filters`. Other ISA BCJ filters (ARM/ARM64/ARM-Thumb/PowerPC/IA64/SPARC) remain unsupported; unknown XZ filter IDs decode as `UnsupportedFeature`.

## Specification

XZ Utils filter documentation:

- **Delta**: distance `1..=256`. Encode `out[i] = in[i] - hist[i % distance]`; decode adds. History starts at zeros. In an XZ Block Header, Delta properties are one byte with value `distance - 1`, so distance 1 is `0x00`, 4 is `0x03`, and 256 is `0xFF`.
- **x86 BCJ**: converts relative `E8`/`E9` 32-bit offsets to/from absolute using unsigned 32-bit wrapping `now_pos + i + 5`. The full liblzma filter is a five-byte sliding-window state machine: it records which of the last five byte positions can start an instruction (`prev_mask`, seeded with `prev_pos = -5`) and only rewrites an `E8`/`E9` whose immediate's top byte is `0x00` or `0xFF` and whose MSByte status is unambiguous (`(prev_mask >> 1) <= 4 && (prev_mask >> 1) != 3`); when ambiguous it inverts `dest` bits above the relevant byte (`1U << (32 - i*8) - 1`) and re-derives `dest` until the examined byte is no longer `0x00`/`0xFF`. Filter instances start at `start_offset`; in an XZ Block the offset is 0 and x86 has **no** filter options (zero-length property, ID `0x04`).

Filter IDs (for `.xz` headers, not this API enum): Delta `0x03`, x86 `0x04`, LZMA2 `0x21`.

## Reference implementation

`src/liblzma/simple/x86.c` and `simple_coder.c` (xz 5.8), `src/liblzma/delta/delta_*.c`. Byte-level vectors are generated with the system `lzma_bcj_x86_encode/decode` (xz 5.8.3) and embedded in the tests.

## Data model

`FilterSpec::{ Delta(distance), BcjX86(start_offset), Lzma1, Lzma2 }`. LZMA1/LZMA2 in the extra chain are configuration errors (the format already has a codec). The root-package `bcj_x86` primitive is the full transform; the container x86 filter shares it with `start_offset = 0`.

## Algorithm

Root-package `EncodeOptions.filters` applies extra filters in array order, then the selected codec/container. Root-package decode runs the codec/container, then extra filters in reverse order. Both directions use `bcj_x86(buffer, start_offset, encode)` which is a one-shot whole-buffer pass (last <5 bytes pass through unchanged).

XZ container-native pre-filters are separate from root-package extra filters: `xz` decodes a Block chain `Delta -> LZMA2` / `x86 -> LZMA2` by LZMA2-decoding the filtered bytes, then applying Delta-decode or x86-decode before Block Check verification. `xz.encode_xz(..., delta_distance=n)` / `(..., bcj_x86=true)` apply the chosen pre-filter before LZMA2 and write the two filter records (`0x03` then `0x21`, or `0x04` then `0x21`) into the Block Header. At most one pre-filter is allowed (Delta and x86 together, or any three-filter chain, is rejected).

Delta distance outside `1..=256` raises `FilterError::InvalidDistance` (mapped to `InvalidConfiguration` at the root); `encode_xz` treats distance 0 as "no Delta" and rejects negative or >256 distances as `Data`.

## Invariants

- `delta_decode(delta_encode(x, d), d) == x`
- `decode_xz(encode_xz(x, delta_distance=d)) == x` for `d in {1, 4, 256}`
- `decode_xz(encode_xz(x, bcj_x86=true)) == x`
- `bcj_x86(bcj_x86(x, off, true), off, false) == x`
- `bcj_x86` output equals `lzma_bcj_x86_encode/decode` byte-for-byte on the embedded vectors (start offsets 0, 1, 4096, and a wrapping `0xFFFFFFF0`), including adjacent/overlapping `E8`/`E9`
- Unknown `.xz` filter ID does not silently skip
- XZ Delta/x86 may appear only before the final LZMA2 filter; either as the last filter is `Data`; x86 properties must be empty; Delta properties must be one byte
- Chains of more than two filters are `UnsupportedFeature`

## Edge cases

Distance 1, 4, and 256; empty input; `E8`/`E9` in the last four bytes (not rewritten); high-bit immediates; non-zero and wrapping `start_offset`; two `E8`/`E9` whose opcode bytes lie inside another instruction's immediate (the MSByte / `prev_mask` cases); immediate top bytes `0x00` and `0xFF`.

## Error cases

Distance 0 or > 256 in root-package extra filters; `encode_xz` rejects `delta_distance` outside 0..=256 and the combination of `delta_distance != 0` with `bcj_x86=true` as `Data`. Putting `Lzma1`/`Lzma2` in the extra filter chain is invalid configuration. In XZ Block Headers: Delta property size other than one byte, x86 property size other than zero, Delta or x86 as the final filter, and chains longer than two filters are rejected (`Data` for recognized-but-misplaced filters/properties, `Unsupported` for unknown IDs and over-long chains).

## Test vectors

Delta `"\x01\x02\x03\x04\x05"` distance 1; 300-byte run distance 256; BCJ `E8 10 00 00 00 90 90`; high-bit immediates with non-zero `start_offset`; truncated `E8` (no 4-byte immediate); empty input; `lzma_bcj_x86_*` exact outputs for `E8 00 00 00 FF 90`, a 17-byte overlapping segment (encode at start 0 and 4096, decode back), and `E8 01 02 03 FF E9 04 05 06 00`. XZ container tests cover self-encoded x86 BCJ round-trip (1808-byte x86-laden payload, Block Header `04 00` record checks), the embedded `xz --x86 --lzma2=preset=6 --check=crc64` reference file, `xz --delta` distances 1 / 4 / 256, malformed Delta property length, non-zero x86 property length, Delta and x86 as final filter, and three-filter chains.

## Compatibility notes

Delta matches liblzma as both a standalone transform and an XZ container filter for the tested distances. The x86 BCJ is the full liblzma transform (not a reversible subset): its output is byte-identical to `lzma_simple_x86_*`, a reference `xz --x86` file decodes, and this encoder's x86-BCJ+LZMA2 `.xz` is decoded by Python `lzma` and `xz -d` via `scripts/diff_encode.py`. Root-package extra `BcjX86` round-trips use the same full transform.

## Open questions

Per-ISA BCJ container filters (ARM/ARM64/ARM-Thumb/PowerPC/IA64/SPARC) and x86 combined with Delta in one chain are later work.
