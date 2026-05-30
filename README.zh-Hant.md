# AI 記帳 (iOS + Android)

語言： [English](./README.md) | **繁體中文** | [简体中文](./README.zh-Hans.md)

AI 記帳是個人財務管理 App，支援多幣別記帳、帳戶管理、預算、代墊、債務管理與備份。

- iOS 是產品 source of truth，也是主要 SwiftUI + SwiftData 實作。
- Android 是持續維護中的 Kotlin + Jetpack Compose 版本，按 iOS 的資訊架構與功能語義對齊。
- Android 保留一個平台專屬能力：桌面小工具。

## 核心功能

- 多帳戶記帳：現金 / 銀行 / 信用卡 / 借貸帳戶
- 多幣別收入、支出、轉帳、代墊與債務流程
- 完整可編輯轉帳流程（含多腳轉帳群組與同帳戶跨幣種轉帳）
- 代墊追蹤、還款管理與結算中心
- 債務管理：借入、還款、免除債務
- 收入/支出報表（分類與標籤鑽取）
- 預算、超支提醒與 AI 預算建議
- 資料健康檢查、JSON 備份/還原、WebDAV 遠端備份、CSV 匯出
- AI 收據掃描（使用者自行填寫 Gemini API Key）

## 平台狀態

### iOS

- SwiftUI + SwiftData 版本，功能完整且持續迭代
- 維護四語：繁體中文、簡體中文、英式英文、日文
- PR 會跑 iOS simulator build 與 string catalog 驗證

### Android

- Kotlin + Jetpack Compose 版本，主頁與核心財務流程已按 iOS 對齊
- Room 本地資料層、parity 測試向量、Android CI build / unit tests
- Android-only summary widget
- 對齊規格見 [`docs/specs/android-ios-parity.md`](./docs/specs/android-ios-parity.md)

## App 內使用教學

- 可在 `設定 > 使用教學` 開啟。
- 首次使用 App 時，系統會自動顯示教學頁。

## 語言支援（iOS）

- 繁體中文（`zh-Hant`）
- 簡體中文（`zh-Hans`）
- 英式英文（`en-GB`）
- 日文（`ja`）

## 技術棧

- iOS：SwiftUI、SwiftData、Charts、`generative-ai-swift`
- Android：Kotlin、Jetpack Compose、Room、WorkManager、Android widgets

## 環境需求

- macOS
- iOS：Xcode（已在 `Xcode 26.2` 驗證）
- Android：JDK 17+ 與 Android SDK

## 快速開始

### iOS

1. 用 Xcode 開啟 `AI 記帳.xcodeproj`
2. 選擇 Simulator 或 iPhone 裝置
3. `Cmd + R` 執行

### Android

```bash
cd android
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest
```

APK 建置流程：[`docs/ANDROID_APK_BUILD.md`](./docs/ANDROID_APK_BUILD.md)

## CI

GitHub Actions 會在 `push` / `pull_request` 到 `main` 時執行：

- `iOS CI`：`Localizable.xcstrings` 驗證 + iOS build
- `Android CI`：`:app:assembleDebug` + `:app:testDebugUnitTest`

## 資料相容性

- 跨平台資料契約：[`docs/specs/data-model.md`](./docs/specs/data-model.md)
- 跨平台 parity 測試向量：[`docs/specs/parity-test-vectors.md`](./docs/specs/parity-test-vectors.md)
- 手動驗證矩陣：[`docs/VALIDATION_MATRIX.md`](./docs/VALIDATION_MATRIX.md)

## 隱私與金鑰

- Gemini API Key 由使用者在 App 內設定
- API Key 儲存在 iOS Keychain 與 Android secure storage
- 專案不包含任何預設 API Key、token、私人備份或私鑰

## 開源文件

- 授權： [MIT](./LICENSE)
- 安全政策： [English](./SECURITY.md) | [繁體中文](./SECURITY.zh-Hant.md) | [简体中文](./SECURITY.zh-Hans.md)
- 貢獻指南： [English](./CONTRIBUTING.md) | [繁體中文](./CONTRIBUTING.zh-Hant.md) | [简体中文](./CONTRIBUTING.zh-Hans.md)
- Pull Request 模板： [`.github/pull_request_template.md`](./.github/pull_request_template.md)
- CI 檢查清單： [`docs/CI_CHECKLIST.md`](./docs/CI_CHECKLIST.md)
- Android APK 建置流程： [`docs/ANDROID_APK_BUILD.md`](./docs/ANDROID_APK_BUILD.md)

## 免責聲明

本專案為個人財務管理工具，請自行評估使用風險並定期備份資料。
