# MoonVCR 发布前检查清单

这份清单记录 0.1.0 版本在提交 Mooncakes 或比赛报名之前必须复核的事项。它只描述仓库中已经存在并能运行的能力，不把规划中的功能写成已完成。

## 当前包信息

| 项目 | 值 |
| --- | --- |
| 模块名 | chenqi-arch/moonbit-project |
| 版本 | 0.1.0 |
| 许可证 | Apache-2.0 |
| 仓库 | https://github.com/chenqi-arch/moonbit-project |
| 包入口 | 根包，导入别名可使用 @moonvcr |

moon.mod 已声明上述元数据。版本发布后，消费者可以使用 moon add chenqi-arch/moonbit-project@0.1.0 添加依赖。

## 本地验收命令

在仓库根目录按顺序运行：

~~~text
moon fmt --check
moon check
moon build
moon test
moon run cmd/moonvcr-demo
moon package --list
git diff --check
git status --short --branch
~~~

验收重点：

- moon test 应保持 42 个测试全部通过；
- demo 应输出 offline replay status=200，证明 strict-offline 回放没有调用 transport；
- moon package --list 应能生成并列出发布归档，归档中包含许可证、README、根包源码、测试、demo 和 specs 文档；
- git diff --check 不应发现空白错误，提交前工作树应干净。

## Mooncakes 预演与正式发布

发布前可以先运行：

~~~text
moon publish --dry-run --frozen
~~~

当前机器如果尚未登录 Mooncakes，该命令会在凭据检查处停止；这不是代码或元数据校验失败。需要发布时，由维护者先完成账号登录，再重新运行预演并人工检查归档内容：

~~~text
moon login
moon publish --frozen
~~~

正式 moon publish 会产生外部注册表变更，本仓库的自动化验收不会代替维护者执行。发布后应从一个干净的临时 MoonBit 项目执行 moon add chenqi-arch/moonbit-project@0.1.0，再运行该项目的检查和测试，确认消费者路径可用。

## 比赛提交前复核

- GitHub 仓库保持公开，提交历史使用普通 Git 提交，不改写、不伪造；
- 当前历史已经超过赛事要求的 10 个有效提交；
- README、LICENSE、CI、离线 demo、核心测试和 MoonBit 包元数据均在仓库中；
- 申报书只写当前仓库已经能运行的功能：显式 transport 录制、敏感信息清理、确定性回放、strict-offline 和 mismatch 诊断；
- 申报书应明确三类场景：SDK/内部 API 回归测试、CI 无网回归、接口契约变更定位；
- 不应宣称第一版已经具备 TLS MITM、系统代理、浏览器录制或自动拦截任意进程流量。

## 安全边界

MoonVCR 不自行截获系统流量。Record 模式是否访问真实网络完全由调用方传入的 transport 决定；Replay 和 StrictOffline 模式不调用 transport。默认脱敏会处理常见凭据，业务专用字段必须通过 RedactionConfig 显式配置。脱敏规则失败时，交互不会写入 cassette。
