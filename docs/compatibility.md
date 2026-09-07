# Compatibility matrix

Evidence, not intention. A cell is `yes` only when tests for that behavior exist and pass. Differential requires comparison against `liblzma` / `xz`.

| Feature | Decoder | Encoder | Streaming | Differential |
| --- | ---: | ---: | ---: | ---: |
| LZMA1 / `.lzma` | yes | yes | yes | decode |
| LZMA2 raw | yes | yes | yes | no |
| XZ | yes | yes | yes | decode |
| CRC32 | yes | N/A | N/A | yes |
| CRC64 | yes | N/A | N/A | yes |
| SHA-256 | no | no | N/A | no |
| BCJ / Delta | yes | yes | yes | no |
| Auto detect xz/lzma | yes | N/A | yes | no |
| concatenated xz | no | N/A | no | no |

Notes:

- Streaming uses the same `encode` / `decode` implementation at `Finish` (`Run` only buffers). Tests cover 1-byte `write`, 1-byte `code(..., Run)`, 1-byte output slots, `reset`, `Run` → `Ok`, `code` after `StreamEnd`, rejecting extra input after `Finish` while draining, empty `Run` to drain after `NeedOutput`, `finish()` returning remaining bytes after `NeedOutput`, retrying `Finish` after `BufferTooSmall` on an empty output buffer (`total_in` unchanged), `Finish` on a full non-empty buffer → `NeedOutput` without dropping input, decoder `SyncFlush` / `write` after `finish`, and `.xz` Footer CRC / Backward Size / reserved flags / Block Data Padding / Index record count.
- XZ encoder writes Stream Header, one LZMA2 Block (Block Header includes compressed and uncompressed size VLIs), Index, and Footer. SHA-256 check and concatenated Streams raise `UnsupportedFeature`. Bytes after Footer, or after a raw LZMA2 end marker, are `DataError`. Index must contain exactly one record whose sizes match the decoded Block (zero records for a no-Block empty Stream). Optional Block compressed size, when present, is a hard window: the LZMA2 decoder must consume exactly those bytes. Overlong VLIs, non-zero Block Header padding, and non-zero Block Data Padding are `DataError`. Unknown Check IDs on decode are `UnsupportedFeature`.
- Extra `filters` (Delta / BCJ) are applied around the codec; they are validated before encode/decode. Container-level filter chains other than LZMA2 are still unsupported.
- LZMA2 compressed-chunk size is 16 bits. If an LZMA payload would exceed 65536 bytes, the encoder writes an uncompressed `0x01` chunk instead of wrapping the size field.
- `memlimit` is decoder dictionary memory, not uncompressed output size. An `.xz` Block whose LZMA2 dictionary property exceeds `memlimit` is `MemoryLimit`.
- Truncated `.xz` (fewer than 6 header bytes, or an `Auto` input that is a proper prefix of the xz magic) is `UnexpectedEof`. Six or more bytes that are not xz magic are `FormatError`.
- Truncated LZMA_Alone under `Format::Auto` (length 1..=12 with a valid properties byte) is `UnexpectedEof`, not `FormatError`.
- **Differential `decode`**: embedded `liblzma` / Python `lzma` vectors (empty, 1 byte, `"hello lzma"`, 64-byte run) decode to the original plaintext. Encoder output is not required to match `xz -6` bytes and is not yet checked by a reference decoder in CI.
- **Differential CRC**: `crc32("123456789")` and `crc64("123456789")` match the published ISO-3309 / xz-utils check strings.
