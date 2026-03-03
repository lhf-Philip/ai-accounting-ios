# 贡献指南

语言： [English](./CONTRIBUTING.md) | [繁體中文](./CONTRIBUTING.zh-Hant.md) | **简体中文**

## 开发流程

1. Fork 本项目
2. 创建分支（建议 `feature/...` 或 `fix/...`）
3. 提交变更与测试结果
4. 发起 Pull Request

## 提交前检查

- Xcode 可以成功 build
- 主要流程手动验证通过：新增交易、转账、报表、备份导入
- 如调整了 UI/信息架构，请同步更新 App 内教学与 README/docs
- 不提交任何敏感数据（API key、token、个人信息、真实备份文件）

## Commit 建议格式

- `feat: ...`
- `fix: ...`
- `docs: ...`
- `chore: ...`

## 问题反馈

- Bug：请使用 GitHub Issue 模板并附复现步骤
- 安全问题：请参考 [SECURITY.zh-Hans.md](./SECURITY.zh-Hans.md)

## 维护者快速合并（Admin Bypass）

如果你是项目维护者（admin 权限），可直接使用：

```bash
scripts/gh-admin-merge.sh <pr-number>
```

说明：

- 默认使用 `squash` 合并。
- 脚本会先等待 checks 完成；只有你明确要跳过时才使用 `--skip-checks`。
- 底层等价命令为 `gh pr merge <pr> --admin`。
