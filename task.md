# 待完成大任务

M0–M8 骨架已落地：一次性 `encode`/`decode`、LZMA1 / 裸 LZMA2 / 单 Stream 单 Block `.xz`、CRC32/CRC64、容器外 Delta 与简化 x86 BCJ、Finish 前整段缓冲的流式外壳。完成状态以 [docs/compatibility.md](./docs/compatibility.md) 为准。

本文件只列**尚未完成的大任务**。实现顺序按正确性 → 兼容性 → 流式语义 → 性能。不要并行铺开，不要把未实现标成 complete。协议见 [AGENTS.md](./AGENTS.md)。

---

## 原则

- 规格不明时先写研究笔记，再改代码。
- 公开 API 已冻结的决策不要顺手改（默认 `.xz` + preset 6 + CRC64、`memlimit` 管字典、错误按标签匹配等）。见 [docs/api.md](./docs/api.md)「已冻结的决策」。
- 每项独立交付：实现 + 测试 + 文档 + 兼容性矩阵。不要混进无关重构。
- 下列项**不是**本列表的目标，不要在根包做：C 名兼容层（M9 `compat` 包）、多线程编码器、自定义 allocator、MicroLZMA、`lzma_index_*` 全套编辑 API。

---

## T1 — 编码侧差分（本库 encode → 参考解码）

**问题**：解码侧已有嵌入的 `liblzma` 向量；编码器输出未经参考 `xz` / `liblzma` 验证。自编自解不能证明格式正确。

**范围**：

- CI 或可执行包：本库编码的 `.xz` / `.lzma` / LZMA2 交给系统 `xz -d` 或 `liblzma` 解回，明文必须一致。
- 覆盖空输入、短文本、重复 run、不可压缩、跨 64 KiB、preset 0 与 6、CRC32/CRC64/`None`。

**不做**：要求本库字节与 `xz -6` 相同（贪心编码器允许不同）。

**验收**：`docs/compatibility.md` 中 LZMA1 / LZMA2 / XZ 的 Differential 列能诚实标 encode；CI 失败不得靠删测试过关。

---

## T2 — LZMA2 跨 chunk 状态保持

**问题**：解码器只接受全重置压缩块 `0xE0..=0xFF`。`0x80` / `0xA0` / `0xC0`（以及未压缩 `0x02` 对字典的更新）是 `UnsupportedFeature`。真实 `liblzma` 码流会跨块复用字典和概率表。

**范围**：

- 共享字典：未压缩块 `0x01`/`0x02` 写入字典；压缩块按重置模式复用或重建概率、reps、lc/lp/pb。
- 控制字节：`0x80` 不重置；`0xA0` 重置 state；`0xC0` 重置 state + properties；`0xE0` 再加重置字典。
- 每个压缩块仍有独立的 range decoder 初始化（无 LZMA end marker）。
- 编码器后续块可改为 `0x80`（在不破坏现有 round-trip 与 `Format::Auto` 的前提下）。

**验收**：手写/参考向量覆盖四种重置；`decode_lzma2(encode_lzma2(x)) == x` 对 >64 KiB 仍成立；畸形控制与截断仍是 `Data`/`Eof`，不 panic。更新 `docs/research/lzma2.md`。

---

## T3 — `.xz` 多 Block

**问题**：编码器只写一个 Block；解码器在读完第一个 Block 后要求 Index 恰好 1 条记录（空 Stream 0 条除外）。

**范围**：

- 解码：循环读 Block 直到 Index 指示符 `0x00`；Index 记录数、每条 Unpadded/Uncompressed Size 与各 Block 一致。
- 编码：允许按策略切多个 Block（至少要能解码多 Block 的参考文件）。若第一版编码器仍只写单 Block，必须在文档里写明，不得假装已编码多 Block。

**验收**：嵌入或差分至少一份多 Block `.xz`；单 Block 与空 Stream 回归保持绿色。

---

## T4 — concatenated `.xz`

**问题**：`DecodeOptions.concatenated` 目前直接 `UnsupportedFeature`。Footer 之后的第二个 Stream 被当成垃圾 `DataError`。

**范围**：

- `concatenated = true` 时：解完一个 Stream 后跳过 Stream Padding（仅 null、且长度为 4 的倍数），再解下一个 Stream，拼接明文。
- `concatenated = false`（默认）：Footer 后不得有剩余字节，行为与现在一致。
- 截断的下一 Stream 头 → `UnexpectedEof`；Padding 非 0 → `DataError`。

**验收**：两段本库或 liblzma `.xz` 拼接能解；默认路径仍拒绝拼接。打开该选项不再抛 `UnsupportedFeature`。

---

## T5 — SHA-256 Check

**问题**：`Check::Sha256` 与 Stream Flags `0x0A` 均未实现。

**范围**：

- 实现与 `liblzma` / FIPS 180-4 一致的 SHA-256；`.xz` Check 字段 32 字节，校验**未压缩**明文。
- `encode`/`decode` 支持 `Check::Sha256`；`ignore_check` 仍跳过核对但必须读满 32 字节。
- 公开 checksum API 是否导出 `sha256`：若导出，写进 `docs/api.md` 并 `moon info`；不导出则保持内部。

**验收**：空、短、分块输入的已知摘要向量；本库 SHA-256 `.xz` round-trip；参考文件能解。兼容性矩阵 SHA-256 可标 yes。

---

## T6 — 容器内过滤器链

**问题**：Delta / BCJ 只在根包对明文做容器外前后处理。`.xz` Block Header 里除 LZMA2 以外的 filter ID 解码为 `UnsupportedFeature`。当前 x86 BCJ 是 E8/E9 可逆子集，不是完整 `liblzma` BCJ。

**范围**（按过滤器拆 PR，不要一次做完所有 ISA）：

1. 完整 x86 BCJ（MSByte / prev_mask，对齐 `simple/x86.c`），并允许出现在 Block Header（ID `0x04`）。
2. Delta 作为 Block 内 filter（ID `0x03`），distance 编码与 liblzma 头格式一致（256 → 0）。
3. ARM / ARM64 / ARM-Thumb / PowerPC / IA64 / SPARC：各为一个后续子任务，先有研究笔记和参考向量再写码。

**验收**：容器内 Delta+LZMA2、x86 BCJ+LZMA2 的参考 `.xz` 能解；编码若写进 Block Header，参考解码器能解。根包额外 `filters` 行为保持不变，除非任务明确要统一。

---

## T7 — 真正增量的流式状态机

**问题**：`Encoder`/`Decoder` 在 `Finish` 前缓冲全部输入，再调用一次性 `encode`/`decode`。`Run` 不产生输出；`NeedInput` 不会发出；`SyncFlush`/`FullFlush` 被拒绝。这不是 liblzma 的增量语义。

**范围**：

- 按字节/块推进 range coder 与 LZMA/LZMA2/XZ 状态；合法输入任意切分，`code(..., Run)` 即可出明文/码流。
- 定义并实现 `SyncFlush` / `FullFlush`（或继续拒绝并在文档写死——不得 silently 当成 `Run`）。
- `NeedInput` / `NeedOutput` 与 `consumed`/`produced` 可测试。
- 不得再做第二套编解码器；一次性 API 必须走同一状态机。

**验收**：1 字节输入、1 字节输出槽、在每个内部状态切开输入，结果与一次性 API 相同；截断不产生错误成功明文。`docs/api.md` 删除「Finish 前整段缓冲」的现行限制描述。

**依赖**：T2 完成后再做此项，否则 LZMA2 增量会缺少跨 chunk 状态。

---

## T8 — 最优解析（性能里程碑 M10）

**问题**：LZMA1 编码器是贪心匹配，回看上限 4096。正确性未用参考解码器钉死后，不要把压缩比优化当主线。

**前置**：T1 编码差分已绿。

**范围**：最优解析或等价动态规划；preset 0..=9 的 dict/lc/lp/pb 已有，可再对齐 nice_len / depth 等**外部可观察**参数。仍不要求与 `xz -6` 字节相同，除非另开「比特流复现」任务。

**验收**：有压缩比/速度数字前后对比；全部现有向量与差分仍通过；确定性保持。

---

## 明确延后（不要当成本文件的执行项）

| 项 | 原因 |
| --- | --- |
| M9 `compat` 包（`lzma_stream` / `lzma_ret` 名） | 不得污染根包；需要时另开任务 |
| 多线程编码器 | 第一版只保证单线程确定性 |
| MicroLZMA | 非核心路径 |
| 自定义 allocator | MoonBit 运行时管理内存 |
| Index 全套编辑 API | 解码只需最小 Index 校验 |

---

## 建议执行顺序

```text
T1 编码差分
 → T2 LZMA2 跨 chunk 状态
 → T3 多 Block
 → T4 concatenated
 → T5 SHA-256
 → T6 容器内过滤器（x86 / Delta 优先）
 → T7 增量流式状态机
 → T8 最优解析
```

T3–T5 在 T2 之后可按依赖拆开做，但不要与 T7 混在同一变更里。T8 不得早于 T1。
