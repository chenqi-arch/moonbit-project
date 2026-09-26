# Contributing

提交应保持一次提交只解决一个清晰问题，不改写已有公开历史，也不要为了数量拆分空提交。

## 开发流程

1. 先为缺陷写能够失败的最小测试；
2. 实现修复并保持核心无 IO 边界；
3. 运行格式、检查、构建、测试、示例和包清单；
4. 更新需求映射、README/CHANGELOG 和兼容说明；
5. 提交中说明目的和验证结果。

```text
moon fmt --check
moon check
moon build
moon test
moon run cmd/moonvcr-demo
moon run cmd/moonvcr-pagination
moon run cmd/moonvcr-order-contract
moon run cmd/moonvcr-restricted-ci
moon package --list
git diff --check
```

native 代码还必须通过 Ubuntu CI 的真实 loopback HTTP、文件 IO 和跨进程验收。

## 安全与兼容

- 只使用合成测试数据，不提交真实 token、Cookie、联系方式或真实业务 cassette；
- 新错误和日志默认不得包含 URL、header 值或 body 原文；
- 新依赖必须记录版本、来源和许可证；
- 不以关闭 TLS 证书验证的方式通过测试；
- 改变 cassette 格式必须提高 `format_version` 并提供迁移或明确拒绝策略；
- 破坏公开 API 时必须更新 `MIGRATION.md` 并按语义化版本处理。
