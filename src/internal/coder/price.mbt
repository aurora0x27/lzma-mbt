///|
/// Approximate bit prices from current probability models (LZMA SDK style).
/// Used only for parse decisions; the range coder still emits the real bits.
const BitPriceShift : Int = 4

///|
const MoveReducingBits : Int = 4

///|
fn make_prob_prices() -> Array[Int] {
  // prices[prob >> 4] ≈ bit cost of encoding a 0 when P(0)=prob/2048.
  let n = 2048 >> MoveReducingBits
  let prices = Array::make(n, 0)
  let mut i = 1 << (MoveReducingBits - 1)
  while i < 2048 {
    let mut w = i
    let mut bit_count = 0
    let mut j = 0
    while j < BitPriceShift {
      w = w * w
      bit_count = bit_count << 1
      while w >= 1 << 16 {
        w = w >> 1
        bit_count = bit_count + 1
      }
      j = j + 1
    }
    prices[i >> MoveReducingBits] = (11 << BitPriceShift) - 15 - bit_count
    i = i + (1 << MoveReducingBits)
  }
  prices
}

///|
let prob_prices : Array[Int] = make_prob_prices()

///|
fn bit_price0(prob : UInt) -> Int {
  prob_prices[uint_as_int(prob) >> MoveReducingBits]
}

///|
fn bit_price1(prob : UInt) -> Int {
  prob_prices[uint_as_int(@rc.BIT_MODEL_TOTAL - prob) >> MoveReducingBits]
}

///|
fn bit_price(prob : UInt, bit : Int) -> Int {
  if bit == 0 {
    bit_price0(prob)
  } else {
    bit_price1(prob)
  }
}

///|
fn tree_price(
  probs : Array[UInt],
  base : Int,
  num_bits : Int,
  value : Int,
) -> Int {
  let mut price = 0
  let mut m = 1
  let mut i = num_bits
  while i > 0 {
    i = i - 1
    let bit = (value >> i) & 1
    price = price + bit_price(probs[base + m], bit)
    m = (m << 1) + bit
  }
  price
}

///|
fn tree_price_rev(
  probs : Array[UInt],
  base : Int,
  num_bits : Int,
  value : Int,
) -> Int {
  let mut price = 0
  let mut m = 1
  let mut i = 0
  while i < num_bits {
    let bit = (value >> i) & 1
    price = price + bit_price(probs[base + m], bit)
    m = (m << 1) + bit
    i = i + 1
  }
  price
}

///|
fn length_price(
  choice : Array[UInt],
  low : Array[UInt],
  mid : Array[UInt],
  high : Array[UInt],
  pos_st : Int,
  len : Int,
) -> Int {
  let n = len - 2
  if n < 8 {
    bit_price(choice[0], 0) + tree_price(low, pos_st * 8, 3, n)
  } else if n < 16 {
    bit_price(choice[0], 1) +
    bit_price(choice[1], 0) +
    tree_price(mid, pos_st * 8, 3, n - 8)
  } else {
    bit_price(choice[0], 1) +
    bit_price(choice[1], 1) +
    tree_price(high, 0, 8, n - 16)
  }
}

///|
fn distance_price(probs : Probs, len : Int, dist : UInt) -> Int {
  let len_state = min_int(len - 2, 3)
  let slot = get_pos_slot(dist)
  let mut price = tree_price(probs.pos_slot, len_state * 64, 6, slot)
  if slot >= 4 {
    let direct_bits = (slot >> 1) - 1
    let base_dist = int_as_uint(2 | (slot & 1)) << direct_bits
    let footer = uint_as_int(dist - base_dist)
    if slot < 14 {
      price = price +
        tree_price_rev(
          probs.spec_pos,
          uint_as_int(base_dist) - slot,
          direct_bits,
          footer,
        )
    } else {
      // Direct bits are ~1 bit each in the price model.
      price = price + ((direct_bits - 4) << BitPriceShift)
      price = price + tree_price_rev(probs.align, 0, 4, footer & 15)
    }
  }
  price
}

///|
/// Map dictionary size (from preset) to a nice_len threshold for lazy matching.
fn nice_len_for_dict(dict_size : Int) -> Int {
  if dict_size <= 1 << 18 {
    8
  } else if dict_size <= 1 << 20 {
    16
  } else if dict_size <= 1 << 22 {
    32
  } else if dict_size <= 1 << 23 {
    64
  } else if dict_size <= 1 << 24 {
    64
  } else {
    128
  }
}

///|
/// Approximate literal price (match-context aware enough for parse choices).
fn literal_price(
  probs : Probs,
  state : Int,
  ps : Int,
  lit_base : Int,
  match_b : Byte,
  symbol : Byte,
) -> Int {
  let mut price = bit_price(probs.is_match[state * 16 + ps], 0)
  let sym = symbol.to_int()
  if state < 7 {
    price = price + tree_price(probs.lit, lit_base, 8, sym)
  } else {
    // Matched literal: approximate as 8 bit decisions at mid probability.
    let mut mb = match_b.to_int()
    let mut ctx = 1
    let mut i = 8
    while i > 0 {
      i = i - 1
      mb = mb << 1
      let match_bit = (mb >> 8) & 1
      let bit = (sym >> i) & 1
      price = price +
        bit_price(probs.lit[lit_base + 0x100 + (match_bit << 8) + ctx], bit)
      ctx = (ctx << 1) | bit
      if bit != match_bit {
        while i > 0 {
          i = i - 1
          let rest = (sym >> i) & 1
          price = price + bit_price(probs.lit[lit_base + ctx], rest)
          ctx = (ctx << 1) | rest
        }
        break
      }
    }
  }
  price
}
