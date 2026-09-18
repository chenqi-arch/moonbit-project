# MoonVCR 可靠性测试与验收说明

这份文档把初审意见中的“可靠性相关测试项和验收说明”映射到仓库中的可运行测试。所有测试使用内存数据或 `ScriptedTransport`，不访问外部网络，也不依赖本地文件系统。

## 验收命令

在仓库根目录执行：

~~~text
moon fmt --check
moon check
moon build
moon test
moon run cmd/moonvcr-demo
moon package --list
git diff --check
~~~

预期结果：格式、检查、构建和打包命令成功；`moon test` 输出 `Total tests: 59, passed: 59, failed: 0.`；演示输出包含 `offline replay status=200` 和 `recorded interactions=1`。

## 测试矩阵

| 验收项 | 测试位置 | 可观察结果 |
| --- | --- | --- |
| 状态码、必要响应头、body 类型和 JSON 字段类型均可通过 | `contract_test.mbt` | 契约报告有效 |
| 状态码、缺少响应头、body 类型、无效 JSON、字段缺失和字段类型错误可定位 | `contract_test.mbt` | 结构化违约，路径和类型明确 |
| 违约摘要顺序稳定 | `contract_test.mbt` | 同一输入得到相同摘要 |
| replay 命中不调用 transport | `reliability_test.mbt` | transport 脚本余量保持不变 |
| strict-offline 未命中不回退联网 | `reliability_test.mbt` | 返回 `ReplayMiss`，transport 余量保持不变 |
| cassette 编码/解码重复 100 次保持稳定 | `reliability_test.mbt` | 每次编码文本完全一致 |
| record → encode → decode → replay → contract 校验闭环 | `reliability_test.mbt` | 回放返回录制响应，契约有效，replay transport 为零 |
| 凭据不进入 cassette | `reliability_test.mbt` | URL、请求头、请求体和响应体中的敏感值均不存在 |
| mismatch 和契约摘要不泄露原文 | `reliability_test.mbt`、`diagnostics_test.mbt` | 摘要不包含凭据、header 值或 body 值 |
| 脱敏失败不污染记录状态 | `session_test.mbt` | 返回 `RedactionFailed`，cassette 交互数仍为零 |

## 验收边界

本版本验证的是显式 transport 接入的录制、确定性回放、严格离线和 cassette 响应契约。它不宣称具备 TLS MITM、系统代理、浏览器录制或自动拦截任意进程流量；这些能力不属于本版本验收范围。

## 安全检查

`MoonVCR_submission.md` 是本地赛事材料，含个人联系方式，已加入 `.gitignore`，不应出现在 GitHub 提交或 Mooncakes 包清单中。发布前必须再次检查 `moon package --list` 和 `git status --short --branch`。
