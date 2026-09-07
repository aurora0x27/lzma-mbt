///|
pub(all) suberror CoderError {
  Eof
  Data
  Limit
  Unsupported
} derive(Debug, Eq)

///|
fn min_int(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn pos_state(pos : Int, pb : Int) -> Int {
  pos & ((1 << pb) - 1)
}

///|
fn lit_index(pos : Int, prev : Byte, lc : Int, lp : Int) -> Int {
  let lp_mask = (1 << lp) - 1
  ((pos & lp_mask) << lc) + (prev.to_int() >> (8 - lc))
}

///|
fn state_lit(state : Int) -> Int {
  if state < 4 {
    0
  } else if state < 10 {
    state - 3
  } else {
    state - 6
  }
}

///|
fn state_match(state : Int) -> Int {
  if state < 7 {
    7
  } else {
    10
  }
}

///|
fn state_rep(state : Int) -> Int {
  if state < 7 {
    8
  } else {
    11
  }
}

///|
fn state_short_rep(state : Int) -> Int {
  if state < 7 {
    9
  } else {
    11
  }
}

///|
fn uint_as_int(v : UInt) -> Int {
  v.reinterpret_as_int()
}

///|
fn int_as_uint(v : Int) -> UInt {
  v.reinterpret_as_uint()
}

///|
fn make_probs(n : Int) -> Array[UInt] {
  Array::make(n, @rc.PROB_INIT)
}

///|
priv struct Probs {
  is_match : Array[UInt]
  is_rep : Array[UInt]
  is_rep_g0 : Array[UInt]
  is_rep_g1 : Array[UInt]
  is_rep_g2 : Array[UInt]
  is_rep0_long : Array[UInt]
  pos_slot : Array[UInt]
  spec_pos : Array[UInt]
  align : Array[UInt]
  len_choice : Array[UInt]
  len_low : Array[UInt]
  len_mid : Array[UInt]
  len_high : Array[UInt]
  rep_len_choice : Array[UInt]
  rep_len_low : Array[UInt]
  rep_len_mid : Array[UInt]
  rep_len_high : Array[UInt]
  lit : Array[UInt]
}

///|
fn Probs::new(lc : Int, lp : Int) -> Probs {
  {
    is_match: make_probs(12 * 16),
    is_rep: make_probs(12),
    is_rep_g0: make_probs(12),
    is_rep_g1: make_probs(12),
    is_rep_g2: make_probs(12),
    is_rep0_long: make_probs(12 * 16),
    pos_slot: make_probs(4 * 64),
    spec_pos: make_probs(256),
    align: make_probs(16),
    len_choice: make_probs(2),
    len_low: make_probs(16 * 8),
    len_mid: make_probs(16 * 8),
    len_high: make_probs(256),
    rep_len_choice: make_probs(2),
    rep_len_low: make_probs(16 * 8),
    rep_len_mid: make_probs(16 * 8),
    rep_len_high: make_probs(256),
    lit: make_probs(0x300 << (lc + lp)),
  }
}

///|
fn dec_bit(
  dec : @rc.RangeDecoder,
  probs : Array[UInt],
  index : Int,
) -> Int raise CoderError {
  dec.decode_bit(probs, index) catch {
    @rc.Eof => raise Eof
    @rc.Data => raise Data
  }
}

///|
fn dec_direct(dec : @rc.RangeDecoder, n : Int) -> UInt raise CoderError {
  dec.decode_direct_bits(n) catch {
    @rc.Eof => raise Eof
    @rc.Data => raise Data
  }
}

///|
fn encode_tree(
  enc : @rc.RangeEncoder,
  probs : Array[UInt],
  base : Int,
  num_bits : Int,
  value : Int,
) -> Unit {
  let mut m = 1
  let mut i = num_bits
  while i > 0 {
    i = i - 1
    let bit = (value >> i) & 1
    enc.encode_bit(probs, base + m, bit)
    m = (m << 1) + bit
  }
}

///|
fn decode_tree(
  dec : @rc.RangeDecoder,
  probs : Array[UInt],
  base : Int,
  num_bits : Int,
) -> Int raise CoderError {
  let mut m = 1
  for _ in 0..<num_bits {
    m = (m << 1) + dec_bit(dec, probs, base + m)
  }
  m - (1 << num_bits)
}

///|
fn encode_tree_rev(
  enc : @rc.RangeEncoder,
  probs : Array[UInt],
  base : Int,
  num_bits : Int,
  value : Int,
) -> Unit {
  let mut m = 1
  let mut i = 0
  while i < num_bits {
    let bit = (value >> i) & 1
    enc.encode_bit(probs, base + m, bit)
    m = (m << 1) + bit
    i = i + 1
  }
}

///|
fn decode_tree_rev(
  dec : @rc.RangeDecoder,
  probs : Array[UInt],
  base : Int,
  num_bits : Int,
) -> Int raise CoderError {
  let mut m = 1
  let mut value = 0
  let mut i = 0
  while i < num_bits {
    let bit = dec_bit(dec, probs, base + m)
    m = (m << 1) + bit
    value = value | (bit << i)
    i = i + 1
  }
  value
}

///|
fn encode_length(
  enc : @rc.RangeEncoder,
  choice : Array[UInt],
  low : Array[UInt],
  mid : Array[UInt],
  high : Array[UInt],
  pos_st : Int,
  len : Int,
) -> Unit {
  let n = len - 2
  if n < 8 {
    enc.encode_bit(choice, 0, 0)
    encode_tree(enc, low, pos_st * 8, 3, n)
  } else if n < 16 {
    enc.encode_bit(choice, 0, 1)
    enc.encode_bit(choice, 1, 0)
    encode_tree(enc, mid, pos_st * 8, 3, n - 8)
  } else {
    enc.encode_bit(choice, 0, 1)
    enc.encode_bit(choice, 1, 1)
    encode_tree(enc, high, 0, 8, n - 16)
  }
}

///|
fn decode_length(
  dec : @rc.RangeDecoder,
  choice : Array[UInt],
  low : Array[UInt],
  mid : Array[UInt],
  high : Array[UInt],
  pos_st : Int,
) -> Int raise CoderError {
  if dec_bit(dec, choice, 0) == 0 {
    2 + decode_tree(dec, low, pos_st * 8, 3)
  } else if dec_bit(dec, choice, 1) == 0 {
    10 + decode_tree(dec, mid, pos_st * 8, 3)
  } else {
    18 + decode_tree(dec, high, 0, 8)
  }
}

///|
fn get_pos_slot(dist : UInt) -> Int {
  if dist < 4U {
    uint_as_int(dist)
  } else {
    let mut ms = 31
    while ((dist >> ms) & 1U) == 0U {
      ms = ms - 1
    }
    ms + ms + uint_as_int((dist >> (ms - 1)) & 1U)
  }
}

///|
fn encode_distance(
  enc : @rc.RangeEncoder,
  probs : Probs,
  len : Int,
  dist : UInt,
) -> Unit {
  let len_state = min_int(len - 2, 3)
  let slot = get_pos_slot(dist)
  encode_tree(enc, probs.pos_slot, len_state * 64, 6, slot)
  if slot >= 4 {
    let direct_bits = (slot >> 1) - 1
    let base_dist = int_as_uint(2 | (slot & 1)) << direct_bits
    let footer = uint_as_int(dist - base_dist)
    if slot < 14 {
      encode_tree_rev(
        enc,
        probs.spec_pos,
        uint_as_int(base_dist) - slot,
        direct_bits,
        footer,
      )
    } else {
      enc.encode_direct_bits(int_as_uint(footer) >> 4, direct_bits - 4)
      encode_tree_rev(enc, probs.align, 0, 4, footer & 15)
    }
  }
}

///|
fn decode_distance(
  dec : @rc.RangeDecoder,
  probs : Probs,
  len : Int,
) -> UInt raise CoderError {
  let len_state = min_int(len - 2, 3)
  let slot = decode_tree(dec, probs.pos_slot, len_state * 64, 6)
  if slot < 4 {
    int_as_uint(slot)
  } else {
    let direct_bits = (slot >> 1) - 1
    let mut dist = int_as_uint(2 | (slot & 1)) << direct_bits
    if slot < 14 {
      dist = dist +
        int_as_uint(
          decode_tree_rev(
            dec,
            probs.spec_pos,
            uint_as_int(dist) - slot,
            direct_bits,
          ),
        )
      dist
    } else {
      dist = dist + (dec_direct(dec, direct_bits - 4) << 4)
      dist = dist + int_as_uint(decode_tree_rev(dec, probs.align, 0, 4))
      dist
    }
  }
}

///|
fn encode_literal(
  enc : @rc.RangeEncoder,
  lit : Array[UInt],
  base : Int,
  state : Int,
  match_byte : Byte,
  symbol : Byte,
) -> Unit {
  let sym = symbol.to_int()
  if state < 7 {
    encode_tree(enc, lit, base, 8, sym)
  } else {
    let mut mb = match_byte.to_int()
    let mut ctx = 1
    let mut i = 8
    while i > 0 {
      i = i - 1
      mb = mb << 1
      let match_bit = (mb >> 8) & 1
      let bit = (sym >> i) & 1
      enc.encode_bit(lit, base + 0x100 + (match_bit << 8) + ctx, bit)
      ctx = (ctx << 1) | bit
      if bit != match_bit {
        while i > 0 {
          i = i - 1
          let rest = (sym >> i) & 1
          enc.encode_bit(lit, base + ctx, rest)
          ctx = (ctx << 1) | rest
        }
        break
      }
    }
  }
}

///|
fn decode_literal(
  dec : @rc.RangeDecoder,
  lit : Array[UInt],
  base : Int,
  state : Int,
  match_byte : Byte,
) -> Byte raise CoderError {
  if state < 7 {
    decode_tree(dec, lit, base, 8).to_byte()
  } else {
    let mut mb = match_byte.to_int()
    let mut ctx = 1
    for _ in 0..<8 {
      mb = mb << 1
      let match_bit = (mb >> 8) & 1
      let bit = dec_bit(dec, lit, base + 0x100 + (match_bit << 8) + ctx)
      ctx = (ctx << 1) | bit
      if bit != match_bit {
        while ctx < 0x100 {
          ctx = (ctx << 1) | dec_bit(dec, lit, base + ctx)
        }
        break
      }
    }
    (ctx & 0xFF).to_byte()
  }
}
