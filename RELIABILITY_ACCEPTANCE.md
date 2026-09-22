# MoonVCR 可靠性测试与验收说明

这份文档把初审提出的“可靠性相关测试项和验收说明”映射到仓库中的可运行测试。它区分 portable 核心、native 适配器和发布包验收，不把尚未执行的环境结果写成通过。

## Portable 核心验收

在仓库根目录执行：

```text
moon fmt --check
moon check
moon build
moon test
moon run cmd/moonvcr-demo
moon package --list
git diff --check
```

当前本地结果（2026-09-22）：格式、检查、构建和 demo 成功；`moon test` 为 `Total tests: 68, passed: 68, failed: 0.`；demo 输出包含 `offline replay status=200` 和 `recorded interactions=1`。MoonBit 仍会提示 `method` 是保留关键字的非致命警告，未把警告伪装成零警告。

## Native 验收

Ubuntu CI 执行：

```text
moon check --target native
moon build --target native
moon test --target native
moon run --target native cmd/moonvcr-native-demo
moon run --target native cmd/moonvcr-native-record
moon run --target native cmd/moonvcr-native-replay
```

native 测试覆盖：

- cassette JSON 文件的同步临时写入、加载、解码和大小限制；
- 已有目标默认拒绝覆盖，显式 replace 才允许更新；
- 真实的官方 HTTP 客户端请求/响应转换代码可被 native 编译；
- 两个独立进程只通过 JSON 文件交接，第二个进程在 `StrictOffline` 中完成回放并调用 `assert_complete`。

当前 Windows 工作站已通过 `moon check --target native`，但执行 native build/test 时工具链明确报告没有 `cl`、`cc`、`gcc` 或 `clang`。因此 native 运行结果只在 Ubuntu CI 作为支持证据；这不是把 Windows 未执行结果写成通过。

## 测试矩阵

| 验收项 | 测试/代码位置 | 可观察结果 |
| --- | --- | --- |
| 结构化匹配键避免分隔符碰撞 | `normalize_test.mbt`、`matcher_test.mbt` | 不同 header 结构不会误命中 |
| ReplayMiss 和 mismatch 不泄露完整 key | `matcher_test.mbt`、`diagnostics_test.mbt` | 只输出长度、类型和指纹 |
| URL 用户信息、百分号编码敏感 query、JSON 路径脱敏 | `redact_test.mbt` | 敏感值不进入 cassette 或摘要 |
| 脱敏失败不污染记录状态 | `session_test.mbt` | 交互数保持为零 |
| replay 命中不调用 transport、strict-offline 不回退网络 | `reliability_test.mbt`、`session_test.mbt` | 脚本 transport 余量不变 |
| cassette 编码/解码稳定性 | `reliability_test.mbt` | 重复编码文本一致 |
| 少调用/全部消费断言 | `session_test.mbt`、native replay demo | `assert_complete` 给出剩余数量 |
| 状态码、必需 header、header 值、body、必需/可选 JSON 字段和数组元素契约 | `contract_test.mbt` | 结构化违约，且摘要不含业务原文 |
| 文件大小上限和原子归档 | `native/archive_test.mbt` | 超限拒绝，成功写入可重新加载 |
| 跨进程录制→文件→离线回放 | `cmd/moonvcr-native-record`、`cmd/moonvcr-native-replay` | 第二个进程输出 offline status=200 |

## 验收边界

本版本验证的是显式 transport 接入的录制、确定性回放、严格离线、响应契约和 native 文件/HTTP 适配。它不宣称 TLS MITM、系统代理、浏览器录制、自动拦截任意进程流量或完整 OpenAPI/JSON Schema；这些能力不属于本版本范围。

## 安全与开源检查

`MoonVCR_submission.md` 含个人联系方式，只保存在本地并被 `.gitignore` 排除。发布前必须再次检查：

```text
moon package --list
git status --short --branch
git diff --check
```

包清单不得包含报名材料或真实凭据；依赖 `moonbitlang/async@0.22.1` 通过 manifest 固定版本，根项目仍使用 Apache-2.0。
