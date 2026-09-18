# MoonVCR 技术设计

状态：阶段 3（设计已确认并完成实现）

项目名称：`MoonVCR：MoonBit HTTP 交互录制回放与离线契约测试库`

## 1. 设计目标

先完成一个可审阅、可测试、可离线运行的垂直闭环：构造请求 → 在录制模式调用显式 transport → 脱敏并写入 cassette → 在回放模式按规则匹配 → 返回保存的响应或结构化 mismatch。所有核心能力都由 MoonBit 实现，网络访问只存在于调用方显式提供的 adapter 中。

设计优先级按以下顺序排列：

1. 回放路径绝不偷偷访问网络。
2. cassette 可确定性序列化、可读、可审阅。
3. 敏感信息默认不落盘。
4. 核心逻辑与具体 HTTP 客户端解耦。
5. 在截止日前交付完整核心路径，而不是堆积未完成的高级功能。

## 2. 模块边界

### 2.1 `model`

定义 `Request`、`Response`、`Header`、`Body`、`Interaction`、`Cassette` 和版本信息。模型只表达数据，不读取文件、不发网络。

### 2.2 `codec`

负责 cassette JSON 的编码、解码和 schema 版本校验。编码器使用固定字段顺序、固定换行和固定数组顺序；不保存时间戳、随机 ID 等会造成无意义 diff 的字段。

### 2.3 `normalize`

提供 URL、查询参数、请求头名称和值的规范化。规范化策略必须是纯函数，并允许匹配配置决定哪些字段参与比较。

### 2.4 `matcher`

根据方法、规范化 URL、查询参数、选定头、请求体和交互消费策略，返回匹配结果或候选差异。匹配器不执行网络，也不负责落盘。

### 2.5 `redact`

提供默认敏感头/参数规则和调用方声明的 JSON 路径规则。清理发生在 cassette 持久化之前；内存中的真实响应仍只在当前调用链中可见。

### 2.6 `store`

定义抽象的 cassette 读写接口，并提供文件实现。文件实现只处理 UTF-8 文本和原子替换策略；目录创建、权限和平台差异限制在这一层。

### 2.7 `session`

编排 `record`、`replay` 和严格离线模式。`replay` 命中时只返回 cassette 响应；未命中时返回 `ReplayMismatch`，不会调用 transport。`record` 才允许调用显式 transport，并在成功后经过 redact/store。

### 2.8 `adapter`

定义最小 transport 接口，例如“输入规范化 Request，返回 Response 或 TransportError”。第一版提供一个示例 adapter，而不是尝试透明拦截任意客户端或系统进程。

### 2.9 `diagnostics`

把 matcher 的差异转成稳定的结构化结果和人类可读摘要。诊断输出不得包含被清理前的敏感值。

## 3. 核心数据结构

cassette 采用版本化 JSON，示意如下（最终字段以 MoonBit 类型和测试为准）：

```json
{
  "format_version": 1,
  "interactions": [
    {
      "request": {
        "method": "GET",
        "url": "https://api.example.test/v1/items?page=1",
        "headers": [{"name": "accept", "value": "application/json"}],
        "body": {"kind": "empty"}
      },
      "response": {
        "status": 200,
        "headers": [{"name": "content-type", "value": "application/json"}],
        "body": {"kind": "text", "value": "{\"items\":[]}"}
      }
    }
  ]
}
```

约束：

- `format_version` 必须存在且未知版本默认拒绝读取。
- 头部在存储前按规范化名称和稳定规则排序。
- body 明确区分 empty、text 和 base64，不猜测内容编码。
- cassette 不写入 access token、cookie 或真实 API key。
- 不把录制时间、机器路径、随机顺序写进核心交互数据。

## 4. 请求处理流程

### Replay

1. 调用方把请求交给 `Session.send`。
2. `normalize` 根据匹配配置生成比较视图。
3. `matcher` 在未消费的交互中按顺序查找候选。
4. 命中则标记该交互已消费并返回保存的响应。
5. 未命中则生成 `ReplayMismatch`；严格离线模式在此结束，不触发 adapter。

### Record

1. 调用方把请求交给 `Session.send`。
2. `session` 调用显式 transport adapter。
3. adapter 返回响应后，`redact` 对请求和必要的响应字段执行清理。
4. `store` 以确定性格式写入 cassette。
5. 返回真实响应，同时保留可测试的写入结果。

### 消费策略

MVP 使用“顺序优先、每条交互默认消费一次”的策略；同一请求需要重复回放时，cassette 中保存多条交互。循环、模糊选择和动态模板推迟到后续版本。

## 5. 错误与安全设计

- `ReplayMismatch`：包含请求摘要、候选交互索引和字段级差异。
- `CassetteDecodeError`：包含版本、字段和位置等可定位信息。
- `TransportError`：由 adapter 负责转换，核心不吞掉真实网络错误。
- `RedactionError`：清理规则无法应用时，record 默认失败而不是写入可能泄露的 cassette。
- replay 模式不接受“未命中后自动联网”的隐式 fallback；若未来提供该能力，必须是显式不同模式。
- 诊断摘要只显示已规范化或已清理的值，测试 fixture 不使用真实凭据。

## 6. 测试策略

按纯函数到端到端逐层验证：

1. model/codec：空 body、文本 body、base64 body、未知版本、稳定重写。
2. normalize/matcher：大小写、查询参数排序、可忽略头、body 策略、顺序消费、未命中候选。
3. redact：默认敏感头、查询参数、JSON 路径、清理失败阻断落盘。
4. session：replay 命中不触网、replay 未命中不触网、record 调 adapter、record 后可立即 replay。
5. diagnostics：差异字段稳定、摘要不泄露敏感值。
6. example：在无网络环境中运行完整 replay；record 示例使用显式开关并写清前置条件。

## 7. 可验证交付物

- MoonBit 源码与包元数据。
- `LICENSE`、README、变更记录和贡献说明。
- 脱敏 cassette fixture。
- 无网络可运行的 replay 示例。
- 覆盖核心路径的测试。
- CI 配置，执行格式检查、检查、构建和测试。
- Mooncakes 发布所需的版本和元数据。

## 8. 风险与取舍

### 风险：MoonBit async/HTTP API 在不同目标上的差异

取舍：核心先保持 transport-independent；只在 adapter 和示例中接入已验证 API，并在 README 标出验证目标。若某个 HTTP 客户端 API 在截止日前不稳定，仍可交付可运行的内存 transport 与离线核心，不牺牲回放安全性。

### 风险：JSON body 深度差异比较过大

取舍：MVP 支持稳定文本/摘要匹配和有限 JSON 字段清理；不在第一版实现完整 JSONPath 语义或复杂动态模板。

### 风险：为了满足 10 个提交而机械拆分

取舍：只按可独立验证的功能里程碑提交。若某项尚未形成用户可见结果，则合并到下一个功能提交，绝不使用空提交或重复提交。

## 9. 阶段门禁

设计阶段完成后，必须确认以下内容再实现：模块边界、cassette schema、匹配默认值、replay 禁网语义、默认清理规则、许可证和首个可运行示例。用户确认后进入任务执行阶段；每次开始一组实现任务前先报告计划和验收标准。

## 10. 初审整改设计：`contract`

新增 `contract.mbt`，保持为无文件、无网络的纯函数模块：

- `ResponseContract` 描述允许状态码、必要响应头、期望 body 类型和 JSON 字段规则；
- `JsonFieldContract` 使用 JSON Pointer 或 dot shorthand 指定必要字段及类型；
- `ContractReport` 按“状态码 → 响应头 → body → JSON 字段”的固定顺序返回 `ContractViolation`；
- `Response::validate_contract` 是公开验收入口，调用方可在 replay 返回响应后直接执行离线契约校验；
- 报告只包含规则路径、期望类型和实际类型，不包含响应头值、JSON 值或 body 原文；
- JSON 路径解析复用现有脱敏模块的路径规则，避免两套路径语义漂移。

可靠性测试新增独立 `reliability_test.mbt`，覆盖 transport 零调用、重复确定性、录制到离线回放闭环、敏感信息不落盘和失败不污染 cassette。所有测试继续在 wasm 目标下运行，不依赖外部网络或文件系统。

## 11. 阶段2发布与申报设计

### 11.1 版本边界

响应契约是公开 API，不能继续写入已经发布的 `0.1.0` 说明。因此本地整改候选版本统一为 `0.2.0`；在正式发布前，文档使用“本地候选版本”措辞，发布后才记录 Mooncakes 可安装事实。

### 11.2 发布包边界

运行时代码、测试、README、LICENSE、CI、demo、规格文档和 `RELIABILITY_ACCEPTANCE.md` 属于可审阅交付物。`MoonVCR_submission.md` 含个人联系方式，只作为本地报名材料，通过 `.gitignore` 和发布前 `moon package --list` 双重检查排除。

### 11.3 证据与申报同步

README 负责新用户复现路径，`RELIABILITY_ACCEPTANCE.md` 负责测试矩阵和预期输出，`RELEASE_CHECKLIST.md` 负责版本、发布顺序和安全边界，申报书只引用这些已实现证据。任何未在源码和测试中验证的网络拦截、浏览器录制或真实 HTTP 客户端能力不写入申报材料。
