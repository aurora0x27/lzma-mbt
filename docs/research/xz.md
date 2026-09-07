# XZ container

## Scope

Single-stream `.xz` files with one Block, LZMA2 filter, and Check None / CRC32 / CRC64. SHA-256, multiple Blocks, concatenated Streams, and extra filters in the container header are out of scope (raise `UnsupportedFeature`).

## Specification

[The .xz File Format](https://tukaani.org/xz/xz-file-format.txt):

1. Stream Header: magic `FD 37 7A 58 5A 00`, two-byte flags (byte0 = 0, byte1 = check ID), CRC32 of flags.
2. Block Header: size encoded as `(header_size / 4) - 1` including CRC32; flags; optional compressed/uncompressed VLIs; filter list; padding; CRC32 of the header except the CRC field.
3. Compressed Data: LZMA2 stream.
4. Block Padding: 0–3 zero bytes so (Block Header + Compressed Data) is a multiple of four.
5. Check: 0 / 4 / 8 / 32 bytes according to Stream Flags.
6. Index: indicator `0x00`, number of records, `(unpadded_size, uncompressed_size)` VLIs, padding, CRC32.
7. Stream Footer: CRC32 of (backward size + flags), backward size `(index_size / 4) - 1`, copy of Stream Flags, magic `59 5A`.

Check IDs used: `0` None, `1` CRC32, `4` CRC64, `0x0A` SHA-256 (rejected).

LZMA2 filter ID is `0x21` with a 1-byte dictionary property.

Unpadded Size in the Index is Block Header + Compressed Data + Check, excluding Block Padding.

## Reference implementation

XZ Utils `stream_encoder.c` / `block_decoder.c` / `index.c`. Layout taken from the file-format document.

## Data model

This encoder writes exactly one Block with compressed-size and uncompressed-size present (`Block Flags` bits 6 and 7), one LZMA2 filter, then Index and Footer.

## Algorithm

Encode: LZMA2-compress plaintext → Stream Header → Block Header (size byte is `(1 + content) / 4`, content padded so the header without CRC is a multiple of 4) → payload → pad → check of **uncompressed** bytes → Index → Footer.

Decode: verify magic and header CRCs; require one LZMA2 filter; if Compressed Size is present, only that many bytes are fed to the LZMA2 decoder and they must be consumed exactly (the `0x00` end marker must be the last byte of that window); if Uncompressed Size is present, it must equal the decoded plaintext length; if Compressed Size is absent, parse LZMA2 until the `0x00` end marker; skip Block Padding; verify check unless `ignore_check`. Index must contain exactly one record matching Unpadded Size and Uncompressed Size (or zero records for an empty Stream). Bytes after Footer magic `YZ` are `Data`.

## Invariants

- `decode_xz(encode_xz(x)) == x` for None/CRC32/CRC64
- Header and Index CRCs match `crc32` of the documented fields
- Footer ends with `YZ`
- Index `(unpadded_size, uncompressed_size)` matches the decoded Block
- Block Header compressed-size VLI, when present, matches LZMA2 bytes consumed
- Block Header uncompressed-size VLI, when present, matches plaintext length
- VLIs use the shortest encoding; Block Header padding after the filter properties is zeros
- Unknown filter ID or SHA-256 check → `UnsupportedFeature`
- More than one Block filter → `UnsupportedFeature`
- Stream Flags reserved bits, Block Flags reserved bits, Footer CRC mismatch, Backward Size mismatch, Footer Flags copy mismatch, Index padding ≠ 0, Block Padding ≠ 0 → `Data`

## Edge cases

Empty payload; compressed size VLI of one byte; check field length 0/4/8; dictionary property for 4 KiB vs preset-6 8 MiB.

## Error cases

Bad magic; Stream Flags CRC mismatch; Block Header CRC mismatch; non-zero header/block padding; overlong VLI; check mismatch; truncated header or payload; more than one filter; leftover bytes after Footer; `check_id` other than 0/1/4 on encode; Index sizes that do not match the Block.

## Test vectors

Self-encoded `"xz container roundtrip"`; empty; CRC32 check; mutated filter ID `0x21 → 0x06`; `notxz!` magic; non-zero Block Data Padding; Index `Number of Records ≠ 1`; unknown Check ID on decode; `liblzma` FORMAT_XZ vectors for empty, `"hello lzma"`, `"a"`, and 64-byte `0xAA` run.

## Compatibility notes

Files are intended to be well-formed `.xz` for the subset above. Byte-level match with `xz -6` is not required (different LZMA encoder). Decoder-side `liblzma` vectors are embedded in `xz_test.mbt`.

## Open questions

Multiple Blocks, concatenated Streams, SHA-256, and Delta/BCJ inside the Block Header remain out of scope.
