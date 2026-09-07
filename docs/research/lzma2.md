# LZMA2

## Scope

Raw LZMA2 chunk streams used inside `.xz` Blocks and as `Format::Lzma2`. The encoder emits dictionary-reset compressed chunks (`0xE0`) when the LZMA payload fits in the 16-bit compressed-size field, uncompressed dictionary-reset chunks (`0x01`) when it would overflow, and an end marker. Decoding also accepts uncompressed chunks without dictionary reset (`0x02`).

## Specification

XZ Utils `lzma2_encoder.c` / `lzma2_decoder.c` and the LZMA2 chunk layout:

| Control | Meaning |
| --- | --- |
| `0x00` | End of stream |
| `0x01` | Uncompressed, dictionary reset |
| `0x02` | Uncompressed, no dictionary reset |
| `0x80..=0xFF` | LZMA compressed; high bits encode reset mode and uncompressed-size high bits |

A compressed chunk with properties carries: uncompressed size − 1 (3 bytes with control high bits), compressed size − 1 (2 bytes), one LZMA properties byte, then a range-coded payload **without** an LZMA end marker.

Dictionary size is **not** stored in a raw LZMA2 stream. In `.xz` it is the one-byte LZMA2 filter property:

```text
dict = (2 | (b & 1)) << ((b >> 1) + 11)   // b in 0..=39
b == 40  →  2^32 − 1
```

## Reference implementation

XZ Utils `src/liblzma/lzma/lzma2_encoder.c`, `lzma2_decoder.c`. Behaviour extracted; not a C transliteration.

## Data model

Sequence of chunks over a shared conceptual dictionary. Compressed chunks from this encoder always reset dictionary, state, and properties (`0xE0`), so each is independently range-coded. Uncompressed chunks (`0x01`) copy bytes through.

## Algorithm

Encode: split input into ≤ 64 KiB pieces; LZMA-encode each without end marker. If the payload length is `1..=65536`, wrap it with `0xE0`, sizes, and properties; otherwise write an uncompressed `0x01` chunk. Finish with `0x00`.

Decode: dispatch on control; copy uncompressed data; for `0xE0..=0xFF` chunks unpack properties and call the shared LZMA decoder with a caller-supplied `dict_size` (from the XZ filter byte, or a memlimit cap for raw LZMA2). Compressed chunks that do not fully reset the dictionary (`0x80` / `0xA0` / `0xC0`) are `Unsupported`.

## Invariants

- `decode_lzma2(encode_lzma2(x)) == x`
- Dictionary bytes needed for decoding must be ≥ distances used
- `dict_size > memlimit` → `MemoryLimit`. Uncompressed output length is not capped by `memlimit`.
- Malformed control / truncated sizes → `DataError` / `UnexpectedEof`, never panic
- Public `decode_lzma2` requires the end marker to consume the entire input; trailing bytes are `Data`. XZ uses `decode_lzma2_consumed` so Block Padding / Check / Index can follow.

## Edge cases

Empty stream (`0x00` only); single uncompressed chunk; compressed size overflowing 16 bits falling back to `0x01`; 64 KiB chunk boundary; properties byte with `lc + lp > 4`.

## Error cases

Unknown control `< 0x80` other than `0x01`/`0x02`; truncated chunk; compressed chunk that is not a full dictionary reset (`0xE0..=0xFF`); properties ≥ 225; `dict_size == 0` → `Limit`.

## Test vectors

Self-encoded `"hello lzma2 stream"`; empty; hand-built uncompressed `"hello"` chunk; truncated `0x01`; control `0x03`; `decode_lzma2_consumed` stops at `0x00` and leaves trailing bytes unconsumed.

## Compatibility notes

Chunk reset mode includes uncompressed fallback when a compressed payload would exceed 65536 bytes. Differential against `liblzma` encoder bytes is not claimed. Decoder-side `0x01`/`0x02` and `0xE0` paths are tested.

## Open questions

State-preserving chunks (`0x80` / `0xA0` / `0xC0`) are specified but not produced. Decoding them is `UnsupportedFeature` because this decoder does not keep a dictionary across chunks.
