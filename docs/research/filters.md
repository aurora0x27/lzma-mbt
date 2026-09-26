# Filters (Delta, BCJ x86 / PowerPC / IA-64 / ARM / ARM-Thumb / ARM64)

## Scope

Standalone Delta plus the full x86 and ARM BCJ transforms (`simple/x86.c`, `simple/arm.c`), and XZ Block-Header chains `Delta -> LZMA2`, `x86 -> LZMA2`, `PowerPC -> LZMA2`, `IA-64 -> LZMA2`, `ARM -> LZMA2`, `ARM-Thumb -> LZMA2`, and `ARM64 -> LZMA2`. Root-package extra filters wrap LZMA/LZMA2/XZ payloads via `EncodeOptions.filters` / `DecodeOptions.filters`. The SPARC BCJ filter remains unsupported; unknown XZ filter IDs decode as `UnsupportedFeature`.

## Specification

XZ Utils filter documentation:

- **Delta**: distance `1..=256`. Encode `out[i] = in[i] - hist[i % distance]`; decode adds. History starts at zeros. In an XZ Block Header, Delta properties are one byte with value `distance - 1`, so distance 1 is `0x00`, 4 is `0x03`, and 256 is `0xFF`.
- **ARM (32-bit) BCJ** (`simple/arm.c`): for every four-byte word whose top byte is `0xEB` (B/BL), adjust the 24-bit branch offset field by the eight-byte pipeline position with 32-bit wrapping: encode `dest = (start_offset + i + 8 + (field << 2)) >> 2`, decode `dest = ((field << 2) - (start_offset + i + 8)) >> 2`. Words are processed in four-byte groups aligned to `start_offset` (start offsets must be a multiple of four). In an XZ Block the offset is 0 and ARM has **no** filter options (zero-length property, ID `0x07`).
- **ARM64 BCJ** (`simple/arm64.c`): reads 32-bit little-endian words in four-byte-aligned groups from `start_offset`. For a `BL` instruction (top six bits `0b100101`) it converts the full 26-bit immediate: encode adds `pc >> 2`, decode subtracts it (mod 2^26). For an `ADRP` instruction (`(word & 0x9F000000) == 0x90000000`) it converts the 21-bit page offset, but only when `(src + 0x00020000) & 0x001C0000 == 0` (within +/-512 MiB); otherwise the word is skipped. `start_offset` is 32-bit wrapping and rounded down to a multiple of four (container offset is 0, ID `0x0A`, no options).
- **PowerPC BCJ** (`simple/powerpc.c`): reads 4-byte big-endian branch words in four-byte-aligned groups from `start_offset`. When `(b0 >> 2) == 0x12` and `(b3 & 3) == 1`, it converts the 24-bit offset field (encode adds `start_offset + i`, decode subtracts it, wrapping), writing `0x48 | ((dest >> 24) & 3)` into `b0` and the remaining bytes of `dest`. In an XZ Block the offset is 0 and PowerPC has **no** filter options (zero-length property, ID `0x05`).
- **IA-64 BCJ** (`simple/ia64.c`): processes 16-byte bundles from `start_offset`. A `BRANCH_TABLE` lookup on the bundle template selects up to three 41-bit slot positions; when a selected slot holds a `brl` instruction (`(inst_norm >> 37) & 0xF == 5` and `(inst_norm >> 9) & 7 == 0`) its 21-bit offset field (bits 13..32 plus bit 36) is adjusted by `start_offset + i` in units of 16 bytes (encode adds, decode subtracts, wrapping). In an XZ Block the offset is 0 and IA-64 has **no** filter options (zero-length property, ID `0x06`).
- **ARM-Thumb BCJ** (`simple/armthumb.c`): reads halfword-aligned 32-bit Thumb `BL` pairs; when `(b[i+1] & 0xF8) == 0xF0` and `(b[i+3] & 0xF8) == 0xF8` it converts the 25-bit offset field (encode `dest = (start_offset + i + 4 + (field << 1)) >> 1`, decode subtracts), writing the `F0.. F8..` opcodes back. Processing is halfword-aligned from `start_offset` (start offsets must be even); a converted pair advances by four bytes, otherwise by two. In an XZ Block the offset is 0 and ARM-Thumb has **no** filter options (zero-length property, ID `0x08`).
- **x86 BCJ**: converts relative `E8`/`E9` 32-bit offsets to/from absolute using unsigned 32-bit wrapping `now_pos + i + 5`. The full liblzma filter is a five-byte sliding-window state machine: it records which of the last five byte positions can start an instruction (`prev_mask`, seeded with `prev_pos = -5`) and only rewrites an `E8`/`E9` whose immediate's top byte is `0x00` or `0xFF` and whose MSByte status is unambiguous (`(prev_mask >> 1) <= 4 && (prev_mask >> 1) != 3`); when ambiguous it inverts `dest` bits above the relevant byte (`1U << (32 - i*8) - 1`) and re-derives `dest` until the examined byte is no longer `0x00`/`0xFF`. Filter instances start at `start_offset`; in an XZ Block the offset is 0 and x86 has **no** filter options (zero-length property, ID `0x04`).

Filter IDs (for `.xz` headers, not this API enum): Delta `0x03`, x86 `0x04`, PowerPC `0x05`, IA-64 `0x06`, ARM `0x07`, ARM-Thumb `0x08`, ARM64 `0x0A`, LZMA2 `0x21`.

## Reference implementation

`src/liblzma/simple/x86.c`, `simple/powerpc.c`, `simple/ia64.c`, `simple/arm.c`, `simple/armthumb.c`, `simple/arm64.c`, and `simple_coder.c` (xz 5.8), `src/liblzma/delta/delta_*.c`. Byte-level x86 and ARM64 vectors are generated with the system `lzma_bcj_x86_encode/decode` and `lzma_bcj_arm64_encode/decode` (xz 5.8.3) and embedded in the tests; PowerPC, IA-64, ARM, and ARM-Thumb are verified against `xz --powerpc` / `xz --ia64` / `xz --arm` / `xz --armthumb` reference files plus self round-trips because liblzma exposes no standalone helper for them.

## Data model

`FilterSpec::{ Delta(distance), BcjX86(start_offset), Lzma1, Lzma2 }`. LZMA1/LZMA2 in the extra chain are configuration errors (the format already has a codec). The root-package `bcj_x86` primitive is the full transform; the container x86 / ARM filters share the same whole-buffer transforms with `start_offset = 0`.

## Algorithm

Root-package `EncodeOptions.filters` applies extra filters in array order, then the selected codec/container. Root-package decode runs the codec/container, then extra filters in reverse order. Both directions use `bcj_x86(buffer, start_offset, encode)` which is a one-shot whole-buffer pass (last <5 bytes pass through unchanged).

XZ container-native pre-filters are separate from root-package extra filters: `xz` decodes a Block chain `Delta -> LZMA2` / `x86 -> LZMA2` / `PowerPC -> LZMA2` / `IA-64 -> LZMA2` / `ARM -> LZMA2` / `ARM-Thumb -> LZMA2` / `ARM64 -> LZMA2` by LZMA2-decoding the filtered bytes, then applying the pre-filter's inverse (Delta-decode, or x86/PowerPC/IA-64/ARM/ARM-Thumb/ARM64 decode) before Block Check verification. `xz.encode_xz` selects the pre-filter with `delta_distance=n`, `bcj_x86=true`, `bcj_powerpc=true`, `bcj_ia64=true`, `bcj_arm=true`, `bcj_armthumb=true`, or `bcj_arm64=true`, and writes the two filter records (`0x03`/`0x04`/`0x05`/`0x06`/`0x07`/`0x08`/`0x0A` then `0x21`) into the Block Header. At most one pre-filter is allowed (any two together, or any three-filter chain, is rejected).

Delta distance outside `1..=256` raises `FilterError::InvalidDistance` (mapped to `InvalidConfiguration` at the root); `encode_xz` treats distance 0 as "no Delta" and rejects negative or >256 distances as `Data`.

## Invariants

- `delta_decode(delta_encode(x, d), d) == x`
- `decode_xz(encode_xz(x, delta_distance=d)) == x` for `d in {1, 4, 256}`
- `decode_xz(encode_xz(x, bcj_x86=true)) == x`
- `decode_xz(encode_xz(x, bcj_arm=true)) == x`
- `decode_xz(encode_xz(x, bcj_powerpc=true)) == x`
- `decode_xz(encode_xz(x, bcj_ia64=true)) == x`
- `decode_xz(encode_xz(x, bcj_armthumb=true)) == x`
- `decode_xz(encode_xz(x, bcj_arm64=true)) == x`
- `bcj_x86(bcj_x86(x, off, true), off, false) == x`; likewise `bcj_arm`
- `bcj_x86` output equals `lzma_bcj_x86_encode/decode` byte-for-byte on the embedded vectors (start offsets 0, 1, 4096, and a wrapping `0xFFFFFFF0`), including adjacent/overlapping `E8`/`E9`
- `bcj_powerpc` decodes `xz --powerpc` output; `bcj_ia64` decodes `xz --ia64` output; `bcj_arm` decodes `xz --arm` output; `bcj_armthumb` decodes `xz --armthumb` output; `bcj_arm64` matches `lzma_bcj_arm64_encode/decode` byte-for-byte on embedded vectors and decodes an `xz --arm64` file; all their encode outputs are accepted by `xz -d` / Python `lzma`
- Unknown `.xz` filter ID does not silently skip
- XZ Delta/x86/PowerPC/IA-64/ARM/ARM-Thumb/ARM64 may appear only before the final LZMA2 filter; any of them as the last filter is `Data`; the BCJ filters' properties must be empty; Delta properties must be one byte
- Chains of more than two filters are `UnsupportedFeature`

## Edge cases

Distance 1, 4, and 256; empty input; `E8`/`E9` in the last four bytes (not rewritten); high-bit immediates; non-zero and wrapping `start_offset`; two `E8`/`E9` whose opcode bytes lie inside another instruction's immediate (the MSByte / `prev_mask` cases); immediate top bytes `0x00` and `0xFF`; ARM words without a `0xEB` top byte (unchanged) and a trailing partial word (passes through).

## Error cases

Distance 0 or > 256 in root-package extra filters; `encode_xz` rejects `delta_distance` outside 0..=256 and any combination of two or more of `delta_distance != 0`, `bcj_x86`, `bcj_powerpc`, `bcj_ia64`, `bcj_arm`, `bcj_armthumb`, `bcj_arm64` as `Data`. Putting `Lzma1`/`Lzma2` in the extra filter chain is invalid configuration. In XZ Block Headers: Delta property size other than one byte, x86/PowerPC/IA-64/ARM/ARM-Thumb/ARM64 property size other than zero, Delta/x86/PowerPC/IA-64/ARM/ARM-Thumb/ARM64 as the final filter, and chains longer than two filters are rejected (`Data` for recognized-but-misplaced filters/properties, `Unsupported` for unknown IDs and over-long chains).

## Test vectors

Delta `"\x01\x02\x03\x04\x05"` distance 1; 300-byte run distance 256; BCJ `E8 10 00 00 00 90 90`; high-bit immediates with non-zero `start_offset`; truncated `E8` (no 4-byte immediate); empty input; `lzma_bcj_x86_*` exact outputs for `E8 00 00 00 FF 90`, a 17-byte overlapping segment (encode at start 0 and 4096, decode back), and `E8 01 02 03 FF E9 04 05 06 00`; ARM exact vectors for a single `00 00 00 EB` word (start 0 / 4096 / wrapping `0xFFFFFFF8`), a two-word buffer, and trailing partial words; ARM64 exact vectors for BL and in-range ADRP words at start 0 / 4096 and an out-of-range ADRP (unchanged); ARM-Thumb vectors for a Thumb `BL` pair at start 0 / 4096, non-matching halfwords, and fewer than four bytes; PowerPC vectors for a branch word at start 0 / 4096, near-miss words, and fewer than four bytes; IA-64 vectors for a bundle at offset 0 (identity) and at offset 16 (field += 1), plus a trailing partial bundle. XZ container tests cover self-encoded x86 and ARM BCJ round-trips (x86-laden 1808-byte, PowerPC-laden 2066-byte, IA-64-laden 2003-byte, ARM-laden 1922-byte, ARM-Thumb-laden 2243-byte, and ARM64-laden 1682-byte payloads, Block Header `04 00` / `05 00` / `06 00` / `07 00` / `08 00` / `0A 00` record checks), the embedded `xz --x86` and `xz --arm` reference files, `xz --delta` distances 1 / 4 / 256, malformed Delta property length, non-zero x86/PowerPC/IA-64/ARM/ARM-Thumb/ARM64 property length, Delta/x86/PowerPC/IA-64/ARM/ARM-Thumb/ARM64 as final filter, and three-filter chains.

## Compatibility notes

Delta matches liblzma as both a standalone transform and an XZ container filter for the tested distances. The x86 BCJ is the full liblzma transform (not a reversible subset): its output is byte-identical to `lzma_simple_x86_*`, a reference `xz --x86` file decodes, and this encoder's x86-BCJ+LZMA2 `.xz` is decoded by Python `lzma` and `xz -d` via `scripts/diff_encode.py`. The ARM BCJ is verified against a reference `xz --arm` file and its ARM-BCJ+LZMA2 encode output is accepted by Python `lzma` and `xz -d`. Root-package extra `BcjX86` round-trips use the same full transform.

## Open questions

The SPARC BCJ container filter and any x86/PowerPC/IA-64/ARM/ARM-Thumb/ARM64 combined with Delta in one chain are later work.
