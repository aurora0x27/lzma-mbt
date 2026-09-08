# Compatibility matrix

Evidence, not intention. A cell is `yes` only when tests for that behavior exist and pass. Differential requires comparison against `liblzma` / `xz`.

| Feature | Decoder | Encoder | Streaming | Differential |
| --- | ---: | ---: | ---: | ---: |
| LZMA1 / `.lzma` | yes | yes | yes | decode+encode |
| LZMA2 raw | yes | yes | yes | decode+encode |
| XZ | yes | yes | yes | decode+encode |
| CRC32 | yes | N/A | N/A | yes |
| CRC64 | yes | N/A | N/A | yes |
| SHA-256 | yes | yes | N/A | yes |
| Extra BCJ / Delta filters | yes | yes | yes | no |
| XZ Delta filter | yes | yes | yes | decode+encode |
| XZ x86 BCJ filter | yes | yes | yes | decode+encode |
| XZ ARM BCJ filter | yes | yes | yes | decode+encode |
| XZ BCJ filters (other ISA) | no | no | no | no |
| Auto detect xz/lzma | yes | N/A | yes | no |
| concatenated xz | yes | N/A | yes | decode |

Notes:

- Streaming tests cover 1-byte and deterministic random input chunks, 1-byte output slots, `NeedInput`, `NeedOutput`, output draining, totals, reset, terminal-state rejection, flush rejection, and `.xz` Footer CRC / Backward Size / reserved flags / Block Data Padding / Index record count. Raw LZMA2 `Decoder::code(..., Run)` persists dictionary, probability, chunk-header, range, and symbol state across calls and emits as symbols complete. Single-stream XZ `Decoder::code(..., Run)` persists Header, Block, payload, Index, and Footer boundaries; declared-size Block payloads reuse the active LZMA2 decoder and can emit before the Footer. x86 / ARM BCJ Blocks are buffered whole (via the one-shot Block decoder) before their plaintext is emitted; Delta Blocks stay incremental. `concatenated=true` and streams with root-level extra filters retain the compatibility path. `write` + `finish` remains whole-input compatible for all formats; the encoder still emits only at `Finish`.
- XZ decoder reads Blocks until the Index indicator `0x00` and requires Index records to match each Block's Unpadded Size and Uncompressed Size (zero records for a no-Block empty Stream). The encoder still writes Stream Header, **one** LZMA2 Block (Block Header includes compressed and uncompressed size VLIs), Index, and Footer. Check IDs None / CRC32 / CRC64 / SHA-256 are supported; unknown Check IDs on decode are `UnsupportedFeature`. With `DecodeOptions.concatenated=false`, bytes after Footer are `DataError`; with `concatenated=true`, the decoder skips Stream Padding (null bytes only, length multiple of four) and decodes subsequent `.xz` Streams. Bytes after a raw LZMA2 end marker remain `DataError`. Optional Block compressed size, when present, is a hard window: the LZMA2 decoder must consume exactly those bytes. Overlong VLIs, non-zero Block Header padding, non-zero Block Data Padding, malformed Stream Padding, and Index/Footer mismatches are `DataError`.
- Extra root-package `filters` (Delta / BCJ) are applied around the codec and are validated before encode/decode. XZ container-native filters are handled separately as Block Header filters before LZMA2: Delta (ID `0x03`), x86 BCJ (ID `0x04`), and ARM BCJ (ID `0x07`) each form a two-filter chain `Delta -> LZMA2` / `x86 -> LZMA2` / `ARM -> LZMA2`. The root-package extra BCJ and the container x86 BCJ use the full liblzma `simple/x86.c` transform (MSByte / `prev_mask`), verified byte-for-byte against `lzma_bcj_x86_encode/decode` vectors; the container ARM BCJ mirrors `simple/arm.c` (24-bit offset of `0xEB`-prefixed words). Other container filter IDs (PowerPC `0x05`, IA-64 `0x06`, ARM-Thumb `0x08`, SPARC `0x09`, ARM64 `0x0A`) are still `UnsupportedFeature`.
- LZMA2 compressed-chunk size is 16 bits. If an LZMA payload would exceed 65536 bytes, the encoder writes an uncompressed `0x01` chunk instead of wrapping the size field. Subsequent compressed chunks use `0x80` (dictionary and probabilities continue). Uncompressed `0x01`/`0x02` update the shared dictionary. A stream must start with a dictionary reset; `0x80`/`0xA0`/`0xC0`/`0x02` as the first chunk is `DataError`.
- `memlimit` is decoder dictionary memory, not uncompressed output size. An `.xz` Block whose LZMA2 dictionary property exceeds `memlimit` is `MemoryLimit`.
- Truncated `.xz` (fewer than 6 header bytes, or an `Auto` input that is a proper prefix of the xz magic) is `UnexpectedEof`. Six or more bytes that are not xz magic are `FormatError`.
- Truncated LZMA_Alone under `Format::Auto` (length 1..=12 with a valid properties byte) is `UnexpectedEof`, not `FormatError`.
- **Differential `decode`**: embedded `liblzma` / Python `lzma` vectors (empty, 1 byte, `"hello lzma"`, 64-byte run; LZMA2: 2 MiB + 100 `'A'` with an `0xE0` then `0x80` chunk; XZ: `xz --block-size=2` files `"aabb"` / `"aabbcc"` with 2 and 3 Blocks; XZ Delta+LZMA2 distances 1 / 4 / 256; `xz --x86 --lzma2=preset=6 --check=crc64` of an x86-laden 1808-byte payload; `xz --arm --lzma2=preset=6 --check=crc64` of an ARM-laden 1922-byte payload) decode to the original plaintext. Concatenated `.xz` tests use multiple self-encoded Streams plus valid and invalid Stream Padding, including `Format::Auto` and streaming `Decoder`.
- **Differential `encode`**: `src/cmd/diff_encode` emits this encoder's `.xz` / `.lzma` / raw LZMA2; CI (`scripts/diff_encode.py`) feeds them to Python `lzma` (liblzma) and `xz -d`. Coverage includes empty, `"hello lzma"`, a 64-byte run, 256-byte mixed, 64 KiB incompressible, a 70000-byte run, presets 0 and 6, XZ checks CRC32 / CRC64 / None / SHA-256, XZ Delta+LZMA2, XZ x86-BCJ+LZMA2, and XZ ARM-BCJ+LZMA2. Encoder bytes are not required to match `xz -6`.
- **Differential checksum**: `crc32("123456789")` and `crc64("123456789")` match the published ISO-3309 / xz-utils check strings. SHA-256 matches FIPS 180-4 vectors for empty input, `"abc"`, and the standard multi-block test string; `.xz --check=sha256` reference data decodes successfully.
