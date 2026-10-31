# Migration guide

## 从 0.3.1 升级到 0.3.2

- JSON Pointer 不再裁剪路径空白：`/token ` 定位 `"token "`，不会定位 `"token"`。dot shorthand 保留原来的格式空白处理。支持字段寻址子集，不支持空字符串根路径；`/` 是空对象键。
- 数组索引 `01`、`+1`、`-` 和超出 Int 范围的数字会明确失败；对象名 `"01"` 不受影响。契约可选字段遇到非法数组索引也报告 `InvalidJsonPathViolation`，仅合法但不存在的字段跳过。
- 重叠路径先在未修改的原始 JSON 上验证全部规则，再按深到浅顺序替换。缺失必填和非法可选路径不能被父级脱敏隐藏。
- 重复 query/header 值的顺序参与匹配；不同名称组仍允许重排。依赖旧版无序重复值的 cassette 应复核并重录，不能指望错误命中继续保持。query 值空白不再被裁剪；编码别名共享顺序组，但原始拼写仍参与最终键。
- native 拒绝大小写不敏感的重复请求头，新增 `HttpAdapterError::UnsupportedDuplicateHeaders`，穷尽匹配错误枚举的调用方要补该分支。调用方须按具体协议预先合并可合并字段，不能让适配器猜测。
- 原始业务响应包含逐条 `Set-Cookie`；字段与属性由固定依赖的公开解析数据规范化重建，只有保存副本会脱敏。
- 导入未脱敏 cassette 时，诊断使用与实际回放相同的比较输入，并另外生成安全展示；不会把原本 ReplayMiss 的情况报为 no mismatch。
- 文件加载改为同一打开句柄有界读取，超限最迟消费到 `max_bytes + 1` 后拒绝。`TooLarge(n)` 是已观察到的超限字节数下界，不再是 stat 得到的总大小；超过 Bytes 的 Int 可表示长度也拒绝，即使传入更大 Int64 限额。

格式版本仍为 1，升级不自动清理旧档案；请审阅历史记录并重录。HTTP 响应仍无硬字节上限；文件读取预算不能作为网络响应的内存保护。七类问题与测试映射见 `AUDIT_REMEDIATION_0.3.2.md`。

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
