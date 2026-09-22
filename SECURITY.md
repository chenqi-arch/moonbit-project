# Security policy

## 数据边界

MoonVCR 只处理调用方显式传入的请求和响应，不自动拦截系统流量。Record 是否访问真实网络由调用方传入的 transport 决定；Replay 和 StrictOffline 不调用 transport。

默认脱敏会清理常见凭据、敏感 query、URL 用户信息和配置的 JSON 路径。业务专用敏感字段仍必须通过 `RedactionConfig` 明确配置。脱敏失败时不会追加 cassette 交互。

## 报告问题

请不要在公开 issue 中粘贴真实 cassette、token、Cookie 或生产 URL。提交问题时使用合成数据，并说明 MoonBit 版本、目标后端、MoonVCR 版本和最小复现步骤。发现可能泄露凭据或绕过 strict-offline 的问题时，请先私下联系仓库维护者。
