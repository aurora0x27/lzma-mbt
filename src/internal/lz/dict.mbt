///|
pub suberror DictError {
  InvalidDistance
} derive(Debug, Eq)

///|
pub struct Dict {
  buf : Array[Byte]
  mut cyclic : Int
  mut filled : Int
}

///|
pub fn Dict::new(size : Int) -> Dict {
  { buf: Array::make(size, b'\x00'), cyclic: 0, filled: 0, }
}

///|
/// Copy the dictionary cursor, fill count, and bytes for a decoder checkpoint.
pub fn Dict::clone(self : Dict) -> Dict {
  let buf = Array::make(self.buf.length(), b'\x00')
  for i in 0..<self.buf.length() {
    buf[i] = self.buf[i]
  }
  { buf, cyclic: self.cyclic, filled: self.filled, }
}

///|
pub fn Dict::reset(self : Dict) -> Unit {
  self.cyclic = 0
  self.filled = 0
}

///|
pub fn Dict::put(self : Dict, b : Byte) -> Unit {
  self.buf[self.cyclic] = b
  self.cyclic = self.cyclic + 1
  if self.cyclic == self.buf.length() {
    self.cyclic = 0
  }
  if self.filled < self.buf.length() {
    self.filled = self.filled + 1
  }
}

///|
/// `dist` is 0-based (0 repeats the last written byte).
pub fn Dict::get(self : Dict, dist : Int) -> Byte raise DictError {
  if dist < 0 || dist >= self.filled {
    raise InvalidDistance
  }
  let size = self.buf.length()
  let mut i = self.cyclic - 1 - dist
  if i < 0 {
    i = i + size
  }
  self.buf[i]
}

///|
pub fn Dict::copy_match(
  self : Dict,
  dist : Int,
  len : Int,
) -> Unit raise DictError {
  for _ in 0..<len {
    self.put(self.get(dist))
  }
}

///|
pub fn Dict::output_byte(self : Dict, dist : Int) -> Byte raise DictError {
  let b = self.get(dist)
  self.put(b)
  b
}
