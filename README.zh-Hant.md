# AI 記帳 (AI Accounting iOS)

語言： [English](./README.md) | **繁體中文** | [简体中文](./README.zh-Hans.md)

AI 記帳是一個以 SwiftUI + SwiftData 開發的 iOS 個人記帳 App，支援多幣別、轉帳、借貸/代墊追蹤、報表分析、備份還原與 AI 收據掃描。

## 介面重構更新（2026-03）

- 主導航重整為：`首頁 / 帳目 / 報表 / 帳戶 / 設定`
- 新增首頁總覽（本月收支、待收代墊、快速入口）
- 新增 App 內建「使用教學」頁，首次啟動會自動顯示
- 設定頁重整為新手引導、偏好設定、資料安全、資料工具

## 主要功能

- 多帳戶記帳：現金 / 銀行 / 信用卡 / 借貸帳戶
- 多幣別交易：每筆交易可使用獨立幣別
- 完整可編輯轉帳流程（含多腳轉帳群組）
- 代墊追蹤與還款管理
- 收入/支出報表（分類與標籤鑽取）
- JSON 全機備份/還原、CSV 匯出
- AI 收據掃描（可選填 Gemini API Key）

## App 內使用教學

- 可在 `設定 > 使用教學` 開啟。
- 首次使用 App 時，系統會自動顯示教學頁。

## 語言支援

- 繁體中文（`zh-Hant`）
- 簡體中文（`zh-Hans`）
- 英式英文（`en-GB`）
- 日文（`ja`）

## 技術棧

- SwiftUI
- SwiftData
- Charts
- Google Generative AI Swift SDK（`generative-ai-swift`）

## 環境需求

- macOS
- Xcode（已在 `Xcode 26.2` 驗證）
- iOS Simulator 或實機

## 快速開始

1. Clone 專案
2. 用 Xcode 開啟 `AI 記帳.xcodeproj`
3. 選擇 Simulator 或 iPhone 裝置
4. `Cmd + R` 執行

## CI

GitHub Actions 會在 `push` / `pull_request` 到 `main` 時執行：

- `Localizable.xcstrings` 結構驗證
- iOS 專案 build 檢查

## 隱私與金鑰

- Gemini API Key 由使用者在 App 內設定
- API Key 儲存在 iOS Keychain（不寫入 repo）
- 專案不包含任何預設 API Key、token 或私鑰

## 資料相容性

- `2026-02-24` 快照版（`4417c97`）到目前版本未做破壞性資料模型遷移
- 舊版 JSON 備份可匯入目前版本

## 開源文件

- 授權： [MIT](./LICENSE)
- 安全政策： [English](./SECURITY.md) | [繁體中文](./SECURITY.zh-Hant.md) | [简体中文](./SECURITY.zh-Hans.md)
- 貢獻指南： [English](./CONTRIBUTING.md) | [繁體中文](./CONTRIBUTING.zh-Hant.md) | [简体中文](./CONTRIBUTING.zh-Hans.md)
- Pull Request 模板： [`.github/pull_request_template.md`](./.github/pull_request_template.md)

## 免責聲明

本專案為個人財務管理工具，請自行評估使用風險並定期備份資料。
