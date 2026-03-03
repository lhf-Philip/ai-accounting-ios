# 贡献指南

语言： [English](./CONTRIBUTING.md) | [繁體中文](./CONTRIBUTING.zh-Hant.md) | **简体中文**

## 工作流程

1. 创建分支（建议 `codex/<topic>`）。
2. 每个 PR 只处理一组变更。
3. 提交时附上验证说明。
4. 发 PR 到 `main`。

## 提交前检查

- iOS 变更：Xcode build 必须通过。
- Android 变更：Android CI 指令必须通过。
- 若有行为变更，需要手动验证核心流程。
- 若调整 UI/信息架构，需同步更新 App 内教学与 README/docs。
- 若调整数据模型或备份行为，需同步更新：
  - `docs/specs/data-model.md`
  - `docs/specs/parity-test-vectors.md`
  - `.github/pull_request_template.md` 兼容性区段
- 不可提交敏感数据（API key、token、个人信息、真实备份文件）。

## Commit 建议前缀

- `feat: ...`
- `fix: ...`
- `refactor: ...`
- `docs: ...`
- `chore: ...`

## 问题反馈

- 一般 bug 请使用 GitHub issue 模板并附重现步骤。
- 安全问题请按 [SECURITY.md](./SECURITY.md) 流程。

## 维护者 Admin Bypass 合并

维护者（admin）可使用：

```bash
scripts/gh-admin-merge.sh <pr-number>
```

说明：

- 默认使用 `squash` 合并。
- 脚本会先等待 checks 完成；只有你明确要跳过时才使用 `--skip-checks`。
- 底层等价命令为 `gh pr merge <pr> --admin`。
