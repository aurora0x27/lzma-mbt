///|
/// p4 — 小图片：已压缩 PNG，通常几乎不再缩小
fn bytes_eq(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// Return percent * 10 (one decimal place), e.g. 41 -> "4.1%".
/// Avoids 32-bit overflow on multi-MiB inputs (c * 1000 may not fit in Int).
fn ratio_pct10(plain : Int, compressed : Int) -> Int {
  if plain == 0 {
    return 0
  }
  if compressed >= 2000000 {
    let denom = plain / 1000
    if denom == 0 {
      return compressed * 1000 / plain
    }
    return compressed / denom
  }
  compressed * 1000 / plain
}

///|
fn main raise {
  let input = "examples/fixtures/small.png"
  let xz = "examples/p4/out/small.png.xz"
  let restored = "examples/p4/out/small.png.restored"

  let plain = @fs.read_file_to_bytes(input)
  let compressed = @lzma.encode(plain[:])
  @fs.write_bytes_to_file(xz, compressed)

  let decoded = @lzma.decode(compressed[:])
  @fs.write_bytes_to_file(restored, decoded)

  if !bytes_eq(plain, decoded) {
    println("FAIL: round-trip mismatch")
    return
  }

  let pct10 = ratio_pct10(plain.length(), compressed.length())

  println("p4 ok — 小图片")
  println("  input=\{input}")
  println("  plain=\{plain.length()} bytes")
  println(
    "  xz=\{compressed.length()} bytes (\{pct10 / 10}.\{pct10 % 10}% of original)",
  )
  println("  note: PNG 已是压缩格式，LZMA 收益通常很小")
  println("  roundtrip_ok=true")
}
