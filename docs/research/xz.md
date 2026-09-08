# XZ container

## Scope

Single-stream and concatenated `.xz` files with one or more Blocks per Stream, LZMA2 filter, an optional Delta or x86-BCJ filter before LZMA2, and Check None / CRC32 / CRC64 / SHA-256. Other ISA container filters (ARM/ARM64/ARM-Thumb/PowerPC/IA64/SPARC/...) are out of scope (raise `UnsupportedFeature`).

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
8. Stream Padding between concatenated Streams is zero or more null bytes, and the padding length must be a multiple of four.

Check IDs used: `0` None, `1` CRC32, `4` CRC64, `0x0A` SHA-256.

Delta filter ID is `0x03` with a 1-byte distance property encoded as `distance - 1`. x86 BCJ filter ID is `0x04` with **no** filter properties (zero-length). LZMA2 filter ID is `0x21` with a 1-byte dictionary property. The supported chains are `LZMA2`, `Delta -> LZMA2`, and `x86 -> LZMA2` (at most one pre-filter before LZMA2).

Unpadded Size in the Index is Block Header + Compressed Data + Check, excluding Block Padding.

## Reference implementation

XZ Utils `stream_encoder.c` / `block_decoder.c` / `index.c`. Layout taken from the file-format document. Multi-Block reference files are produced with `xz --block-size=`.

## Data model

This encoder writes exactly one Block with compressed-size and uncompressed-size present (`Block Flags` bits 6 and 7), one LZMA2 filter optionally preceded by a Delta or x86 BCJ filter record, then Index and Footer.

The decoder loops: while the next byte is not `0x00`, parse a Block; then parse Index and Footer. Index `Number of Records` must equal the number of Blocks actually decoded; each record's Unpadded Size and Uncompressed Size must match that Block.

## Algorithm

Encode: optionally pre-filter plaintext with x86 BCJ or Delta (at most one) → LZMA2-compress the filtered bytes → Stream Header → Block Header (size byte is `(1 + content) / 4`, content padded so the header without CRC is a multiple of 4) → payload → pad → check of **uncompressed** bytes → Index (one record) → Footer.

Decode one Stream: verify magic and header CRCs; for each Block, require the final filter to be LZMA2 and allow at most one preceding Delta or x86 filter; if Compressed Size is present, only that many bytes are fed to the LZMA2 decoder and they must be consumed exactly (the `0x00` end marker must be the last byte of that window); undo the pre-filter on the LZMA2 output (Delta-decode, or x86-decode with `start_offset` 0); if Uncompressed Size is present, it must equal the final plaintext length; if Compressed Size is absent, parse LZMA2 until the `0x00` end marker (subsequent Blocks / Index are not part of that window because the LZMA2 decoder stops at the end marker); skip Block Padding; verify that Block's check over the final plaintext unless `ignore_check`. Concatenate plaintext across Blocks. Index records must match every Block (zero records for an empty Stream).

With `concatenated=false`, any byte after the Stream Footer magic `YZ` is `Data`. With `concatenated=true`, after each Footer the decoder skips Stream Padding (null bytes only, length multiple of four) and decodes the next `.xz` Stream if bytes remain. A truncated next Stream header is `Eof`; non-null padding or padding whose zero run is not a multiple of four is `Data`.

## Invariants

- `decode_xz(encode_xz(x)) == x` for None/CRC32/CRC64/SHA-256
- `decode_xz(encode_xz(x, delta_distance=d)) == x` for Delta distances 1, 4, and 256
- `decode_xz(encode_xz(x, bcj_x86=true)) == x` (self-encoded x86 BCJ Blocks)
- `decode_xz(stream_a || padding || stream_b, concatenated=true) == plain_a || plain_b` when `padding` is all zeros and its length is a multiple of four
- Header and Index CRCs match `crc32` of the documented fields
- Footer ends with `YZ`
- Index record count equals the number of Blocks
- Index `(unpadded_size, uncompressed_size)` of record *i* matches decoded Block *i*
- Block Header compressed-size VLI, when present, matches LZMA2 bytes consumed
- Block Header uncompressed-size VLI, when present, matches that Block's plaintext length
- VLIs use the shortest encoding; Block Header padding after the filter properties is zeros
- Unknown filter ID or unknown Check ID → `UnsupportedFeature`
- Chains with more than two filters (more than one pre-filter before LZMA2) → `UnsupportedFeature`
- Delta or x86 BCJ as the final filter, or malformed Delta/LZMA2/x86 properties → `Data` (x86 BCJ must have a zero-length property)
- Stream Flags reserved bits, Block Flags reserved bits, Footer CRC mismatch, Backward Size mismatch, Footer Flags copy mismatch, Index padding ≠ 0, Block Padding ≠ 0 → `Data`

## Edge cases

Empty payload (0 Blocks, empty Index); single Block; 2+ Blocks; compressed size VLI of one byte; check field length 0/4/8/32; dictionary property for 4 KiB vs preset-6 8 MiB; Delta distances 1/4/256; x86 BCJ blocks with adjacent/overlapping E8/E9 and 0x00/0xFF immediate top bytes; truncation in a later Block's Header / Data / Check; two and three concatenated Streams; Stream Padding of 4 and 8 null bytes between Streams.

## Error cases

Bad magic; Stream Flags CRC mismatch; Block Header CRC mismatch; non-zero header/block padding; overlong VLI; check mismatch; truncated header or payload (including a later Block); unsupported filter chain; malformed filter properties; leftover bytes after Footer when concatenated mode is off; non-zero Stream Padding; Stream Padding zero run whose length is not a multiple of four; truncated next Stream header in concatenated mode; `check_id` other than 0/1/4/10 on encode; Index record count or sizes that do not match the decoded Blocks.

## Test vectors

Self-encoded `"xz container roundtrip"`; empty; CRC32 / SHA-256 checks; self-encoded Delta distances 1 / 4 / 256; self-encoded x86 BCJ Block (1808-byte x86-laden payload) round-trip plus Block Header record checks; mutated filter ID `0x21 → 0x06`; malformed Delta property size; x86 property size must be zero; Delta as final filter; x86 BCJ as final filter; unknown pre-filter ID (`0x05`); three-filter chain; `notxz!` magic; non-zero Block Data Padding; Index `Number of Records` not equal to the Block count; unknown Check ID on decode; `liblzma` FORMAT_XZ vectors for empty, `"hello lzma"`, `"a"`, and 64-byte `0xAA` run; `xz --block-size=2 --check=crc32` vectors for `"aabb"` (2 Blocks) and `"aabbcc"` (3 Blocks); `xz --check=sha256` vector for `"sha256 reference"`; `xz --delta=dist=1/4/256 --lzma2=preset=0 --check=crc32` vectors for `"abcdefabcdef"`; `xz --x86 --lzma2=preset=6 --check=crc64` vector for the same 1808-byte payload. Concatenated tests cover two self-encoded Streams, 4- and 8-byte Stream Padding, three Streams including an empty Stream, `Format::Auto`, streaming `Decoder::write` plus `finish`, default rejection, malformed padding, and truncated next headers. Encode-side CI dumps this encoder's `.xz` (CRC32 / CRC64 / None / SHA-256, Delta+LZMA2, x86-BCJ+LZMA2, presets 0 and 6, including >64 KiB) and requires Python `lzma.FORMAT_XZ` plus `xz -d` to recover the plaintext. Encoder output remains a single Block.

## Compatibility notes

Files are intended to be well-formed `.xz` for the subset above. Byte-level match with `xz -6` is not required (different LZMA encoder). Decoder-side `liblzma` vectors are embedded in `xz_test.mbt`. Encoder output is checked by a reference decoder in CI (`scripts/diff_encode.py`). Multi-Block **decode** is checked against `xz --block-size=` files; concatenated decode is checked with self-encoded Streams because `.xz` Stream Padding and header boundaries are container-level syntax independent of the LZMA payload. Delta+LZMA2 and x86-BCJ+LZMA2 decode use embedded `xz` reference files, and both container chains' encode output is decoded by Python `lzma` and `xz -d`. This encoder does not emit multiple Blocks or concatenated Streams.

## Open questions

Other ISA BCJ filters (ARM/ARM64/ARM-Thumb/PowerPC/IA64/SPARC) inside the Block Header remain out of scope until each has a research note and per-ISA reference vectors. Whether the encoder should split large plaintext into multiple Blocks or emit concatenated Streams is a later task; it is not required for decoder compatibility.
