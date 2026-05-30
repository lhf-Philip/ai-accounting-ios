# AI Accounting (iOS + Android)

Language: **English** | [繁體中文](./README.zh-Hant.md) | [简体中文](./README.zh-Hans.md)

AI Accounting is a personal finance app for multi-currency bookkeeping, account tracking, budgeting, advances, debt management, and backups.

- iOS is the product source of truth and the primary SwiftUI + SwiftData implementation.
- Android is an active Kotlin + Jetpack Compose implementation that follows the iOS information architecture and parity checklist.
- Android keeps one platform-specific extension: the home-screen widget.

## Core Features

- Multi-account bookkeeping for cash, bank, credit card, and debt accounts
- Multi-currency income, expense, transfer, advance, and debt flows
- Fully editable transfer flows, including grouped and same-account cross-currency transfers
- Advance tracking with repayment management and settlement centre views
- Debt management with borrow, repay, and debt-forgiveness semantics
- Income/expense charts with category/tag drill-down
- Budgets, overspending alerts, and AI-assisted budget suggestions
- Data health checks, JSON backup/restore, WebDAV remote backup with optional encryption, and CSV export
- Optional AI receipt scanning with a user-provided Gemini API key

## Platform Status

### iOS

- Production-focused SwiftUI app with SwiftData persistence
- Four maintained localisations: Traditional Chinese, Simplified Chinese, British English, and Japanese
- Simulator CI build and string-catalog validation on pull requests

### Android

- Kotlin + Jetpack Compose app with the same main tabs and core finance flows as iOS
- Room-backed local data layer, parity test vectors, and Android CI build/unit tests
- Android-only widget for quick summary visibility
- Ongoing parity work is tracked in [`docs/specs/android-ios-parity.md`](./docs/specs/android-ios-parity.md)

## In-App User Guide

- You can open the guide from `Settings > User Guide`.
- On first launch, the app shows the guide automatically.

## Localisation

iOS UI currently supports:

- Traditional Chinese (`zh-Hant`)
- Simplified Chinese (`zh-Hans`)
- British English (`en-GB`)
- Japanese (`ja`)

## Tech Stack

- iOS: SwiftUI, SwiftData, Charts, `generative-ai-swift`
- Android: Kotlin, Jetpack Compose, Room, WorkManager, Android widgets

## Requirements

- macOS
- Xcode (verified with `Xcode 26.2`) for iOS
- JDK 17+ and Android SDK for Android

## Quick Start

### iOS

1. Open `AI 記帳.xcodeproj` in Xcode.
2. Select a simulator or device.
3. Run with `Cmd + R`.

### Android

```bash
cd android
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest
```

Detailed APK build guide: [`docs/ANDROID_APK_BUILD.md`](./docs/ANDROID_APK_BUILD.md)

## CI

GitHub Actions on `push` / `pull_request` to `main`:

- `iOS CI`: string catalog validation + iOS simulator build
- `Android CI`: `:app:assembleDebug` + `:app:testDebugUnitTest`

## Data Compatibility

- Backup JSON contract: [`docs/specs/data-model.md`](./docs/specs/data-model.md)
- Cross-platform parity vectors: [`docs/specs/parity-test-vectors.md`](./docs/specs/parity-test-vectors.md)
- Manual validation matrix: [`docs/VALIDATION_MATRIX.md`](./docs/VALIDATION_MATRIX.md)

## Privacy and Secrets

- Gemini API key is provided by each user inside the app.
- API key is stored in iOS Keychain and Android secure storage.
- The repository does not include default API keys, tokens, personal backups, or private keys.

## Open-Source Documents

- License: [MIT](./LICENSE)
- Security policy: [English](./SECURITY.md) | [繁體中文](./SECURITY.zh-Hant.md) | [简体中文](./SECURITY.zh-Hans.md)
- Contribution guide: [English](./CONTRIBUTING.md) | [繁體中文](./CONTRIBUTING.zh-Hant.md) | [简体中文](./CONTRIBUTING.zh-Hans.md)
- Pull request template: [`.github/pull_request_template.md`](./.github/pull_request_template.md)
- CI checklist: [`docs/CI_CHECKLIST.md`](./docs/CI_CHECKLIST.md)
- Deployment guide: [`docs/DEPLOYMENT.md`](./docs/DEPLOYMENT.md)
- Android APK build guide: [`docs/ANDROID_APK_BUILD.md`](./docs/ANDROID_APK_BUILD.md)
- WebDAV remote backup guide: [`docs/REMOTE_BACKUP.md`](./docs/REMOTE_BACKUP.md)

## Disclaimer

This project is provided as-is for personal finance management. Please evaluate your own risk and keep regular backups.
