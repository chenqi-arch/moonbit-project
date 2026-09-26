# MoonVCR 终审验收矩阵

本文件记录当前终审候选的可复验门禁。只有命令实际成功并获得对应 CI/发布证据后，状态才能标为完成。

## 当前证据

| 范围 | 命令或证据 | 当前状态 |
| --- | --- | --- |
| 核心格式/检查/构建 | `moon fmt --check`、`moon check`、`moon build` | 本地与 GitHub Ubuntu CI 通过 |
| 核心测试 | `moon test` | 76/76 通过，含可靠性与容量用例 |
| 三组成功场景 | pagination、order-contract、restricted-ci | 本地与 GitHub Ubuntu CI 通过 |
| 三组故障场景 | 对应 `*-failure` 命令 | 本地与 GitHub Ubuntu CI 均确认非零退出 |
| native 类型检查 | `moon check --target native` | Windows 本地通过 |
| native 构建/测试 | GitHub Ubuntu native job | 85/85 通过 |
| 真实 HTTP 与跨进程回放 | GitHub loopback acceptance | 通过：真实 HTTP、录制 2 条、关服、新进程回放 2 条，网络调用 0 |
| 容量资源数据 | 本地 `Measure-Command`；CI `/usr/bin/time -v` | 100/1,000/10,000 条 3/3 通过；Ubuntu CI 0.34 s，最大 RSS 67,120 KB |
| 包清单与个人数据排除 | `moon package --list` + ZIP/tracked-file scan | 本地通过：64 个归档条目，含 LICENSE，不含申报书、个人联系方式、凭据或 Git 元数据 |
| 独立消费者 | 从 Mooncakes 安装 `chenqi-arch/moonbit-project@0.3.0` | `moon check` 与 strict-offline smoke 通过，输出 `registry consumer passed version=0.3.0 status=200 network_calls=0` |
| 正式包场景 | 从消费者的 `.mooncakes` 缓存直接运行 | pagination、order-contract、restricted-ci 全部零退出；对应三个 failure 命令全部非零退出 |
| Mooncakes 发布 | `moon publish`、服务端结果、重新下载复验 | `200 OK`；公开的 `0.3.0` 已被全新消费者下载并实测 |

Mooncakes 预演证据：`moon publish --dry-run` 的服务端状态为 `202 Accepted`，明确返回 `0.3.0` 预演成功且未产生变更。从该归档创建的独立消费者输出 `independent consumer passed version=0.3.0 status=200 network_calls=0`。

正式发布证据：发布 commit 与标签 `v0.3.0` 均指向 `a8ab4767cf1ccfb71eff3ae88f7b018bb4eb0e01`；对应 Actions run [36246697037](https://github.com/chenqi-arch/moonbit-project/actions/runs/36246697037) 的 `check` 与 `native` job 全部成功。`moon publish` 返回 `200 OK`。随后在全新目录通过依赖解析器下载 `chenqi-arch/moonbit-project@0.3.0`，独立消费者与正式包内三组场景均通过，故障命令均按设计非零退出。

Windows 本地直接在很深的 `.mooncakes` 缓存目录对整个正式包执行一次全包 `moon check` 时，MoonBit `v0.10.12` 因生成路径缺失报告 compiler bug；这不是项目断言失败。验收采用两项互补证据：全新消费者对公开 API 的 `moon check` 成功，以及同一发布 SHA 的 Ubuntu CI 完整 check/native 测试成功。未将该 Windows 工具链异常记为通过。

## 平台与边界

- 核心：wasm 本地验证，Ubuntu CI 验证；
- native HTTP/文件 IO：只声明 GitHub Ubuntu CI 实测支持；
- Windows native：当前机器缺少 C 编译器，只完成类型检查，不宣称可运行；
- TLS：使用官方客户端默认校验，不提供跳过校验；
- Redirect：保留 302，由调用方决定策略；
- 非 2xx：作为正常 HTTP Response 返回，再由契约或业务断言处理。

## 完成条件

1. `specs/moonvcr-final/tasks.md` 的 A–D 全部有代码、测试和文档证据；
2. GitHub 核心与 native job 全绿；
3. 发布包不含报名材料、个人信息或合成测试凭据之外的数据；
4. 独立消费者从正式 Mooncakes 包运行三类场景；
5. 冻结提交 SHA、版本、tag、CI run 和发布结果相互一致。
