# MoonVCR

MoonVCR 是一个 MoonBit 原生的 HTTP 交互录制、回放与离线契约测试库。它把调用方明确交给它的请求和响应保存为可审阅的 JSON cassette，在开发机和 CI 中按稳定规则回放，并在接口变化时给出不泄露业务数据的差异报告。

它解决的是一个很具体的问题：SDK、内部服务和第三方 API 的回归测试不应该依赖实时网络，也不应该把真实凭据和不稳定响应带进 CI。MoonVCR 不会偷偷拦截系统流量，调用方必须显式提供 transport，因此网络边界和测试数据来源是可审计的。

## 当前版本交付范围

- MoonBit 核心模型：`Request`、`Response`、`Interaction`、版本化 `Cassette` 以及确定性 JSON 编解码。
- 确定性匹配：规范化方法、URL/query、选定请求头和文本/Base64 body；支持按 cassette 顺序消费重复请求。
- 三种会话：`Record`、`Replay`、`StrictOffline`。严格离线未命中时直接返回错误，不会回退到网络。
- 数据安全：默认清理常见凭据、敏感 query 和 JSON 路径；URL 用户信息也会被清理；脱敏失败时不写入 cassette。
- 安全诊断：候选摘要只输出字段类型、长度和指纹，不复制未知 header、body 或凭据原文。
- 响应契约：状态码、必需响应头、响应头精确值、body 表示类型、必需/可选 JSON 字段和数组直接元素类型校验；报告提供稳定顺序和安全摘要。
- 原生适配层：基于 MoonBit 官方 `moonbitlang/async` 的 HTTP 请求适配器，以及带大小上限、同步临时文件和显式覆盖语义的 cassette 文件归档器。
- 可验证样例：可离线运行的核心 demo、原生文件归档 demo、核心回归测试和 GitHub Actions 双目标 CI。

明确不在本版本范围内：TLS MITM、系统代理、浏览器自动注入、任意进程流量拦截和完整 OpenAPI/JSON Schema 生成。这些能力会扩大权限边界，不属于当前库的可审计核心。

## 安装

发布 `0.3.0` 后，在 MoonBit 项目中添加：

```text
moon add chenqi-arch/moonbit-project@0.3.0
```

核心包默认不依赖网络或文件系统，适合 wasm 和纯离线测试。需要真实 HTTP 或 cassette 文件时，再显式导入 native 子包；它依赖 MoonBit 官方异步库并只支持 native 目标。

## 最小离线回放

```mbt
import { "chenqi-arch/moonbit-project" @moonvcr, }

let cassette = @moonvcr.Cassette::decode(cassette_text)
let session = @moonvcr.Session::with_defaults(
  cassette,
  @moonvcr.SessionMode::StrictOffline,
)
let offline_transport = (_ : @moonvcr.Request) => {
  Err(@moonvcr.TransportError::Failed("network disabled"))
}
let response = session.send(request, offline_transport)
```

`StrictOffline` 只读取内存中的 cassette。回放未命中会得到 `ReplayMiss`，不会调用传入的 transport，更不会暗中访问网络。需要确认 cassette 已全部消费时，可调用 `session.assert_complete()`。

## 显式录制

核心库不替调用方选择 HTTP 客户端：

```mbt
let session = @moonvcr.Session::with_defaults(
  @moonvcr.Cassette::empty(),
  @moonvcr.SessionMode::Record,
)
let response = session.send(request, request => http_client_send(request))
let cassette_text = @moonvcr.Cassette::encode(session.cassette())
```

异步 HTTP 客户端可以把响应交给 `session.record_response(request, response)`；这样异步 I/O 和可移植核心仍然分层，测试可以只替换 transport。

## 原生 HTTP 与文件归档

```mbt
import {
  "chenqi-arch/moonbit-project" @moonvcr,
  "chenqi-arch/moonbit-project/native" @moonvcr_native,
}

let response = @moonvcr_native.record_http(session, request)
@moonvcr_native.save_cassette_new("fixtures/items.json", session.cassette())
let restored = @moonvcr_native.load_cassette_default("fixtures/items.json")
```

原生归档器默认限制 cassette 为 10 MB，先写入同目录临时文件并同步，再执行不覆盖重命名；`save_cassette_replace` 才会显式替换已有文件。HTTP 适配器支持标准方法、请求头、文本和 Base64 body，并将响应转回 MoonVCR 模型。底层网络错误不会把 URL 或凭据带进公开错误摘要。

原生边界的完整说明见 [`native/README.md`](native/README.md)。

## 响应契约

契约用于回答“回放响应是否仍满足接口约定”，不是替代完整 OpenAPI 校验：

```mbt
let contract : @moonvcr.ResponseContract = {
  allowed_statuses: [200],
  required_headers: ["content-type"],
  required_header_values: [
    { name: "content-type", expected_value: "application/json", },
  ],
  body_kind: Some(@moonvcr.ContractBodyKind::ExpectTextBody),
  json_fields: [
    {
      path: "/items",
      expected_kind: @moonvcr.JsonValueKind::JsonArray,
    },
  ],
  optional_json_fields: [
    {
      path: "/next_page",
      expected_kind: @moonvcr.JsonValueKind::JsonString,
    },
  ],
  json_array_elements: [
    {
      path: "/items",
      expected_kind: @moonvcr.JsonValueKind::JsonObject,
    },
  ],
}
let report = response.validate_contract(contract)
if !report.is_valid() {
  println(report.summary())
}
```

契约差异会区分状态码、缺失 header、header 值、body 类型、非法 JSON、缺失字段和 JSON 类型错误。`optional_json_fields` 允许字段缺席，但字段出现时仍必须满足类型；`json_array_elements` 校验数组中每个直接元素的类型。报告只展示 header 值的长度和稳定指纹，不展示 header 原文或 JSON 值。

## 三个实际使用场景

1. **SDK 回归**：录制经过审查和脱敏的第三方 API 响应，后续每次 SDK 改动都在 `StrictOffline` 中重复验证，不受供应商限流和数据波动影响。
2. **CI 无网回归**：CI 只加载仓库内 cassette，未命中立即失败；`assert_complete` 还能发现测试漏掉了 cassette 中的交互。
3. **接口契约变更**：旧 cassette 回放后执行 `validate_contract`，可在合并请求中定位状态码、必需 header、body 或 JSON 字段类型变化。

## 验证

核心目标（默认 portable/wasm）：

```text
moon fmt --check
moon check
moon build
moon test
moon run cmd/moonvcr-demo
moon package --list
```

原生目标（CI 在 Ubuntu 上执行）：

```text
moon check --target native
moon build --target native
moon test --target native
moon run --target native cmd/moonvcr-native-demo
moon run --target native cmd/moonvcr-native-record
moon run --target native cmd/moonvcr-native-replay
```

原生 demo 的稳定输出是 `native archive roundtrip interactions=1`；随后两个独立进程分别输出 `native record saved interactions=1` 和 `native replay offline status=200`。当前核心回归套件包含 68 个测试；GitHub Actions 同时检查 portable 和 native 目标。Windows 本地执行 native build/test 需要安装可用的 C 编译器，缺少编译器时仍可运行所有核心检查和测试。

## 开源信息

- GitHub：<https://github.com/chenqi-arch/moonbit-project>
- Mooncakes 模块：`chenqi-arch/moonbit-project`
- 许可证：Apache License 2.0，见 [`LICENSE`](LICENSE)
- 设计、需求和任务记录：[`specs/moonvcr-final/`](specs/moonvcr-final/)
- 发布与验收记录：[`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md)、[`RELIABILITY_ACCEPTANCE.md`](RELIABILITY_ACCEPTANCE.md)
