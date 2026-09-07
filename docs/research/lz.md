# LZ dictionary

## Scope

Sliding dictionary used by LZMA match copy. Encoder match search may use the source buffer directly; the decoder must honor `dict_size`.

## Specification

LZMA distances are 0-based (`rep0`). A copy of length `len` at distance `d` reads bytes at `pos - d - 1`. Minimum match length is 2. Maximum is 273.

A distance is invalid if `d + 1 >` bytes already produced (and not wrapping through a full dictionary). End marker uses distance `0xFFFFFFFF` and is not a copy.

## Reference implementation

`liblzma` `lz_decoder.c` dictionary wrap.

## Data model

Cyclic `Array[Byte]` of `dict_size`, write cursor, `filled` count.

## Invariants

- `filled <= dict_size`
- Get(distance) only when `distance < filled` (`filled` caps at `dict_size`, including after wrap)
- Put advances `filled` up to `dict_size`

## Edge cases

Empty dict at first literal; distance 0 (repeat last byte); copy overlapping the write position (must be byte-by-byte).

## Error cases

Distance too far → `DataError`.

## Test vectors

Manual put/get/copy, overlapping copy, and wrap after `dict_size` writes.

## Compatibility notes

Overlap copies must match C memmove-from-behind-write-pos semantics (byte-by-byte).

## Open questions

None.
