# 公共接口设计

## 问题

在 MoonBit 中给出一套小而稳定的 LZMA/XZ 接口，要求：

- 外部可观察行为与相关 `liblzma` / XZ 规格对齐
- API 本身是 MoonBit 习惯用法，不是 C `lzma_stream` 的逐行翻译
- 一次性编解码和增量流式都能表达
- 畸形输入、内存上限、不支持特性都有明确错误，不 panic

包分层见 [architecture.md](./architecture.md)。本文描述**根包与格式包的对外形状**。内部算法包没有稳定 API。

实现与本文不一致时，以源码与 `src/pkg.generated.mbti` 为准，并回头改本文。

---

## 设计原则

1. **根包够用**：`import "aurora0x27/lzma-mbt"` 应能完成 `.lzma` / LZMA2 / `.xz` 的常见编解码。
2. **状态不泄漏**：`Encoder` / `Decoder` 是抽象类型。外部不能读字典、概率表、range coder 寄存器。
3. **输入借用、输出拥有**：输入用 `BytesView`；函数返回的 `Bytes` 由调用方拥有。流式 `code` 写入调用方提供的输出缓冲。
4. **错误用 `raise`**：统一 `suberror LzmaError`（MoonBit 保留名 `Error`）。不要用整数码，不要用 `Result` 作为主通道。
5. **默认值要安全**：解码 `memlimit = None` 表示字典 **128 MiB**；编码默认 `.xz` + preset 6 + CRC64。
6. **流式切分无关**：合法输入可按任意 chunk 经 `write` 再 `finish`（或 `code(..., Run)` 缓冲后 `code(..., Finish)`）解码，结果与一次性 `decode` 相同。当前实现在 `Finish` 前整段缓冲，不是按字节推进的 LZMA 状态机。
7. **未实现即报错**：过滤器、check 类型、preset 若不支持，返回 `UnsupportedFeature`，禁止假装成功。

---

## 模块与导入

```text
import {
  "aurora0x27/lzma-mbt" @lzma,
}
```

常用路径：

```text
let compressed = @lzma.encode(plain[:])
let plain2 = @lzma.decode(compressed[:])
```

格式专用（可选）：

```text
import {
  "aurora0x27/lzma-mbt/lzma" @lzma1,
  "aurora0x27/lzma-mbt/lzma2" @lzma2,
  "aurora0x27/lzma-mbt/xz" @xz,
  "aurora0x27/lzma-mbt/checksum" @checksum,
}
```

根包用 `pub using` 再导出 checksum 的 `crc32` / `crc64`。`LzmaError`、`Format`、`EncodeOptions`、`DecodeOptions`、`Encoder`、`Decoder`、`encode`、`decode` 都在根包。

---

## 错误

```moonbit
/// 所有公开编解码路径抛出的错误。MoonBit 保留名 `Error` 不可用，因此类型名为 `LzmaError`。
/// 畸形压缩数据不得 panic；内部不变量破坏可另用 assert，且不得由外部输入触发。
pub suberror LzmaError {
  /// 头部、属性字节、过滤器 ID、距离/长度等不合法。
  InvalidInput(String)
  /// 流在合法终止前结束。
  UnexpectedEof
  /// 调用方给出的 lc/lp/pb、dict_size、preset、memlimit 等不合法。
  InvalidConfiguration(String)
  /// 规格允许但本版本未实现，或编译目标不支持。
  UnsupportedFeature(String)
  /// 解码所需内存超过 DecodeOptions.memlimit。
  MemoryLimit
  /// 码流在范围解码或校验上失败（损坏数据）。
  DataError
  /// 输出缓冲不足以完成当前 `code` 动作中必须写出的字节。
  /// 仅流式 API 使用；一次性 API 由库部分配输出。
  BufferTooSmall
  /// 容器魔数/Flags 与请求的 Format 不符。
  FormatError
} derive(Debug, Eq)
```

与 `liblzma` 的大致对应（行为对齐，不是数值对齐）：

| 本库 | `lzma_ret`（参考） |
| --- | --- |
| 成功路径的 `Status::Ok` / `StreamEnd` | `LZMA_OK` / `LZMA_STREAM_END` |
| `UnexpectedEof` | `LZMA_BUF_ERROR`（在输入耗尽且未结束时）等需按规格细分 |
| `DataError` | `LZMA_DATA_ERROR` |
| `FormatError` | `LZMA_FORMAT_ERROR` |
| `InvalidConfiguration` / `InvalidInput` | `LZMA_OPTIONS_ERROR` |
| `MemoryLimit` | `LZMA_MEMLIMIT_ERROR` |
| `UnsupportedFeature` | `LZMA_UNSUPPORTED_CHECK` 及未实现过滤器 |
| `BufferTooSmall` | `LZMA_BUF_ERROR`（输出侧） |

错误按**标签**匹配（`err is DataError`），不要把 `String` 载荷当稳定 API。

---

## 格式、校验、动作、状态

```moonbit
/// 压缩容器/滤镜格式。解码可用 Auto。
pub(all) enum Format {
  /// 根据魔数在 `.xz` 与 `.lzma`（LZMA_Alone）之间自动识别。
  /// 仅解码合法；编码必须指定具体格式。
  Auto
  /// LZMA1 raw / LZMA_Alone（`.lzma` 文件）。
  Lzma
  /// LZMA2 裸流（无 .xz 容器）。
  Lzma2
  /// `.xz` Stream。
  Xz
} derive(Debug, Eq)

/// 完整性校验。编码进容器；解码时必须验证（除非显式 `ignore_check`）。
pub(all) enum Check {
  None
  Crc32
  Crc64
  /// 枚举占位；编解码均抛 `UnsupportedFeature`。
  Sha256
} derive(Debug, Eq)

pub(all) enum Action {
  /// 追加输入到内部缓冲。本版本在 `Finish` 前不产生压缩/解压输出。
  Run
  /// 本版本不支持，`code` 抛 `InvalidConfiguration`。
  SyncFlush
  /// 本版本不支持，`code` 抛 `InvalidConfiguration`。
  FullFlush
  /// 结束输入，运行与一次性 API 相同的 `encode`/`decode`，再向 `output` 排空。
  Finish
} derive(Debug, Eq)

pub(all) enum Status {
  /// `Run` 已缓冲输入，尚无编解码输出。
  Ok
  /// `Finish` 完成，待写出字节已全部排空。
  StreamEnd
  /// 留给将来的增量状态机；当前 `Run` 返回 `Ok`，不会发出此状态。
  NeedInput
  /// 输出缓冲已满，调用方取走数据后再 `code` 或 `finish()`。
  NeedOutput
} derive(Debug, Eq)
```

`Action`：本版本只支持 `Run` 与 `Finish`。`SyncFlush` / `FullFlush` → `InvalidConfiguration`。

`Status`：`Finish` 之前的 `Run` 返回 `Ok`（输入被缓冲，尚无压缩/解压输出）。`NeedInput` 留给将来的增量状态机；当前实现在 `Finish` 前整段缓冲，因此不会发出 `NeedInput`。`Finish` 之后是 `NeedOutput` 或 `StreamEnd`。页脚后的多余字节、裸 LZMA2 尾部垃圾按 `DataError` 拒绝。

---

## 选项

```moonbit
/// 压缩档位。数值含义对齐 liblzma preset 0..=9。
/// `extreme` 对齐 `LZMA_PRESET_EXTREME`。
pub(all) struct Preset {
  level : Int        // 0..=9
  extreme : Bool
} derive(Debug, Eq)

pub fn Preset::default() -> Preset {
  { level: 6, extreme: false }
}

pub fn Preset::new(level : Int, extreme? : Bool = false) -> Preset raise LzmaError

/// LZMA1 属性。`EncodeOptions.props = None` 时整份由 preset 推导；`Some` 则整份覆盖。
pub(all) struct LzmaProps {
  lc : Int           // 0..=8
  lp : Int           // 0..=4，且 lc+lp <= 4
  pb : Int           // 0..=4
  dict_size : UInt   // 实现将校验上下限
} derive(Debug, Eq)

pub(all) struct EncodeOptions {
  format : Format
  preset : Preset
  check : Check
  /// 覆盖 preset 推导出的 LZMA 属性。None 表示完全由 preset 决定。
  props : LzmaProps?
  /// 容器外的额外过滤器（Delta / BCJ）。空表示不另做前后处理。
  /// `.xz` 容器内仍只写 LZMA2；链里不能再放 Lzma1/Lzma2。
  filters : Array[FilterSpec]
} derive(Debug, Eq)

pub fn EncodeOptions::default() -> EncodeOptions {
  {
    format: Format::Xz,
    preset: Preset::default(),
    check: Check::Crc64,
    props: None,
    filters: [],
  }
}

pub(all) struct DecodeOptions {
  format : Format
  /// 解码器字典/状态内存上限（字节）。None → 128 MiB。不限制明文长度。
  memlimit : UInt64?
  /// 是否解码连接的多 Stream（.xz concatenated）。对齐 LZMA_CONCATENATED。
  concatenated : Bool
  /// 跳过完整性校验。默认 false。仅用于调试或已由外层校验的场景。
  ignore_check : Bool
  /// 编解码完成后（或编码前）对明文做的额外过滤器，与容器内 LZMA2 无关。
  /// 解码时按相反顺序应用。不要把 Lzma1/Lzma2 放进这里。
  filters : Array[FilterSpec]
} derive(Debug, Eq)

pub fn DecodeOptions::default() -> DecodeOptions {
  {
    format: Format::Auto,
    memlimit: None,
    concatenated: false,
    ignore_check: false,
    filters: [],
  }
}
```

`FilterSpec` 定义在根包（`options.mbt`）。`filters` 包只提供 `delta_encode` / `delta_decode` / `bcj_x86` 原语。

```moonbit
pub(all) enum FilterSpec {
  Lzma1(LzmaProps)
  Lzma2(LzmaProps)
  Delta(distance~ : Int)
  BcjX86(start_offset~ : UInt)
}
```

`EncodeOptions::validate` / `DecodeOptions::validate` 在 `encode`/`decode`/`Encoder::new`/`Decoder::new`/`reset` 时执行：

- `Format::Auto` 不能用于 `encode` → `InvalidConfiguration`
- `lc + lp > 4` 或越界、`dict_size` 越界 → `InvalidConfiguration`
- `Preset.extreme`、`Check::Sha256`、`concatenated` → `UnsupportedFeature`
- 链里的 `Lzma1`/`Lzma2`、Delta `distance` 不在 `1..=256` → `InvalidConfiguration`
- `.xz` + `Check::None` 允许，且必须能被解码器识别
- 根包 `filters` 是**额外**前后处理（先 Delta/BCJ，再交给容器编解码）。`.xz` 容器内过滤器仍由 Block Header 描述，本版本只写 LZMA2
- `memlimit` 限制**解码字典/状态内存**（`None` → 128 MiB），不限制解压后明文长度。裸 LZMA2 流内没有字典字段，用 `min(memlimit, MAX_DICT_SIZE)` 作为字典上限。LZMA_Alone 头里过小的 dict 会先上取整到 4096 再与 `memlimit` 比较
- `Format::Auto` 只认 `.xz` 魔数与合法 LZMA_Alone 属性字节（`lc+lp <= 4`）。典型裸 LZMA2（控制字节 `0xE0`）→ `FormatError`，须显式 `Format::Lzma2`。显式 `Format::Lzma` 时，长度 ≥ 13 且属性字节不合法同样 → `FormatError`；更短的截断头由解码器报 `UnexpectedEof`。`Auto` 下：不完整 `.xz` 魔数前缀，或长度 `1..=12` 且首字节是合法 LZMA 属性 → `UnexpectedEof`。显式 `Format::Xz` 且输入短于 6 字节 → `UnexpectedEof`
- `EncodeOptions.check` 只作用于 `Format::Xz`；LZMA / LZMA2 裸流忽略该字段
- XZ VLI 必须是最短编码；Block Header 在过滤器属性之后的填充必须为 0
- `BcjX86.start_offset` 是 32 位指令指针初值，按无符号环绕（与 C `uint32_t` 一致）

---

## 一次性 API（根包）

这是默认入口。一次性 `encode`/`decode` 与流式 `Finish` 调用同一实现，避免两套编解码器。

```moonbit
/// 压缩整个输入。返回完整压缩流（含所选格式的头/尾）。
pub fn encode(
  input : BytesView,
  options? : EncodeOptions = EncodeOptions::default(),
) -> Bytes raise LzmaError

/// 解压整个输入。输入必须是完整流；截断 → UnexpectedEof。
pub fn decode(
  input : BytesView,
  options? : DecodeOptions = DecodeOptions::default(),
) -> Bytes raise LzmaError
```

语义：

| 项 | 约定 |
| --- | --- |
| 空输入 | `encode` 产生合法空流（该格式允许的最小包裹）；`decode` 对合法空流返回空 `Bytes` |
| 输出分配 | 库部分配完整明文。`memlimit` 管字典，不管输出长度 |
| 所有权 | 不修改 `input` 背后的 `Bytes` |
| 确定性 | 同一 `options` + 同一输入，编码器输出字节级确定（本实现不引入随机化/多线程重排） |

格式包提供更窄的函数（错误类型是内部 `CoderError`，根包再映射为 `LzmaError`）：

```moonbit
// aurora0x27/lzma-mbt/lzma
pub fn encode_alone(
  input : BytesView,
  lc : Int,
  lp : Int,
  pb : Int,
  dict_size : UInt,
) -> Bytes
pub fn decode_alone(input : BytesView, memlimit : UInt64) -> Bytes raise CoderError

// aurora0x27/lzma-mbt/lzma2
pub fn encode_lzma2(...) -> Bytes
pub fn decode_lzma2(input, memlimit, dict_size?) -> Bytes raise CoderError
pub fn decode_lzma2_consumed(input, memlimit, dict_size?) -> (Bytes, Int) raise CoderError
// 裸 `decode_lzma2` 在 `0x00` 结束标记之后若仍有字节 → Data
// `decode_lzma2_consumed` 返回消费的压缩字节数，供 `.xz` Block 后面的 Padding/Check/Index 继续解析

// aurora0x27/lzma-mbt/xz
pub fn encode_xz(..., check_id? : Int = 4) -> Bytes raise CoderError
pub fn decode_xz(input, memlimit, ignore_check : Bool) -> Bytes raise CoderError
// Stream Footer `YZ` 之后若仍有字节 → Data（含未声明的 concatenated 流）
```

根包 `encode`/`decode` 按 `options.format` 分派到这些函数。`check_id` 只接受 `0` / `1` / `4`。

---

## 流式 API（根包）

### 为什么不照搬 `lzma_code`

C API 用 `next_in`/`avail_in` 指针对，是因为 C 没有切片。MoonBit 有 `BytesView`。流式循环应显式返回**消耗了多少输入、写出了多少输出**，否则无法测试“输出缓冲耗尽”和“任意切分输入”。

### 类型

```moonbit
/// 增量编码器。`Finish` 前缓冲输入；`Finish` 时调用与一次性 API 相同的 `encode`。
pub type Encoder

/// 增量解码器。`Finish` 前缓冲输入；`Finish` 时调用与一次性 API 相同的 `decode`。
pub type Decoder

pub(all) struct CodeResult {
  /// 本次从 input 消费的字节数，0..=input.length()
  consumed : Int
  /// 本次写入 output 的字节数，0..=output 剩余容量
  produced : Int
  status : Status
} derive(Debug, Eq)
```

`Encoder` / `Decoder` 默认抽象：外部不可构造字面量，只能 `new`。

### 构造

```moonbit
pub fn Encoder::new(
  options? : EncodeOptions = EncodeOptions::default(),
) -> Encoder raise LzmaError

pub fn Decoder::new(
  options? : DecodeOptions = DecodeOptions::default(),
) -> Decoder raise LzmaError
```

构造失败（非法选项、无法分配字典）不得留下半初始化对象；要么返回可用实例，要么 `raise`。

### 主循环

```moonbit
/// 处理一轮输入/输出。
///
/// - `input`：尚未消费的输入视图。允许长度为 0。
/// - `output`：调用方预分配的 `OutputBuf`（`data` + `start` 游标）。
/// - `action`：本轮意图。`SyncFlush`/`FullFlush` 被拒绝；解码器不得因此改写已解码明文。
pub fn Encoder::code(
  self : Encoder,
  input : BytesView,
  output : OutputBuf,
  action : Action,
) -> CodeResult raise LzmaError

pub fn Decoder::code(
  self : Decoder,
  input : BytesView,
  output : OutputBuf,
  action : Action,
) -> CodeResult raise LzmaError
```

**已选定**：调用方预分配 `Array[Byte]` + `start` 写入游标。`OutputBuf::new(size=n)` 分配 n 个可写字节（全 0）。`remaining() == 0` 且缓冲长度为 0 时，若 `Finish` 尚未提交过输出，`code` 在消费本次 `input` 之前抛 `BufferTooSmall`（`total_in` 不增加），可用同一 `input` 换更大的缓冲重试。若缓冲长度大于 0 但已写满（`start == data.length()`），`Finish` 仍消费本次 `input` 并返回 `NeedOutput`。排空时可用空 `input` 的 `Run` 或 `Finish`。

```moonbit
pub(all) struct OutputBuf {
  data : Array[Byte]
  mut start : Int
}
```

包装方法：

```moonbit
/// 追加输入。不产生输出；压缩/解压发生在 `finish` 或 `code(..., Finish)`。
pub fn Encoder::write(self : Encoder, input : BytesView) -> Unit raise LzmaError
pub fn Encoder::finish(self : Encoder) -> Bytes raise LzmaError
pub fn Decoder::write(self : Decoder, input : BytesView) -> Unit raise LzmaError
pub fn Decoder::finish(self : Decoder) -> Bytes raise LzmaError
```

`write`/`finish` 与 `code` 共用同一 `encode`/`decode`，没有第二套编解码器。流式在 `Finish` 前缓冲全部输入。`write` 与 `code` 的 `input` 都会追加到内部缓冲，不要把同一段数据喂两次。

`code(..., Finish)` 若因输出槽不足返回 `NeedOutput`，可继续 `code` 排空，或调用 `finish()` 取走剩余未写出字节。已经 `StreamEnd`（或 `finish()` 已返回完整结果）后再 `finish()` → `InvalidConfiguration`。

`Finish` 已提交、输出尚未排空（`NeedOutput`）：

- 非空 `input` → `InvalidConfiguration`
- 可继续 `code`（空 `input`）排空，或 `finish()` 取剩余字节

`StreamEnd` 之后：

- 再 `code` → `InvalidConfiguration`
- 再 `finish()` → `InvalidConfiguration`
- 允许 `reset`

### 计数与生命周期

```moonbit
pub fn Encoder::total_in(self : Encoder) -> UInt64
pub fn Encoder::total_out(self : Encoder) -> UInt64
pub fn Decoder::total_in(self : Decoder) -> UInt64
pub fn Decoder::total_out(self : Decoder) -> UInt64

/// 回到 new() 之后的状态，保留 options。用于复用分配。
pub fn Encoder::reset(self : Encoder) -> Unit raise LzmaError
pub fn Decoder::reset(self : Decoder) -> Unit raise LzmaError
```

MoonBit 无析构器义务对应 `lzma_end`：对象不可达后由运行时回收。`reset` 是显式复用接口，不是释放接口。

### 流式不变量（测试必须覆盖）

当前实现在 `Finish` 前缓冲全部输入，`code(..., Run)` 只追加缓冲并返回 `Ok`，不解码。对任意合法输入 `bytes` 和任意切分 `chunks`（拼接等于 `bytes`）：

```text
decode(bytes) == Decoder::write(chunks...) ; Decoder::finish()
```

`code(..., Finish)` 与 `write` + `finish` 结果相同。不要把 `Run` 当成按块推进的 LZMA 状态机。

还要覆盖：

- 每次 `code` 只提供 1 字节输入
- 输出槽容量为 1
- `Finish` 时输出槽已满但长度 > 0 → `NeedOutput`，输入已被消费
- 空 `OutputBuf` 上的 `Finish` → `BufferTooSmall`，且不增加 `total_in`
- `NeedOutput` 之后用空 `input` 的 `Run` 排空
- `Finish` 时仍有未写完的尾部
- 截断输入 → `UnexpectedEof`，且不得产出与完整流不同的“成功明文”
- 重复 `Finish`
- `memlimit` 小于字典需求 → `MemoryLimit`，发生在读头之后、扩字典之前

---

## LZMA 属性编解码（根包）

`.lzma` 文件头含 1 字节 properties + 4 字节 dict_size + 8 字节 uncompressed size。这些是公开规格，应有纯函数：

```moonbit
pub fn pack_props(lc : Int, lp : Int, pb : Int) -> Byte raise LzmaError
pub fn unpack_props(props : Byte) -> (Int, Int, Int) raise LzmaError

/// 0xFFFF_FFFF_FFFF_FFFF 表示未知大小，对齐 LZMA_Alone。
pub const UNKNOWN_SIZE : UInt64 = 0xFFFF_FFFF_FFFF_FFFF
```

---

## Checksum 包

```moonbit
pub fn crc32(data : BytesView, init? : UInt = 0) -> UInt
pub fn crc64(data : BytesView, init? : UInt64 = 0) -> UInt64
```

多项式、初值、反射、最终异或必须与 `liblzma` / ISO 实现差分一致。`init` 用于分块累加：

```text
crc32(a ++ b) == crc32(b, init=crc32(a))
```

SHA-256 列在 `Check` 里但对编码/解码都返回 `UnsupportedFeature`。

---

## 所有权与可变语义

| 对象 | 所有权 | 可变 |
| --- | --- | --- |
| `encode`/`decode` 的 `input` | 调用方，只读视图 | 库不得写入 |
| 返回的 `Bytes` | 调用方 | 调用方可任意使用 |
| `Encoder`/`Decoder` | 调用方持有抽象值 | `code`/`reset` 可变内部状态 |
| `OutputBuf.data` | 调用方 | 仅 `[start:]` 可被写入 |
| 字典内存 | 编码器/解码器实例 | 随 `reset` 可复用，不泄漏到 API |

禁止在公开 API 出现：

- 原始指针
- 需要成对 `free` 的句柄
- 全局可变编码器状态
- 隐式线程局部缓冲

---

## 推荐用法

### 一次性

```moonbit
test {
  let src = b"hello lzma"
  let out = encode(src[:], options={
    ..EncodeOptions::default(),
    format: Format::Xz,
  })
  let back = decode(out[:])
  assert_eq(back, src)
}
```

### 流式解码（任意切分）

当前实现在 `Finish` 前缓冲全部输入，因此按块喂入时用 `write`，最后 `finish`：

```moonbit
fn decompress_chunks(chunks : Array[Bytes]) -> Bytes raise LzmaError {
  let dec = Decoder::new()
  for c in chunks {
    dec.write(c[:])
  }
  dec.finish()
}
```

需要 `NeedOutput` 时再用 `Decoder::code` 与调用方 `OutputBuf`。`Run` 在 `Finish` 前返回 `Ok`，不产生明文。

根包黑盒测试覆盖上述循环（`src/api_test.mbt`）。

---

## 明确不在 v1 公开的内容

| 项目 | 原因 |
| --- | --- |
| `lzma_easy_encoder` 等 C 函数名 | M9 compat 包再考虑 |
| 自定义 allocator | MoonBit 运行时管理内存；只需 `memlimit` |
| 多线程编码 | 确定性与后端并发未就绪 |
| MicroLZMA | 非核心路径 |
| `lzma_index_*` 全套索引编辑 API | 先做解码所需的最小 Index 校验 |
| 稳定的内部 range coder API | 外部不应依赖 |

---

## 兼容性矩阵

完成状态以 [compatibility.md](./compatibility.md) 为准，必须有测试证据。

`Format::Auto` 只区分 `.xz` 魔数与 LZMA_Alone 头；裸 LZMA2 必须显式 `Format::Lzma2`。

---

## 已冻结的决策

1. 编码默认 `Format::Xz` + preset 6 + CRC64。
2. `memlimit = None` → 128 MiB 字典上限（`DEFAULT_MEMLIMIT`）。
3. `OutputBuf` 为调用方 `Array[Byte]` + `start`；`OutputBuf::new(size=n)` 分配 n 个可写槽。
4. 一次性 LZMA_Alone 写真实未压缩大小。
5. 错误按标签匹配；`String` 载荷不是稳定 API。
6. 单 Stream `.xz` 在 Footer 之后不得有剩余字节；裸 LZMA2 在结束标记之后同样不得有剩余字节。
7. `.xz` 解码器接受 0..N 个 Block；Index 记录必须与各 Block 的 Unpadded Size / Uncompressed Size 逐条一致。编码器当前仍只写 1 个 Block。Block Header 里的 Compressed Size 与 Uncompressed Size（编码器两者都写）必须与 LZMA2 消费字节数 / 明文长度一致。VLI 禁止非最短编码。

---

## 建议的实现顺序（相对接口）

已按该顺序落地。流式入口与一次性 `encode`/`decode` 是同一实现，不要再做第二套编解码器。真正按字节推进的增量状态机是后续任务。
