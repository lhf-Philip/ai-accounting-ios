# AI Accounting (iOS + Android)

Language: **English** | [繁體中文](./README.zh-Hant.md) | [简体中文](./README.zh-Hans.md)

AI Accounting is a personal finance app project.

- iOS app is production-ready (SwiftUI + SwiftData).
- Android app currently has a scaffold baseline (Jetpack Compose) for phased parity implementation.

## iOS Features (Current)

- Multi-account bookkeeping (cash, bank, credit card, debt)
- Multi-currency transactions (currency per transaction)
- Fully editable transfer flows (including multi-leg transfer groups)
- Advance tracking and repayment management
- Income/expense charts with category/tag drill-down
- Full JSON backup/restore and CSV export
- Optional AI receipt scanning with Gemini API key

## Android Status (Scaffold)

- App shell with Compose entry screen
- Widget stub (`SummaryWidgetProvider`)
- Unit-test scaffold
- CI workflow baseline

See: `android/README.md`

## In-App User Guide (iOS)

- You can open the guide from `Settings > User Guide`.
- On first launch, the app shows the guide automatically.

## Localization

iOS UI currently supports:

- Traditional Chinese (`zh-Hant`)
- Simplified Chinese (`zh-Hans`)
- British English (`en-GB`)
- Japanese (`ja`)

## Tech Stack

- iOS: SwiftUI, SwiftData, Charts, `generative-ai-swift`
- Android: Kotlin, Jetpack Compose (scaffold phase)

## Requirements

- macOS
- Xcode (verified with `Xcode 26.2`) for iOS
- JDK 17+ and Android SDK for Android

## Quick Start

### iOS

1. Open `AI 記帳.xcodeproj` in Xcode.
2. Select a simulator or device.
3. Run with `Cmd + R`.

### Android (Scaffold)

```bash
cd android
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest
```

## CI

GitHub Actions on `push` / `pull_request` to `main`:

- `iOS CI`: string catalog validation + iOS simulator build
- `Android CI`: `:app:assembleDebug` + `:app:testDebugUnitTest`

## Data Compatibility

- Backup JSON contract: `docs/specs/data-model.md`
- Cross-platform parity vectors: `docs/specs/parity-test-vectors.md`

## Privacy and Secrets

- Gemini API key is provided by each user inside the app.
- API key is stored in iOS Keychain.
- The repository does not include default API keys, tokens, or private keys.

## Open-Source Documents

- License: [MIT](./LICENSE)
- Security policy: [English](./SECURITY.md) | [繁體中文](./SECURITY.zh-Hant.md) | [简体中文](./SECURITY.zh-Hans.md)
- Contribution guide: [English](./CONTRIBUTING.md) | [繁體中文](./CONTRIBUTING.zh-Hant.md) | [简体中文](./CONTRIBUTING.zh-Hans.md)
- Pull request template: [`.github/pull_request_template.md`](./.github/pull_request_template.md)
- CI checklist: [`docs/CI_CHECKLIST.md`](./docs/CI_CHECKLIST.md)
- Deployment guide: [`docs/DEPLOYMENT.md`](./docs/DEPLOYMENT.md)

## Disclaimer

This project is provided as-is for personal finance management. Please evaluate your own risk and keep regular backups.
