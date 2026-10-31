# Security policy

## 支持范围

0.3.0 及更早版本存在已证实脱敏绕过：JSON 规则遇到非 Text Body 被跳过；编码查询参数名在解码前转小写导致漏识别；fragment 与部分自定义编码名也可能保留敏感内容。0.3.1 的修复与验证进度见 `FINAL_ACCEPTANCE.md` 和 `specs/security-0.3.1/acceptance.md`。不得将旧 CI 全绿等同于旧版本安全。

升级不会清洗旧 cassette。请审阅历史录制文件（包括 Base64 解码后的内容）并重录；如果确认真实凭据已进入共享资产，应根据实际影响轮换凭据并处理共享副本。这里没有证据表明用户真实资料已经公开泄露。

安全修复面向当前 `main` 和最新 Mooncakes 稳定版。报告问题时请说明版本、目标平台、最小复现和敏感数据类别；不要在公开 issue 粘贴真实凭据或 cassette。

## 项目安全边界

- MoonVCR 不是网络代理，不做 TLS MITM 或系统流量拦截；
- Record 只调用使用者显式提供或选择的 transport；
- Replay/StrictOffline 不进行网络回退；
- 默认规则清理常见 header/query 名，不自动扫描任何 Body；业务敏感 JSON 字段必须显式配置；
- 任意 JSON 规则存在时，非 Text Body、无效 JSON 或非法配置失败关闭；可选路径只允许有效 JSON 缺少字段；
- URL fragment 一律移除；query 只解码一次；畸形编码按原样比较，不模拟应用层多次解码；
- Session 内部状态字段私有，公开快照修改不改变内部数据；录制只允许 Record，native helper 尊重离线模式；
- 会话返回的 transport 错误载荷已清理，TransportError/Session Debug 仅显示安全描述；原始数据对象和自行构造的错误仍应谨慎处理；
- 诊断中的短指纹不是加密或匿名化保证；
- native HTTP 不提供关闭 TLS 证书校验的选项；
- cassette 仍应按可能含敏感信息的测试资产管理和审阅。

`Cassette::encode` 和 native 文件保存只编解码/保存输入，不自动脱敏。直接构造包含原文的 cassette 再保存属于调用方主动持久化原始数据。Record 成功时返回的响应仍为业务所需原文，只有保存在 session 中的副本经过规则处理。路径、规则名称和未知业务字段也可能含敏感信息，不应在配置中嵌入凭据。

## 报告方式

优先通过 GitHub 仓库的私密安全报告功能提交漏洞。若不可用，请创建不含漏洞细节的普通 issue，请求维护者提供私密沟通渠道。

报告应包含影响版本、复现步骤、预期/实际行为、可能泄露的数据类别和建议修复；不要附带真实用户数据。
