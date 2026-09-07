# LZMA2

## Scope

Raw LZMA2 chunk streams used inside `.xz` Blocks and as `Format::Lzma2`. Chunks share one dictionary. Compressed chunks have independent range-coder initialization (no LZMA end marker). Reset mode is encoded in the control byte.

## Specification

XZ Utils `lzma2_encoder.c` / `lzma2_decoder.c` and the LZMA2 chunk layout:

| Control | Meaning |
| --- | --- |
| `0x00` | End of stream |
| `0x01` | Uncompressed, dictionary reset |
| `0x02` | Uncompressed, no dictionary reset |
| `0x80..=0x9F` | LZMA compressed; no reset |
| `0xA0..=0xBF` | LZMA compressed; reset state (probs, reps, LZMA state) |
| `0xC0..=0xDF` | LZMA compressed; reset state + new properties |
| `0xE0..=0xFF` | LZMA compressed; reset dictionary + state + new properties |

Low five bits of a compressed control byte are the high bits of uncompressed size − 1. A properties byte follows only for `0xC0..=0xFF`.

A new stream must begin with a dictionary reset (`0x01` or `0xE0..=0xFF`). After `0x01` / dictionary reset, the next LZMA chunk must carry properties (`0xC0` or `0xE0`). `0x02` / `0x80` / `0xA0` as the first chunk is `Data`.

Each compressed chunk carries: uncompressed size − 1, compressed size − 1, optional properties, then a range-coded payload **without** an LZMA end marker. The range decoder is re-initialized for every compressed chunk.

Dictionary size is **not** stored in a raw LZMA2 stream. In `.xz` it is the one-byte LZMA2 filter property:

```text
dict = (2 | (b & 1)) << ((b >> 1) + 11)   // b in 0..=39
b == 40  →  2^32 − 1
```

## Reference implementation

XZ Utils `src/liblzma/lzma/lzma2_encoder.c`, `lzma2_decoder.c`. Behaviour extracted; not a C transliteration.

## Data model

One `LzmaDec` / `LzmaEnc` session per stream: sliding dictionary, probability tables, four reps, LZMA state index, and `pos` since the last dictionary reset. Uncompressed chunks write through the dictionary. `pos` is used for `pos_state` and literal context.

## Algorithm

Encode: split input into ≤ 64 KiB pieces. Keep a session across pieces. The first compressed chunk is `0xE0`; later compressed chunks are `0x80` (state continues). After an uncompressed `0x01` fallback (payload would exceed 65536 bytes), the next compressed chunk is `0xC0`. Match length is capped at the current piece so a match cannot cross the chunk boundary. Finish with `0x00`.

Decode: start with `need_dict_reset` and `need_props`. Dispatch on control; copy uncompressed bytes into the dictionary; for compressed chunks apply the reset mode, then decode exactly the declared uncompressed length with a fresh range decoder.

## Invariants

- `decode_lzma2(encode_lzma2(x)) == x` including inputs larger than 64 KiB
- Dictionary bytes needed for decoding must be ≥ distances used
- `dict_size > memlimit` → `MemoryLimit`. Uncompressed output length is not capped by `memlimit`.
- Malformed control / truncated sizes → `DataError` / `UnexpectedEof`, never panic
- Public `decode_lzma2` requires the end marker to consume the entire input; trailing bytes are `Data`. XZ uses `decode_lzma2_consumed` so Block Padding / Check / Index can follow.

## Edge cases

Empty stream (`0x00` only); single uncompressed chunk; compressed size overflowing 16 bits falling back to `0x01`; 64 KiB chunk boundary with `0x80` continuation; properties byte with `lc + lp > 4`; `0x01` then `0x02`; `0x01` then `0xC0`.

## Error cases

Unknown control `< 0x80` other than `0x01`/`0x02`; truncated chunk; missing dictionary reset at the start of a stream; `0x80`/`0xA0` when properties have not been set; properties ≥ 225; LZMA end marker inside an LZMA2 chunk; `dict_size == 0` → `Limit`.

## Test vectors

Self-encoded `"hello lzma2 stream"`; empty; 70000-byte run (first chunk `0xE0`, second `0x80`); `0x01`+`0x02` `"abcd"`; whitebox `0xA0` and `0xC0` sessions; `liblzma` FORMAT_RAW vector of 2 MiB + 100 `'A'` (`0xE0` then `0x80`). Encode-side CI covers empty, short text, a 64-byte run, mixed 256/65536-byte payloads, and a 70000-byte run via Python `lzma.FORMAT_RAW` and `xz -d --format=raw --lzma2=...`.

## Compatibility notes

Encoder bytes are not required to match `liblzma` encoder output. Subsequent compressed chunks use `0x80` so a reference decoder must keep dictionary and probabilities. Decoder-side `0x01`/`0x02`/`0x80`/`0xA0`/`0xC0`/`0xE0` are tested. Encoder output of this implementation is accepted by `liblzma` / `xz` in CI.

## Open questions

None for reset-mode decoding. The encoder does not emit `0xA0` (state reset without new properties); that control is covered by whitebox vectors.
