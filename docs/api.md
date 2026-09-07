# 公共接口设计

## 问题

在 MoonBit 中给出一套小而稳定的 LZMA/XZ 接口，要求：

- 外部可观察行为与相关 `liblzma` / XZ 规格对齐
- API 本身是 MoonBit 习惯用法，不是 C `lzma_stream` 的逐行翻译
- 一次性编解码和增量流式都能表达
- 畸形输入、内存上限、不支持特性都有明确错误，不 panic

包分层见 [architecture.md](./architecture.md)。本文冻结**根包与格式包的对外形状**。内部算法包没有稳定 API。

本文中的代码是设计草案，不是已实现源码。实现时若必须改签名，先更新本文并写明原因。

---

## 设计原则

1. **根包够用**：`import "aurora0x27/lzma-mbt"` 应能完成 `.lzma` / LZMA2 / `.xz` 的常见编解码。
2. **状态不泄漏**：`Encoder` / `Decoder` 是抽象类型。外部不能读字典、概率表、range coder 寄存器。
3. **输入借用、输出拥有**：输入用 `BytesView`；函数返回的 `Bytes` 由调用方拥有。流式 `code` 写入调用方提供的输出缓冲。
4. **错误用 `raise`**：统一 `suberror Error`。不要用整数码，不要用 `Result` 作为主通道。
5. **默认值要安全**：解码默认施加内存上限意识；编码默认等价 `liblzma` preset 6 + CRC64（`.xz`）或 LZMA Alone 的惯用参数（见下方开放问题）。
6. **流式切分无关**：合法输入按任意 chunk 喂给 `Decoder::code`，结果与一次性解码相同。
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

根包用 `pub using` 再导出 `Error`、`Format`、`EncodeOptions`、`DecodeOptions`、`Encoder`、`Decoder`、`encode`、`decode`。用户不必同时 import 四个包。

---

## 错误

```moonbit
/// 所有公开编解码路径抛出的错误。
/// 畸形压缩数据不得 panic；内部不变量破坏可另用 assert，且不得由外部输入触发。
pub suberror Error {
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
} derive(Show, Eq)
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

`Show` 必须稳定、可测，供 `inspect` 快照。不要把内部指针或未初始化状态打进消息。

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
} derive(Show, Eq)

/// 完整性校验。编码进容器；解码时必须验证（除非显式 IgnoreCheck）。
pub(all) enum Check {
  None
  Crc32
  Crc64
  Sha256
} derive(Show, Eq)

pub(all) enum Action {
  /// 消耗输入、产生输出，不强制对齐块边界。
  Run
  /// 同步刷新：已消耗输入对应的压缩数据必须全部可输出。
  /// 不是所有编码器都支持。
  SyncFlush
  /// 结束当前 XZ Block（若适用）。
  FullFlush
  /// 结束整个流。之后只能再 `code` 直到 `StreamEnd`。
  Finish
} derive(Show, Eq)

pub(all) enum Status {
  Ok
  StreamEnd
  /// 还需要更多输入才能继续（解码器常见）。
  NeedInput
  /// 输出缓冲已满，调用方取走数据后再调用。
  NeedOutput
} derive(Show, Eq)
```

`Action` 的合法组合按编码器种类限制，与 `liblzma` 相同：不支持的动作 → `InvalidConfiguration`，而不是忽略。

---

## 选项

```moonbit
/// 压缩档位。数值含义对齐 liblzma preset 0..=9。
/// `extreme` 对齐 `LZMA_PRESET_EXTREME`。
pub(all) struct Preset {
  level : Int        // 0..=9
  extreme : Bool
} derive(Show, Eq)

pub fn Preset::default() -> Preset {
  { level: 6, extreme: false }
}

pub fn Preset::new(level : Int, extreme~ : Bool = false) -> Preset raise Error

/// LZMA1 属性。未填写的字段由 preset 推导。
pub(all) struct LzmaProps {
  lc : Int           // 0..=8
  lp : Int           // 0..=4，且 lc+lp <= 4
  pb : Int           // 0..=4
  dict_size : UInt   // 实现将校验上下限
} derive(Show, Eq)

pub(all) struct EncodeOptions {
  format : Format
  preset : Preset
  check : Check
  /// 覆盖 preset 推导出的 LZMA 属性。None 表示完全由 preset 决定。
  props : LzmaProps?
  /// 过滤器链。空表示“该格式的默认链”（.xz 默认为 LZMA2）。
  /// 非空时 format 必须能承载该链。
  filters : Array[FilterSpec]
} derive(Show, Eq)

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
  /// 解码器允许使用的内存上限（字节）。None 表示实现定义的安全默认上限，
  /// 不得解释为“无限”。需要接近无限时显式传入一个很大的 UInt64。
  memlimit : UInt64?
  /// 是否解码连接的多 Stream（.xz concatenated）。对齐 LZMA_CONCATENATED。
  concatenated : Bool
  /// 跳过完整性校验。默认 false。仅用于调试或已由外层校验的场景。
  ignore_check : Bool
} derive(Show, Eq)

pub fn DecodeOptions::default() -> DecodeOptions {
  {
    format: Format::Auto,
    memlimit: None,
    concatenated: false,
    ignore_check: false,
  }
}
```

`FilterSpec` 在 `filters` 包定义，根包再导出。第一版至少要能表示：

```moonbit
pub(all) enum FilterSpec {
  Lzma1(LzmaProps)
  Lzma2(LzmaProps)
  Delta(distance~ : Int)
  BcjX86(start_offset~ : UInt)
  // 其余 BCJ 变体按 M7 追加；未实现的构造函数不要先放出来
} derive(Show, Eq)
```

校验规则（编码前、解码读头后都要执行）：

- `Format::Auto` 不能用于 `encode` → `InvalidConfiguration`
- `lc + lp > 4` 或越界 → `InvalidConfiguration`
- `dict_size` 超过实现上限或为 0 → `InvalidConfiguration`
- `.xz` + `Check::None` 允许，但必须能被解码器识别
- 过滤器链长度、顺序不合法 → `InvalidInput` 或 `InvalidConfiguration`（编码侧后者，解码侧前者）

---

## 一次性 API（根包）

这是默认入口。内部仍走流式状态机，保证与 chunked 解码一致。

```moonbit
/// 压缩整个输入。返回完整压缩流（含所选格式的头/尾）。
pub fn encode(
  input : BytesView,
  options~ : EncodeOptions = EncodeOptions::default(),
) -> Bytes raise Error

/// 解压整个输入。输入必须是完整流；截断 → UnexpectedEof。
pub fn decode(
  input : BytesView,
  options~ : DecodeOptions = DecodeOptions::default(),
) -> Bytes raise Error
```

语义：

| 项 | 约定 |
| --- | --- |
| 空输入 | `encode` 产生合法空流（该格式允许的最小包裹）；`decode` 对合法空流返回空 `Bytes` |
| 输出分配 | 库部分配；失败用 `MemoryLimit` 或实现定义的增长上限，不能无限扩张（防 zip bomb） |
| 所有权 | 不修改 `input` 背后的 `Bytes` |
| 确定性 | 同一 `options` + 同一输入，编码器输出字节级确定（本实现不引入随机化/多线程重排） |

格式包可提供更窄的函数，避免误用 Auto：

```moonbit
// aurora0x27/lzma-mbt/lzma
pub fn encode_alone(input : BytesView, props~ : LzmaProps = ...) -> Bytes raise Error
pub fn decode_alone(input : BytesView, memlimit~ : UInt64?) -> Bytes raise Error

// aurora0x27/lzma-mbt/xz
pub fn encode_stream(input : BytesView, options~ : EncodeOptions) -> Bytes raise Error
pub fn decode_stream(input : BytesView, options~ : DecodeOptions) -> Bytes raise Error
```

根包 `encode`/`decode` 按 `options.format` 分派到这些函数。

---

## 流式 API（根包）

### 为什么不照搬 `lzma_code`

C API 用 `next_in`/`avail_in` 指针对，是因为 C 没有切片。MoonBit 有 `BytesView`。流式循环应显式返回**消耗了多少输入、写出了多少输出**，否则无法测试“输出缓冲耗尽”和“任意切分输入”。

### 类型

```moonbit
/// 增量编码器。拥有字典、概率状态、未写出的压缩字节。
pub type Encoder

/// 增量解码器。
pub type Decoder

pub(all) struct CodeResult {
  /// 本次从 input 消费的字节数，0..=input.length()
  consumed : Int
  /// 本次写入 output 的字节数，0..=output 剩余容量
  produced : Int
  status : Status
} derive(Show, Eq)
```

`Encoder` / `Decoder` 默认抽象：外部不可构造字面量，只能 `new`。

### 构造

```moonbit
pub fn Encoder::new(
  options~ : EncodeOptions = EncodeOptions::default(),
) -> Encoder raise Error

pub fn Decoder::new(
  options~ : DecodeOptions = DecodeOptions::default(),
) -> Decoder raise Error
```

构造失败（非法选项、无法分配字典）不得留下半初始化对象；要么返回可用实例，要么 `raise`。

### 主循环

```moonbit
/// 处理一轮输入/输出。
///
/// - `input`：尚未消费的输入视图。允许长度为 0。
/// - `output`：可写缓冲。实现必须通过明确的输出槽写入；
///   第一版使用 `Array[Byte]` 的追加或预分配缓冲（见下方输出槽）。
/// - `action`：本轮意图。解码器对 SyncFlush/FullFlush 的处理按规格拒绝或忽略，
///   不得改变已解码明文。
pub fn Encoder::code(
  self : Encoder,
  input : BytesView,
  output : OutputBuf,
  action : Action,
) -> CodeResult raise Error

pub fn Decoder::code(
  self : Decoder,
  input : BytesView,
  output : OutputBuf,
  action : Action,
) -> CodeResult raise Error
```

`OutputBuf` 选择（实现时二选一，选定后写进本文）：

**推荐**：调用方预分配 `FixedArray[Byte]` + 写入区间，避免隐藏增长。

```moonbit
pub(all) struct OutputBuf {
  data : Array[Byte]
  /// 已填充长度。code 从 data[start:] 写入，并增加 start。
  start : Int
}
```

为降低第一版摩擦力，允许提供包装方法：

```moonbit
/// 将当前可产生的输出追加到 Bytes，直到 NeedInput 或 StreamEnd。
/// 仍必须能用 `code` 表达输出缓冲耗尽。
pub fn Encoder::write(self : Encoder, input : BytesView) -> Bytes raise Error
pub fn Encoder::finish(self : Encoder) -> Bytes raise Error
pub fn Decoder::write(self : Decoder, input : BytesView) -> Bytes raise Error
pub fn Decoder::finish(self : Decoder) -> Bytes raise Error
```

`write`/`finish` 是 `code` 的派生，不能有第二套状态机。

### 计数与生命周期

```moonbit
pub fn Encoder::total_in(self : Encoder) -> UInt64
pub fn Encoder::total_out(self : Encoder) -> UInt64
pub fn Decoder::total_in(self : Decoder) -> UInt64
pub fn Decoder::total_out(self : Decoder) -> UInt64

/// 回到 new() 之后的状态，保留 options。用于复用分配。
pub fn Encoder::reset(self : Encoder) -> Unit raise Error
pub fn Decoder::reset(self : Decoder) -> Unit raise Error
```

MoonBit 无析构器义务对应 `lzma_end`：对象不可达后由运行时回收。`reset` 是显式复用接口，不是释放接口。

`StreamEnd` 之后：

- 再 `code(..., Run)` → `InvalidConfiguration`
- 允许 `reset`
- `Finish` 后必须继续 `code` 直到 `StreamEnd`，以便写出尾部（Index、Footer、range coder 冲刷）

### 流式不变量（测试必须覆盖）

对任意合法输入 `bytes` 和任意切分 `chunks`（`chunks` 拼接等于 `bytes`）：

```text
decode(bytes) == fold(Decoder::code, chunks)
```

还要覆盖：

- 每次 `code` 只提供 1 字节输入
- 输出槽容量为 1
- `Finish` 时仍有未写完的尾部
- 截断输入 → `UnexpectedEof`，且不得产出与完整流不同的“成功明文”
- 重复 `Finish`
- `memlimit` 小于字典需求 → `MemoryLimit`，发生在读头之后、扩字典之前

---

## LZMA 属性编解码（`lzma` 包）

`.lzma` 文件头含 1 字节 properties + 4 字节 dict_size + 8 字节 uncompressed size。这些是公开规格，应有纯函数：

```moonbit
pub fn pack_props(lc : Int, lp : Int, pb : Int) -> Byte raise Error
pub fn unpack_props(props : Byte) -> (lc : Int, lp : Int, pb : Int) raise Error

/// 0xFFFF_FFFF_FFFF_FFFF 表示未知大小，对齐 LZMA_Alone。
pub let UNKNOWN_SIZE : UInt64 = 0xFFFF_FFFF_FFFF_FFFF
```

根包可以再导出 `pack_props` / `unpack_props`，因为用户写 raw LZMA 时需要。

---

## Checksum 包

```moonbit
pub fn crc32(data : BytesView, init~ : UInt = 0) -> UInt
pub fn crc64(data : BytesView, init~ : UInt64 = 0) -> UInt64
```

多项式、初值、反射、最终异或必须与 `liblzma` / ISO 实现差分一致。`init` 用于分块累加：

```text
crc32(a ++ b) == crc32(b, init=crc32(a))
```

SHA-256 在 M6 需要时再公开，未实现前对 `Check::Sha256` 编码返回 `UnsupportedFeature`。

---

## 所有权与可变语义（必须写进实现注释）

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

```moonbit
fn decompress_chunks(chunks : Array[BytesView]) -> Bytes raise Error {
  let dec = Decoder::new()
  let buf = Array::new(capacity=4096)
  let mut i = 0
  while true {
    let input = if i < chunks.length() { chunks[i] } else { b""[:] }
    let action = if i >= chunks.length() { Action::Finish } else { Action::Run }
    let r = dec.code(input, output_from(buf), action)
    i = i + r.consumed 的切分逻辑 // 实现时按 BytesView 推进，此处仅示意
    match r.status {
      StreamEnd => break
      NeedInput | Ok | NeedOutput => continue
    }
  }
  bytes_from(buf)
}
```

实现落地后，用真实可编译示例替换这段示意，并放进根包黑盒测试。

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

## 兼容性矩阵（接口承诺，不是完成状态）

下表是**接口层打算覆盖的范围**。实现完成前全部为 no。更新完成状态时必须有测试证据，见 `AGENTS.md` 第 26 节。

| 功能 | 一次性解码 | 一次性编码 | 流式 | 差分测试 |
| --- | ---: | ---: | ---: | ---: |
| LZMA1 / `.lzma` | 计划 | 计划 | 计划 | 计划 |
| LZMA2 裸流 | 计划 | 计划 | 计划 | 计划 |
| XZ | 计划 | 计划 | 计划 | 计划 |
| CRC32 | 计划 | 计划 | N/A | 计划 |
| CRC64 | 计划 | 计划 | N/A | 计划 |
| SHA-256 | 计划 | 计划 | N/A | 计划 |
| BCJ / Delta | 计划（M7） | 计划（M7） | 计划 | 计划 |
| Auto 探测 xz/lzma | 计划 | 否 | 计划 | 计划 |
| concatenated xz | 计划 | 否 | 计划 | 计划 |

---

## 开放问题

1. **编码默认格式**：根包 `EncodeOptions::default()` 现定为 `Format::Xz` + preset 6 + CRC64，对齐 `xz` CLI 常见行为。若希望库名“lzma”更贴 `.lzma`，可改为 `Format::Lzma`。**未拍板前实现不得 silently 改默认值。**
2. **`memlimit` 默认具体数字**：建议对齐 `liblzma` 在无显式 limit 时的做法或给出保守值（例如 128 MiB）。需对照参考实现后再写死。
3. **`OutputBuf` 最终类型**：等 `internal/bit` 有字节缓冲原语后再定，避免公开 `Array[Byte]` 与 `FixedArray[Byte]` 混用。
4. **未知未压缩大小的 LZMA_Alone 编码**：编码器是否始终写 `UNKNOWN_SIZE`，还是在一次性 API 里写真实大小。一次性 API 已知长度，**倾向写真实大小**；流式在 `Finish` 前未知则必须写 `UNKNOWN_SIZE` 或改用 LZMA2/XZ。
5. **错误消息字符串是否属于稳定 API**：建议 `Error` 的标签稳定，`String` 载荷仅供调试，测试用标签匹配而不是全文匹配。

---

## 建议的实现顺序（相对接口）

1. `Error` + `Preset`/`LzmaProps` 校验 + `pack_props`/`unpack_props`
2. `checksum`
3. `decode`（LZMA1）一次性
4. `Decoder::code`（同一套解码器）
5. `encode` / `Encoder::code`
6. LZMA2、XZ、过滤器依次挂到同一 `Format` 分派

不要先做第二套“简单解码器”再在流式里重写。
