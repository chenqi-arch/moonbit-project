# MoonVCR

**MoonVCR：MoonBit HTTP 交互录制回放与离线契约测试库**

MoonVCR 将经过允许的 HTTP 请求与响应保存为可审阅的 cassette，并在开发和 CI 中离线回放。它面向需要稳定、可重复测试的 MoonBit SDK、服务端和内部 API。

当前版本正在按垂直切片开发。第一批内容已经包含：

- 版本化的请求、响应、请求头、请求体、交互和 cassette 模型；
- 确定性 JSON 编码与解码；
- 未知 schema 版本和损坏 JSON 的类型化错误；
- 无网络即可运行的核心测试。

## 本地验证

安装 MoonBit 工具链后，在仓库根目录运行：

```text
moon check
moon test
moon fmt --check
```

当前 cassette 是纯文本 JSON，目标是让变更可以通过 Git 逐行审阅。录制引擎、请求匹配、默认敏感信息清理和 HTTP adapter 会在后续功能提交中加入；在这些能力完成前，不把本项目描述为已经具备完整网络录制能力。

## 项目边界

MoonVCR 是原创 MoonBit 实现，不机械移植其他语言的 VCR 源码。项目借鉴 HTTP 录制/回放工具的通用思想，但会保持自己的数据结构、匹配语义和 MoonBit API。第一版不实现 TLS MITM、系统代理或自动拦截任意进程流量。

## 许可证

Apache License 2.0，详见 [LICENSE](LICENSE)。
