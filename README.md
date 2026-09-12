# MoonVCR

**MoonVCR：MoonBit HTTP 交互录制回放与离线契约测试库**

MoonVCR 将经过允许的 HTTP 请求与响应保存为可审阅的 cassette，并在开发和 CI 中离线回放。它面向需要稳定、可重复测试的 MoonBit SDK、服务端和内部 API。

当前版本正在按垂直切片开发。第一批内容已经包含：

- 版本化的请求、响应、请求头、请求体、交互和 cassette 模型；
- 确定性 JSON 编码与解码；
- 未知 schema 版本和损坏 JSON 的类型化错误；
- URL、查询参数和请求头规范化，以及可配置的 body 匹配策略；
- 确定性 matcher、顺序消费和候选摘要；
- 显式 transport 的 record、replay 与 strict-offline 会话；
- 无网络即可运行的核心测试。

## 本地验证

安装 MoonBit 工具链后，在仓库根目录运行：

```text
moon check
moon test
moon fmt --check
```

当前 cassette 是纯文本 JSON，目标是让变更可以通过 Git 逐行审阅。record 模式只调用调用方显式传入的 transport，replay 和 strict-offline 模式不会调用 transport；因此核心库本身不拦截系统流量，也不会暗中联网。敏感信息清理、HTTP adapter 和可复制示例仍在后续功能提交中，在这些能力完成前，不把本项目描述为完整的开箱即用网络录制器。

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

MoonVCR 是原创 MoonBit 实现，不机械移植其他语言的 VCR 源码。项目借鉴 HTTP 录制/回放工具的通用思想，但会保持自己的数据结构、匹配语义和 MoonBit API。第一版不实现 TLS MITM、系统代理或自动拦截任意进程流量。当前版本还没有默认脱敏器；不要把真实 token、cookie 或个人数据写入测试 cassette，脱敏策略将在后续提交中加入。

## 许可证

Apache License 2.0，详见 [LICENSE](LICENSE)。
