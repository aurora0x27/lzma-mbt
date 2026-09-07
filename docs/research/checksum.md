# Checksums

## Scope

CRC-32 and CRC-64 as used by XZ / `liblzma`. SHA-256 is out of scope until an XZ file actually needs it; encoding with `Check::Sha256` stays `UnsupportedFeature`.

## Specification

`liblzma` `lzma_crc32` / `lzma_crc64`:

- CRC-32: ISO 3309 / ITU-T V.42, reflected polynomial `0xEDB88320`, `crc = ~crc` before and after the byte loop.
- CRC-64: ECMA-182, reflected polynomial `0xC96C5795D7870F42`, same invert bracketing.

The public `init` argument is a running CRC value (the value returned by a previous call), not the internal inverted register.

## Reference implementation

`src/liblzma/check/crc32_fast.c`, `crc64_fast.c` in XZ Utils.

## Data model

256-entry tables generated at initialization from the polynomials.

## Algorithm

```text
crc = ~init
for each byte b:
  crc = table[(crc ^ b) & 0xFF] ^ (crc >> 8)
return ~crc
```

## Invariants

`crc32(a ++ b) == crc32(b, init=crc32(a))` (and the CRC-64 analogue). Empty input returns `init` unchanged (`crc32(b"", init=0) == 0`).

## Edge cases

Empty; one byte; 9-byte IEEE check string `123456789`; two-chunk split.

## Error cases

None: checksums are total functions on `BytesView`.

## Test vectors

| Input | CRC-32 | CRC-64 (ECMA) |
| --- | --- | --- |
| `""` | `0x00000000` | `0x0000000000000000` |
| one `0x00` byte | `0xD202EF8D` | `0x1FADA17364673F59` |
| `"123456789"` | `0xCBF43926` | `0x995DC9BBDF1939FA` |

## Compatibility notes

Must match `lzma_crc32` / `lzma_crc64` byte-for-byte, including the `init` chaining convention.

## Open questions

None.
