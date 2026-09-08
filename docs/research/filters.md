# Filters (Delta, BCJ x86 / ARM)

## Scope

Standalone Delta plus the full x86 and ARM BCJ transforms (`simple/x86.c`, `simple/arm.c`), and XZ Block-Header chains `Delta -> LZMA2`, `x86 -> LZMA2`, and `ARM -> LZMA2`. Root-package extra filters wrap LZMA/LZMA2/XZ payloads via `EncodeOptions.filters` / `DecodeOptions.filters`. Other ISA BCJ filters (ARM64/ARM-Thumb/PowerPC/IA64/SPARC) remain unsupported; unknown XZ filter IDs decode as `UnsupportedFeature`.

## Specification

XZ Utils filter documentation:

- **Delta**: distance `1..=256`. Encode `out[i] = in[i] - hist[i % distance]`; decode adds. History starts at zeros. In an XZ Block Header, Delta properties are one byte with value `distance - 1`, so distance 1 is `0x00`, 4 is `0x03`, and 256 is `0xFF`.
- **ARM (32-bit) BCJ** (`simple/arm.c`): for every four-byte word whose top byte is `0xEB` (B/BL), adjust the 24-bit branch offset field by the eight-byte pipeline position with 32-bit wrapping: encode `dest = (start_offset + i + 8 + (field << 2)) >> 2`, decode `dest = ((field << 2) - (start_offset + i + 8)) >> 2`. Words are processed in four-byte groups aligned to `start_offset` (start offsets must be a multiple of four). In an XZ Block the offset is 0 and ARM has **no** filter options (zero-length property, ID `0x07`).
- **x86 BCJ**: converts relative `E8`/`E9` 32-bit offsets to/from absolute using unsigned 32-bit wrapping `now_pos + i + 5`. The full liblzma filter is a five-byte sliding-window state machine: it records which of the last five byte positions can start an instruction (`prev_mask`, seeded with `prev_pos = -5`) and only rewrites an `E8`/`E9` whose immediate's top byte is `0x00` or `0xFF` and whose MSByte status is unambiguous (`(prev_mask >> 1) <= 4 && (prev_mask >> 1) != 3`); when ambiguous it inverts `dest` bits above the relevant byte (`1U << (32 - i*8) - 1`) and re-derives `dest` until the examined byte is no longer `0x00`/`0xFF`. Filter instances start at `start_offset`; in an XZ Block the offset is 0 and x86 has **no** filter options (zero-length property, ID `0x04`).

Filter IDs (for `.xz` headers, not this API enum): Delta `0x03`, x86 `0x04`, ARM `0x07`, LZMA2 `0x21`.

## Reference implementation

`src/liblzma/simple/x86.c`, `simple/arm.c`, and `simple_coder.c` (xz 5.8), `src/liblzma/delta/delta_*.c`. Byte-level x86 vectors are generated with the system `lzma_bcj_x86_encode/decode` (xz 5.8.3) and embedded in the tests; ARM is verified against an `xz --arm` reference file plus self round-trips because liblzma exposes no standalone `lzma_bcj_arm_encode/decode`.

## Data model

`FilterSpec::{ Delta(distance), BcjX86(start_offset), Lzma1, Lzma2 }`. LZMA1/LZMA2 in the extra chain are configuration errors (the format already has a codec). The root-package `bcj_x86` primitive is the full transform; the container x86 / ARM filters share the same whole-buffer transforms with `start_offset = 0`.

## Algorithm

Root-package `EncodeOptions.filters` applies extra filters in array order, then the selected codec/container. Root-package decode runs the codec/container, then extra filters in reverse order. Both directions use `bcj_x86(buffer, start_offset, encode)` which is a one-shot whole-buffer pass (last <5 bytes pass through unchanged).

XZ container-native pre-filters are separate from root-package extra filters: `xz` decodes a Block chain `Delta -> LZMA2` / `x86 -> LZMA2` / `ARM -> LZMA2` by LZMA2-decoding the filtered bytes, then applying the pre-filter's inverse (Delta-decode, or x86/ARM decode) before Block Check verification. `xz.encode_xz(..., delta_distance=n)` / `(..., bcj_x86=true)` / `(..., bcj_arm=true)` apply the chosen pre-filter before LZMA2 and write the two filter records (`0x03` then `0x21`, `0x04` then `0x21`, or `0x07` then `0x21`) into the Block Header. At most one pre-filter is allowed (any two together, or any three-filter chain, is rejected).

Delta distance outside `1..=256` raises `FilterError::InvalidDistance` (mapped to `InvalidConfiguration` at the root); `encode_xz` treats distance 0 as "no Delta" and rejects negative or >256 distances as `Data`.

## Invariants

- `delta_decode(delta_encode(x, d), d) == x`
- `decode_xz(encode_xz(x, delta_distance=d)) == x` for `d in {1, 4, 256}`
- `decode_xz(encode_xz(x, bcj_x86=true)) == x`
- `decode_xz(encode_xz(x, bcj_arm=true)) == x`
- `bcj_x86(bcj_x86(x, off, true), off, false) == x`; likewise `bcj_arm`
- `bcj_x86` output equals `lzma_bcj_x86_encode/decode` byte-for-byte on the embedded vectors (start offsets 0, 1, 4096, and a wrapping `0xFFFFFFF0`), including adjacent/overlapping `E8`/`E9`
- `bcj_arm` decodes `xz --arm` output byte-for-byte and its encode output is accepted by `xz -d` / Python `lzma`
- Unknown `.xz` filter ID does not silently skip
- XZ Delta/x86/ARM may appear only before the final LZMA2 filter; any of them as the last filter is `Data`; x86/ARM properties must be empty; Delta properties must be one byte
- Chains of more than two filters are `UnsupportedFeature`

## Edge cases

Distance 1, 4, and 256; empty input; `E8`/`E9` in the last four bytes (not rewritten); high-bit immediates; non-zero and wrapping `start_offset`; two `E8`/`E9` whose opcode bytes lie inside another instruction's immediate (the MSByte / `prev_mask` cases); immediate top bytes `0x00` and `0xFF`; ARM words without a `0xEB` top byte (unchanged) and a trailing partial word (passes through).

## Error cases

Distance 0 or > 256 in root-package extra filters; `encode_xz` rejects `delta_distance` outside 0..=256 and any combination of two or more of `delta_distance != 0`, `bcj_x86`, `bcj_arm` as `Data`. Putting `Lzma1`/`Lzma2` in the extra filter chain is invalid configuration. In XZ Block Headers: Delta property size other than one byte, x86/ARM property size other than zero, Delta/x86/ARM as the final filter, and chains longer than two filters are rejected (`Data` for recognized-but-misplaced filters/properties, `Unsupported` for unknown IDs and over-long chains).

## Test vectors

Delta `"\x01\x02\x03\x04\x05"` distance 1; 300-byte run distance 256; BCJ `E8 10 00 00 00 90 90`; high-bit immediates with non-zero `start_offset`; truncated `E8` (no 4-byte immediate); empty input; `lzma_bcj_x86_*` exact outputs for `E8 00 00 00 FF 90`, a 17-byte overlapping segment (encode at start 0 and 4096, decode back), and `E8 01 02 03 FF E9 04 05 06 00`; ARM exact vectors for a single `00 00 00 EB` word (start 0 / 4096 / wrapping `0xFFFFFFF8`), a two-word buffer, and trailing partial words. XZ container tests cover self-encoded x86 and ARM BCJ round-trips (x86-laden 1808-byte and ARM-laden 1922-byte payloads, Block Header `04 00` / `07 00` record checks), the embedded `xz --x86` and `xz --arm` reference files, `xz --delta` distances 1 / 4 / 256, malformed Delta property length, non-zero x86/ARM property length, Delta/x86/ARM as final filter, and three-filter chains.

## Compatibility notes

Delta matches liblzma as both a standalone transform and an XZ container filter for the tested distances. The x86 BCJ is the full liblzma transform (not a reversible subset): its output is byte-identical to `lzma_simple_x86_*`, a reference `xz --x86` file decodes, and this encoder's x86-BCJ+LZMA2 `.xz` is decoded by Python `lzma` and `xz -d` via `scripts/diff_encode.py`. The ARM BCJ is verified against a reference `xz --arm` file and its ARM-BCJ+LZMA2 encode output is accepted by Python `lzma` and `xz -d`. Root-package extra `BcjX86` round-trips use the same full transform.

## Open questions

Per-ISA BCJ container filters (ARM64/ARM-Thumb/PowerPC/IA64/SPARC) and x86/ARM combined with Delta in one chain are later work.
