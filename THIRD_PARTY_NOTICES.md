# Third-party notices

MoonVCR 自身使用 Apache License 2.0。当前直接依赖如下：

| 依赖 | 固定版本 | 用途 | 来源 | 许可证 |
| --- | --- | --- | --- | --- |
| `moonbitlang/async` | `0.22.1` | native HTTP、文件 IO、超时和异步运行时 | https://github.com/moonbitlang/async | Apache License 2.0 |
| `moonbitlang/core` | 随 MoonBit 工具链 | JSON、debug、UTF-8、Base64 | https://github.com/moonbitlang/core | Apache License 2.0 |

项目通过公开 API 使用上述依赖，没有复制其源文件到本仓库。依赖的完整许可证文本以上游发布包为准；`moonbitlang/async@0.22.1` 发布包内含 `LICENSE`，manifest 声明 `Apache-2.0`。

GitHub Actions 中的 `actions/checkout@v5` 仅用于 CI，不进入 Mooncakes 运行时包。
