///|
pub const TOP : UInt = 0x01000000U

///|
pub const BIT_MODEL_TOTAL : UInt = 2048U

///|
pub const PROB_INIT : UInt = 1024U

///|
pub const MOVE_BITS : Int = 5

///|
pub suberror RcError {
  Eof
  Data
} derive(Debug, Eq)

///|
pub fn prob_update_0(prob : UInt) -> UInt {
  prob + ((BIT_MODEL_TOTAL - prob) >> MOVE_BITS)
}

///|
pub fn prob_update_1(prob : UInt) -> UInt {
  prob - (prob >> MOVE_BITS)
}

///|
pub struct RangeEncoder {
  mut low : UInt64
  mut range : UInt
  mut cache : UInt
  mut cache_size : UInt64
  out : @bit.Writer
}

///|
pub fn RangeEncoder::new() -> RangeEncoder {
  {
    low: 0UL,
    range: 0xFFFFFFFFU,
    cache: 0U,
    cache_size: 1UL,
    out: @bit.Writer::new(),
  }
}

///|
fn RangeEncoder::shift_low(self : RangeEncoder) -> Unit {
  let low32 = @bit.uint_lo32(self.low)
  let high = @bit.uint_lo32(self.low >> 32)
  if low32 < 0xFF000000U || high != 0U {
    let mut temp = @bit.uint_to_byte(self.cache)
    while true {
      let summed = @bit.byte_to_uint(temp) + high
      self.out.write_u8(@bit.uint_to_byte(summed))
      temp = b'\xFF'
      self.cache_size = self.cache_size - 1UL
      if self.cache_size == 0UL {
        break
      }
    }
    self.cache = low32 >> 24
  }
  self.cache_size = self.cache_size + 1UL
  self.low = (low32 << 8).to_uint64()
}

///|
fn RangeEncoder::normalize(self : RangeEncoder) -> Unit {
  if self.range < TOP {
    self.range = self.range << 8
    self.shift_low()
  }
}

///|
pub fn RangeEncoder::encode_bit(
  self : RangeEncoder,
  probs : Array[UInt],
  index : Int,
  bit : Int,
) -> Unit {
  let mut prob = probs[index]
  let bound = (self.range >> 11) * prob
  if bit == 0 {
    self.range = bound
    prob = prob_update_0(prob)
  } else {
    self.low = self.low + bound.to_uint64()
    self.range = self.range - bound
    prob = prob_update_1(prob)
  }
  probs[index] = prob
  self.normalize()
}

///|
pub fn RangeEncoder::encode_direct_bits(
  self : RangeEncoder,
  value : UInt,
  num_bits : Int,
) -> Unit {
  let mut n = num_bits
  while n > 0 {
    self.range = self.range >> 1
    n = n - 1
    if ((value >> n) & 1U) != 0U {
      self.low = self.low + self.range.to_uint64()
    }
    self.normalize()
  }
}

///|
pub fn RangeEncoder::flush(self : RangeEncoder) -> Bytes {
  for _ in 0..<5 {
    self.shift_low()
  }
  self.out.to_bytes()
}

///|
pub struct RangeDecoder {
  mut range : UInt
  mut code : UInt
  mut pos : Int
  data : BytesView
}

///|
pub fn RangeDecoder::new(data : BytesView) -> RangeDecoder raise RcError {
  if data.length() < 5 {
    raise Eof
  }
  if data[0] != b'\x00' {
    raise Data
  }
  let mut code = 0U
  let mut i = 1
  while i < 5 {
    code = (code << 8) | @bit.byte_to_uint(data[i])
    i = i + 1
  }
  { range: 0xFFFFFFFFU, code, pos: 5, data, }
}

///|
fn RangeDecoder::read_byte(self : RangeDecoder) -> UInt raise RcError {
  if self.pos >= self.data.length() {
    raise Eof
  }
  let b = @bit.byte_to_uint(self.data[self.pos])
  self.pos = self.pos + 1
  b
}

///|
fn RangeDecoder::normalize(self : RangeDecoder) -> Unit raise RcError {
  if self.range < TOP {
    self.range = self.range << 8
    self.code = (self.code << 8) | self.read_byte()
  }
}

///|
pub fn RangeDecoder::decode_bit(
  self : RangeDecoder,
  probs : Array[UInt],
  index : Int,
) -> Int raise RcError {
  let prob = probs[index]
  let bound = (self.range >> 11) * prob
  if self.code < bound {
    self.range = bound
    probs[index] = prob_update_0(prob)
    self.normalize()
    0
  } else {
    self.range = self.range - bound
    self.code = self.code - bound
    probs[index] = prob_update_1(prob)
    self.normalize()
    1
  }
}

///|
pub fn RangeDecoder::decode_direct_bits(
  self : RangeDecoder,
  num_bits : Int,
) -> UInt raise RcError {
  let mut result = 0U
  let mut n = num_bits
  while n > 0 {
    self.range = self.range >> 1
    self.code = self.code - self.range
    let t = if self.code >> 31 != 0U { 0xFFFFFFFFU } else { 0U }
    self.code = self.code + (self.range & t)
    result = (result << 1) + (t + 1U)
    n = n - 1
    self.normalize()
  }
  result
}
