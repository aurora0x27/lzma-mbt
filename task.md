# 待完成大任务

M0–M8 骨架已落地：一次性 `encode`/`decode`、LZMA1 / 裸 LZMA2（含跨 chunk 字典与 `0x80`/`0xA0`/`0xC0`/`0xE0`）/ 单 Stream `.xz`（解码 0..N Block，编码仍为 1 Block）、CRC32/CRC64/SHA-256、容器外 Delta 与完整 x86 BCJ、XZ 容器内 Delta 与全部 BCJ（x86/PowerPC/IA-64/ARM/ARM-Thumb/SPARC/ARM64）、Finish 前整段缓冲的流式外壳。编码侧差分（本库 encode → `xz -d` / liblzma）已在 CI 落地。T8 已以 lazy + dict 回看落地（见下文）。完成状态以 [docs/compatibility.md](./docs/compatibility.md) 为准。

本文件只列**尚未完成的大任务**。实现顺序按正确性 → 兼容性 → 流式语义 → 性能。不要并行铺开，不要把未实现标成 complete。协议见 [AGENTS.md](./AGENTS.md)。

---

## 原则

- 规格不明时先写研究笔记，再改代码。
- 公开 API 已冻结的决策不要顺手改（默认 `.xz` + preset 6 + CRC64、`memlimit` 管字典、错误按标签匹配等）。见 [docs/api.md](./docs/api.md)「已冻结的决策」。
- 每项独立交付：实现 + 测试 + 文档 + 兼容性矩阵。不要混进无关重构。
- 下列项**不是**本列表的目标，不要在根包做：C 名兼容层（M9 `compat` 包）、多线程编码器、自定义 allocator、MicroLZMA、`lzma_index_*` 全套编辑 API。

---

## 通用完成门（每一项都适用）

一项任务只有同时满足下面全部条件，才可从本文件删除，并在兼容性矩阵里把对应格子改成 `yes` / `decode+encode`。

**命令（必须全绿）**

```text
moon check --deny-warn
moon fmt --check
moon test --deny-warn
python3 scripts/diff_encode.py
```

**标准**

- 新行为有正例；畸形输入有负例；不得 panic。
- 不得靠删除或削弱已有测试过 CI。
- 合法输入按任意 chunk 经现有流式外壳 `write`+`finish` 的结果，须与一次性 `decode` 相同（T7 之前 `Run` 仍可只缓冲）。
- `docs/research/<组件>.md`、`docs/compatibility.md`、必要时 `docs/api.md` 已更新。
- 差分列只有在对照 `liblzma` / `xz` 的测试存在且通过时才能标 encode/decode。
- 编码器字节仍不要求与 `xz -6` 相同，除非另开「比特流复现」任务。

**已落地回归（实现后续任务时不得变红）**

| 项 | 最低回归 |
| --- | --- |
| T1 编码差分 | `scripts/diff_encode.py` 现有 35 案（空 / 短 / run / 不可压缩 / 跨 64 KiB / preset 0 与 6 / CRC32·CRC64·None·SHA-256 / XZ Delta+LZMA2 / XZ x86-BCJ+LZMA2 / XZ PowerPC-BCJ+LZMA2 / XZ IA-64-BCJ+LZMA2 / XZ ARM-BCJ+LZMA2 / XZ ARM64-BCJ+LZMA2 / XZ ARM-Thumb-BCJ+LZMA2 / XZ SPARC-BCJ+LZMA2） |
| T2 LZMA2 跨 chunk | `0xE0` 后 `0x80`、白盒 `0xA0`/`0xC0`、`0x01`+`0x02`、70 000 字节第二块为 `0x80`、liblzma 2 MiB+100 `'A'` 向量；打头 `0x80`/`0xA0`/`0xC0`/`0x02` 仍是 `Data` |
| `.xz` 多 Block 解码 | `xz --block-size=2` 的 `"aabb"`（2 Block）与 `"aabbcc"`（3 Block）；空 Stream / 单 Block / Footer 后垃圾回归；Index 记录数或逐条 size 不符 → `DataError`；第二 Block Header/Data/Check 截断 → `Eof`；编码器 Index 仍为 1 条 |
| XZ 容器内 Delta | 自编码 distance 1 / 4 / 256；`xz --delta=dist=1/4/256 --lzma2=preset=0` 参考 `.xz`；编码差分含 Delta+LZMA2 并由 Python `lzma` / `xz -d` 解码；非法属性长度、Delta 作为最后一条、三过滤器链均有负例 |
| XZ 容器内 IA-64 BCJ | `bcj_ia64` 镜像 `simple/ia64.c`（16 字节 bundle / BRANCH_TABLE / 64 位槽位）；`xz --ia64` 参考 `.xz` 能解；自编码 round-trip（Header 记录 `0x06` 无属性）；StreamDecoder 整块路径 chunk 喂入一致；编码差分含 IA-64-BCJ+LZMA2；属性非空 / 作为最后一条 → `Data` |
| XZ 容器内 PowerPC BCJ | `bcj_powerpc` 镜像 `simple/powerpc.c`；`xz --powerpc` 参考 `.xz` 能解；自编码 round-trip（Header 记录 `0x05` 无属性）；StreamDecoder 整块路径 chunk 喂入一致；编码差分含 PowerPC-BCJ+LZMA2；PowerPC 属性非空 / 作为最后一条 → `Data` |
| XZ 容器内 ARM-Thumb BCJ | `bcj_armthumb` 镜像 `simple/armthumb.c`；`xz --armthumb` 参考 `.xz` 能解；自编码 round-trip（Header 记录 `0x08` 无属性）；StreamDecoder 整块路径 chunk 喂入一致；编码差分含 ARM-Thumb-BCJ+LZMA2；ARM-Thumb 属性非空 / 作为最后一条 → `Data` |
| XZ 容器内 ARM64 BCJ | `bcj_arm64` 与 `lzma_bcj_arm64_*` 字节一致（BL/ADRP 向量）；`xz --arm64` 参考 `.xz` 能解；自编码 round-trip（Header 记录 `0x0A` 无属性）；StreamDecoder 整块路径 chunk 喂入一致；编码差分含 ARM64-BCJ+LZMA2；ARM64 属性非空 / ARM64 作为最后一条 → `Data` |
| XZ 容器内 ARM BCJ | `bcj_arm` 镜像 `simple/arm.c`；`xz --arm` 参考 `.xz` 能解；自编码 round-trip（Header 记录 `0x07` 无属性）；StreamDecoder 整块路径 chunk 喂入一致；编码差分含 ARM-BCJ+LZMA2；ARM 属性非空 / ARM 作为最后一条 → `Data`；多前置过滤器同给 → `Data` |
| Flush 拒绝语义 | `Encoder`/`Decoder` 对 `SyncFlush`/`FullFlush` 抛 `InvalidConfiguration`，不消费输入、不写输出、计数不变、不按 `Run`；拒绝后仍可正常 `write`/`finish` |
| `.lzma` 增量解码 | 1 字节与固定种子随机 chunk 与一次性 `decode` 明文一致；13 字节 header 逐字节/逐长度切开；unknown size（`0xFF..FF`）靠 end marker 收尾；截断 header → `Eof`；非法属性 → `Data`；memlimit 过小 → `Limit`；`StreamEnd` 后再喂输入 → `Data` |
| XZ 容器内 SPARC BCJ | `bcj_sparc` 镜像 `simple/sparc.c`；`xz --sparc` 参考 `.xz` 能解；自编码 round-trip（Header 记录 `0x09` 无属性）；StreamDecoder 整块路径 chunk 喂入一致；编码差分含 SPARC-BCJ+LZMA2；属性非空 / 作为最后一条 → `Data` |
| XZ 容器内 x86 BCJ | `bcj_x86` 与 `lzma_bcj_x86_*` 字节一致（overlap / prev_mask 向量）；`xz --x86` 参考 `.xz` 能解；自编码 round-trip（Header 记录 `0x04` 无属性）；StreamDecoder 整块路径 chunk 喂入一致；编码差分含 x86-BCJ+LZMA2；x86 属性非空 / x86 作为最后一条 → `Data`，未知 prefilter / 三过滤器链 → `Unsupported` |

## T7 — 真正增量的流式状态机

当前已完成 T7a 的 API 契约、`NeedInput`/`NeedOutput`、随机分块回归，T7b 的裸 LZMA2 控制头/完整 chunk 状态机，T7c 的 LZMA 符号级 active payload，T7d 的单 Stream XZ Header、Block、payload、Index/Footer 增量状态，以及 `.lzma` 的增量头部与符号级 payload（声明大小时仍要求并校验 end marker）。声明压缩大小的 XZ Block 会复用 active LZMA2 解码器并在 Footer 前产生明文；`concatenated=true`、无压缩大小字段的 Block 和带根级额外 filters 的 XZ 保持兼容路径。三种容器的 `Decoder::code(..., Run)` 已真正增量；`SyncFlush`/`FullFlush` 已冻结为拒绝语义并写死（见回归表与 `docs/api.md`）；剩余为 `Encoder` 的增量输出。

**问题**：`Encoder`/`Decoder` 在 `Finish` 前缓冲全部输入，再调用一次性 `encode`/`decode`。`Run` 不产生输出；`NeedInput` 不会发出；`SyncFlush`/`FullFlush` 被拒绝。这不是 liblzma 的增量语义。

**范围**：

- 按字节/块推进 range coder 与 LZMA/LZMA2/XZ 状态；合法输入任意切分，`code(..., Run)` 即可出明文/码流。
- `SyncFlush` / `FullFlush`：**已冻结为继续拒绝**——`InvalidConfiguration`，不消费输入 / 不写输出 / 不改计数 / 不按 `Run` 处理；`docs/api.md` 写死，测试锁定。
- `NeedInput` / `NeedOutput` 与 `consumed`/`produced` 可测试。
- 不得再做第二套编解码器；一次性 API 必须走同一状态机。

**测试**

等价性（`.xz` / `.lzma` / 裸 LZMA2 各至少一组短文本 + 一组跨 64 KiB）：

- 一次性 `decode(encode(x))` 与流式 `code(..., Run)` 循环再 `Finish` 的明文/码流语义相同。
- 输入每次 1 字节、输出槽每次 1 字节。
- 输入在「每个已文档化的内部状态」切开（至少：Stream Header 中、Block Header 中、LZMA2 控制字节后、压缩 payload 中、Index、Footer）。
- 随机 chunk 大小（固定种子）≥ 50 次切分，结果与一次性 API 相同。

状态与计数：

- `Run` 在输入耗尽且未结束时发出 `NeedInput`（或文档中等价、可测的契约），且 `consumed`/`produced` 与缓冲一致。
- 输出槽满 → `NeedOutput`；随后用空输入 `Run`/`Finish` 能排空，不丢字节。
- `total_in` / `total_out` 在 `BufferTooSmall` 重试后不倒退、不重复计算（对齐现有空输出槽回归）。

Flush：

- 若实现 `SyncFlush`/`FullFlush`：各有正例（flush 后参考解码器能解已写出的码流前缀，或文档规定的可解码边界）；重复 flush 不损坏状态。
- 继续拒绝（已实现并锁定）：encoder/decoder 各 `SyncFlush` / `FullFlush` 负例断言 `InvalidConfiguration`、`total_in`/`total_out` 不变、`output` 未写入，且拒绝后正常 `write`/`finish` 仍可用；`docs/api.md` 写死「不是 `Run`」。

负例：

- 截断流在 `Finish` 时 `UnexpectedEof` / `DataError`，不得返回「成功但短一截」的明文。
- `StreamEnd` 之后再 `Run` 有效载荷 → 与当前拒绝语义一致或更严，须有测试。
- 畸形控制/坏 CRC 在增量路径与一次性路径错误标签一致。

**标准**

- [ ] `docs/api.md` 删除「Finish 前整段缓冲」及「`Run` 不产生输出 / 不发出 `NeedInput`」的现行限制。
- [ ] 兼容性矩阵 Streaming 列仍为 yes，且注释改为真正增量（不再写 Finish 前整段缓冲）。
- [ ] 一次性 `encode`/`decode` 与 `Encoder`/`Decoder` 共用同一状态机（代码结构或测试能证明不是第二套实现）。
- [ ] T1 差分与 T2 LZMA2 跨 chunk 回归绿色。

---

## T8 — 最优解析（性能里程碑 M10）— 已落地（lazy + dict 回看）

**落地范围（非完整 GetOptimum DP）**：

- 匹配搜索距离 `min(window, dict_size)`（去掉硬编码 4096）。
- HC3 `MatchChainDepth = 256`。
- 长度优先候选 + 近似 bit price 平局决胜 + `nice_len` lazy 解析。

**证据**：见 `docs/research/lzma.md`「Performance note (T8 lazy + dict lookback)」。syslog 对 xz-6 从 ~5.2× 降至 ~1.09×；large.txt 从 2152→1700 字节。`moon test` + `scripts/diff_encode.py` 绿。

**标准**

- [x] 在 `docs/research/lzma.md` 写下前后压缩比与时间表。
- [x] 兼容性矩阵 Encoder 仍为 yes；Differential 仍含 encode。
- [x] 公开 API 未擅自改默认 preset / check / 格式。
- [x] 回看随 `dict_size`（内部），未新增外部可观察搜索宽度 API；`memlimit` 语义未改。

完整 OPT 数组 DP 若仍需要，另开任务；不再阻塞本文件主线。

---

## 明确延后（不要当成本文件的执行项）

这些项**没有**实现任务。标准是：根包不出现对应 API，也不把兼容性矩阵标成 yes。

| 项 | 原因 | 测试/标准 |
| --- | --- | --- |
| M9 `compat` 包（`lzma_stream` / `lzma_ret` 名） | 不得污染根包 | 根包 `pkg.generated.mbti` 无 `lzma_stream`/`lzma_ret`；需要时另开任务 |
| 多线程编码器 | 第一版只保证单线程确定性 | 同输入两次 `encode` 字节相同；无线程相关公开选项 |
| MicroLZMA | 非核心路径 | 无 MicroLZMA 公开入口；未知格式仍 `FormatError` / `UnsupportedFeature` |
| 自定义 allocator | MoonBit 运行时管理内存 | 无 allocator 回调 API |
| Index 全套编辑 API | 解码只需最小 Index 校验 | 无 `lzma_index_*` 编辑接口；解码只测记录数与 size 一致 |

---

## 建议执行顺序

```text
T7 增量流式状态机（.lzma 增量余量）
```

（T8 lazy + dict 回看已落地；完整 OPT DP 非阻塞项。）
