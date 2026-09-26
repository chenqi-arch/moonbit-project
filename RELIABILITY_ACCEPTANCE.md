# MoonVCR 可靠性测试与验收说明

本文件把可靠性目标映射到可运行测试和故障门禁。测试数量只用于核对执行完整性，不能代替逐项行为验收。

## 核心验收命令

```text
moon fmt --check
moon check
moon build
moon test
moon run cmd/moonvcr-demo
moon run cmd/moonvcr-pagination
moon run cmd/moonvcr-order-contract
moon run cmd/moonvcr-restricted-ci
moon package --list
git diff --check
```

故障命令必须非零：

```text
moon run cmd/moonvcr-pagination-failure
moon run cmd/moonvcr-order-contract-failure
moon run cmd/moonvcr-restricted-ci-failure
```

## 核心矩阵

| 验收项 | 证据位置 | 通过标准 |
| --- | --- | --- |
| 匹配键无分隔符碰撞 | `normalize_test.mbt`、`matcher_test.mbt` | 结构不同的请求不能误命中 |
| query/header 重复、空值、Unicode | `normalize_test.mbt` | 正反例行为固定 |
| ReplayMiss 不泄露完整 key | `session_test.mbt`、`reliability_test.mbt` | error/summary 无植入秘密 |
| URL 用户信息、fragment、编码参数脱敏 | `redact_test.mbt` | cassette 无秘密原文 |
| 请求/响应独立规则、必填/可选规则 | `redact_test.mbt`、`session_test.mbt` | 跨侧字段不误报，必填失败不追加 |
| Session 输入/输出快照隔离 | `session_test.mbt` | 外部修改不改变既定回放 |
| 重复消费、多/少调用、完整消费 | `session_test.mbt` | 错误不误消费，`assert_complete` 可阻断 |
| 状态/header 值/body/JSON/数组契约 | `contract_test.mbt` | 正例有效，负例路径与类型明确 |
| 诊断和契约摘要不带原文 | `diagnostics_test.mbt`、`contract_test.mbt` | 仅输出安全描述 |
| 三业务场景 | `cmd/moonvcr-*` | 成功命令为零，故障命令非零 |
| 受限网络不调用 transport | `cmd/moonvcr-restricted-ci` | 输出 `network_calls=0` |
| 100/1,000/10,000 条容量 | `capacity_test.mbt` | 编码、解码、末项回放均成功 |

## Native IO 矩阵

Ubuntu CI 的 native job 执行：

1. `moon check --target native`、`moon build --target native`、`moon test --target native --serial`；
2. 启动 `cmd/moonvcr-loopback-server`；
3. `cmd/moonvcr-native-http-acceptance` 验证 GET、POST、请求/响应 header、JSON、非法 UTF-8 字节转 Base64、连接失败、超时、503 和 302；
4. `cmd/moonvcr-native-record` 通过真实 HTTP 录制两条交互、脱敏并保存；
5. 关闭 loopback 服务并确认端口不可达；
6. 新进程运行 `cmd/moonvcr-native-replay`，加载文件、离线回放、检查订单契约和完整消费；
7. `/usr/bin/time -v` 记录容量用例的实际时间与最大常驻内存。

文件层测试覆盖：缺失文件、负大小限制、过大输入、损坏 JSON、未知格式版本、默认禁止覆盖、临时文件冲突保护和显式替换。失败路径必须保持已有目标文件不变。

## 容量说明

Windows 本地 wasm 单独运行 100/1,000/10,000 条容量用例为 3/3 通过；2026-09-26 一次测量墙钟约 559 ms，包含测试进程启动开销。该数字只描述当次机器与工具链，不是性能承诺。最终时间与最大常驻内存以冻结提交的 Ubuntu CI `/usr/bin/time -v` 输出为准。

建议默认单 cassette 不超过 10 MB；10,000 条是本轮验收规模，不表示无限扩展。matcher 是线性候选扫描，大型套件应按服务、资源或测试域拆分 cassette。

## 平台边界

- 核心 wasm：Windows 本地与 Ubuntu CI；
- native HTTP/文件 IO：Ubuntu CI；
- Windows native：当前仅类型检查，因为本机没有 C 编译器，不宣称运行支持；
- 外部互联网：集成验收只访问 `127.0.0.1`，不依赖第三方服务；
- TLS：不关闭官方客户端证书验证；本轮 loopback 使用 HTTP，未把本地 HTTP 当作 TLS 验证证据。

## 安全与发布检查

- `MoonVCR_submission.md` 被 `.gitignore` 排除；
- `moon package --list` 不得包含报名材料或个人联系方式；
- 测试只含合成凭据，且最终录制文件会搜索确保秘密原文为零；
- 依赖与许可证见 `THIRD_PARTY_NOTICES.md`；
- 最终证据状态见 `FINAL_ACCEPTANCE.md`。
