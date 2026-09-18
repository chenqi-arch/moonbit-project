# MoonVCR

**MoonVCR：MoonBit HTTP 交互录制回放与离线契约测试库**

MoonVCR 将经过允许的 HTTP 请求与响应保存为可审阅的 cassette，并在开发和 CI 中离线回放。它面向需要稳定、可重复测试的 MoonBit SDK、服务端和内部 API。

0.2.0 整改版在 0.1.0 的基础上完成一条可运行的闭环：调用方显式提供 transport，MoonVCR 负责记录、脱敏、回放、响应契约校验和离线诊断。当前版本已经包含：

- 版本化的请求、响应、请求头、请求体、交互和 cassette 模型；
- 确定性 JSON 编码与解码；
- 未知 schema 版本和损坏 JSON 的类型化错误；
- URL、查询参数和请求头规范化，以及可配置的 body 匹配策略；
- 确定性 matcher、顺序消费和候选摘要；
- 显式 transport 的 record、replay 与 strict-offline 会话；
- 默认敏感头/查询参数清理，以及可配置 JSON Pointer/dot 路径清理；
- 不泄露原文的字段级 mismatch 诊断；
- 状态码、必要响应头、body 类型和 JSON 字段类型的响应契约校验；
- 有限响应脚本 transport 与无网络可运行示例；
- 无网络即可运行的核心测试。

## 安装与最小用法

Mooncakes `0.2.0` 已正式发布，可在你的 MoonBit 项目中直接添加：

~~~text
moon add chenqi-arch/moonbit-project@0.2.0
~~~

在代码中导入根包并创建会话：

~~~mbt
import { "chenqi-arch/moonbit-project" @moonvcr, }

let cassette = @moonvcr.Cassette::decode(cassette_text)
let session = @moonvcr.Session::with_defaults(
  cassette,
  @moonvcr.SessionMode::StrictOffline,
)
let result = session.send(
  request,
  offline_transport,
)
~~~

上面是 API 轮廓，cassette_text、request 和 offline_transport 由调用方提供；可直接运行的完整版本见 cmd/moonvcr-demo。回放只依赖内存中的 cassette 文本，不会因为回放未命中而偷偷联网。录制时则由调用方把现有 HTTP 客户端封装成 transport，并明确决定何时访问真实网络。

## 响应契约校验

回放得到的 `Response` 可以在不访问网络或文件系统的情况下执行契约校验。报告只返回规则路径、期望类型和实际类型，不复制响应头值、JSON 值或完整 body：

~~~mbt
let contract : @moonvcr.ResponseContract = {
  allowed_statuses: [200],
  required_headers: ["content-type"],
  body_kind: Some(@moonvcr.ContractBodyKind::ExpectTextBody),
  json_fields: [
    {
      path: "/items",
      expected_kind: @moonvcr.JsonValueKind::JsonArray,
    },
  ],
}
let report = response.validate_contract(contract)
if !report.is_valid() {
  println(report.summary())
}
~~~

契约校验适合放在 SDK 回归、接口升级和 CI 回放之后；它不是 OpenAPI 或完整 JSON Schema 实现，而是面向 cassette 的小型、确定性验收层。

## 本地验证

安装 MoonBit 工具链后，在仓库根目录运行：

```text
moon check
moon build
moon test
moon fmt --check
moon run cmd/moonvcr-demo
moon package --list
```

当前测试套件共 59 个测试：原有核心回归 42 个、响应契约测试 10 个、可靠性回归 7 个。命令示例会在 transport 被调用时主动失败；成功输出 `offline replay status=200` 即证明
strict-offline 回放没有触网。cassette 是纯文本 JSON，变更可以通过 Git 逐行审阅。
record 模式只调用调用方显式传入的 transport，replay 和 strict-offline 模式不会调用
transport；核心库不拦截系统流量，也不会暗中联网。

可靠性测试矩阵和可复制的验收结果见 [RELIABILITY_ACCEPTANCE.md](RELIABILITY_ACCEPTANCE.md)。

## 最小内存回放

回放不需要网络或文件系统，调用方可以把 cassette 文本交给 `Cassette::decode`，再创建 `Replay` 会话：

```mbt
let cassette = Cassette::decode(cassette_text)
let session = Session::with_defaults(cassette, Replay)
let offline_transport = (_ : Request) => {
  Err(TransportError::Failed("network disabled"))
}
let response = session.send(request, offline_transport)
```

匹配会规范化方法、URL/query、选定的 header 和 body，并按 cassette 顺序消费重复请求。未命中返回 `SessionError::ReplayMiss`，而不是尝试访问网络。

## 项目边界

MoonVCR 是原创 MoonBit 实现，不机械移植其他语言的 VCR 源码。项目借鉴 HTTP 录制/回放工具的通用思想，但会保持自己的数据结构、匹配语义和 MoonBit API。第一版不实现 TLS MITM、系统代理或自动拦截任意进程流量。录制前仍应审核请求和响应中是否存在个人数据；默认脱敏器会优先清理常见凭据，业务专用字段请通过 RedactionConfig 显式配置。

## 显式录制

MoonVCR 不会自行拦截网络。调用方把已有 HTTP 客户端封装成 transport，再交给 Record
会话；transport 收到的是真实请求，cassette 中保存的是脱敏副本：

~~~mbt
let session = Session::with_defaults(Cassette::empty(), Record)
let transport = (request : Request) => {
  // 在这里调用你的 HTTP 客户端，并转换成 Response。
  http_client_send(request)
}
let response = session.send(request, transport)
let cassette_text = Cassette::encode(session.cassette())
~~~

如果暂时没有 HTTP 客户端，可以用仓库自带的有限响应适配器做确定性测试：

~~~mbt
let scripted = ScriptedTransport::new([
  { status: 200, headers: [], body: Text("ok"), },
])
let session = Session::with_defaults(Cassette::empty(), Record)
let response = session.send(request, (request) => scripted.send(request))
~~~

RedactionConfig::default() 会清理常见 Authorization、Cookie、API key、token 和签名字段。
还可以在 json_paths 中配置 /credentials/token 或 credentials.token；配置路径缺失或
JSON 无效时返回 SessionError::RedactionFailed，该交互不会写入 cassette。

## 诊断与安全

未命中返回 SessionError::ReplayMiss，而不是尝试访问网络。需要查看原因时，可以在同一个
会话上调用 session.diagnose(request)。摘要只包含字段类型、长度和指纹，不包含未知 header、
body 或凭据原文。运行仓库中的离线复现命令：

~~~text
moon run cmd/moonvcr-demo
~~~

## 许可证

Apache License 2.0，详见 [LICENSE](LICENSE)。

`MoonVCR_submission.md` 只用于赛事报名，含联系方式，已被 Git 和发布包排除；它不属于 MoonVCR 运行时或公开包内容。
