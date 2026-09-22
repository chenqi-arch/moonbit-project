# MoonVCR 0.3.0 发布与终审复核清单

这份清单只记录可以复验的事实。0.2.0 仍是 Mooncakes 上的已发布版本；0.3.0 增加安全匹配修复、响应头值/JSON 字段契约、native 文件/HTTP 适配和跨进程离线回放，在所有证据完成前不把它写成已发布。

## 当前包信息

| 项目 | 值 |
| --- | --- |
| 模块名 | `chenqi-arch/moonbit-project` |
| 拟发布版本 | `0.3.0` |
| 许可证 | Apache-2.0 |
| 仓库 | <https://github.com/chenqi-arch/moonbit-project> |
| 包入口 | 根包；导入别名可使用 `@moonvcr` |
| 原生依赖 | `moonbitlang/async@0.22.1`，仅 native 子包 |

## 本地 portable 验收（已完成）

```text
moon fmt --check
moon check
moon build
moon test
moon run cmd/moonvcr-demo
moon package --list
git diff --check
```

截至 2026-09-22，以上命令已在 Windows 工作区完成；核心测试为 68/68 通过，demo 输出离线回放 200 和录制 1 条交互。检查仍有 MoonBit 对 `method` 保留关键字的非致命警告。

## Native 与跨进程验收（由 Ubuntu CI 完成）

```text
moon check --target native
moon build --target native
moon test --target native
moon run --target native cmd/moonvcr-native-demo
moon run --target native cmd/moonvcr-native-record
moon run --target native cmd/moonvcr-native-replay
```

必须保存 CI run URL、提交 SHA 和完整输出。Windows 本地缺少 C 编译器，不能用本机结果替代 native CI 证据。

## 发布前步骤

1. 检查工作树只包含本轮明确的源代码、测试、文档和 CI 修改；不修改既有 Git 历史。
2. 在干净工作树执行 `moon publish --dry-run --frozen`，确认 0.3.0 包清单不含 `MoonVCR_submission.md`、个人联系方式、临时目录或测试凭据。
3. 完成 GitHub Actions portable/native 双 job，并保存提交 SHA、run URL、工具链版本和测试数量。
4. 执行 `moon publish --frozen` 发布 0.3.0；保存服务端结果，不把 dry-run 当成正式发布。
5. 在独立消费者目录执行 `moon add chenqi-arch/moonbit-project@0.3.0`、`moon check`，运行 README 的离线回放和契约示例。
6. 更新本文件和 `RELIABILITY_ACCEPTANCE.md`，只填入已经实际发生的版本、SHA、CI 和包结果。

## 终审材料边界

- GitHub 仓库保持公开，提交历史使用普通 Git 提交，不改写、不伪造；
- README、许可证、依赖版本、支持目标和限制与代码一致；
- 申报书只描述显式 transport 录制、脱敏、确定性回放、strict-offline、响应契约、native 文件归档和实际测试结果；
- 不宣称 TLS MITM、系统代理、浏览器录制或自动拦截任意进程流量；
- `MoonVCR_submission.md` 只在本地报名使用，不进入 GitHub 或 Mooncakes 包。
