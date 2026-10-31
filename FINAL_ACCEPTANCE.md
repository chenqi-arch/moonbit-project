# MoonVCR 终审验收矩阵

## 0.3.2 独立审核整改与正式发布（2026-10-31）

独立审核发现七类问题，新增10项测试在0.3.1有8项失败；不能用旧绿色CI证明安全。整改与通过标准见 `AUDIT_REMEDIATION_0.3.2.md`。原始断言保持，未经改写的审核测试文件在隔离副本重跑10/10；原始公网最小反例脚本对0.3.2也退出0。

| 范围 | 实际结果与证据 |
| --- | --- |
| 发布提交与标签 | `a5b3b4634d77b360226e8f6350fe228cbbc86206` / `v0.3.2`，普通追加提交，旧tag未改写 |
| 冻结提交CI | [run41185323935](https://github.com/chenqi-arch/moonbit-project/actions/runs/41185323935) check/native全绿，两个作业moonc均为0.10.14；此前修复提交5bea80b的CI41185113305也通过 |
| 核心/native测试 | 核心129/129，Ubuntu native154/154（包含核心129，不相加）；原审核10项、扩展路径/契约、3600组诊断/回放对照、native 3项头部与10项预算测试 |
| 真实HTTP与文件 | 双Set-Cookie业务原值/公开属性保留，录制副本两条脱敏、离线回放；重复头网络前拒绝；同句柄增长/替换及无限流/短读预算测试通过 |
| 业务与跨进程 | 三成功场景零退出、三故障场景非零；真实HTTP录制2条秘密留存0，关服后新进程严格离线回放2条、网络调用0 |
| 候选包消费者 | README check/build/run；既有12拒绝/1024编码、新12条空白Pointer、顺序/诊断/索引/重叠断言及私有字段负例均通过 |
| Mooncakes正式发布 | [0.3.2](https://mooncakes.io/docs/chenqi-arch/moonbit-project@0.3.2)；预演服务端202 Accepted，正式发布200 OK、退出0 |
| 正式公网消费 | 主代理新目录明确下载0.3.2；子代理独立空MOON_HOME亦明确下载0.3.2和async0.22.1；README与全部新旧安全断言、私有字段负例均通过 |
| 文件一致性与隐私 | ZIP、下载包、干净冻结工作树87文件SHA256三方一致；含LICENSE，排除申报书/真实联系方式/访问令牌/本地工具和Git元数据 |

关键输出：`Total tests: 129, passed: 129, failed: 0`；`Total tests: 154, passed: 154, failed: 0`；`audit acceptance passed pointer_cases=12 retained_secrets=0 duplicate_order=preserved diagnosis=consistent invalid_indices=rejected overlapping_rules=stable`；`README consumer acceptance passed package=0.3.2 origin=public-registry`。独立空缓存为 `_build/public-audit-032-c659a31a`，消费者 `_build/c-946de674/consumer`。

0.3.2发布完成后，CI公网步骤已从明确标注的旧API基线切换为默认读取manifest的0.3.2，执行完整新旧安全断言。发布后的文档/CI收尾提交不属于Mooncakes包源提交，tag仍指向上述冻结SHA。测试覆盖已列明的路径与平台，不代表所有输入无漏洞或主办方已重新批准。

## 0.3.1 历史安全修复（未覆盖本轮新增缺陷）

0.3.0 未通过正式验收，官方指出的两项脱敏漏洞成立。下方旧版绿色测试记录不构成安全合格结论。本轮按 `specs/security-0.3.1/acceptance.md` 重新取证，详细漏洞、独立复核与限制见 `SECURITY_FIX_REPORT.md`。

| 范围 | 本轮状态 |
| --- | --- |
| 官方两项漏洞与新增边界 | 已修复，先写的 8 项反例在旧版为 1 通过/7 失败；修复后新矩阵通过 |
| 核心检查/构建/测试 | 本地 moonc 0.10.14，92/92 通过，包含 16 项新增安全测试 |
| 独立对抗性复核 | 1,024 编码组合敏感值留存为 0；独立 Session 40 组合通过；字段注入负例编译失败 |
| 候选归档消费者 | 从 0.3.1 ZIP 导入，README check/build/run、安全12拒绝+1024编码组合、私有字段负例通过；这是归档验证，不是公网发布 |
| native 类型检查/构建/测试 | 本地类型检查通过；Ubuntu CI 104/104通过，含核心92项及12项native，不能将92与104相加 |
| 真实 HTTP 与跨进程回放 | Ubuntu CI：GET/POST/headers/JSON/bytes/errors/timeout/status/redirect通过；录制2条、秘密留存0，关服后新进程回放2条、网络调用0 |
| GitHub 发布提交与标签 | `f7ba916138a72af2450b5c8ae8696f43d59ff36d`，`v0.3.1`；[CI run41163071443](https://github.com/chenqi-arch/moonbit-project/actions/runs/41163071443) check/native全绿 |
| Mooncakes 正式发布 | 0.3.1服务端预演202 Accepted，正式发布200 OK，发布命令退出0 |
| 正式公网包消费者 | 新目录从公网下载0.3.1，README check/build/run，12条失败关闭录制、1024编码录制和私有字段负例均通过；origin=public-registry |
| 正式包一致性与隐私 | 发布前80个归档文件与干净发布提交工作树一致；公网下载的80文件逐一SHA256一致；含LICENSE，不含申报书、真实个人资料、工具链或Git元数据 |

实际日志摘录：`Total tests: 92, passed: 92, failed: 0`；`Total tests: 104, passed: 104, failed: 0`；`real HTTP recording saved interactions=2 secrets=0`；`cross-process strict offline replay passed interactions=2 network_calls=0`；`security acceptance passed rejected=12 encoded_names=1024 retained_secrets=0`；`Consumer private Session field access rejected as expected`；`README consumer acceptance passed package=0.3.1 origin=public-registry`。

发布在短临时路径完成：Windows旧工具链的发布验证在深目录下会触发生成文件缺失；带`--frozen`的预演也因验证解包目录尚无依赖而失败。修复路径是解出同一候选ZIP至短路径、逐文件校验一致，正常解析依赖后验证与发布，未跳过检查。发布后的文档/CI收尾提交不属于包源提交，不改写v0.3.1原指向。

## 0.3.0 历史执行记录（已知有安全漏洞）

本文件记录当前终审候选的可复验门禁。只有命令实际成功并获得对应 CI/发布证据后，状态才能标为完成。

2026-09-30 最新赛事标准复核见 `COMPETITION_ACCEPTANCE.md`。本地工具链已升级为 `moonc v0.10.14+7d59c7ec9`，核心 76 项与全部成功/失败场景重新通过；最新 README 完整消费者从 Mooncakes 下载 0.3.0 后 check/build/run 通过。两个 CI 作业现强制检查 `moonc >= 0.10.14`。

新增标准的远端证据：提交 `be3ba010d3ffb84e22fb0c254c741a13b74e0304`，[Actions run 36689633295](https://github.com/chenqi-arch/moonbit-project/actions/runs/36689633295) 的 check/native 全部成功。日志确认两者均为 `moonc v0.10.14+7d59c7ec9`，核心 76/76、native 85/85 通过；真实 HTTP 与新进程严格离线回放再次成功（2 条交互、网络调用 0），README 公网消费者再次成功。以下 0.3.0 发布清单与发布日期证据保留为历史记录，不将本次文档/CI 修改冒充重新发布的包。

## 旧版历史证据

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
