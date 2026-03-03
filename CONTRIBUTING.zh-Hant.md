# 貢獻指南

語言： [English](./CONTRIBUTING.md) | **繁體中文** | [简体中文](./CONTRIBUTING.zh-Hans.md)

## 開發流程

1. Fork 本專案
2. 建立分支（建議 `feature/...` 或 `fix/...`）
3. 提交變更與測試結果
4. 開立 Pull Request

## 提交前檢查

- Xcode 可成功 build
- 主要流程可手動驗證：新增交易、轉帳、報表、備份匯入
- 若有調整 UI/資訊架構，請同步更新 App 內教學與 README/docs
- 不提交任何敏感資料（API key、token、個資、真實備份檔）

## Commit 建議格式

- `feat: ...`
- `fix: ...`
- `docs: ...`
- `chore: ...`

## 問題回報

- Bug：請使用 GitHub Issue 模板並附重現步驟
- 安全問題：請參考 [SECURITY.zh-Hant.md](./SECURITY.zh-Hant.md)

## 維護者快速合併（Admin Bypass）

若你是專案維護者（admin 權限），可直接使用：

```bash
scripts/gh-admin-merge.sh <pr-number>
```

說明：

- 預設使用 `squash` 合併。
- 腳本會先等待 checks 完成；只有在你明確要跳過時才用 `--skip-checks`。
- 底層等價指令為 `gh pr merge <pr> --admin`。
