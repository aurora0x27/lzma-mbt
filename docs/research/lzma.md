# LZMA1

## Scope

LZMA1 range-coded literals, matches, repeats, and the LZMA_Alone (`.lzma`) 13-byte header. Encoder is greedy (not optimal parser). Decoder must accept streams from this encoder and, when vectors exist, from `liblzma`.

## Specification

- Header: 1-byte properties `(pb * 5 + lp) * 9 + lc`, LE u32 dict size, LE u64 unpacked size (`0xFFFF_FFFF_FFFF_FFFF` = unknown). Header dict sizes below 4096 are rounded up (liblzma).
- 12 states; `pos_state = pos & ((1 << pb) - 1)`.
- Range coder as in `docs/research/range_coder.md`.
- End marker: new-match distance `0xFFFFFFFF`.
- `lc + lp <= 4`, `lc <= 8`, `lp,pb <= 4`.

## Reference implementation

XZ Utils `lzma_decoder.c` / `lzma_encoder.c`. Algorithm extracted; not a C transliteration.

## Data model

Probability tables (`is_match`, `is_rep*`, length, pos slot, align, literals), four reps, 12-state index, dictionary, range coder.

## Algorithm

Per symbol: decode `is_match[state][pos_state]`. Literal vs match/rep. Length/distance as in LZMA SDK. Copy from dictionary.

Encoder: at each position prefer a repeat of length ≥ 2, else a new match ≥ 2 from a bounded backward search (lookback capped at 4096 even if `dict_size` is larger), else a literal. Always emit an end marker. One-shot encode writes the real unpacked size. LZMA2 reuses the same session across chunks: match length is capped at the remaining bytes of the current chunk so a match cannot cross a chunk boundary.

## Invariants

- `decode(encode(x)) == x` for this implementation
- Chunked `Decoder::write` + `finish` equals one-shot `decode` on the same bytes. Raw LZMA2 `code(..., Run)` is resumable at LZMA symbol boundaries; `.xz` and LZMA_Alone container parsing remains buffered.
- Invalid distances and truncated range input fail with `DataError` / `UnexpectedEof`

## Edge cases

Empty payload; single byte; long run of one byte; incompressible; known vs unknown size.

## Error cases

Bad properties byte; dict size 0 / over max; dict over `memlimit` **after** rounding below 4096 up to 4096; first range byte ≠ 0; truncated header (13 bytes). Known-size streams that would copy a match past the unpacked size are `DataError`.

## Test vectors

Empty, `"a"`, `"hello lzma"`, 64-byte run, 256 mixed bytes — produced by this encoder and self-decoded. Additional `liblzma` FORMAT_ALONE vectors (unknown size, dict 4096) for the same payloads. Encode-side: CI dumps `.lzma` from this encoder and `xz -d --format=lzma` / Python `lzma.FORMAT_ALONE` must recover the plaintext.

## Compatibility notes

Greedy encoding will not match `xz -6` bytes. Decoder alignment with `liblzma` is required when reference streams are available. Encoder output is checked by a reference decoder in CI (`scripts/diff_encode.py`).

## Open questions

Optimal parsing is deferred (performance milestone).
