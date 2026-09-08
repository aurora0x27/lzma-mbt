///|
/// Caller-owned output slot. `code` writes at `data[start]` and advances `start`.
/// `size` is the number of writable bytes (not a hint).
pub(all) struct OutputBuf {
  data : Array[Byte]
  mut start : Int
}

///|
pub fn OutputBuf::new(size? : Int = 0) -> OutputBuf {
  let n = if size < 0 { 0 } else { size }
  { data: Array::make(n, b'\x00'), start: 0, }
}

///|
/// Writable bytes left (`data.length() - start`). Out-of-range `start` is 0.
pub fn OutputBuf::remaining(self : OutputBuf) -> Int {
  if self.start < 0 || self.start > self.data.length() {
    0
  } else {
    self.data.length() - self.start
  }
}

///|
/// Bytes already written, `data[0:start]`.
pub fn OutputBuf::written(self : OutputBuf) -> Bytes {
  if self.start <= 0 {
    return b""
  }
  let n = if self.start > self.data.length() {
    self.data.length()
  } else {
    self.start
  }
  Bytes::from_array(self.data[:n])
}

///|
fn check_output(output : OutputBuf) -> Unit raise LzmaError {
  if output.start < 0 || output.start > output.data.length() {
    raise BufferTooSmall
  }
}

///|
pub(all) struct CodeResult {
  consumed : Int
  produced : Int
  status : Status
} derive(Debug, Eq)

///|
priv struct Session {
  input : Array[Byte]
  pending : Array[Byte]
  stream_decoder : @lzma2.StreamDecoder?
  xz_decoder : @xz.StreamDecoder?
  mut pending_pos : Int
  mut finished : Bool
  mut complete : Bool
  mut total_in : UInt64
  mut total_out : UInt64
}

///|
struct Encoder {
  options : EncodeOptions
  session : Session
}

///|
struct Decoder {
  options : DecodeOptions
  session : Session
}

///|
fn Session::fresh(
  stream_decoder? : @lzma2.StreamDecoder? = None,
  xz_decoder? : @xz.StreamDecoder? = None,
) -> Session {
  {
    input: [],
    pending: [],
    stream_decoder,
    xz_decoder,
    pending_pos: 0,
    finished: false,
    complete: false,
    total_in: 0UL,
    total_out: 0UL,
  }
}

///|
fn Session::clear(self : Session) -> Unit {
  self.input.clear()
  self.pending.clear()
  self.pending_pos = 0
  self.finished = false
  self.complete = false
  self.total_in = 0UL
  self.total_out = 0UL
  match self.stream_decoder {
    None => ()
    Some(dec) => dec.reset()
  }
  match self.xz_decoder {
    None => ()
    Some(dec) => dec.reset()
  }
}

///|
fn add_count(total : UInt64, n : Int) -> UInt64 {
  total + n.reinterpret_as_uint().to_uint64()
}

///|
fn fill_pending(pending : Array[Byte], src : Bytes) -> Unit {
  pending.clear()
  for b in src[:] {
    pending.push(b)
  }
}

///|
fn append_pending(pending : Array[Byte], src : Bytes) -> Unit {
  for b in src[:] {
    pending.push(b)
  }
}

///|
fn drain_pending(
  pending : Array[Byte],
  pending_pos : Int,
  output : OutputBuf,
) -> (Int, Int) {
  let mut pos = pending_pos
  let mut produced = 0
  while pos < pending.length() && output.start < output.data.length() {
    output.data[output.start] = pending[pos]
    output.start = output.start + 1
    pos = pos + 1
    produced = produced + 1
  }
  (produced, pos)
}

///|
fn pending_status(
  done : Bool,
  pending_pos : Int,
  pending_len : Int,
  output : OutputBuf,
) -> Status raise LzmaError {
  if done == false {
    return NeedInput
  }
  if pending_pos >= pending_len {
    return StreamEnd
  }
  if output.remaining() == 0 {
    if output.data.length() == 0 {
      raise BufferTooSmall
    }
    return NeedOutput
  }
  StreamEnd
}

///|
fn pending_rest(pending : Array[Byte], pos : Int) -> Bytes {
  if pos < 0 || pos >= pending.length() {
    b""
  } else {
    Bytes::from_array(pending[pos:])
  }
}

///|
fn reject_unsupported_action(action : Action) -> Unit raise LzmaError {
  match action {
    SyncFlush | FullFlush =>
      raise InvalidConfiguration("SyncFlush/FullFlush are not supported")
    Run | Finish => ()
  }
}

///|
fn reject_input_after_finish(
  finished : Bool,
  input : BytesView,
) -> Unit raise LzmaError {
  if finished && input.length() > 0 {
    raise InvalidConfiguration("cannot add input after Finish")
  }
}

///|
fn Session::code(
  self : Session,
  input : BytesView,
  output : OutputBuf,
  action : Action,
  produce : (Bytes) -> Bytes raise LzmaError,
  kind : String,
  run_can_finish? : Bool = false,
) -> CodeResult raise LzmaError {
  check_output(output)
  reject_unsupported_action(action)
  if self.finished && self.pending_pos >= self.pending.length() {
    raise InvalidConfiguration("\{kind} already finished")
  }
  reject_input_after_finish(self.finished, input)
  // Empty output cannot receive the Finish payload. Fail before consuming
  // this call's input so the caller can retry with the same bytes.
  if action is Finish && self.complete == false && output.data.length() == 0 {
    raise BufferTooSmall
  }
  for b in input {
    self.input.push(b)
  }
  let consumed = input.length()
  self.total_in = add_count(self.total_in, consumed)
  match self.stream_decoder {
    Some(decoder) => {
      let (produced_bytes, done0) = decoder.feed(input) catch {
        @coder.Eof => raise UnexpectedEof
        @coder.Data => raise DataError
        @coder.Limit => raise MemoryLimit
        @coder.Unsupported => raise UnsupportedFeature("lzma2 feature")
      }
      let mut done = done0
      append_pending(self.pending, produced_bytes)
      if action is Finish && done == false {
        let _ = decoder.finish() catch {
          @coder.Eof => raise UnexpectedEof
          @coder.Data => raise DataError
          @coder.Limit => raise MemoryLimit
          @coder.Unsupported => raise UnsupportedFeature("lzma2 feature")
        }
        done = true
      }
      self.complete = done
      self.finished = done
      let (produced, new_pos) = drain_pending(
        self.pending,
        self.pending_pos,
        output,
      )
      self.pending_pos = new_pos
      self.total_out = add_count(self.total_out, produced)
      let status = pending_status(
        self.complete,
        self.pending_pos,
        self.pending.length(),
        output,
      )
      return { consumed, produced, status, }
    }
    None => ()
  }
  match self.xz_decoder {
    Some(decoder) => {
      let (produced_bytes, done0) = decoder.feed(input) catch {
        @coder.Eof => raise UnexpectedEof
        @coder.Data => raise DataError
        @coder.Limit => raise MemoryLimit
        @coder.Unsupported => raise UnsupportedFeature("xz feature")
      }
      let mut done = done0
      append_pending(self.pending, produced_bytes)
      if action is Finish && done == false {
        let _ = decoder.finish() catch {
          @coder.Eof => raise UnexpectedEof
          @coder.Data => raise DataError
          @coder.Limit => raise MemoryLimit
          @coder.Unsupported => raise UnsupportedFeature("xz feature")
        }
        done = true
      }
      self.complete = done
      self.finished = done
      let (produced, new_pos) = drain_pending(
        self.pending,
        self.pending_pos,
        output,
      )
      self.pending_pos = new_pos
      self.total_out = add_count(self.total_out, produced)
      let status = pending_status(
        self.complete,
        self.pending_pos,
        self.pending.length(),
        output,
      )
      return { consumed, produced, status, }
    }
    None => ()
  }
  if action is Run &&
    run_can_finish &&
    self.complete == false &&
    self.input.length() > 0 {
    let src = Bytes::from_array(self.input[:])
    let mut run_complete = true
    let out = produce(src) catch {
      UnexpectedEof => {
        run_complete = false
        b""
      }
      err => raise err
    }
    if run_complete {
      fill_pending(self.pending, out)
      self.pending_pos = 0
      self.complete = true
      self.finished = true
    }
  }
  if action is Finish && self.complete == false {
    let src = Bytes::from_array(self.input[:])
    fill_pending(self.pending, produce(src))
    self.pending_pos = 0
    self.complete = true
    self.finished = true
  }
  let (produced, new_pos) = drain_pending(
    self.pending,
    self.pending_pos,
    output,
  )
  self.pending_pos = new_pos
  self.total_out = add_count(self.total_out, produced)
  let status = pending_status(
    self.complete,
    self.pending_pos,
    self.pending.length(),
    output,
  )
  { consumed, produced, status, }
}

///|
fn Session::write(
  self : Session,
  input : BytesView,
  kind : String,
) -> Unit raise LzmaError {
  if self.finished {
    raise InvalidConfiguration("\{kind} already finished")
  }
  for b in input {
    self.input.push(b)
  }
  self.total_in = add_count(self.total_in, input.length())
}

///|
fn Session::finish_now(
  self : Session,
  produce : (Bytes) -> Bytes raise LzmaError,
  kind : String,
) -> Bytes raise LzmaError {
  if self.complete {
    if self.pending_pos >= self.pending.length() {
      raise InvalidConfiguration("\{kind} already finished")
    }
    let rest = pending_rest(self.pending, self.pending_pos)
    self.pending_pos = self.pending.length()
    self.finished = true
    self.total_out = add_count(self.total_out, rest.length())
    return rest
  }
  let src = Bytes::from_array(self.input[:])
  let out = produce(src)
  self.finished = true
  self.complete = true
  self.total_out = out.length().reinterpret_as_uint().to_uint64()
  out
}

///|
pub fn Encoder::new(
  options? : EncodeOptions = EncodeOptions::default(),
) -> Encoder raise LzmaError {
  options.validate()
  { options, session: Session::fresh(), }
}

///|
pub fn Decoder::new(
  options? : DecodeOptions = DecodeOptions::default(),
) -> Decoder raise LzmaError {
  options.validate()
  let stream_decoder = match options.format {
    Lzma2 => {
      let limit = effective_memlimit(options.memlimit)
      Some(
        @lzma2.StreamDecoder::new(
          limit,
          dict_size=dict_cap_from_memlimit(limit),
        ) catch {
          @coder.Eof => raise UnexpectedEof
          @coder.Data => raise DataError
          @coder.Limit => raise MemoryLimit
          @coder.Unsupported => raise UnsupportedFeature("lzma2 feature")
        },
      )
    }
    Auto | Lzma | Xz => None
  }
  let xz_decoder : @xz.StreamDecoder? = if options.format == Format::Xz &&
    options.concatenated == false &&
    options.filters.length() == 0 {
    Some(
      @xz.StreamDecoder::new(
        effective_memlimit(options.memlimit),
        options.ignore_check,
      ),
    )
  } else {
    None
  }
  { options, session: Session::fresh(stream_decoder~, xz_decoder~), }
}

///|
pub fn Encoder::total_in(self : Encoder) -> UInt64 {
  self.session.total_in
}

///|
pub fn Encoder::total_out(self : Encoder) -> UInt64 {
  self.session.total_out
}

///|
pub fn Decoder::total_in(self : Decoder) -> UInt64 {
  self.session.total_in
}

///|
pub fn Decoder::total_out(self : Decoder) -> UInt64 {
  self.session.total_out
}

///|
pub fn Encoder::reset(self : Encoder) -> Unit raise LzmaError {
  self.options.validate()
  self.session.clear()
}

///|
pub fn Decoder::reset(self : Decoder) -> Unit raise LzmaError {
  self.options.validate()
  self.session.clear()
}

///|
pub fn Encoder::code(
  self : Encoder,
  input : BytesView,
  output : OutputBuf,
  action : Action,
) -> CodeResult raise LzmaError {
  let options = self.options
  self.session.code(
    input,
    output,
    action,
    (src : Bytes) => encode(src[:], options~),
    "encoder",
  )
}

///|
pub fn Decoder::code(
  self : Decoder,
  input : BytesView,
  output : OutputBuf,
  action : Action,
) -> CodeResult raise LzmaError {
  let options = self.options
  self.session.code(
    input,
    output,
    action,
    (src : Bytes) => decode(src[:], options~),
    "decoder",
    run_can_finish=true,
  )
}

///|
pub fn Encoder::write(
  self : Encoder,
  input : BytesView,
) -> Unit raise LzmaError {
  self.session.write(input, "encoder")
}

///|
pub fn Encoder::finish(self : Encoder) -> Bytes raise LzmaError {
  let options = self.options
  self.session.finish_now((src : Bytes) => encode(src[:], options~), "encoder")
}

///|
pub fn Decoder::write(
  self : Decoder,
  input : BytesView,
) -> Unit raise LzmaError {
  self.session.write(input, "decoder")
}

///|
pub fn Decoder::finish(self : Decoder) -> Bytes raise LzmaError {
  let options = self.options
  self.session.finish_now((src : Bytes) => decode(src[:], options~), "decoder")
}
