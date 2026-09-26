# MoonVCR

**MoonVCR：MoonBit HTTP 交互录制回放与离线契约测试库**

MoonVCR 把经过允许的 HTTP 请求和响应保存为可审阅的 JSON cassette，随后在开发机或 CI 中严格离线回放。它解决 SDK、内部 API 和服务端测试依赖真实网络、第三方服务不稳定、测试凭据容易泄露、接口变更难定位的问题。

项目由两层组成：

- 无 IO 核心：数据模型、确定性匹配、Record/Replay/StrictOffline 会话、脱敏、诊断和响应契约，可在 wasm 环境运行；
- `native` 适配层：基于官方 `moonbitlang/async` 的真实 HTTP 客户端和 cassette 文件读写，当前由 Ubuntu GitHub CI 验证。

MoonVCR 不拦截系统流量。录制只会调用使用者显式选择的 transport；Replay 和 StrictOffline 不会回退联网。

## 当前状态

- Mooncakes 已发布稳定基线：`chenqi-arch/moonbit-project@0.2.0`；
- 仓库 `main` 是终审候选开发线，包含真实 loopback HTTP、文件档案、独立请求/响应脱敏、增强契约和三组验收场景；
- 候选版完成全部验收后再冻结新版本号和发布，未发布能力不能通过 `0.2.0` 安装获得。

## 已实现能力

- 版本化 Request、Response、Interaction 和 Cassette 模型；
- 确定性 JSON 编解码，拒绝损坏 JSON、错误结构和未知格式版本；
- 方法、URL/query、选定 header 和 body 的确定性匹配；
- 无分隔符歧义的长度编码匹配键，以及重复交互按顺序消费；
- Record、Replay、StrictOffline 会话，剩余交互计数和完整消费断言；
- URL 用户信息、fragment、百分号编码敏感参数、常见敏感 header/query 脱敏；
- 请求与响应独立的必填/可选 JSON 路径脱敏，失败时不写入 cassette；
- 不暴露请求、响应和凭据原文的 replay miss、mismatch 与契约摘要；
- 状态码、header 存在性/精确值、body 类型、必填/可选 JSON 字段和数组元素契约；
- native 真实 HTTP GET/POST、header、JSON、二进制 body、连接失败和超时转换；
- native cassette 大小限制、默认禁止覆盖、显式替换、同目录临时文件和同步写入；
- 分页 SDK、订单兼容性、受限网络 CI 三组成功与故障场景；
- 100、1,000、10,000 条交互的确定性容量验收。

## 安装

已发布稳定版：

```text
moon add chenqi-arch/moonbit-project@0.2.0
```

当前终审候选仍从本仓库验证，待所有门禁通过后再发布新的 Mooncakes 版本。不要把仓库 `main` 的候选能力误写成 `0.2.0` 已发布能力。

## 核心快速开始

```mbt
import { "chenqi-arch/moonbit-project" @moonvcr, }

let cassette = @moonvcr.Cassette::decode(cassette_text)
let session = @moonvcr.Session::with_defaults(
  cassette,
  @moonvcr.StrictOffline,
)
let response = match session.replay(request) {
  Ok(response) => response
  Err(error) => abort(error.summary())
}
match session.assert_complete() {
  Ok(_) => ()
  Err(error) => abort(error.summary())
}
```

`Session::replay` 没有 transport 参数，因此不具备联网回退路径。需要与既有同步 transport 兼容时可使用 `Session::send`；Replay/StrictOffline 分支仍不调用 transport。

## 显式录制与脱敏

```mbt
let request_rules = RedactionConfig::default()
request_rules.json_paths.push("/credentials/token")
let response_rules = RedactionConfig::default()
response_rules.optional_json_paths.push("/session/token")

let session = Session::new_with_redaction_policy(
  Cassette::empty(),
  Record,
  MatchConfig::default(),
  { request: request_rules, response: response_rules, },
)
let result = session.record_response(request, response)
let text = session.cassette().encode()
```

`json_paths` 是必填规则：路径缺失、路径非法或 body 不是有效 JSON 时失败关闭，当前交互不会写入 cassette。`optional_json_paths` 在字段不存在时跳过，但路径非法和 JSON 非法仍失败。未知业务敏感字段不会被自动猜测，必须显式配置。

## 响应契约

```mbt
let contract : ResponseContract = {
  allowed_statuses: [200, 201],
  required_headers: ["content-type"],
  required_header_values: [
    { name: "content-type", expected_value: "application/json", },
  ],
  body_kind: Some(ExpectTextBody),
  json_fields: [{ path: "/id", expected_kind: JsonNumber, }],
  optional_json_fields: [{ path: "/note", expected_kind: JsonString, }],
  json_array_elements: [{ path: "/items", expected_kind: JsonObject, }],
}
let report = response.validate_contract(contract)
guard report.is_valid() else { abort(report.summary()) }
```

报告只包含规则、路径、类型和不可逆短摘要，不复制业务原文。该能力是面向 cassette 的小型确定性检查，不是完整 OpenAPI/JSON Schema 实现，也不会自动监测未录制的线上变化。

## Native HTTP 与文件档案

候选版的 `native` 包使用 `moonbitlang/async@0.22.1`：

```mbt
let response = @native.send_http_with_timeout(request, 2_000)
let recorded = @native.record_http(session, request, timeout_millis=2_000)
@native.save_cassette_new("fixtures/orders.json", session.cassette())
let cassette = @native.load_cassette_default("fixtures/orders.json")
```

- 超时、连接/协议失败、非法方法和非法 body 被转换为不含 URL/凭据的安全错误；
- 非 2xx 和 3xx 原样返回给业务契约判断；
- TLS 证书验证使用官方客户端默认值，没有“关闭证书验证”选项；
- 不承诺自动跟随重定向，验收固定检查 302 保持为 302；
- `save_cassette_new` 默认拒绝覆盖，`save_cassette_replace` 才允许显式替换；
- 默认加载上限为 10 MB，超限在 JSON 解码前拒绝。

## 可运行场景

成功场景：

```text
moon run cmd/moonvcr-pagination
moon run cmd/moonvcr-order-contract
moon run cmd/moonvcr-restricted-ci
```

预期输出：

```text
pagination SDK offline regression passed pages=2
order compatibility contract passed status headers JSON array optional-field
restricted-network CI passed network_calls=0
```

故障场景必须返回非零：

```text
moon run cmd/moonvcr-pagination-failure
moon run cmd/moonvcr-order-contract-failure
moon run cmd/moonvcr-restricted-ci-failure
```

它们分别证明请求变化会 ReplayMiss、订单字段/header 违约会阻断、严格离线未命中不会调用 transport。

## 验收命令

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
```

native 真 HTTP 验收由 GitHub Ubuntu CI 自动完成：启动 MoonBit loopback 服务，验证 GET、POST、header、JSON、二进制、超时、连接失败、非 2xx 和 302；随后真实录制并保存 cassette，关闭服务，再由新进程加载并严格离线回放。

详细矩阵见 [RELIABILITY_ACCEPTANCE.md](RELIABILITY_ACCEPTANCE.md) 和 [FINAL_ACCEPTANCE.md](FINAL_ACCEPTANCE.md)。

## 支持矩阵

| 能力 | wasm（Windows 本地已验证） | Linux native（GitHub CI） | Windows native |
| --- | --- | --- | --- |
| 核心模型/匹配/会话/脱敏/契约 | 支持 | 支持 | 类型检查通过 |
| 内存与脚本 transport | 支持 | 支持 | 类型检查通过 |
| 官方 async HTTP + 文件 IO | 不适用 | 支持并集成验收 | 未声明运行支持 |
| 跨进程文件回放 | 不适用 | 支持并集成验收 | 未声明运行支持 |

本机 Windows 缺少 C 编译器，因此只完成 native 类型检查；运行支持只声明 CI 实测的 Ubuntu。JS/Node、macOS 和 Windows native 当前不列为已支持。

## 主要 API

- `Cassette::empty/decode/encode`
- `MatchConfig::default`
- `RedactionConfig::default`、`RedactionPolicy::default/symmetric`
- `Session::with_defaults/new/new_with_redaction/new_with_redaction_policy`
- `Session::send/record_response/replay/diagnose/cassette`
- `Session::remaining_interactions/assert_complete`
- `Response::validate_contract`、`ContractReport::is_valid/summary`
- `ScriptedTransport::new/send/remaining`
- native：`send_http/send_http_with_timeout/record_http`
- native：`load_cassette/load_cassette_default/save_cassette_new/save_cassette_replace`

编译器生成的完整接口以 `pkg.generated.mbti` 和 `native/pkg.generated.mbti` 为准。

## 故障排查

- `ReplayMiss`：调用 `session.diagnose(request)`；检查 URL/query、选定 header、body 策略和重复调用次数；
- `IncompleteReplay`：有录制交互未被业务流程消费；
- `RedactionFailed`：必填 JSON 路径缺失、路径无效或 body 不是 JSON；
- `HTTP request timed out`：增大明确期限或排查服务延迟；
- `cassette JSON decode failed`：检查文件是否截断、结构和格式版本；
- native 构建提示无 C 编译器：安装受支持的 C 工具链，或使用 Ubuntu CI 验收。

## 边界与限制

- 不做 TLS MITM、系统代理、浏览器录制或任意进程流量拦截；
- 不自动发现所有业务敏感字段；
- 不实现完整 OpenAPI/JSON Schema；
- cassette 默认加载上限 10 MB，容量验收覆盖到 10,000 条，不承诺无限规模；
- matcher 为确定性线性候选扫描，大 cassette 应按服务或测试套件拆分；
- 并发共享同一个可变 Session 不在当前保证范围内；
- `moonbitlang/async` API 仍可能变化，依赖版本被固定并由 CI 验证。

## 开源与安全

MoonVCR 使用 Apache License 2.0。依赖来源和许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，安全边界见 [SECURITY.md](SECURITY.md)，参与开发见 [CONTRIBUTING.md](CONTRIBUTING.md)，版本变化见 [CHANGELOG.md](CHANGELOG.md) 和 [MIGRATION.md](MIGRATION.md)。

所有示例均使用合成域名和合成凭据。`MoonVCR_submission.md` 含赛事联系方式，只保存在本地并被 Git 与发布包排除。
