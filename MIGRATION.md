# Migration guide

## 从 0.2.0 源码迁移到当前候选

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
