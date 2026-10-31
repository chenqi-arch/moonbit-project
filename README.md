# MoonVCR

**MoonVCR：MoonBit HTTP 交互录制回放与离线契约测试库**

MoonVCR 把经过允许的 HTTP 请求和响应保存为可审阅的 JSON cassette，随后在开发机或 CI 中严格离线回放。它解决 SDK、内部 API 和服务端测试依赖真实网络、第三方服务不稳定、测试凭据容易泄露、接口变更难定位的问题。

项目由两层组成：

- 无 IO 核心：数据模型、确定性匹配、Record/Replay/StrictOffline 会话、脱敏、诊断和响应契约，可在 wasm 环境运行；
- `native` 适配层：基于官方 `moonbitlang/async` 的真实 HTTP 客户端和 cassette 文件读写，当前由 Ubuntu GitHub CI 验证。

MoonVCR 不拦截系统流量。录制只会调用使用者显式选择的 transport；Replay 和 StrictOffline 不会回退联网。

## 当前状态

- 当前源码修复版本：`0.3.2`；发布状态与对应 SHA/CI 证据见 `FINAL_ACCEPTANCE.md`；
- `0.3.1` 及更早版本存在已确认的脱敏绕过或错误匹配，不能依据旧 CI 全绿认定安全；请升级并审阅重录旧档案；
- `0.3.2` 对独立审核发现的七类问题补充修复，包括精确 JSON 路径、重复参数顺序、native 头信息、有界文件读取和诊断一致性；逐项说明见 `AUDIT_REMEDIATION_0.3.2.md`，兼容行为见 `MIGRATION.md`。

## 已实现能力

- 版本化 Request、Response、Interaction 和 Cassette 模型；
- 确定性 JSON 编解码，拒绝损坏 JSON、错误结构和未知格式版本；
- 方法、URL/query、选定 header 和 body 的确定性匹配；
- 无分隔符歧义的长度编码匹配键，以及重复交互按顺序消费；
- Record、Replay、StrictOffline 会话，剩余交互计数和完整消费断言；
- URL 用户信息、fragment、百分号编码敏感参数、常见敏感 header/query 脱敏；
- 请求与响应独立的必填/可选 JSON 路径脱敏，失败时不写入 cassette；
- 不直接回显请求/响应值的 replay miss 与 mismatch；契约报告包含配置的规则和字段路径，不应在这些名称中配置凭据；
- 状态码、header 存在性/精确值、body 类型、必填/可选 JSON 字段和数组元素契约；
- native 真实 HTTP GET/POST、header、JSON、二进制 body、连接失败和超时转换；
- native cassette 大小限制、默认禁止覆盖、显式替换、同目录临时文件和同步写入；
- 分页 SDK、订单兼容性、受限网络 CI 三组成功与故障场景；
- 100、1,000、10,000 条交互的确定性容量验收。

## 安装

要求 MoonBit 编译器 `moonc >= 0.10.14`。先运行 `moon version --all`，注意核对其中的 `moonc` 行；工具链过旧时运行 `moon upgrade`。CI 在检查和 native 两个作业开始时都会执行最低版本门禁。

安装 0.3.2（正式发布状态以 `FINAL_ACCEPTANCE.md` 为准）：

```text
moon add chenqi-arch/moonbit-project@0.3.2
```

Mooncakes 发布包、Git 标签和 GitHub 验收证据见 `FINAL_ACCEPTANCE.md`。

最新赛事九项标准与证据逐条对应见 `COMPETITION_ACCEPTANCE.md`。PowerShell 下可运行 `./scripts/check-toolchain.ps1` 核对最低编译器版本，运行 `./scripts/verify-public-consumer.ps1` 自动复现下述快速开始；两个脚本也由 Ubuntu CI 执行。

## 核心快速开始

下面是可以完整运行的独立消费者。先用 `moon new moonvcr-consumer` 创建项目，在该目录运行上面的 `moon add` 命令。将 `cmd/main/moon.pkg` 改为：

```text
import {
  "chenqi-arch/moonbit-project" @moonvcr,
}

pkgtype(kind: "executable")
```

将 `cmd/main/main.mbt` 改为：

```mbt
fn main {
  let cassette_text = @moonvcr.Cassette::encode(@moonvcr.example_cassette())
  let cassette = @moonvcr.Cassette::decode(cassette_text) catch {
    _ => abort("cassette decode failed")
  }
  let request : @moonvcr.Request = {
    method: "GET",
    url: "https://api.example.test/v1/items?page=1",
    headers: [{ name: "accept", value: "application/json", }],
    body: @moonvcr.Empty,
  }
  let session = @moonvcr.Session::with_defaults(
    cassette,
    @moonvcr.StrictOffline,
  )
  let response = match session.replay(request) {
    Ok(response) => response
    Err(error) => abort(error.summary())
  }
  guard response.status == 200 else { abort("unexpected status") }
  match session.assert_complete() {
    Ok(_) => ()
    Err(error) => abort(error.summary())
  }
  println("offline consumer passed status=200")
}
```

运行 `moon check`、`moon build`、`moon run cmd/main`，应输出 `offline consumer passed status=200`。该示例使用内存档案，合成域名不会被访问。

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

`json_paths` 是必填规则：路径缺失、路径非法或 body 不是有效 Text JSON 时失败关闭，当前交互不会写入 cassette。`optional_json_paths` 只允许有效 Text JSON 中的字段缺失；它不允许 Empty、Base64、损坏 JSON 或非法路径绕过检查。任一 JSON 规则存在时，非 Text Body 一律拒绝，不会尝试猜测解码。未配置 JSON 规则时，Empty/Text/Base64 仍按原样保留，默认不会自动识别 Body 内的秘密。

GET 空 Body 与 POST JSON 应使用独立的请求/响应策略和会话，不能把 POST 的必填路径直接套在空 GET 请求上。完整真实示例见 `cmd/moonvcr-native-record`。录制成功仍把原始响应交给调用方业务代码，脱敏保护的是保存的副本。

query 名称单次 UTF-8 百分号解码后转小写；URL 原始 `+` 视为空格，`%2B` 视为字面加号，自定义规则中的 `+` 按字面解释。无效编码保持原样，不递归解码。URL fragment 完全丢弃，userinfo 全部替换。

JSON Pointer 路径必须原文以 `/` 开始，键中的空格、Tab、换行和 `~0/~1` 转义精确保留；只有 dot shorthand 会裁剪格式空白。本库支持字段寻址子集，空字符串根路径不支持，`/` 可以定位空对象键。数组只接受 `0` 或无前导零的十进制索引；对象键 `"01"` 仍合法。必填/可选规则先在原始 JSON 上验证，再按深度从深到浅覆盖，父子重叠规则不受配置次序影响。

匹配允许不同 query 名称、不同 header 名称换序，但保留每个同名组内部的值顺序；同名 query 的编码别名也归到同组。query 值不裁剪空白。不同名称之间的全局顺序不参与匹配；依赖该顺序的接口不在当前匹配策略范围内。原始百分号拼写仍参与最终匹配，等价编码可能保守地未命中。

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

报告包含规则、路径、类型、长度和非密码学短指纹，不复制响应值。指纹可被枚举，不提供加密或匿名化保证；不要公开含敏感结构信息的诊断。该能力是面向 cassette 的小型确定性检查，不是完整 OpenAPI/JSON Schema 实现，也不会自动监测未录制的线上变化。

## Native HTTP 与文件档案

已发布的 `native` 包使用 `moonbitlang/async@0.22.1`；以下为异步函数内的 API 片段，完整入口见 `cmd/moonvcr-native-record` 与 `cmd/moonvcr-native-replay`：

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
- native 底层头部 Map 无法无损发送重复请求头，因此同名请求头（大小写不敏感）会在发网前返回 `UnsupportedDuplicateHeaders`，不能静默覆盖；
- 原始业务响应保留各个 `Set-Cookie` 及公开解析属性；按依赖解析结果规范化重建，不保证 HTTP 字节拼写。录制副本才按规则逐条脱敏；
- `save_cassette_new` 默认拒绝覆盖，`save_cassette_replace` 才允许显式替换；
- 默认加载上限为 10 MB，同一打开句柄最多读取上限加一字节，在 UTF-8/JSON 解码前拒绝超限；文件增长/路径替换不绕过读取预算。`TooLarge(n)` 的 n 是观察到的字节数下界，不是完整文件大小。

`record_response` 只允许 Record 模式；其他模式返回 `InvalidMode`。`native.record_http` 遇到 Replay/StrictOffline 时直接离线回放，不执行 HTTP；显式 `send_http` 仍是调用方主动请求网络的入口。

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
moon run cmd/moonvcr-security-acceptance
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

完整接口可用 `moon info --target native` 生成；根包接口 `pkg.generated.mbti` 保存在仓库中。Session 内部字段私有，请用 `cassette()` 取得隔离副本，用 `mode()` 查看模式。

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
- native HTTP 当前使用依赖的完整响应 API，没有响应字节数硬上限；只应对可信、大小受控的服务录制，cassette 文件上限不约束网络响应大小；
- `Cassette::encode`、文件保存和手工构造的 Request/Response 不是自动脱敏入口；应通过 Record 会话录制、审阅副本后保存，不能直接序列化原始数据；
- 不实现完整 OpenAPI/JSON Schema；
- cassette 默认加载上限 10 MB，容量验收覆盖到 10,000 条，不承诺无限规模；
- matcher 为确定性线性候选扫描，大 cassette 应按服务或测试套件拆分；
- 并发共享同一个可变 Session 不在当前保证范围内；
- `moonbitlang/async` API 仍可能变化，依赖版本被固定并由 CI 验证。

## 开源与安全

MoonVCR 使用 Apache License 2.0。依赖来源和许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，安全边界见 [SECURITY.md](SECURITY.md)，参与开发见 [CONTRIBUTING.md](CONTRIBUTING.md)，版本变化见 [CHANGELOG.md](CHANGELOG.md) 和 [MIGRATION.md](MIGRATION.md)。

所有示例均使用合成域名和合成凭据。`MoonVCR_submission.md` 含赛事联系方式，只保存在本地并被 Git 与发布包排除。
