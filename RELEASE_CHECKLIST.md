# MoonVCR 0.3.0 发布与终审复核清单

本清单用于核对 `chenqi-arch/moonbit-project@0.3.0` 的源码、CI、Mooncakes 包和消费者行为。发布结果只能在实际成功后写入 `FINAL_ACCEPTANCE.md`，不预先声明通过。

## 包信息

| 项目 | 值 |
| --- | --- |
| 模块名 | `chenqi-arch/moonbit-project` |
| 版本 | `0.3.0` |
| 许可证 | Apache-2.0 |
| 仓库 | https://github.com/chenqi-arch/moonbit-project |
| 核心目标 | wasm；Ubuntu CI 同时验证 native |
| native 依赖 | `moonbitlang/async@0.22.1` |

## 发布前门禁

- [x] `moon fmt --check`、`moon check`、`moon build` 通过；
- [x] wasm 测试 76/76 通过；
- [x] Ubuntu native 测试 85/85 通过；
- [x] 真实 HTTP 与跨进程 strict-offline 回放通过，回放网络调用为 0；
- [x] 三组业务成功场景通过，三组故障场景均非零退出；
- [x] 100/1,000/10,000 条容量用例通过，实测数据已记录；
- [x] `moon package --list` 与归档扫描通过：64 项，含 LICENSE，不含申报书、联系方式、凭据或 Git 元数据；
- [x] `moon publish --dry-run` 服务端返回 `202 Accepted`，确认未产生变更；
- [x] 预演归档已被全新消费者模块导入并成功 strict-offline 回放。

## 正式发布步骤

1. 提交并推送发布文档，等待该确切 SHA 的 `check` 与 `native` job 全绿；
2. 在该 SHA 创建附注标签 `v0.3.0`，不改写历史；
3. 执行 `moon publish`，记录 Mooncakes 服务端响应；
4. 在不使用工作树源码的干净目录执行 `moon fetch chenqi-arch/moonbit-project@0.3.0` 和消费者测试；
5. 核对标签 SHA、CI run、Mooncakes 版本和最终验收证据一致。

## 发布后必须填写的证据

- 发布 commit 与 tag SHA；
- 对应 GitHub Actions run URL；
- Mooncakes 服务端成功状态；
- 公开包重新下载、check 与运行输出；
- `specs/moonvcr-final/tasks.md` 的 E1/E2 只在上述证据齐全后勾选。

## 边界与开源合规

- 仓库保留真实普通提交，不改写、不伪造、不为凑数量拆分提交；
- 项目不宣称 TLS MITM、系统代理、浏览器录制或自动拦截任意进程流量；
- Record 是否联网由调用方显式 transport 决定；Replay 与 StrictOffline 不调用 transport；
- 依赖许可来源见 `THIRD_PARTY_NOTICES.md`，安全与隐私边界见 `SECURITY.md`。

## 历史基线

`0.2.0` 的历史发布证据为 commit `f696d26`、GitHub Actions run `35334754331`、Mooncakes `200 OK`；该版本不含 0.3.0 的 native HTTP/档案与新验收场景。
