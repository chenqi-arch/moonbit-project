# Changelog

本项目遵循语义化版本。未发布内容只有在验收、版本冻结和 Mooncakes 发布完成后才会移动到正式版本段。

## Unreleased

暂无。

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
