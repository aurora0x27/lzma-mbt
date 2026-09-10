///|
pub suberror FilterError {
  InvalidDistance
} derive(Debug, Eq)

///|
pub fn delta_encode(
  input : BytesView,
  distance : Int,
) -> Bytes raise FilterError {
  if distance < 1 || distance > 256 {
    raise InvalidDistance
  }
  let hist = Array::make(distance, b'\x00')
  let out = Array(capacity=input.length())
  let mut i = 0
  for b in input {
    let p = i % distance
    let prev = hist[p].to_int()
    let cur = b.to_int()
    out.push(((cur - prev) & 0xFF).to_byte())
    hist[p] = b
    i = i + 1
  }
  Bytes::from_array(out[:])
}

///|
pub fn delta_decode(
  input : BytesView,
  distance : Int,
) -> Bytes raise FilterError {
  if distance < 1 || distance > 256 {
    raise InvalidDistance
  }
  let hist = Array::make(distance, b'\x00')
  let out = Array(capacity=input.length())
  let mut i = 0
  for b in input {
    let p = i % distance
    let prev = hist[p].to_int()
    let cur = (b.to_int() + prev) & 0xFF
    let nb = cur.to_byte()
    out.push(nb)
    hist[p] = nb
    i = i + 1
  }
  Bytes::from_array(out[:])
}

///|
/// The x86 filter rewrites only immediates whose top byte is 0x00 or 0xFF.
fn x86_test_msbyte(b : Byte) -> Bool {
  b == b'\x00' || b == b'\xFF'
}

///|
fn x86_le_u32_at(d : Array[Byte], i : Int) -> UInt {
  d[i].to_int().reinterpret_as_uint() |
  (d[i + 1].to_int().reinterpret_as_uint() << 8) |
  (d[i + 2].to_int().reinterpret_as_uint() << 16) |
  (d[i + 3].to_int().reinterpret_as_uint() << 24)
}

///|
fn byte_of(v : UInt) -> Byte {
  (v & 0xFFU).reinterpret_as_int().to_byte()
}

///|
/// `MASK_TO_BIT_NUMBER` from liblzma `simple/x86.c`, indexed by `prev_mask >> 1`
/// (only 0..=4 reach the adjust loop).
fn x86_bit_number(v : Int) -> Int {
  match v {
    0 => 0
    1 => 1
    2 | 3 => 2
    4 => 3
    _ => 0
  }
}

///|
/// Core of liblzma `simple/x86.c`. Transforms `d[0..size]` in place and
/// returns the number of bytes fully processed together with the updated
/// `prev_mask` / `prev_pos` state. 32-bit positions and masks wrap, matching
/// the C `uint32_t` arithmetic (MoonBit `UInt` wraps; shifts by >= 32 behave
/// like x86 `shl`, same as the C code does at -O0 on real hardware).
fn x86_filter_core(
  d : Array[Byte],
  size : Int,
  now_pos : UInt,
  encode : Bool,
  prev_mask0 : UInt,
  prev_pos0 : UInt,
) -> (Int, UInt, UInt) {
  let mut prev_mask = prev_mask0
  let mut prev_pos = prev_pos0
  if size < 5 {
    return (0, prev_mask, prev_pos)
  }
  if now_pos - prev_pos > 5U {
    prev_pos = now_pos - 5U
  }
  let limit = size - 5
  let mut buffer_pos = 0
  while buffer_pos <= limit {
    let mut b = d[buffer_pos]
    if b != b'\xE8' && b != b'\xE9' {
      buffer_pos = buffer_pos + 1
      continue
    }
    // Distance from the previous candidate opcode start, wrapping.
    let offset = now_pos + buffer_pos.reinterpret_as_uint() - prev_pos
    prev_pos = now_pos + buffer_pos.reinterpret_as_uint()
    if offset > 5U {
      prev_mask = 0U
    } else {
      let mut k = 0
      while k < offset.reinterpret_as_int() {
        prev_mask = (prev_mask & 0x77U) << 1
        k = k + 1
      }
    }
    b = d[buffer_pos + 4]
    // Convert only when the immediate's MSByte is 0x00/0xFF and the MSByte
    // status recorded in prev_mask says the result is unambiguous.
    if x86_test_msbyte(b) && prev_mask >> 1 <= 4U && prev_mask >> 1 != 3U {
      let mut src = x86_le_u32_at(d, buffer_pos + 1)
      let ip = now_pos + buffer_pos.reinterpret_as_uint() + 5U
      let mut dest = if encode { src + ip } else { src - ip }
      // The adjust loop re-derives `dest` from a toggled `src` until the byte
      // being examined is no longer an ambiguous 0x00/0xFF, mirroring the C.
      while true {
        if prev_mask == 0U {
          break
        }
        let bit = x86_bit_number((prev_mask >> 1).reinterpret_as_int())
        let shift = 24 - bit * 8
        b = byte_of(dest >> shift)
        if x86_test_msbyte(b) == false {
          break
        }
        let mask = (1U << (32 - bit * 8)) - 1U
        src = dest ^ mask
        dest = if encode { src + ip } else { src - ip }
      }
      // `~(((dest >> 24) & 1) - 1)` in C: 0xFF when bit 31 is set else 0x00.
      d[buffer_pos + 4] = if ((dest >> 31) & 1U) == 1U {
        b'\xFF'
      } else {
        b'\x00'
      }
      d[buffer_pos + 3] = byte_of(dest >> 16)
      d[buffer_pos + 2] = byte_of(dest >> 8)
      d[buffer_pos + 1] = byte_of(dest)
      buffer_pos = buffer_pos + 5
      prev_mask = 0U
    } else {
      buffer_pos = buffer_pos + 1
      prev_mask = prev_mask | 1U
      if x86_test_msbyte(b) {
        prev_mask = prev_mask | 0x10U
      }
    }
  }
  (buffer_pos, prev_mask, prev_pos)
}

///|
/// Full x86 BCJ filter matching liblzma `simple/x86.c` (`lzma_bcj_x86_*`),
/// including the MSByte / `prev_mask` state for overlapping instructions.
/// `start_offset` seeds the 32-bit instruction pointer; encode and decode are
/// inverse one-shot transforms of a whole buffer.
pub fn bcj_x86(input : BytesView, start_offset : UInt, encode : Bool) -> Bytes {
  let data = Array(capacity=input.length())
  for b in input {
    data.push(b)
  }
  let n = data.length()
  ignore(x86_filter_core(data, n, start_offset, encode, 0U, 0xFFFFFFFBU))
  Bytes::from_array(data[:])
}

///|
/// ARM (32-bit) BCJ filter matching liblzma `simple/arm.c`: every 4-byte word
/// whose top byte is `0xEB` (B/BL) has its 24-bit offset field adjusted by the
/// 8-byte pipeline position `start_offset + i + 8`. `start_offset` is 32-bit
/// wrapping; trailing bytes that are not part of a full word pass through.
pub fn bcj_arm(input : BytesView, start_offset : UInt, encode : Bool) -> Bytes {
  let data = Array(capacity=input.length())
  for b in input {
    data.push(b)
  }
  let n = data.length()
  let size = n / 4 * 4
  let mut i = 0
  while i < size {
    if data[i + 3] == b'\xEB' {
      let src = (
          data[i].to_int().reinterpret_as_uint() |
          (data[i + 1].to_int().reinterpret_as_uint() << 8) |
          (data[i + 2].to_int().reinterpret_as_uint() << 16)
        ) <<
        2
      let base = start_offset + i.reinterpret_as_uint() + 8U
      let dest = if encode { (base + src) >> 2 } else { (src - base) >> 2 }
      data[i] = byte_of(dest)
      data[i + 1] = byte_of(dest >> 8)
      data[i + 2] = byte_of(dest >> 16)
    }
    i = i + 4
  }
  Bytes::from_array(data[:])
}

///|
fn le_u32_at(d : Array[Byte], i : Int) -> UInt {
  d[i].to_int().reinterpret_as_uint() |
  (d[i + 1].to_int().reinterpret_as_uint() << 8) |
  (d[i + 2].to_int().reinterpret_as_uint() << 16) |
  (d[i + 3].to_int().reinterpret_as_uint() << 24)
}

///|
fn set_le_u32(d : Array[Byte], i : Int, v : UInt) -> Unit {
  d[i] = byte_of(v)
  d[i + 1] = byte_of(v >> 8)
  d[i + 2] = byte_of(v >> 16)
  d[i + 3] = byte_of(v >> 24)
}

///|
/// ARM64 BCJ filter matching liblzma `simple/arm64.c` (`lzma_bcj_arm64_*`):
/// converts the 26-bit immediate of `BL` instructions and the page immediate
/// of `ADRP` instructions (the latter only within +/-512 MiB). Processing is
/// 4-byte aligned from `start_offset`; `start_offset` is 32-bit wrapping and
/// rounded down to a multiple of four.
pub fn bcj_arm64(
  input : BytesView,
  start_offset : UInt,
  encode : Bool,
) -> Bytes {
  let data = Array(capacity=input.length())
  for b in input {
    data.push(b)
  }
  let n = data.length()
  let size = n / 4 * 4
  let start = start_offset & 0xFFFFFFFCU
  let mut i = 0
  while i < size {
    let pc = start + i.reinterpret_as_uint()
    let instr0 = le_u32_at(data, i)
    if instr0 >> 26 == 0x25U {
      // BL: convert the full 26-bit immediate.
      let src = instr0
      let add = if encode { pc >> 2 } else { 0U - (pc >> 2) }
      let imm = ((src + add) & 0x03FFFFFFU) | 0x94000000U
      set_le_u32(data, i, imm)
    } else if (instr0 & 0x9F000000U) == 0x90000000U {
      // ADRP: convert only values within +/-512 MiB.
      let src = ((instr0 >> 29) & 3U) | ((instr0 >> 3) & 0x001FFFFCU)
      if ((src + 0x00020000U) & 0x001C0000U) != 0U {
        i = i + 4
        continue
      }
      let page = if encode { pc >> 12 } else { 0U - (pc >> 12) }
      let dest = src + page
      let mut instr = instr0 & 0x9000001FU
      instr = instr | ((dest & 3U) << 29)
      instr = instr | ((dest & 0x0003FFFCU) << 3)
      instr = instr | ((0U - (dest & 0x00020000U)) & 0x00E00000U)
      set_le_u32(data, i, instr)
    }
    i = i + 4
  }
  Bytes::from_array(data[:])
}
