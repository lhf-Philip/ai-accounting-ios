# 貢獻指南

語言： [English](./CONTRIBUTING.md) | **繁體中文** | [简体中文](./CONTRIBUTING.zh-Hans.md)

## 工作流程

1. 建立分支（建議 `codex/<topic>`）。
2. 每個 PR 只處理一組變更。
3. 提交時附上驗證說明。
4. 發 PR 到 `main`。

## 提交前檢查

- iOS 變更：Xcode build 必須通過。
- Android 變更：Android CI 指令必須通過。
- 若有行為變更，需手動驗證核心流程。
- 若調整 UI/資訊架構，需同步更新 App 內教學與 README/docs。
- 若調整資料模型或備份行為，需同步更新：
  - `docs/specs/data-model.md`
  - `docs/specs/parity-test-vectors.md`
  - `.github/pull_request_template.md` 相容性區段
- 不可提交敏感資料（API key、token、個資、真實備份檔）。

## Commit 建議前綴

- `feat: ...`
- `fix: ...`
- `refactor: ...`
- `docs: ...`
- `chore: ...`

## 回報問題

- 一般 bug 請使用 GitHub issue 模板並附重現步驟。
- 安全問題請依 [SECURITY.md](./SECURITY.md) 流程。

## 維護者 Admin Bypass 合併

維護者（admin）可使用：

```bash
scripts/gh-admin-merge.sh <pr-number>
```

說明：

- 預設使用 `squash` 合併。
- 腳本會先等待 checks 完成；只有在你明確要跳過時才用 `--skip-checks`。
- 底層等價指令為 `gh pr merge <pr> --admin`。
