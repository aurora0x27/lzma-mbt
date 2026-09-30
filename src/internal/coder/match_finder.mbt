///|
/// Hash-chain match finder (HC3-style). Search distance is capped by the
/// caller at `min(window, dict_size)`. Candidate walks are capped at
/// `MatchChainDepth` so encode stays O(n · depth), not O(n · dict).
const MatchChainDepth : Int = 256

///|
const MatchHashSize : Int = 65536

///|
/// Soft hint for initial chain capacity / seed window when dict is huge.
const MatchSeedCap : Int = 65536

///|
fn hash3(b0 : Byte, b1 : Byte, b2 : Byte) -> Int {
  let h = (b0.to_int() << 16) ^ (b1.to_int() << 8) ^ b2.to_int()
  h & (MatchHashSize - 1)
}

///|
/// Positions are absolute indices into the current encode input buffer.
priv struct MatchFinder {
  hash : Array[Int]
  /// `chain[pos - base]` = previous absolute position with the same 3-byte hash.
  chain : Array[Int]
  base : Int
}

///|
fn MatchFinder::new(base : Int) -> MatchFinder {
  {
    hash: Array::make(MatchHashSize, -1),
    chain: Array(capacity=MatchSeedCap + 1024),
    base,
  }
}

///|
fn MatchFinder::chain_at(self : MatchFinder, pos : Int) -> Int {
  let i = pos - self.base
  if i < 0 || i >= self.chain.length() {
    -1
  } else {
    self.chain[i]
  }
}

///|
fn MatchFinder::set_chain(self : MatchFinder, pos : Int, prev : Int) -> Unit {
  let i = pos - self.base
  while self.chain.length() <= i {
    self.chain.push(-1)
  }
  self.chain[i] = prev
}

///|
fn MatchFinder::insert(
  self : MatchFinder,
  input : BytesView,
  pos : Int,
) -> Unit {
  if pos < 0 || pos + 2 >= input.length() {
    self.set_chain(pos, -1)
    return
  }
  let h = hash3(input[pos], input[pos + 1], input[pos + 2])
  let prev = self.hash[h]
  self.set_chain(pos, prev)
  self.hash[h] = pos
}

///|
/// Seed hashes for absolute positions `[from, to)`.
fn MatchFinder::seed(
  self : MatchFinder,
  input : BytesView,
  from : Int,
  to : Int,
) -> Unit {
  let mut p = from
  while p < to {
    self.insert(input, p)
    p = p + 1
  }
}

///|
/// Longest new match at `pos` with distance in `1..=max_dist`.
/// `window` is the filled dictionary size (`LzmaEnc.pos`).
fn MatchFinder::find(
  self : MatchFinder,
  input : BytesView,
  pos : Int,
  window : Int,
  avail : Int,
  max_dist : Int,
) -> (Int, UInt)? {
  if avail < 2 || window < 1 || max_dist < 1 {
    return None
  }
  let dist_cap = min_int(window, max_dist)
  let max_len = min_int(273, avail)
  if pos + 2 >= input.length() {
    return find_new_match_linear(input, pos, dist_cap, window, avail)
  }
  let h = hash3(input[pos], input[pos + 1], input[pos + 2])
  let mut cur = self.hash[h]
  let mut best_len = 1
  let mut best_dist0 = 0U
  let mut depth = 0
  while cur >= 0 && depth < MatchChainDepth {
    let dist = pos - cur
    if dist < 1 {
      break
    }
    if dist > dist_cap {
      break
    }
    let len = match_len_at(input, pos, dist - 1, max_len, window)
    if len > best_len {
      best_len = len
      best_dist0 = int_as_uint(dist - 1)
      if len == max_len {
        break
      }
    }
    cur = self.chain_at(cur)
    depth = depth + 1
  }
  if best_len >= 2 {
    Some((best_len, best_dist0))
  } else {
    None
  }
}

///|
/// Linear fallback used only when fewer than 3 bytes remain (rare).
fn find_new_match_linear(
  input : BytesView,
  pos : Int,
  max_dist : Int,
  window : Int,
  avail : Int,
) -> (Int, UInt)? {
  if avail < 2 {
    return None
  }
  let max_len = min_int(273, avail)
  let mut best_len = 1
  let mut best_dist = 0U
  let mut d = 1
  while d <= max_dist {
    let len = match_len_at(input, pos, d - 1, max_len, window)
    if len > best_len {
      best_len = len
      best_dist = int_as_uint(d - 1)
      if len == max_len {
        break
      }
    }
    d = d + 1
  }
  if best_len >= 2 {
    Some((best_len, best_dist))
  } else {
    None
  }
}
