# Changelog

## 0.3.0 - unreleased

- 修复请求匹配键的结构碰撞问题，并让公开 miss/diagnostic 摘要只包含安全描述。
- 加强 URL 用户信息、百分号编码敏感 query 和 JSON 路径脱敏覆盖。
- 增加会话快照、剩余交互计数和 `assert_complete`。
- 增加响应头精确值契约，报告使用长度和指纹而不复制 header 原文。
- 增加可选 JSON 字段和数组直接元素类型契约，并补充缺席/错误类型回归测试。
- 增加 native cassette 文件归档、官方 HTTP 适配器以及跨进程离线回放 demo。
- 增加 portable/native CI 矩阵和发布前验收文档。

## 0.2.0

- 增加响应状态、body 表示和 JSON 字段类型契约。
- 增加可靠性回归测试、脱敏和离线 demo。
