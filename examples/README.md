# Examples

面向典型输入类型的可运行示例。每个 `pN` 是独立 MoonBit 可执行模块，读取 `fixtures/` 中的样本，写出 `.xz` 并校验 round-trip。

| 示例 | 输入类型 | Fixture |
| --- | --- | --- |
| [p1](./p1/) | 小文字 | `fixtures/small.txt`（约几十字节） |
| [p2](./p2/) | 大段文字 | `fixtures/large.txt`（约 512 KiB） |
| [p3](./p3/) | 系统日志 | `fixtures/syslog.log`（合成 syslog，约 250 KiB） |
| [p4](./p4/) | 小图片 | `fixtures/small.png`（64×64 PNG） |
| [p5](./p5/) | 大图片 | `fixtures/large.png`（本地准备，约数 MiB） |

在仓库根目录运行：

```bash
make examples-fixtures   # 准备 large.png（若不存在）
make examples            # 依次运行 p1..p5
make example-p3          # 只跑系统日志示例
```

大图 `fixtures/large.png` 默认不入库（体积大）。`make examples-fixtures` 会从
`$HOME/Pictures/wallpaper/CuteCat.png` 复制；也可自行放入任意较大 PNG/JPEG。

预期现象简述：

- **文本 / 日志**：重复多，压缩率通常很好
- **PNG / JPEG**：本身已压缩，体积往往几乎不变，但 round-trip 仍应成功
