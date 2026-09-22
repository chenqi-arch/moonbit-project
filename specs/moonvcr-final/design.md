# MoonVCR 终审完善设计

## 目标与约束

MoonVCR 保持无 IO 核心：档案模型、规范化、匹配、会话、脱敏、诊断和契约校验可以在受限网络和 wasm 场景运行。真实 HTTP 和文件档案由独立适配层提供，避免把平台依赖渗入核心包。

终审交付以三条证据链为准：

1. 核心错误可复现且不会泄露档案内容；
2. 真实服务录制后可在新进程离线回放；
3. 干净消费者项目能安装正式 Mooncakes 包并运行文档场景。

## 模块边界

```text
moonvcr.mbt       档案类型、JSON 编解码、版本错误
normalize.mbt     请求规范化和结构化匹配键
matcher.mbt       未消费交互匹配
session.mbt       Record / Replay / StrictOffline 状态机
redact.mbt        请求、响应独立的安全副本
diagnostics.mbt   仅描述字段的差异摘要
contract.mbt      小型确定性响应契约
adapter.mbt       内存脚本 transport 和适配接口
io/               平台文件保存和加载（目标后端明确后实现）
examples/         三个可复制业务场景和故障演示
```

核心公开错误只包含错误类别、索引、字段路径、长度或不可逆描述。匹配器内部可以使用结构化 key，但不得直接将 key 作为公开错误 payload。`Cassette`、`Request`、`Response` 和配置在创建会话时复制；公开 accessor 返回副本或只读摘要，避免调用方通过别名修改内部状态。

## 匹配设计

请求键使用带长度的字段序列（字段名、长度、值），而不是用未转义分隔符连接。规范化只处理明确约定的差异：方法大写、header 名小写、值两端空白、查询对排序；片段不参加匹配。重复 query/header 保持计数语义，body 默认精确匹配，忽略 body 必须显式设置。现有 cassette 格式不改变，旧档案仍可读取。

## 脱敏与诊断设计

`RedactionConfig` 拆分 request JSON 路径与 response JSON 路径，并支持必需/可选策略。默认敏感头和查询参数继续清理；URL 解析至少覆盖用户信息、百分号编码键名和 fragment 的明确规则。脱敏失败时 record 不追加交互，replay 不返回潜在未脱敏数据。

诊断只返回 `MismatchKind`、字段路径、实际/期望类型、长度和稳定摘要。`ReplayMiss` 不携带完整 normalized key；增加公开 `MismatchReport` 生成函数供调试。测试数据中的秘密字符串会在 cassette、异常对象和 summary 上做完整搜索。

## 会话设计

`Record` 仅调用调用方传入的 transport；`Replay` 和 `StrictOffline` 仅查 cassette。每次命中前检查索引，命中后才标记 consumed；所有错误保持状态不变。增加 `remaining_interactions` 与 `assert_complete`，让调用方选择把少调用视为失败。新会话从 cassette 快照初始化，多个会话互不共享消费状态。

## HTTP 与文件 IO 设计

先用最小探针锁定 MoonBit 工具链、官方 HTTP 包版本及目标后端。核心库不主动拦截系统流量，也不关闭 TLS 验证。适配层将真实客户端的请求、响应、连接错误和超时转换为核心类型；记录和回放仍由同一 Session API 完成。

文件层只接收已编码的 cassette 文本。保存采用“同目录临时文件 → flush/close → 平台支持的替换”顺序，默认拒绝覆盖；加载限制字节数并调用核心 decode。平台不支持安全替换时返回明确错误。由于官方 async 的 native 支持矩阵和 API 可能变化，依赖与平台矩阵写入 CI 和 README，未验证平台不列为支持。

## 契约设计

保留状态码、必需头存在、body 表示和 JSON 路径类型规则；新增精确媒体类型/头值、可选字段和数组元素规则，报告仍只包含路径与类型。规则构造阶段拒绝空路径、重复冲突和不支持的数组通配符。契约报告由调用方显式断言，库不吞掉失败。

## 示例、测试与 CI

每个示例都包含合成服务响应、请求、cassette、通过输出和故障输出。真实 E2E 使用本地服务，不访问第三方 API：录制进程保存档案，回放进程在服务关闭后运行。核心单测覆盖结构化 key、脱敏、状态和契约；集成测试覆盖文件和真实 loopback；消费者测试从 Mooncakes 安装而非源码引用。

CI 顺序固定为格式、check、build、unit test、integration test、离线示例、package manifest 和消费者检查。任何命令失败返回非零；移除重复步骤。每次发布记录工具链版本、提交 SHA、包版本、测试结果和支持平台。

## 开源与兼容

根包继续 Apache-2.0。新依赖必须写入 manifest 并记录来源和许可证；示例不含个人资料或真实凭据。0.2.x 保持 cassette 格式兼容；需要破坏 API 时提高主版本或提供迁移说明。README 只描述已经运行过的命令和平台。
