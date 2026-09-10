# lzma-mbt

MoonBit 实现的 LZMA / LZMA2 / XZ 编解码库，目标对齐 `liblzma` 的外部可观察行为（格式、校验、错误语义），而不是翻译 C 代码。

模块名：`aurora0x27/lzma-mbt`。开发约定见 [AGENTS.md](./AGENTS.md)，分层与接口见 [docs/](./docs/)。

## 状态

- 默认编码：`.xz` + preset 6 + CRC64
- 默认解码：`Format::Auto`（`.xz` / LZMA_Alone；裸 LZMA2 须显式指定），内存上限 128 MiB（字典，不是明文长度）
- LZMA1 / LZMA2 / XZ 可 round-trip；`.xz` 解码支持同一 Stream 内多个 Block（编码仍写单个 Block）；解码侧有嵌入的 `liblzma` 向量；编码侧由 CI 交给 `xz -d` / Python `lzma` 解回
- `Preset.extreme`、容器内 PowerPC/IA64/ARM-Thumb/SPARC 等 BCJ 过滤器尚未实现（`UnsupportedFeature`）；`.xz` Block Header 过滤器链支持 LZMA2、`Delta -> LZMA2`、`x86 BCJ -> LZMA2`、`ARM BCJ -> LZMA2` 与 `ARM64 BCJ -> LZMA2`
- 默认拒绝 `.xz` Footer 之后或裸 LZMA2 结束标记之后的多余字节；`DecodeOptions.concatenated=true` 时支持连接的多 `.xz` Stream 与规范 Stream Padding
- 编码器是贪心匹配，不保证与 `xz -6` 字节相同

兼容性矩阵：[docs/compatibility.md](./docs/compatibility.md)

## 使用

```moonbit
import {
  "aurora0x27/lzma-mbt" @lzma,
}

let src = b"hello"
let compressed = @lzma.encode(src[:])
let roundtrip = @lzma.decode(compressed[:])
```

流式（`write` + `finish` 保持分块等价；编码器在 `Finish` 前缓冲，解码器完整流到达后可提前排出）：

```moonbit
let dec = @lzma.Decoder::new()
dec.write(chunk0[:])
dec.write(chunk1[:])
let roundtrip = dec.finish()
```

指定 LZMA_Alone：

```moonbit
let enc = @lzma.encode(src[:], options={
  ..@lzma.EncodeOptions::default(),
  format: @lzma.Format::Lzma,
})
```

## 构建

需要 MoonBit toolchain（本仓库 CI 使用 `chawyehsu/setup-moonup@v1`，版本号见仓库根 `moonbit-version`）。**强制工具链版本 `moon 0.1.20260904`**（内置 core `0.10.12+1634b282e`，对应 moonup 发行标识 `0.10.12+1634b282e`），见 `docs/research/toolchain.md`；用其它版本时不要静默适配，先停下来确认。编码差分还需要 Python 3（标准库 `lzma`）以及 `xz`。

```text
moon check --deny-warn
moon fmt --check
moon test --deny-warn
python3 scripts/diff_encode.py
```
