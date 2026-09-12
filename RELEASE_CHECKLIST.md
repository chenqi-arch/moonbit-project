# MoonVCR 发布与比赛提交检查清单

这份清单记录 0.1.0 版本发布和比赛报名的最终核验结果。它只描述仓库中已经存在并能运行的能力，不把规划中的功能写成已完成。

## 当前包信息

| 项目 | 值 |
| --- | --- |
| 模块名 | chenqi-arch/moonbit-project |
| 版本 | 0.1.0 |
| 许可证 | Apache-2.0 |
| 仓库 | https://github.com/chenqi-arch/moonbit-project |
| 包入口 | 根包，导入别名可使用 @moonvcr |

moon.mod 已声明上述元数据。版本已发布，消费者可以使用 moon add chenqi-arch/moonbit-project@0.1.0 添加依赖。

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
- git diff --check 不应发现空白错误，提交前代码工作树应干净；报名用申报书文件可以在仓库外单独保存。

## Mooncakes 预演与正式发布记录

发布前预演命令（已执行）：

~~~text
moon publish --dry-run --frozen
~~~

预演完成后，维护者完成 Mooncakes 登录并执行正式发布：

~~~text
moon login
moon publish --frozen
~~~

正式发布结果：服务器返回 200 OK。随后已从隔离临时项目执行 moon fetch chenqi-arch/moonbit-project@0.1.0，消费者下载验证成功；moon search 也能返回公开的 0.1.0 版本。

## 比赛提交前复核

- GitHub 仓库保持公开，提交历史使用普通 Git 提交，不改写、不伪造；
- 当前历史已经超过赛事要求的 10 个有效提交；
- README、LICENSE、CI、离线 demo、核心测试和 MoonBit 包元数据均在仓库中；
- 申报书只写当前仓库已经能运行的功能：显式 transport 录制、敏感信息清理、确定性回放、strict-offline 和 mismatch 诊断；
- 申报书应明确三类场景：SDK/内部 API 回归测试、CI 无网回归、接口契约变更定位；
- 不应宣称第一版已经具备 TLS MITM、系统代理、浏览器录制或自动拦截任意进程流量。

## 安全边界

MoonVCR 不自行截获系统流量。Record 模式是否访问真实网络完全由调用方传入的 transport 决定；Replay 和 StrictOffline 模式不调用 transport。默认脱敏会处理常见凭据，业务专用字段必须通过 RedactionConfig 显式配置。脱敏规则失败时，交互不会写入 cassette。
