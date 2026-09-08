# Checksums

## Scope

CRC-32, CRC-64, and SHA-256 as used by XZ / `liblzma`. In `.xz`, the Check field covers the Block's uncompressed plaintext bytes.

## Specification

`liblzma` `lzma_crc32` / `lzma_crc64` and FIPS 180-4 SHA-256:

- CRC-32: ISO 3309 / ITU-T V.42, reflected polynomial `0xEDB88320`, `crc = ~crc` before and after the byte loop.
- CRC-64: ECMA-182, reflected polynomial `0xC96C5795D7870F42`, same invert bracketing.
- SHA-256: initial hash words and round constants from FIPS 180-4 section 4.2.2 / 5.3.3; messages are padded with one `1` bit, zeros to 448 mod 512, then the 64-bit big-endian bit length.

The public CRC `init` argument is a running CRC value (the value returned by a previous call), not the internal inverted register. SHA-256 exposes `Sha256State` for chunked hashing because a digest alone is not a resumable state; the accumulated byte length and partial 64-byte block are part of the algorithm state.

## Reference implementation

`src/liblzma/check/crc32_fast.c`, `crc64_fast.c`, and `sha256.c` in XZ Utils. SHA-256 constants and padding are checked against FIPS 180-4 vectors.

## Data model

CRC uses 256-entry tables generated at initialization from the polynomials. SHA-256 state is eight 32-bit words, a partial 64-byte block buffer, and a 64-bit byte counter.

## Algorithm

```text
crc = ~init
for each byte b:
  crc = table[(crc ^ b) & 0xFF] ^ (crc >> 8)
return ~crc
```

SHA-256 processes each 512-bit block with the standard message schedule:

```text
W[0..15] = block words, big-endian
W[i] = sigma1(W[i-2]) + W[i-7] + sigma0(W[i-15]) + W[i-16]
```

Finalization pads from the accumulated byte length and emits the eight hash words in big-endian order.

## Invariants

`crc32(a ++ b) == crc32(b, init=crc32(a))` (and the CRC-64 analogue). Empty input returns `init` unchanged (`crc32(b"", init=0) == 0`). For SHA-256, `Sha256State::new().update(a).update(b).finish() == sha256(a ++ b)`.

## Edge cases

Empty; one byte; 9-byte IEEE check string `123456789`; SHA-256 `"abc"` and multi-block vector; two-chunk split.

## Error cases

None: checksums are total functions on `BytesView`.

## Test vectors

| Input | CRC-32 | CRC-64 (ECMA) | SHA-256 |
| --- | --- | --- | --- |
| `""` | `0x00000000` | `0x0000000000000000` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| one `0x00` byte | `0xD202EF8D` | `0x1FADA17364673F59` | N/A |
| `"123456789"` | `0xCBF43926` | `0x995DC9BBDF1939FA` | N/A |
| `"abc"` | N/A | N/A | `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad` |
| FIPS multi-block string | N/A | N/A | `248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1` |

## Compatibility notes

CRC must match `lzma_crc32` / `lzma_crc64` byte-for-byte, including the `init` chaining convention. SHA-256 must match FIPS 180-4 and XZ Utils `sha256.c`; XZ Check ID `0x0A` stores exactly 32 digest bytes over the uncompressed Block payload.

## Open questions

None.
