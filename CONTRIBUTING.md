# Contributing to MoonVCR

感谢参与。请先说明问题的复现输入、目标后端和期望行为，再提交小而完整的改动。

提交前在仓库根目录运行：

```text
moon fmt --check
moon check
moon build
moon test
moon run cmd/moonvcr-demo
git diff --check
```

涉及 native 代码时，还应在具备 C 编译器的环境运行 `moon check --target native`、`moon test --target native` 和对应 demo。不要在测试或示例中放入真实凭据、个人信息或第三方生产数据；请使用合成 cassette。

提交信息应说明行为变化和验证命令。不要改写已有提交历史；新增依赖必须在 `moon.mod` 中固定版本并说明来源与许可证。
