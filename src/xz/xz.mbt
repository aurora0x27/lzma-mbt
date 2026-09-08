///|
fn write_vli(w : @bit.Writer, v0 : UInt64) -> Unit {
  let mut v = v0
  while v >= 0x80UL {
    let b = ((v & 0x7FUL) | 0x80UL).reinterpret_as_int64().to_int()
    w.write_u8(b.to_byte())
    v = v >> 7
  }
  w.write_u8(v.reinterpret_as_int64().to_int().to_byte())
}

///|
fn vli_min_len(v : UInt64) -> Int {
  let mut n = 1
  let mut x = v
  while x >= 0x80UL {
    n = n + 1
    x = x >> 7
  }
  n
}

///|
fn read_vli(r : @bit.Reader) -> UInt64 raise @coder.CoderError {
  let mut result = 0UL
  let mut shift = 0
  let mut n = 0
  for _ in 0..<9 {
    let b = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
    n = n + 1
    let v = b.to_int().reinterpret_as_uint().to_uint64()
    result = result | ((v & 0x7FUL) << shift)
    if (v & 0x80UL) == 0UL {
      if n != vli_min_len(result) {
        raise @coder.Data
      }
      return result
    }
    shift = shift + 7
  }
  raise @coder.Data
}

///|
fn pad_to_4(w : @bit.Writer) -> Unit {
  while w.length() % 4 != 0 {
    w.write_u8(b'\x00')
  }
}

///|
fn check_field_size(check_id : Int) -> Int raise @coder.CoderError {
  match check_id {
    0 => 0
    1 => 4
    4 => 8
    10 => 32
    _ => raise @coder.Unsupported
  }
}

///|
fn write_check(w : @bit.Writer, check_id : Int, data : BytesView) -> Unit {
  match check_id {
    1 => w.write_u32_le(@checksum.crc32(data))
    4 => w.write_u64_le(@checksum.crc64(data))
    10 => w.write_bytes(@checksum.sha256(data)[:])
    _ => ()
  }
}

///|
fn bytes_from_view(data : BytesView) -> Bytes {
  let out = Array(capacity=data.length())
  for b in data {
    out.push(b)
  }
  Bytes::from_array(out[:])
}

///|
fn bytes_equal(a : BytesView, b : BytesView) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut i = 0
  while i < a.length() {
    if a[i] != b[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
fn bytes_to_u32_le(v : BytesView) -> UInt {
  v[0].to_int().reinterpret_as_uint() |
  (v[1].to_int().reinterpret_as_uint() << 8) |
  (v[2].to_int().reinterpret_as_uint() << 16) |
  (v[3].to_int().reinterpret_as_uint() << 24)
}

///|
fn bytes_to_u64_le(v : BytesView) -> UInt64 {
  bytes_to_u32_le(v[0:4]).to_uint64() |
  (bytes_to_u32_le(v[4:8]).to_uint64() << 32)
}

///|
/// Sizes recorded for one decoded Block, used to check Index records.
pub struct BlockSizes {
  unpadded : UInt64
  uncompressed : UInt64
}

///|
priv struct BlockFilters {
  dict_size : UInt
  delta_distance : Int
  x86 : Bool
}

///|
priv struct BlockHeader {
  hbytes_len : Int
  filters : BlockFilters
  declared_comp : UInt64?
  declared_uncomp : UInt64?
}

///|
fn parse_block_filters(
  hr : @bit.Reader,
  nfilters : Int,
) -> BlockFilters raise @coder.CoderError {
  if nfilters < 1 || nfilters > 2 {
    raise @coder.Unsupported
  }
  let mut delta_distance = 0
  let mut x86 = false
  let mut dict_size = 0U
  let mut i = 0
  while i < nfilters {
    let fid = read_vli(hr)
    let psz64 = read_vli(hr)
    if psz64 > hr.remaining().reinterpret_as_uint().to_uint64() {
      raise @coder.Data
    }
    let psz = psz64.reinterpret_as_int64().to_int()
    let props = hr.read_exact(psz) catch { @bit.Eof => raise @coder.Eof }
    if i == nfilters - 1 {
      // The final filter must be the LZMA2 codec. A recognized pre-filter in
      // the final position is an invalid chain; unknown IDs are unsupported.
      if fid == 0x03UL || fid == 0x04UL {
        raise @coder.Data
      }
      if fid != 0x21UL {
        raise @coder.Unsupported
      }
      if psz != 1 {
        raise @coder.Data
      }
      dict_size = @lzma2.lzma2_dict_size(props[0])
    } else {
      // With at most two filters only one pre-filter can be listed; it is
      // either Delta (0x03, one-byte property) or x86 BCJ (0x04, no options).
      if fid != 0x03UL && fid != 0x04UL {
        raise @coder.Unsupported
      }
      if fid == 0x03UL {
        if psz != 1 {
          raise @coder.Data
        }
        delta_distance = props[0].to_int() + 1
      } else {
        if psz != 0 {
          raise @coder.Data
        }
        x86 = true
      }
    }
    i = i + 1
  }
  { dict_size, delta_distance, x86, }
}

///|
fn parse_index_and_footer(
  r : @bit.Reader,
  flags : Bytes,
  blocks : Array[BlockSizes],
) -> Int raise @coder.CoderError {
  let data = r.rest()
  let start = r.position()
  let ind = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  if ind != b'\x00' {
    raise @coder.Data
  }
  let nrec = read_vli(r)
  if nrec != blocks.length().reinterpret_as_uint().to_uint64() {
    raise @coder.Data
  }
  let mut i = 0
  while i < blocks.length() {
    let unpadded = read_vli(r)
    let uncompressed = read_vli(r)
    if unpadded != blocks[i].unpadded || uncompressed != blocks[i].uncompressed {
      raise @coder.Data
    }
    i = i + 1
  }
  while r.position() % 4 != 0 {
    let z = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
    if z != b'\x00' {
      raise @coder.Data
    }
  }
  let idx_len = r.position() - start
  let stored_crc = r.read_u32_le() catch { @bit.Eof => raise @coder.Eof }
  if @checksum.crc32(data[0:idx_len]) != stored_crc {
    raise @coder.Data
  }
  let fcrc = r.read_u32_le() catch { @bit.Eof => raise @coder.Eof }
  let backward = r.read_u32_le() catch { @bit.Eof => raise @coder.Eof }
  let g0 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let g1 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  if g0 != flags[0] || g1 != flags[1] {
    raise @coder.Data
  }
  let expected_back = ((idx_len + 4) / 4 - 1).reinterpret_as_uint()
  if backward != expected_back {
    raise @coder.Data
  }
  let foot = @bit.Writer::new()
  foot.write_u32_le(backward)
  foot.write_u8(g0)
  foot.write_u8(g1)
  if @checksum.crc32(foot.to_bytes()[:]) != fcrc {
    raise @coder.Data
  }
  let y = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let z = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  if y != b'\x59' || z != b'\x5A' {
    raise @coder.Data
  }
  r.position()
}

///|
/// Stream Padding is only null bytes and a multiple of four (including zero).
/// Called after a Stream Footer when `concatenated` is set. A following
/// non-null byte is left unconsumed so the next Stream Header can be parsed.
fn skip_stream_padding(r : @bit.Reader) -> Unit raise @coder.CoderError {
  let mut n = 0
  while r.remaining() > 0 && r.rest()[0] == b'\x00' {
    ignore(r.read_u8() catch { @bit.Eof => raise @coder.Eof })
    n = n + 1
  }
  if n % 4 != 0 {
    raise @coder.Data
  }
}

///|
/// Parse and validate a Block Header, leaving the data area untouched.
fn parse_block_header(r : @bit.Reader) -> BlockHeader raise @coder.CoderError {
  let hs = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let header_len = (hs.to_int() + 1) * 4
  let rest_hdr = r.read_exact(header_len - 5) catch {
    @bit.Eof => raise @coder.Eof
  }
  let hdr_arr : Array[Byte] = [hs]
  for b in rest_hdr {
    hdr_arr.push(b)
  }
  let hbytes = Bytes::from_array(hdr_arr[:])
  let hcrc = r.read_u32_le() catch { @bit.Eof => raise @coder.Eof }
  if @checksum.crc32(hbytes[:]) != hcrc {
    raise @coder.Data
  }
  let hr = @bit.Reader::new(hbytes[:])
  ignore(hr.read_u8() catch { @bit.Eof => raise @coder.Eof })
  let bflags = hr.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let bf = bflags.to_int()
  if (bf & 0x3C) != 0 {
    raise @coder.Data
  }
  let nfilters = (bf & 0x03) + 1
  let mut declared_comp : UInt64? = None
  if (bf & 0x40) != 0 {
    declared_comp = Some(read_vli(hr))
  }
  let mut declared_uncomp : UInt64? = None
  if (bf & 0x80) != 0 {
    declared_uncomp = Some(read_vli(hr))
  }
  let filters = parse_block_filters(hr, nfilters)
  while hr.remaining() > 0 {
    let z = hr.read_u8() catch { @bit.Eof => raise @coder.Eof }
    if z != b'\x00' {
      raise @coder.Data
    }
  }
  { hbytes_len: hbytes.length(), filters, declared_comp, declared_uncomp, }
}

///|
/// Decode one Block starting at the current reader position. The next byte
/// must already have been peeked as a non-zero Block Header Size (0x00 is
/// the Index indicator, not a Block).
fn decode_one_block(
  r : @bit.Reader,
  memlimit : UInt64,
  ignore_check : Bool,
  check_id : Int,
  check_n : Int,
) -> (Bytes, UInt64, Int) raise @coder.CoderError {
  let hs = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let header_len = (hs.to_int() + 1) * 4
  let rest_hdr = r.read_exact(header_len - 5) catch {
    @bit.Eof => raise @coder.Eof
  }
  let hdr_arr : Array[Byte] = [hs]
  for b in rest_hdr {
    hdr_arr.push(b)
  }
  let hbytes = Bytes::from_array(hdr_arr[:])
  let hcrc = r.read_u32_le() catch { @bit.Eof => raise @coder.Eof }
  if @checksum.crc32(hbytes[:]) != hcrc {
    raise @coder.Data
  }
  let hr = @bit.Reader::new(hbytes[:])
  ignore(hr.read_u8() catch { @bit.Eof => raise @coder.Eof })
  let bflags = hr.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let bf = bflags.to_int()
  if (bf & 0x3C) != 0 {
    raise @coder.Data
  }
  let nfilters = (bf & 0x03) + 1
  let has_comp_size = (bf & 0x40) != 0
  let mut declared_comp : UInt64? = None
  if has_comp_size {
    declared_comp = Some(read_vli(hr))
  }
  let mut declared_uncomp : UInt64? = None
  if (bf & 0x80) != 0 {
    declared_uncomp = Some(read_vli(hr))
  }
  let filters = parse_block_filters(hr, nfilters)
  while hr.remaining() > 0 {
    let z = hr.read_u8() catch { @bit.Eof => raise @coder.Eof }
    if z != b'\x00' {
      raise @coder.Data
    }
  }
  let rest = r.rest()
  let window = match declared_comp {
    Some(n) => {
      let cap = rest.length().reinterpret_as_uint().to_uint64()
      if n > cap {
        raise @coder.Eof
      }
      rest[0:n.reinterpret_as_int64().to_int()]
    }
    None => rest
  }
  let (filtered, used) = @lzma2.decode_lzma2_consumed(
    window,
    memlimit,
    dict_size=filters.dict_size,
  )
  let plain = if filters.delta_distance != 0 {
    @filters.delta_decode(filtered[:], filters.delta_distance) catch {
      _ => raise @coder.Data
    }
  } else if filters.x86 {
    @filters.bcj_x86(filtered[:], 0U, false)
  } else {
    filtered
  }
  match declared_comp {
    Some(_) => if used != window.length() { raise @coder.Data }
    None => ()
  }
  match declared_uncomp {
    Some(n) =>
      if n != plain.length().reinterpret_as_uint().to_uint64() {
        raise @coder.Data
      }
    None => ()
  }
  ignore(r.read_exact(used) catch { @bit.Eof => raise @coder.Eof })
  let pad = (4 - used % 4) % 4
  for _ in 0..<pad {
    let z = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
    if z != b'\x00' {
      raise @coder.Data
    }
  }
  let stored = r.read_exact(check_n) catch { @bit.Eof => raise @coder.Eof }
  if ignore_check == false {
    let ok = match check_id {
      0 => true
      1 =>
        stored.length() == 4 &&
        @checksum.crc32(plain[:]) == bytes_to_u32_le(stored[:])
      4 =>
        stored.length() == 8 &&
        @checksum.crc64(plain[:]) == bytes_to_u64_le(stored[:])
      10 =>
        stored.length() == 32 &&
        bytes_equal(stored, @checksum.sha256(plain[:])[:])
      _ => false
    }
    if ok == false {
      raise @coder.Data
    }
  }
  let unpadded = (hbytes.length() + 4 + used + check_n)
    .reinterpret_as_uint()
    .to_uint64()
  (plain, unpadded, r.position())
}

///|
/// Incremental XZ container parser. It retains explicit Block payload state
/// between calls and commits Index records only after padding, Check, and
/// size validation. Blocks without a declared compressed size use the
/// one-shot decoder because their payload boundary is not known yet.
pub struct StreamDecoder {
  mut buf : Array[Byte]
  mut pos : Int
  mut started : Bool
  mut done : Bool
  mut flags : Bytes?
  mut check_id : Int
  memlimit : UInt64
  ignore_check : Bool
  blocks : Array[BlockSizes]
  mut active_block : Bool
  mut active_lzma2 : @lzma2.StreamDecoder?
  mut active_payload_remaining : Int
  mut active_comp_total : Int
  mut active_hbytes_len : Int
  mut active_declared_uncomp : UInt64?
  mut active_delta_distance : Int
  active_plain : Array[Byte]
  mut active_delta_history : Array[Byte]
  mut active_delta_pos : Int
}

///|
pub fn StreamDecoder::new(
  memlimit : UInt64,
  ignore_check : Bool,
) -> StreamDecoder {
  {
    buf: [],
    pos: 0,
    started: false,
    done: false,
    flags: None,
    check_id: 0,
    memlimit,
    ignore_check,
    blocks: [],
    active_block: false,
    active_lzma2: None,
    active_payload_remaining: 0,
    active_comp_total: 0,
    active_hbytes_len: 0,
    active_declared_uncomp: None,
    active_delta_distance: 0,
    active_plain: [],
    active_delta_history: [],
    active_delta_pos: 0,
  }
}

///|
pub fn StreamDecoder::reset(self : StreamDecoder) -> Unit {
  self.buf.clear()
  self.pos = 0
  self.started = false
  self.done = false
  self.flags = None
  self.check_id = 0
  self.blocks.clear()
  self.active_block = false
  self.active_lzma2 = None
  self.active_payload_remaining = 0
  self.active_comp_total = 0
  self.active_hbytes_len = 0
  self.active_declared_uncomp = None
  self.active_delta_distance = 0
  self.active_plain.clear()
  self.active_delta_history.clear()
  self.active_delta_pos = 0
}

///|
fn StreamDecoder::available(self : StreamDecoder) -> Int {
  self.buf.length() - self.pos
}

///|
fn StreamDecoder::compact(self : StreamDecoder) -> Unit {
  if self.pos > 0 && (self.pos >= 4096 || self.pos * 2 >= self.buf.length()) {
    let next = Array(capacity=self.available())
    for b in self.buf[self.pos:] {
      next.push(b)
    }
    self.buf = next
    self.pos = 0
  }
}

///|
fn StreamDecoder::suffix(self : StreamDecoder) -> Bytes {
  let out = Array(capacity=self.available())
  for b in self.buf[self.pos:] {
    out.push(b)
  }
  Bytes::from_array(out[:])
}

///|
fn StreamDecoder::read_header(
  self : StreamDecoder,
) -> Unit raise @coder.CoderError {
  if self.available() < 12 {
    raise @coder.Eof
  }
  let m = self.buf[self.pos:self.pos + 6]
  if m[0] != b'\xFD' ||
    m[1] != b'\x37' ||
    m[2] != b'\x7A' ||
    m[3] != b'X' ||
    m[4] != b'Z' ||
    m[5] != b'\x00' {
    raise @coder.Data
  }
  let f0 = self.buf[self.pos + 6]
  let f1 = self.buf[self.pos + 7]
  if f0 != b'\x00' {
    raise @coder.Data
  }
  let flags = Bytes::from_array([f0, f1][:])
  let crc_bytes = Array(capacity=4)
  for b in self.buf[self.pos + 8:self.pos + 12] {
    crc_bytes.push(b)
  }
  let stored = bytes_to_u32_le(Bytes::from_array(crc_bytes[:])[:])
  if @checksum.crc32(flags[:]) != stored {
    raise @coder.Data
  }
  self.flags = Some(flags)
  self.check_id = f1.to_int()
  check_field_size(self.check_id) |> ignore
  self.pos = self.pos + 12
  self.started = true
}

///|
fn StreamDecoder::append_active_output(
  self : StreamDecoder,
  filtered : Bytes,
  out : @bit.Writer,
) -> Unit raise @coder.CoderError {
  if self.active_block == false {
    raise @coder.Data
  }
  if self.active_delta_distance == 0 {
    for b in filtered[:] {
      self.active_plain.push(b)
    }
    out.write_bytes(filtered[:])
    return
  }
  let distance = self.active_delta_distance
  if self.active_delta_history.length() == 0 {
    self.active_delta_history = Array::make(distance, b'\x00')
  }
  let decoded = @bit.Writer::new()
  for b in filtered[:] {
    let prev = self.active_delta_history[self.active_delta_pos].to_int()
    let value = ((b.to_int() + prev) & 0xFF).to_byte()
    self.active_delta_history[self.active_delta_pos] = value
    self.active_delta_pos = (self.active_delta_pos + 1) % distance
    self.active_plain.push(value)
    decoded.write_u8(value)
  }
  out.write_bytes(decoded.to_bytes()[:])
}

///|
fn StreamDecoder::active_check_ok(self : StreamDecoder) -> Bool {
  let plain = Bytes::from_array(self.active_plain[:])
  match self.active_declared_uncomp {
    Some(n) => if n != plain.length().to_uint64() { return false }
    None => ()
  }
  true
}

///|
fn StreamDecoder::clear_active(self : StreamDecoder) -> Unit {
  self.active_block = false
  self.active_lzma2 = None
  self.active_payload_remaining = 0
  self.active_plain.clear()
  self.active_delta_history.clear()
  self.active_delta_pos = 0
}

///|
fn StreamDecoder::finish_active(
  self : StreamDecoder,
  out : @bit.Writer,
) -> Unit raise @coder.CoderError {
  if self.active_block == false {
    raise @coder.Data
  }
  let comp = self.active_comp_total
  let pad = (4 - comp % 4) % 4
  if self.available() < pad + check_field_size(self.check_id) {
    raise @coder.Eof
  }
  for _ in 0..<pad {
    if self.buf[self.pos] != b'\x00' {
      raise @coder.Data
    }
    self.pos = self.pos + 1
  }
  let stored = Bytes::from_array(
    self.buf[self.pos:self.pos + check_field_size(self.check_id)],
  )
  let plain = Bytes::from_array(self.active_plain[:])
  if self.ignore_check == false {
    let ok = match self.check_id {
      0 => true
      1 => @checksum.crc32(plain[:]) == bytes_to_u32_le(stored)
      4 => @checksum.crc64(plain[:]) == bytes_to_u64_le(stored)
      10 => bytes_equal(stored, @checksum.sha256(plain[:])[:])
      _ => false
    }
    if ok == false {
      raise @coder.Data
    }
  }
  self.pos = self.pos + check_field_size(self.check_id)
  if self.active_check_ok() == false {
    raise @coder.Data
  }
  self.blocks.push({
    unpadded: (self.active_hbytes_len +
    4 +
    comp +
    check_field_size(self.check_id))
    .reinterpret_as_uint()
    .to_uint64(),
    uncompressed: plain.length().to_uint64(),
  })
  self.clear_active()
  self.compact()
  ignore(out)
}

///|
pub fn StreamDecoder::feed(
  self : StreamDecoder,
  input : BytesView,
) -> (Bytes, Bool) raise @coder.CoderError {
  if self.done && input.length() > 0 {
    raise @coder.Data
  }
  for b in input {
    self.buf.push(b)
  }
  let out = @bit.Writer::new()
  if self.started == false {
    self.read_header() catch {
      @coder.Eof => return (out.to_bytes(), false)
      err => raise err
    }
  }
  let flags = match self.flags {
    None => raise @coder.Data
    Some(v) => v
  }
  while self.done == false {
    if self.available() < 1 {
      break
    }
    if self.active_block {
      let decoder = match self.active_lzma2 {
        None => raise @coder.Data
        Some(v) => v
      }
      if self.active_payload_remaining > 0 {
        let take = if self.available() < self.active_payload_remaining {
          self.available()
        } else {
          self.active_payload_remaining
        }
        let chunk = Bytes::from_array(self.buf[self.pos:self.pos + take])
        self.pos = self.pos + take
        self.active_payload_remaining = self.active_payload_remaining - take
        let (filtered, done) = decoder.feed(chunk[:])
        self.append_active_output(filtered, out)
        if self.active_payload_remaining == 0 && done == false {
          raise @coder.Data
        }
        if self.active_payload_remaining > 0 {
          break
        }
      }
      self.finish_active(out) catch {
        @coder.Eof => break
        err => raise err
      }
      continue
    }
    let suffix = self.suffix()
    if suffix[0] == b'\x00' {
      let r = @bit.Reader::new(suffix[:])
      let used = parse_index_and_footer(r, flags, self.blocks) catch {
        @coder.Eof => break
        err => raise err
      }
      self.pos = self.pos + used
      self.done = true
      break
    }
    let r = @bit.Reader::new(suffix[:])
    let header = parse_block_header(r) catch {
      @coder.Eof => break
      err => raise err
    }
    // x86 BCJ is a five-byte sliding-window filter, so Blocks using it are
    // decoded whole (once their payload, padding, and Check are buffered)
    // through the same one-shot path as Blocks without a declared compressed
    // size. Delta Blocks keep the incremental per-chunk path.
    let whole = match header.declared_comp {
      None => true
      Some(_) => header.filters.x86
    }
    if whole {
      let (plain, unpadded, used) = decode_one_block(
        @bit.Reader::new(suffix[:]),
        self.memlimit,
        self.ignore_check,
        self.check_id,
        check_field_size(self.check_id),
      ) catch {
        @coder.Eof => break
        err => raise err
      }
      out.write_bytes(plain[:])
      self.blocks.push({ unpadded, uncompressed: plain.length().to_uint64(), })
      self.pos = self.pos + used
      self.compact()
      continue
    }
    let comp = match header.declared_comp {
      Some(n) => n.reinterpret_as_int64().to_int()
      None => raise @coder.Data
    }
    if comp < 1 {
      raise @coder.Data
    }
    let decoder = @lzma2.StreamDecoder::new(
      self.memlimit,
      dict_size=header.filters.dict_size,
    )
    self.active_block = true
    self.active_lzma2 = Some(decoder)
    self.active_payload_remaining = comp
    self.active_comp_total = comp
    self.active_hbytes_len = header.hbytes_len
    self.active_declared_uncomp = header.declared_uncomp
    self.active_delta_distance = header.filters.delta_distance
    self.active_plain.clear()
    self.active_delta_history.clear()
    self.active_delta_pos = 0
    self.pos = self.pos + r.position()
  }
  (out.to_bytes(), self.done)
}

///|
pub fn StreamDecoder::finish(
  self : StreamDecoder,
) -> Bytes raise @coder.CoderError {
  if self.done == false {
    raise @coder.Eof
  }
  b""
}

///|
/// Encode a single-Block `.xz` Stream. `delta_distance` and `bcj_x86` select
/// the optional container pre-filter written into the Block Header; at most
/// one pre-filter is supported (x86 BCJ has no filter options, so it is
/// stored as filter ID `0x04` with a zero-length property).
pub fn encode_xz(
  input : BytesView,
  lc : Int,
  lp : Int,
  pb : Int,
  dict_size : UInt,
  check_id? : Int = 4,
  delta_distance? : Int = 0,
  bcj_x86? : Bool = false,
) -> Bytes raise @coder.CoderError {
  // A single Block is enough for a well-formed stream; multi-Block splitting
  // is not required for decoder compatibility (see docs/research/xz.md).
  let check_n = check_field_size(check_id)
  if delta_distance < 0 || delta_distance > 256 {
    raise @coder.Data
  }
  if bcj_x86 && delta_distance != 0 {
    raise @coder.Data
  }
  let pre = if bcj_x86 {
    @filters.bcj_x86(input, 0U, true)
  } else if delta_distance != 0 {
    @filters.delta_encode(input, delta_distance) catch {
      _ => raise @coder.Data
    }
  } else {
    bytes_from_view(input)
  }
  let payload = @lzma2.encode_lzma2(pre[:], lc, lp, pb, dict_size)
  let flags = Bytes::from_array([b'\x00', check_id.to_byte()][:])
  let w = @bit.Writer::new()
  w.write_bytes(b"\xFD\x37\x7A\x58\x5A\x00"[:])
  w.write_bytes(flags[:])
  w.write_u32_le(@checksum.crc32(flags[:]))
  let content = @bit.Writer::new()
  let has_pre = bcj_x86 || delta_distance != 0
  content.write_u8(if has_pre { b'\xC1' } else { b'\xC0' })
  write_vli(content, payload.length().reinterpret_as_uint().to_uint64())
  write_vli(content, input.length().reinterpret_as_uint().to_uint64())
  if bcj_x86 {
    // x86 BCJ: filter ID 0x04, empty filter properties (size 0).
    content.write_u8(b'\x04')
    content.write_u8(b'\x00')
  } else if delta_distance != 0 {
    content.write_u8(b'\x03')
    content.write_u8(b'\x01')
    content.write_u8((delta_distance - 1).to_byte())
  }
  content.write_u8(b'\x21')
  content.write_u8(b'\x01')
  content.write_u8(@lzma2.lzma2_dict_prop(dict_size))
  while (1 + content.length()) % 4 != 0 {
    content.write_u8(b'\x00')
  }
  let hdr = @bit.Writer::new()
  hdr.write_u8(((1 + content.length()) / 4).to_byte())
  hdr.write_bytes(content.to_bytes()[:])
  let hbytes = hdr.to_bytes()
  w.write_bytes(hbytes[:])
  w.write_u32_le(@checksum.crc32(hbytes[:]))
  w.write_bytes(payload[:])
  let pad = (4 - payload.length() % 4) % 4
  for _ in 0..<pad {
    w.write_u8(b'\x00')
  }
  write_check(w, check_id, input)
  let unpadded = hbytes.length() + 4 + payload.length() + check_n
  let index = @bit.Writer::new()
  index.write_u8(b'\x00')
  write_vli(index, 1UL)
  write_vli(index, unpadded.reinterpret_as_uint().to_uint64())
  write_vli(index, input.length().reinterpret_as_uint().to_uint64())
  pad_to_4(index)
  let ibytes = index.to_bytes()
  w.write_bytes(ibytes[:])
  w.write_u32_le(@checksum.crc32(ibytes[:]))
  let backward = ((ibytes.length() + 4) / 4 - 1).reinterpret_as_uint()
  let foot = @bit.Writer::new()
  foot.write_u32_le(backward)
  foot.write_bytes(flags[:])
  let fb = foot.to_bytes()
  w.write_u32_le(@checksum.crc32(fb[:]))
  w.write_bytes(fb[:])
  w.write_bytes(b"\x59\x5A"[:])
  w.to_bytes()
}

///|
pub fn decode_xz(
  input : BytesView,
  memlimit : UInt64,
  ignore_check : Bool,
  concatenated? : Bool = false,
) -> Bytes raise @coder.CoderError {
  let r = @bit.Reader::new(input)
  let out = @bit.Writer::new()
  let mut done = false
  while done == false {
    out.write_bytes(decode_xz_stream(r, memlimit, ignore_check)[:])
    if concatenated == false {
      if r.remaining() != 0 {
        raise @coder.Data
      }
      done = true
    } else {
      skip_stream_padding(r)
      done = r.remaining() == 0
    }
  }
  out.to_bytes()
}

///|
fn decode_xz_stream(
  r : @bit.Reader,
  memlimit : UInt64,
  ignore_check : Bool,
) -> Bytes raise @coder.CoderError {
  let m0 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let m1 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let m2 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let m3 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let m4 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let m5 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  if m0 != b'\xFD' ||
    m1 != b'\x37' ||
    m2 != b'\x7A' ||
    m3 != b'\x58' ||
    m4 != b'\x5A' ||
    m5 != b'\x00' {
    raise @coder.Data
  }
  let f0 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  let f1 = r.read_u8() catch { @bit.Eof => raise @coder.Eof }
  if f0 != b'\x00' {
    raise @coder.Data
  }
  let flags = Bytes::from_array([f0, f1][:])
  let fcrc = r.read_u32_le() catch { @bit.Eof => raise @coder.Eof }
  if @checksum.crc32(flags[:]) != fcrc {
    raise @coder.Data
  }
  let check_id = f1.to_int()
  let check_n = check_field_size(check_id)
  let out = @bit.Writer::new()
  let recs : Array[BlockSizes] = []
  while true {
    if r.remaining() == 0 {
      raise @coder.Eof
    }
    // Block Header Size 0 is invalid, so 0x00 is the Index indicator.
    if r.rest()[0] == b'\x00' {
      break
    }
    let (plain, unpadded, _) = decode_one_block(
      r, memlimit, ignore_check, check_id, check_n,
    )
    recs.push({
      unpadded,
      uncompressed: plain.length().reinterpret_as_uint().to_uint64(),
    })
    out.write_bytes(plain[:])
  }
  parse_index_and_footer(r, flags, recs) |> ignore
  out.to_bytes()
}
