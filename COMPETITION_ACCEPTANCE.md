# MoonVCR 最终验收标准对应表

按选手于 2026-09-30 提供的最新验收指南逐条复核。无需再提交报名表，开发与证据通过普通 Git 提交公开在仓库中。以下不代表举办方的最终评审决定。

| 标准 | 实现与复核入口 |
| --- | --- |
| 1. MoonBit 为主要实现语言，moonc 不低于 0.10.14 | 产品实现与测试均为 `.mbt`；本地使用 `moonc v0.10.14+7d59c7ec9`。`scripts/check-toolchain.ps1` 在两个 CI 作业中拒绝低于 0.10.14 的编译器，比较的是 moonc 而非 moon 版本 |
| 2. GitHub 公开可访问，提交记录清晰 | https://github.com/chenqi-arch/moonbit-project；普通开发与修复提交保留目的和测试线索，发布标签 `v0.3.0` 保留原指向，未重写历史 |
| 3. 源代码结构清晰，核心功能可完成 | 根包分别提供 codec、normalize、matcher、session、redact、diagnostics、contract；`native/` 提供真实 HTTP 与文件档案；`cmd/` 为完整示例。功能及边界见 README，测试映射见 RELIABILITY_ACCEPTANCE.md |
| 4. README 说明目标、安装、使用与可复现示例 | README 包含完整消费者的 `moon.pkg` 和 `fn main`，以及安装、运行命令和预期输出；`scripts/verify-public-consumer.ps1` 直接提取 README 代码并从 Mooncakes 下载正式包进行 check/build/run |
| 5. CI 覆盖检查、构建、测试 | `.github/workflows/ci.yml` 的 check/native 作业分别执行对应后端的 check、build、test，并执行版本门禁、场景和集成验收 |
| 6. 至少一个可运行示例 | `moon run cmd/moonvcr-demo`；另有 pagination、order-contract、restricted-ci 三个业务场景与故障用例 |
| 7. 测试覆盖核心功能路径 | 核心 76 项，Ubuntu native 85 项（含核心），不能相加为 161 项；覆盖编解码、匹配、顺序/完整消费、脱敏、错误、响应契约、容量、文件失败路径；真实 HTTP 录制后关服，由新进程加载并严格离线回放 |
| 8. 发布到 Mooncakes | `chenqi-arch/moonbit-project@0.3.0` 已正式发布；https://mooncakes.io/docs/chenqi-arch/moonbit-project@0.3.0；独立消费者使用公开下载包，源码不通过本地路径覆盖 |
| 9. OSI 认可的许可证与上游合规 | 根 LICENSE 为完整 [OSI 认可的 Apache License 2.0](https://opensource.org/license/apache-2.0)，manifest 同步声明 Apache-2.0；THIRD_PARTY_NOTICES.md 列明 core 与 async 来源/许可证，未移植其他 VCR 项目源码 |

## 2026-09-30 复核

- 新工具链：官方 Windows x86_64 下载包 SHA256 为 `faae225a8287d0ce69e44b5b3f754af988e97f4446056d8f32ceb3ddb998fce7`，与官方校验值一致。
- 实际编译器：`moonc v0.10.14+7d59c7ec9 (2026-09-18)`；build driver 为 `moon 0.1.20260920`。
- 核心格式、check、build、76/76 测试，四个成功入口及三个非零失败入口：本地重新通过。
- native 类型检查：Windows 本地通过；native 运行及跨进程集成仍以 Ubuntu CI 为支持证据。
- 新版工具链增加了既有测试隐式导入和 trait 方法提升的弃用提醒；这些提醒不会改变测试断言结果，但不宣称编译零警告。
- 新版 README 独立消费者：从 Mooncakes 重新下载 0.3.0，check/build/run 全部通过，输出 `offline consumer passed status=200` 与 `README public consumer acceptance passed package=0.3.0`。
- 版本门禁正反例：旧工具链 `0.10.12` 被明确拒绝，新工具链 `0.10.14` 通过；默认项目工具链已升级，旧工具链备份留在被 Git 忽略的 `.tools/`。
- 公开可访问性：GitHub 无登录 API 查询返回 `private=false`、`visibility=public`；本次修改的 CI 成功后补入运行链接。

## 支持边界

核心 wasm 已在 Windows 与 Ubuntu 验证；HTTP/文件档案运行支持只声明 Ubuntu native。TLS 使用官方客户端默认校验；本地 HTTP 集成不作为 TLS 握手实测证据。版本与历史发布记录见 FINAL_ACCEPTANCE.md，具体失败路径见 RELIABILITY_ACCEPTANCE.md。
