# Range coder

## Scope

LZMA 32-bit range encoder/decoder and 11-bit probability updates. Not a general arithmetic coder.

## Specification

LZMA SDK / `liblzma` `range_decoder.h`, `range_encoder.h`:

- `kTopValue = 1 << 24`
- `kBitModelTotal = 1 << 11` (2048)
- `kMoveBits = 5`
- Probability init: 1024
- Decoder init reads 5 bytes; the first must be 0 (`liblzma` `rc_read_init`). `code == range` is not rejected at init.
- Encoder `cacheSize` starts at 1; flush calls `ShiftLow` five times

## Reference implementation

XZ Utils `src/liblzma/rangecoder/`. Behavior, not C control flow, is copied.

## Data model

- Encoder: `low: UInt64`, `range: UInt`, `cache`, `cache_size`, output bytes
- Decoder: `code: UInt`, `range: UInt`, input cursor
- Probability: `UInt` in `1..=2047` after updates (0 and 2048 are avoided by the update rule)

## Algorithm

See `src/internal/range_coder/range.mbt`. Bit 0 shortens `range` to `bound`; bit 1 subtracts `bound` from both `range` and `code`/`low`.

## Invariants

- After every bit, `range >= kTopValue` following normalize
- Encode then decode of the same bit sequence with the same initial probs recovers the bits
- `liblzma` treats `rc.code == 0` as a finished decoder; this implementation does not require it after a known uncompressed size (LZMA_Alone stops at the declared length)

## Edge cases

Empty bit sequence (flush only); long runs of 0 or 1; truncated 5-byte init.

## Error cases

First init byte ≠ 0 → data error; unexpected EOF during normalize → eof.

## Test vectors

Self-inverse bit strings in whitebox tests. No public bitstream format besides LZMA.

## Compatibility notes

Must interoperate with `liblzma` LZMA streams. Decoder-side vectors plus encode-side CI (`scripts/diff_encode.py`) cover this.

The decoder input is appendable for incremental callers. Each bit/direct-bit operation rolls back its arithmetic registers (and the probability cell for a bit operation) if normalization reaches the current input boundary, so the same operation can be retried after appending bytes. LZMA symbol-level continuation still requires a higher-level checkpoint around sequences of operations.

## Open questions

None for the bit coder itself.
