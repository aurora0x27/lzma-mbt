# Compatibility matrix

Evidence, not intention. A cell is `yes` only when tests for that behavior exist and pass. Differential requires comparison against `liblzma` / `xz`.

| Feature | Decoder | Encoder | Streaming | Differential |
| --- | ---: | ---: | ---: | ---: |
| LZMA1 / `.lzma` | yes | yes | yes | decode+encode |
| LZMA2 raw | yes | yes | yes | decode+encode |
| XZ | yes | yes | yes | decode+encode |
| CRC32 | yes | N/A | N/A | yes |
| CRC64 | yes | N/A | N/A | yes |
| SHA-256 | no | no | N/A | no |
| BCJ / Delta | yes | yes | yes | no |
| Auto detect xz/lzma | yes | N/A | yes | no |
| concatenated xz | no | N/A | no | no |

Notes:

- Streaming uses the same `encode` / `decode` implementation at `Finish` (`Run` only buffers). Tests cover 1-byte `write`, 1-byte `code(..., Run)`, 1-byte output slots, `reset`, `Run` → `Ok`, `code` after `StreamEnd`, rejecting extra input after `Finish` while draining, empty `Run` to drain after `NeedOutput`, `finish()` returning remaining bytes after `NeedOutput`, retrying `Finish` after `BufferTooSmall` on an empty output buffer (`total_in` unchanged), `Finish` on a full non-empty buffer → `NeedOutput` without dropping input, decoder `SyncFlush` / `write` after `finish`, and `.xz` Footer CRC / Backward Size / reserved flags / Block Data Padding / Index record count.
- XZ decoder reads Blocks until the Index indicator `0x00` and requires Index records to match each Block's Unpadded Size and Uncompressed Size (zero records for a no-Block empty Stream). The encoder still writes Stream Header, **one** LZMA2 Block (Block Header includes compressed and uncompressed size VLIs), Index, and Footer. SHA-256 check and concatenated Streams raise `UnsupportedFeature`. Bytes after Footer, or after a raw LZMA2 end marker, are `DataError`. Optional Block compressed size, when present, is a hard window: the LZMA2 decoder must consume exactly those bytes. Overlong VLIs, non-zero Block Header padding, and non-zero Block Data Padding are `DataError`. Unknown Check IDs on decode are `UnsupportedFeature`.
- Extra `filters` (Delta / BCJ) are applied around the codec; they are validated before encode/decode. Container-level filter chains other than LZMA2 are still unsupported.
- LZMA2 compressed-chunk size is 16 bits. If an LZMA payload would exceed 65536 bytes, the encoder writes an uncompressed `0x01` chunk instead of wrapping the size field. Subsequent compressed chunks use `0x80` (dictionary and probabilities continue). Uncompressed `0x01`/`0x02` update the shared dictionary. A stream must start with a dictionary reset; `0x80`/`0xA0`/`0xC0`/`0x02` as the first chunk is `DataError`.
- `memlimit` is decoder dictionary memory, not uncompressed output size. An `.xz` Block whose LZMA2 dictionary property exceeds `memlimit` is `MemoryLimit`.
- Truncated `.xz` (fewer than 6 header bytes, or an `Auto` input that is a proper prefix of the xz magic) is `UnexpectedEof`. Six or more bytes that are not xz magic are `FormatError`.
- Truncated LZMA_Alone under `Format::Auto` (length 1..=12 with a valid properties byte) is `UnexpectedEof`, not `FormatError`.
- **Differential `decode`**: embedded `liblzma` / Python `lzma` vectors (empty, 1 byte, `"hello lzma"`, 64-byte run; LZMA2: 2 MiB + 100 `'A'` with an `0xE0` then `0x80` chunk; XZ: `xz --block-size=2` files `"aabb"` / `"aabbcc"` with 2 and 3 Blocks) decode to the original plaintext.
- **Differential `encode`**: `src/cmd/diff_encode` emits this encoder's `.xz` / `.lzma` / raw LZMA2; CI (`scripts/diff_encode.py`) feeds them to Python `lzma` (liblzma) and `xz -d`. Coverage includes empty, `"hello lzma"`, a 64-byte run, 256-byte mixed, 64 KiB incompressible, a 70000-byte run, presets 0 and 6, and XZ checks CRC32 / CRC64 / None. Encoder bytes are not required to match `xz -6`.
- **Differential CRC**: `crc32("123456789")` and `crc64("123456789")` match the published ISO-3309 / xz-utils check strings.
