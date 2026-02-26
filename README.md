# AI 記帳 (AI Accounting iOS)

AI 記帳是一個以 SwiftUI + SwiftData 開發的 iOS 個人記帳 App，支援多幣別、轉帳、借貸、報表分析、備份還原與 AI 收據掃描。

## 主要功能

- 多帳戶記帳：現金/銀行/信用卡等帳戶類型
- 多幣別交易：每筆交易可使用獨立幣別
- 轉帳與借貸流程：含正負號一致性與雙邊交易聯動
- 報表分析：依分類/標籤查看支出結構
- 捷徑記帳：快速記錄常用交易
- 備份與還原：JSON 全機備份、CSV 匯出
- AI 收據掃描：可選填 Gemini API Key 啟用

## 技術棧

- SwiftUI
- SwiftData
- Charts
- Google Generative AI Swift SDK (`generative-ai-swift`)

## 環境需求

- macOS
- Xcode（已在 `Xcode 26.2` 驗證）
- iOS Simulator 或實機

## 快速開始

1. Clone 專案
2. 用 Xcode 開啟 `AI 記帳.xcodeproj`
3. 選擇 Simulator 或 iPhone 裝置
4. `Cmd + R` 執行

## AI Key 與隱私

- Gemini API Key 由使用者在 App 內設定
- API Key 儲存在 iOS Keychain（不寫入 repo）
- 專案不包含任何預設 API Key、token 或私鑰

## 資料相容性

- `2026-02-24` 快照版 (`4417c97`) 到目前版本未做破壞性資料模型遷移
- 舊版 JSON 備份可匯入目前版本

## 開源文件

- License: [MIT](./LICENSE)
- Security policy: [SECURITY.md](./SECURITY.md)
- Contribution guide: [CONTRIBUTING.md](./CONTRIBUTING.md)
- Pull Request template: [`.github/pull_request_template.md`](./.github/pull_request_template.md)

## 免責聲明

本專案為個人財務管理工具，請自行評估使用風險並定期備份資料。
