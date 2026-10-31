# Migration guide

## 从 0.3.0 升级到 0.3.1

这是安全修复，行为有意收紧：

- required 或 optional JSON 规则遇到 Empty/Base64 都会报错；不会自动解码 Base64。为 GET 空请求与 POST JSON 分配独立的策略/会话，不要通过删除必填规则来绕过校验。
- URL fragment 不再保存，编码敏感 query 名按 UTF-8 解码后大小写归一化。userinfo 全部隐藏。
- Session 五个状态字段明确私有，直接访问 `session.cassette` 的旧代码必须改用 `session.cassette()` 副本，读取模式使用 `session.mode()`。
- `record_response` 在非 Record 下返回新增的 `SessionError::InvalidMode`，穷尽匹配错误枚举的调用方需补这一项；`native.record_http` 在离线模式执行回放。
- 会话 transport 错误不再返回原始字符串；在 transport 自己的可信边界内管理详细错误，不能把凭据复制到公共日志。
- 诊断不再直接显示自定义 method 或原始 header/query 名，只显示安全描述；指纹不是密码学匿名化。

旧 cassette 的格式版本仍为 1，但升级不会追溯清理已经保存的秘密。请审阅并重新录制历史数据；确认包含真实凭据的共享档案时，按实际影响轮换和处理副本。

## 从 0.2.0 迁移到 0.3.0

### RedactionConfig

手写完整 literal 时新增 `optional_json_paths`：

```mbt
let config : RedactionConfig = {
  headers: [],
  query_parameters: [],
  json_paths: ["/required/token"],
  optional_json_paths: ["/optional/token"],
}
```

使用 `RedactionConfig::default()` 的代码无需修改。请求和响应需要不同规则时使用 `Session::new_with_redaction_policy` 和 `RedactionPolicy`。原有 `Session::new_with_redaction` 仍把同一规则对称应用到两侧。

### ResponseContract

手写完整 literal 时新增三个数组字段：`required_header_values`、`optional_json_fields`、`json_array_elements`。不需要时传空数组；`ResponseContract::permissive()` 无需修改。

### Session 完整消费

旧行为不会自动因为“少调用一次”失败。需要完整回归保证时，在业务流程末尾显式调用 `session.assert_complete()`。

### Native 适配器

核心包仍无 IO 依赖。真实 HTTP 和文件操作从 `chenqi-arch/moonbit-project/native` 导入，并仅在支持的 native 目标使用。不要在 wasm 包中导入 native 子包。

## Cassette 格式

当前仍使用 `format_version = 1`，没有格式迁移。未知版本继续明确拒绝，不会猜测或静默降级。
