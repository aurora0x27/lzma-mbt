# XZ container

## Scope

Single-stream `.xz` files with one or more Blocks, LZMA2 filter, and Check None / CRC32 / CRC64. SHA-256, concatenated Streams, and extra filters in the container header are out of scope (raise `UnsupportedFeature`).

The encoder still writes exactly one Block. The decoder accepts 0..N Blocks.

## Specification

[The .xz File Format](https://tukaani.org/xz/xz-file-format.txt):

1. Stream Header: magic `FD 37 7A 58 5A 00`, two-byte flags (byte0 = 0, byte1 = check ID), CRC32 of flags.
2. Zero or more Blocks. Each Block Header: size encoded as `(header_size / 4) - 1` including CRC32; flags; optional compressed/uncompressed VLIs; filter list; padding; CRC32 of the header except the CRC field.
3. Compressed Data: LZMA2 stream (each Block is an independent LZMA2 stream).
4. Block Padding: 0–3 zero bytes so (Block Header + Compressed Data) is a multiple of four.
5. Check: 0 / 4 / 8 / 32 bytes according to Stream Flags. The Check covers that Block's **uncompressed** bytes only.
6. Index: indicator `0x00` (a Block Header Size of 0 is invalid, so this byte is never a Block), number of records, `(unpadded_size, uncompressed_size)` VLIs for **each** Block in order, padding, CRC32.
7. Stream Footer: CRC32 of (backward size + flags), backward size `(index_size / 4) - 1`, copy of Stream Flags, magic `59 5A`.

Check IDs used: `0` None, `1` CRC32, `4` CRC64, `0x0A` SHA-256 (rejected).

LZMA2 filter ID is `0x21` with a 1-byte dictionary property.

Unpadded Size in the Index is Block Header + Compressed Data + Check, excluding Block Padding.

## Reference implementation

XZ Utils `stream_encoder.c` / `block_decoder.c` / `index.c`. Layout taken from the file-format document. Multi-Block reference files are produced with `xz --block-size=`.

## Data model

This encoder writes exactly one Block with compressed-size and uncompressed-size present (`Block Flags` bits 6 and 7), one LZMA2 filter, then Index and Footer.

The decoder loops: while the next byte is not `0x00`, parse a Block; then parse Index and Footer. Index `Number of Records` must equal the number of Blocks actually decoded; each record's Unpadded Size and Uncompressed Size must match that Block.

## Algorithm

Encode: LZMA2-compress plaintext → Stream Header → Block Header (size byte is `(1 + content) / 4`, content padded so the header without CRC is a multiple of 4) → payload → pad → check of **uncompressed** bytes → Index (one record) → Footer.

Decode: verify magic and header CRCs; for each Block, require one LZMA2 filter; if Compressed Size is present, only that many bytes are fed to the LZMA2 decoder and they must be consumed exactly (the `0x00` end marker must be the last byte of that window); if Uncompressed Size is present, it must equal the decoded plaintext length; if Compressed Size is absent, parse LZMA2 until the `0x00` end marker (subsequent Blocks / Index are not part of that window because the LZMA2 decoder stops at the end marker); skip Block Padding; verify that Block's check unless `ignore_check`. Concatenate plaintext across Blocks. Index records must match every Block (zero records for an empty Stream). Bytes after Footer magic `YZ` are `Data`.

## Invariants

- `decode_xz(encode_xz(x)) == x` for None/CRC32/CRC64
- Header and Index CRCs match `crc32` of the documented fields
- Footer ends with `YZ`
- Index record count equals the number of Blocks
- Index `(unpadded_size, uncompressed_size)` of record *i* matches decoded Block *i*
- Block Header compressed-size VLI, when present, matches LZMA2 bytes consumed
- Block Header uncompressed-size VLI, when present, matches that Block's plaintext length
- VLIs use the shortest encoding; Block Header padding after the filter properties is zeros
- Unknown filter ID or SHA-256 check → `UnsupportedFeature`
- More than one Block filter → `UnsupportedFeature`
- Stream Flags reserved bits, Block Flags reserved bits, Footer CRC mismatch, Backward Size mismatch, Footer Flags copy mismatch, Index padding ≠ 0, Block Padding ≠ 0 → `Data`

## Edge cases

Empty payload (0 Blocks, empty Index); single Block; 2+ Blocks; compressed size VLI of one byte; check field length 0/4/8; dictionary property for 4 KiB vs preset-6 8 MiB; truncation in a later Block's Header / Data / Check.

## Error cases

Bad magic; Stream Flags CRC mismatch; Block Header CRC mismatch; non-zero header/block padding; overlong VLI; check mismatch; truncated header or payload (including a later Block); more than one filter; leftover bytes after Footer; `check_id` other than 0/1/4 on encode; Index record count or sizes that do not match the decoded Blocks.

## Test vectors

Self-encoded `"xz container roundtrip"`; empty; CRC32 check; mutated filter ID `0x21 → 0x06`; `notxz!` magic; non-zero Block Data Padding; Index `Number of Records` not equal to the Block count; unknown Check ID on decode; `liblzma` FORMAT_XZ vectors for empty, `"hello lzma"`, `"a"`, and 64-byte `0xAA` run; `xz --block-size=2 --check=crc32` vectors for `"aabb"` (2 Blocks) and `"aabbcc"` (3 Blocks). Encode-side CI dumps this encoder's `.xz` (CRC32 / CRC64 / None, presets 0 and 6, including >64 KiB) and requires Python `lzma.FORMAT_XZ` plus `xz -d` to recover the plaintext. Encoder output remains a single Block.

## Compatibility notes

Files are intended to be well-formed `.xz` for the subset above. Byte-level match with `xz -6` is not required (different LZMA encoder). Decoder-side `liblzma` vectors are embedded in `xz_test.mbt`. Encoder output is checked by a reference decoder in CI (`scripts/diff_encode.py`). Multi-Block **decode** is checked against `xz --block-size=` files; this encoder does not emit multiple Blocks.

## Open questions

Concatenated Streams, SHA-256, and Delta/BCJ inside the Block Header remain out of scope. Whether the encoder should split large plaintext into multiple Blocks is a later task; it is not required for decoder compatibility.
