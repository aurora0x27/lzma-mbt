# MoonBit 项目架构与本库分层

## 问题

本仓库要在 MoonBit 中独立实现 `liblzma` 的核心能力。在写算法之前，需要先回答两件事：

1. MoonBit 项目在工具链层面实际长什么样（模块、包、可见性、测试、依赖方向）。
2. 这些约定如何映射到本库的分层，才能同时满足 `AGENTS.md` 的分层要求，以及 MoonBit 的包边界。

本文只定架构，不定算法细节。公共函数签名见 [api.md](./api.md)。

---

## MoonBit 项目长什么样

结论先说：MoonBit 的组织单位是 **模块（module）+ 包（package）**，目录即包，和 Go 接近；可见性比 Go 更细；公开 API 最终会落到 `pkg.generated.mbti` 上。

### 1. 两层配置

| 层级 | 配置文件 | 作用 |
| --- | --- | --- |
| 模块 | `moon.mod`（旧：`moon.mod.json`，已弃用） | 发布单元。声明模块名、版本、源码根、第三方依赖 |
| 包 | `moon.pkg`（旧：`moon.pkg.json`，已弃用） | 编译单元 / 命名空间。声明 import、是否可执行、测试依赖 |

新项目应使用 DSL 格式的 `moon.mod` / `moon.pkg`，不要再写 JSON。

模块名通常是 `user-name/project-name`。包的完整标识是：

```text
user-name/project-name/相对源码根的路径
```

例如源码根为 `src` 时，`src/lzma/moon.pkg` 对应包 `aurora0x27/lzma-mbt/lzma`。

### 2. 官方默认目录

`moon new` 当前会生成类似结构（配置已切到新 DSL）：

```text
my_project/
├── moon.mod
├── moon.pkg                 # 根包 username/my_project
├── my_project.mbt
├── my_project_test.mbt      # 黑盒测试
├── cmd/main/
│   ├── moon.pkg             # 可执行包
│   └── main.mbt
├── README.mbt.md
└── Agents.md
```

也可以把源码收进 `src/`，在 `moon.mod` 里写 `source = "src"`。库项目更适合这种布局：仓库根留给文档、CI、研究笔记，源码根只放包。

同一目录下所有 `.mbt` 属于同一个包，必须有一份 `moon.pkg`。新建子目录却不放 `moon.pkg`，该目录不是包。

### 3. 依赖方向

依赖声明分两步，缺一不可：

1. **模块级**：在 `moon.mod` 的 `import { ... }` 声明外部模块（旧 JSON 的 `deps`）。
2. **包级**：在 `moon.pkg` 的 `import { ... }` 声明要用的包，可加别名：

```text
import {
  "aurora0x27/lzma-mbt/lzma" @lzma,
  "moonbitlang/core/builtin",
}
```

代码里通过 `@别名.符号` 访问。标准库里的 `@json`、`@test` 等同样需要显式 import，否则会有 `core_package_not_imported`。

禁止循环依赖：MoonBit 构建系统按包图编译，环会直接失败。这也是本库必须单向分层的工具链原因，不只是风格问题。

### 4. 可见性（决定 API 边界）

默认：**函数私有，类型抽象**。这是 MoonBit 刻意鼓励信息隐藏。

| 对象 | 写法 | 外部能做什么 |
| --- | --- | --- |
| 函数 / 顶层 `let` | 无修饰符 | 不可见 |
| 函数 / 顶层 `let` | `pub` | 可调用 / 可读 |
| 类型 | `priv type` | 完全不可见 |
| 类型 | `type`（默认） | 只看见名字，看不见表示 |
| 类型 | `pub type` / `pub struct` | 只读：可模式匹配、可读字段，不可构造/修改 |
| 类型 | `pub(all)` | 可构造、可读、可改（若可变） |
| trait | `priv` / 默认抽象 / `pub` / `pub(open)` | 从不可见到允许外部实现 |

约束：`pub` 实体不能暴露 `priv` 类型。编码器/解码器状态应使用**默认抽象类型**，外部只能通过公开方法操作，不能拆开内部字典和概率表。

跨包再导出用 `pub using @pkg { fn, type, trait }`。根包应用它收敛对外表面，而不是让用户 import 十几个内部包。

### 5. `internal` 包

路径形如 `a/b/c/internal/x` 的包，**只允许** `a/b/c` 及其子包 import。外部模块无法依赖这些包。

这是把“算法实现”和“稳定 API”切开的语言级手段。本库的 range coder、match finder、概率模型应放在 `internal/` 下，而不是做成可被任意 mooncakes 依赖的公开包。

### 6. 测试模型

测试块类型是 `() -> Unit raise Error`。

| 文件 | 访问权限 | 用途 |
| --- | --- | --- |
| 源文件内的 `test { ... }` | 白盒 | 紧挨实现的不变量 |
| `*_wbtest.mbt` | 白盒（可见包内私有成员） | 内部状态机、边界 |
| `*_test.mbt` | 黑盒（只看见 `pub`） | 模拟外部用户；能抓住“忘了 pub” |

`*_test.mbt` 由构建系统做成独立测试包，通过 `@包名` 引用当前包。包配置里还有 `test-import` / `wbtest-import`。

`moon info` 会生成 `pkg.generated.mbti`，这是对外 API 的形式化摘要。公共包的 `.mbti` 变化等于破坏性变更。

### 7. 可执行包、后端、虚拟包

- 库包默认即可；带 `main` 的包需要 `pkgtype(kind: "executable")`。
- 后端：`wasm` / `wasm-gc` / `js` / `native`。模块可用 `preferred_target`、`supported_targets`；单文件差异用 `moon.pkg` 的 `targets`。
- 虚拟包是实验特性，用于编译期替换实现。差分测试若要对接系统 `liblzma`，可以以后再评估，当前不作为架构前提。

### 8. 错误处理习惯

MoonBit 现在以 `raise` + `suberror` 为主，而不是把 `Result` 当作默认错误通道。

```text
suberror Error { InvalidInput(String) }

pub fn decode(data : BytesView) -> Bytes raise Error
```

畸形输入必须 `raise` 明确错误，不能 `panic` / `abort`。这和 `AGENTS.md` 第 14 节一致。

### 9. 对本库的直接推论

1. 一个 git 仓库 = 一个模块 `aurora0x27/lzma-mbt`。
2. `source = "src"`，每个算法层一个包。
3. 对外只稳定少数包；实现包进 `internal/`。
4. 编码器/解码器状态用抽象类型；选项、枚举用 `pub(all)`。
5. 每个包自带白盒 + 黑盒测试；根包黑盒测试覆盖“用户真正 import 的 API”。
6. 依赖只能向下：`api → xz → lzma2 → lzma → range_coder → bit`，禁止反向。

---

## 本库分层

### 设计原则

1. **规范先于实现**：包边界按 XZ/LZMA 规格和 `liblzma` 的外部可观察行为切，不按 C 源文件切。
2. **公开面要小**：外部默认只 import 根包。格式专用包可以公开，但不保证内部算法包稳定。
3. **独立实现，行为对齐**：不把 `liblzma` 的指针、`lzma_ret`、宏翻译成 MoonBit；对齐的是比特流、错误分类、流式状态。
4. **流式 API 与一次性路径共用实现**：`Encoder`/`Decoder` 在 `Finish` 前缓冲输入，再调用同一套 `encode`/`decode`。真正按字节推进的 LZMA 状态机是后续任务，不得再做第二套编解码器来假装增量。
5. **增量交付**：包可以先有接口和空实现/测试桩，但不得把未完成包标成 complete。

### 目标目录

```text
lzma-mbt/
├── moon.mod
├── AGENTS.md
├── README.md
├── docs/
│   ├── architecture.md      # 本文
│   ├── api.md
│   ├── compatibility.md
│   └── research/            # 组件研究笔记
└── src/
    ├── moon.pkg             # 根包：aurora0x27/lzma-mbt
    ├── error.mbt
    ├── options.mbt
    ├── codec.mbt
    ├── stream.mbt
    ├── lzma/                # 公开：LZMA1 / .lzma
    ├── lzma2/               # 公开：LZMA2
    ├── xz/                  # 公开：.xz 容器
    ├── checksum/            # 公开：CRC32/CRC64 等（容器与差分都需要）
    ├── filters/             # 公开：BCJ/Delta 等，按里程碑增量
    └── internal/
        ├── bit/
        ├── range_coder/
        ├── lz/
        └── coder/           # 共享编码器/解码器状态机胶水，不对外
```

根包只做再导出和“易用 API”。格式细节放在 `lzma` / `lzma2` / `xz`。

`cmd/` 现在不需要。这是库项目，不是 CLI。以后若做参考工具或差分驱动，再加 `src/cmd/...` 可执行包。

### 包标识与职责

模块名：`aurora0x27/lzma-mbt`（与 GitHub 仓库一致）。源码根：`src`。

| 包 | 对外 | 职责 | 允许依赖 |
| --- | :---: | --- | --- |
| `aurora0x27/lzma-mbt` | 是 | 易用编解码、流式入口、错误/选项再导出 | `lzma`, `lzma2`, `xz`, `checksum`, `filters`, `internal/coder` |
| `.../lzma` | 是 | LZMA_Alone 头与 payload | `internal/coder`, `internal/bit` |
| `.../lzma2` | 是 | LZMA2 chunk、字典重置、未压缩块 | `internal/coder`, `internal/bit` |
| `.../xz` | 是 | Stream/Block/Index/Footer | `lzma2`, `checksum`, `internal/coder`, `internal/bit` |
| `.../checksum` | 是 | CRC32、CRC64 | 无（仅 core） |
| `.../filters` | 是 | Delta、简化 x86 BCJ（根包额外前后处理） | 无（仅 core） |
| `.../internal/bit` | 否 | 位/字节读写、整数打包 | 无（或仅 core） |
| `.../internal/range_coder` | 否 | 范围编解码、概率更新 | `internal/bit` |
| `.../internal/lz` | 否 | 滑动字典 | `internal/bit` |
| `.../internal/coder` | 否 | LZMA 状态机胶水，供 `lzma`/`lzma2` 使用 | `range_coder`, `lz`, `bit` |

依赖只能从上到下：

```text
根包
  ├─► xz ──► lzma2 ─┐
  ├─► lzma ─────────┼► internal/coder ─► range_coder / lz ─► bit
  ├─► filters       │
  └─► checksum ◄────┘  （xz 校验字段）
```

`.xz` Block 内的过滤器链仍只有 LZMA2。Delta / BCJ 由根包在容器外前后处理，`xz` 包不依赖 `filters`。

任何时候出现 `bit → lzma` 或 `lzma → xz`，都视为架构错误，应停下来改任务而不是“顺便改一层”。

### 与 `AGENTS.md` 概念层的对应

`AGENTS.md` 第 4 节的 `src/bit`、`src/range_coder` 是**概念层**。落地时把实现层放进 `internal/`，公开层保留格式名。这样：

- 外部用户不能 `import "aurora0x27/lzma-mbt/internal/range_coder"`。
- 内部包仍可被本模块所有子包使用（`internal` 规则：对根包及其 `**` 可见）。
- 以后若确实要把 checksum 当独立算法库用，它已经在公开层，不必再搬。

### 每个包内部的文件习惯

不强制一函数一文件。按**状态机/不变量**拆文件，例如 `lzma`：

```text
src/lzma/
├── moon.pkg
├── alone.mbt
├── alone_test.mbt
└── pkg.generated.mbti
```

研究笔记放 `docs/research/lzma.md`，不把规格长文塞进源码注释。源码注释只写“为什么”。

### 测试与差分的位置

| 类型 | 放哪 |
| --- | --- |
| 单元 / 属性 / 负例 | 对应包的 `_test.mbt` / `_wbtest.mbt` |
| 根 API 黑盒 | `src/*_test.mbt` |
| 参考向量 | 嵌在对应 `*_test.mbt` 的字节字面量里（尚无独立 `tests/vectors/` 目录） |
| 与系统 `liblzma` 的差分驱动 | 后续独立任务：可执行包或 CI 脚本；未落地前不要假装已差分 |

`checksum` 和 `bit` 必须先有可独立复现的向量，上层才能做差分。

### 里程碑与包启用顺序

与 `AGENTS.md` 第 25 节对齐，包不是一次建齐再空转：

| 里程碑 | 先建立的包 | 对外 API |
| --- | --- | --- |
| M0 | `moon.mod`、`src/moon.pkg`、CI | 无 |
| M1 | `internal/bit`、`checksum` | checksum 可先公开 |
| M2 | `internal/range_coder` | 不公开 |
| M3 | `internal/lz`、`internal/coder`、`lzma` | `decode`（LZMA1） |
| M4 | `lzma` 编码器 | `encode`（LZMA1） |
| M5 | `lzma2` | LZMA2 编解码 |
| M6 | `xz` | `.xz` |
| M7 | `filters` | 过滤器链 |
| M8 | 根包 `stream.mbt` | `write`/`code`/`finish`（Finish 前整段缓冲） |
| M9 | 可选 `compat` 包 | 仅当需要 C 名映射 |
| M10 | 不新增包 | 性能 |

未到达的里程碑：可以先在文档里留接口，**不要**在根包 `pub using` 尚未存在的符号。

### 兼容性层（M9）明确不做的事

不把下列 C 形状作为 MoonBit 主 API：

- `lzma_stream` 的 `next_in` / `avail_in` 指针对
- `lzma_ret` 整数码
- `lzma_allocator` 回调
- 需要调用方 `lzma_end` 释放的隐式堆状态

行为兼容通过测试与差分保证；API 兼容若需要，另开 `compat` 包，且不得污染根包。

### 开放问题

1. **模块名是否固定为 `aurora0x27/lzma-mbt`**：与当前 GitHub 远程一致。若以后改在 mooncakes.io 的组织名下发布，只改 `moon.mod` 的 `name`，包相对路径保持不变。
2. **`filters` 是否从一开始就公开**：已公开。未实现的过滤器与 `FilterSpec::Lzma1`/`Lzma2` 在额外链中返回 `InvalidConfiguration` / `UnsupportedFeature`，不能 silently skip。
3. **差分测试如何调用参考实现**：解码侧已嵌入 `liblzma` 向量。编码器输出与 `xz -6` 字节对齐、以及 CI 里用参考解码器解本库码流，仍是独立任务。
4. **多线程编码器**：`liblzma` 有 `lzma_stream_encoder_mt`。MoonBit 后端与并发模型未作为本阶段前提，**第一版只保证单线程语义**。

### 建议的下一步

M0–M8 骨架与正确性测试已在本仓库落地。后续独立任务：

1. 编码输出对接 `xz -d` / `liblzma` 的差分（目前差分列仅为 decode）
2. LZMA2 跨 chunk 状态保持（`0x80`/`0xA0`）
3. `.xz` 多 Block、concatenated Streams、SHA-256
4. 完整 x86 BCJ 及 ARM 等过滤器作为容器内 filter
5. 真正增量的 range/LZMA 状态机（现在 `Finish` 前整段缓冲）
