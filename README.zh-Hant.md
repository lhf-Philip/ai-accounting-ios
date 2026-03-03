# AI 記帳 (iOS + Android)

語言： [English](./README.md) | **繁體中文** | [简体中文](./README.zh-Hans.md)

AI 記帳是個人財務管理專案。

- iOS 版本目前為主線，功能完整且持續迭代。
- Android 版本目前為骨架階段（Jetpack Compose），用於後續與 iOS 對齊。

## iOS 主要功能

- 多帳戶記帳：現金 / 銀行 / 信用卡 / 借貸帳戶
- 多幣別交易：每筆交易可使用獨立幣別
- 完整可編輯轉帳流程（含多腳轉帳群組）
- 代墊追蹤與還款管理
- 收入/支出報表（分類與標籤鑽取）
- JSON 全機備份/還原、CSV 匯出
- AI 收據掃描（可選填 Gemini API Key）

## Android 狀態（骨架）

- Compose app shell
- Widget stub（`SummaryWidgetProvider`）
- Unit test scaffold
- Android CI baseline

詳見：`android/README.md`

## App 內使用教學（iOS）

- 可在 `設定 > 使用教學` 開啟。
- 首次使用 App 時，系統會自動顯示教學頁。

## 語言支援（iOS）

- 繁體中文（`zh-Hant`）
- 簡體中文（`zh-Hans`）
- 英式英文（`en-GB`）
- 日文（`ja`）

## 技術棧

- iOS：SwiftUI、SwiftData、Charts、`generative-ai-swift`
- Android：Kotlin、Jetpack Compose（骨架階段）

## 環境需求

- macOS
- iOS：Xcode（已在 `Xcode 26.2` 驗證）
- Android：JDK 17+ 與 Android SDK

## 快速開始

### iOS

1. 用 Xcode 開啟 `AI 記帳.xcodeproj`
2. 選擇 Simulator 或 iPhone 裝置
3. `Cmd + R` 執行

### Android（骨架）

```bash
gradle -p android :app:assembleDebug
gradle -p android :app:testDebugUnitTest
```

## CI

GitHub Actions 會在 `push` / `pull_request` 到 `main` 時執行：

- `iOS CI`：`Localizable.xcstrings` 驗證 + iOS build
- `Android CI`：`:app:assembleDebug` + `:app:testDebugUnitTest`

## 資料相容性

- 跨平台資料契約：`docs/specs/data-model.md`
- 跨平台 parity 測試向量：`docs/specs/parity-test-vectors.md`

## 隱私與金鑰

- Gemini API Key 由使用者在 App 內設定
- API Key 儲存在 iOS Keychain（不寫入 repo）
- 專案不包含任何預設 API Key、token 或私鑰

## 開源文件

- 授權： [MIT](./LICENSE)
- 安全政策： [English](./SECURITY.md) | [繁體中文](./SECURITY.zh-Hant.md) | [简体中文](./SECURITY.zh-Hans.md)
- 貢獻指南： [English](./CONTRIBUTING.md) | [繁體中文](./CONTRIBUTING.zh-Hant.md) | [简体中文](./CONTRIBUTING.zh-Hans.md)
- Pull Request 模板： [`.github/pull_request_template.md`](./.github/pull_request_template.md)
- CI 檢查清單： [`docs/CI_CHECKLIST.md`](./docs/CI_CHECKLIST.md)

## 免責聲明

本專案為個人財務管理工具，請自行評估使用風險並定期備份資料。
