# MoonVCR 0.2.0 发布与比赛复核清单

这份清单记录 0.2.0 从本地验收到正式发布的可复验结果。0.1.0 是此前已经发布的基线版本；0.2.0 包含响应契约校验和可靠性测试整改，已通过 GitHub CI、Mooncakes 发布和隔离消费者安装验证。

## 当前包信息

| 项目 | 值 |
| --- | --- |
| 模块名 | `chenqi-arch/moonbit-project` |
| 版本 | `0.2.0` |
| 许可证 | Apache-2.0 |
| 仓库 | https://github.com/chenqi-arch/moonbit-project |
| 包入口 | 根包，导入别名可使用 `@moonvcr` |

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

- `moon test` 应保持 59 个测试全部通过；
- demo 应输出 `offline replay status=200` 和 `recorded interactions=1`；
- `moon package --list` 应包含源码、测试、README、LICENSE、CI、demo、规格和可靠性验收说明，不应包含 `MoonVCR_submission.md`；
- `git diff --check` 不应发现空白错误；
- 发布前工作树应只包含明确准备提交的内容。

完整测试矩阵见 [RELIABILITY_ACCEPTANCE.md](RELIABILITY_ACCEPTANCE.md)。

## 发布过程与结果

1. 已在干净的 Windows PowerShell 环境完成本地验收。
2. 已检查 `moon.mod`、README、申报材料和报名信息使用同一个版本号 `0.2.0`。
3. 已创建有实际内容的普通 Git 提交，没有修改既有历史。
4. 已推送 `main`，GitHub Actions `MoonVCR CI` 运行成功。
5. 已执行 `moon publish --dry-run --frozen`；服务端返回 `202 Accepted`，明确表示 dry-run 成功且未产生变更。
6. 已执行 `moon publish --frozen`，服务端返回 `200 OK`，正式发布 `chenqi-arch/moonbit-project@0.2.0`。
7. 已在隔离消费者项目执行 `moon fetch chenqi-arch/moonbit-project@0.2.0`、`moon add`、`moon check`，并运行导入 smoke test 成功。

正式发布证据：Git commit `f696d26`，GitHub Actions run `35334754331`，Mooncakes 服务端 `200 OK`；消费者运行输出 `consumer import ok: MoonVCR 0.2.0`。

## 比赛材料边界

- GitHub 仓库保持公开，历史使用普通 Git 提交，不改写、不伪造；
- 当前历史已经超过赛事要求的 10 个有效提交；
- 申报书只描述已经实现并能复验的显式 transport 录制、脱敏、确定性回放、strict-offline、响应契约校验和 mismatch 诊断；
- 申报书中的可靠性验收命令和结果必须与 `RELIABILITY_ACCEPTANCE.md` 一致；
- `MoonVCR_submission.md` 只保存在本地用于报名，含联系方式，不进入 GitHub 或 Mooncakes 包。

## 明确不宣称

第一版不具备 TLS MITM、系统代理、浏览器录制或自动拦截任意进程流量。Record 是否访问真实网络完全由调用方传入的 transport 决定；Replay 和 StrictOffline 不调用 transport。
