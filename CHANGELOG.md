# Changelog

本项目遵循语义化版本。未发布内容只有在验收、版本冻结和 Mooncakes 发布完成后才会移动到正式版本段。

## Unreleased

暂无。0.3.2 已正式发布，完整证据见 FINAL_ACCEPTANCE.md。

## 0.3.2 - 2026-10-31

- JSON Pointer 按原文保留空白键，契约检查同样精确寻址；数组索引严格拒绝前导零等非法形式。
- 重叠必填/可选规则先验证原始JSON，再深到浅覆盖，结果不依赖声明顺序。
- 匹配保留同名query/header内部值顺序，保留query值空白；编码别名按同名组处理。
- native 发网前明确拒绝重复请求头；恢复逐条Set-Cookie与公开属性供业务使用，录制副本再脱敏。
- native 档案一次打开、有界分块读取，最多消耗上限加一字节，防止增长/路径替换绕过预算。
- 诊断判等复用真实回放输入，原始导入档案的ReplayMiss不再报告无差异；安全显示单独处理。
- 固化原审核10项、路径/契约扩展、3600组合对照、native同句柄与Cookie验收，新增候选/公网包断言及七项整改映射。

行为变化与边界见 MIGRATION.md；逐项整改见 AUDIT_REMEDIATION_0.3.2.md。发布提交为a5b3b46，tag v0.3.2；核心129/native154、正式包独立消费者与87文件一致性均通过。

## 0.3.1 - 2026-10-31

- 修复 required/optional JSON 规则在 Empty/Base64 上绕过检查；任一侧失败不追加交互。
- 修复编码参数名先转小写再解码的识别错误；支持 UTF-8 自定义名称和 form `+`，保留单次解码边界。
- 移除 fragment，完整隐藏 authority 中用户信息；修复非密码学指纹的过度文档声明。
- Session 字段明确私有；错误 Debug 和 transport 载荷不回显秘密；非 Record 不允许显式追加，native helper 在离线模式不触网。
- 同步新录制交互的消费状态，避免同一会话录制后回放越界；诊断头部比较复用结构化键，避免错报“无差异”。
- 增加针对性安全回归、1,024 个编码组合、native 文件与模式测试，以及候选归档/公网包独立消费者验证。
- 调整真实 GET/POST 示例为独立必填策略，新增安全验收命令，保留旧版本影响和迁移说明。

## 0.3.0 - 2026-09-26

### Added

- 官方 async native HTTP 适配器，支持显式毫秒超时和安全错误分类；
- cassette native 文件加载、默认 10 MB 上限、默认禁止覆盖和显式安全替换；
- 真实 loopback HTTP 与跨进程“录制、关服、离线回放”验收；
- 请求/响应独立的必填与可选 JSON 脱敏路径；
- header 值、可选 JSON 字段和数组元素契约；
- Session 快照隔离、剩余交互计数和完整消费断言；
- 分页 SDK、订单兼容、受限网络 CI 的成功与故障命令；
- 100/1,000/10,000 条 cassette 容量验收。

### Changed

- 匹配键改为长度编码结构，消除 header/query/body 分隔符碰撞；
- `ReplayMiss` 与诊断输出不再暴露完整匹配键或业务原文；
- demo 和故障场景失败时返回非零；
- CI 拆分核心与 native job，删除重复打包步骤。

### Compatibility

- cassette `format_version` 仍为 1，旧 cassette 可继续读取；
- `Session::new_with_redaction` 和 `redact_interaction` 保留为对称脱敏兼容入口；
- 新增字段会影响源码中手写完整 struct literal 的调用方，迁移方法见 `MIGRATION.md`。

## 0.2.0

- 增加轻量响应契约与可靠性测试；
- 已发布到 Mooncakes。

## 0.1.0

- 首个可用版本：cassette、匹配、录制/回放、脱敏、诊断和脚本 transport。
