# AI Accounting iOS

Language: **English** | [繁體中文](./README.zh-Hant.md) | [简体中文](./README.zh-Hans.md)

AI Accounting iOS is a personal finance app built with SwiftUI + SwiftData.
It supports multi-currency bookkeeping, transfers, debt/advance tracking, reports, backup/restore, and AI receipt scanning.

## What's New in UI (2026-03)

- New information architecture: `Home / Ledger / Reports / Accounts / Settings`
- New Home dashboard with monthly overview and quick entry points
- New in-app User Guide page, with first-launch onboarding sheet
- Settings page reorganized into onboarding, preferences, data safety, and tools

## Core Features

- Multi-account bookkeeping (cash, bank, credit card, debt)
- Multi-currency transactions (currency per transaction)
- Fully editable transfer flows (including multi-leg transfer groups)
- Advance tracking and repayment management
- Income/expense charts with category/tag drill-down
- Full JSON backup/restore and CSV export
- Optional AI receipt scanning with Gemini API key

## In-App User Guide

- You can open the guide from `Settings > User Guide`.
- On first launch, the app shows the guide automatically.

## Localization

App UI currently supports:

- Traditional Chinese (`zh-Hant`)
- Simplified Chinese (`zh-Hans`)
- British English (`en-GB`)
- Japanese (`ja`)

## Tech Stack

- SwiftUI
- SwiftData
- Charts
- Google Generative AI Swift SDK (`generative-ai-swift`)

## Requirements

- macOS
- Xcode (verified with `Xcode 26.2`)
- iOS Simulator or physical iPhone

## Quick Start

1. Clone this repository.
2. Open `AI 記帳.xcodeproj` in Xcode.
3. Select a simulator or device.
4. Run with `Cmd + R`.

## CI

GitHub Actions runs on `push` and `pull_request` to `main`:

- `Localizable.xcstrings` validation
- iOS simulator build

## Privacy and Secrets

- Gemini API key is provided by each user inside the app.
- API key is stored in iOS Keychain.
- The repository does not include default API keys, tokens, or private keys.

## Data Compatibility

- No breaking data-model migration from snapshot `4417c97` (2026-02-24) to current releases.
- Existing JSON backups remain import-compatible.

## Open-Source Documents

- License: [MIT](./LICENSE)
- Security policy: [English](./SECURITY.md) | [繁體中文](./SECURITY.zh-Hant.md) | [简体中文](./SECURITY.zh-Hans.md)
- Contribution guide: [English](./CONTRIBUTING.md) | [繁體中文](./CONTRIBUTING.zh-Hant.md) | [简体中文](./CONTRIBUTING.zh-Hans.md)
- Pull request template: [`.github/pull_request_template.md`](./.github/pull_request_template.md)

## Disclaimer

This project is provided as-is for personal finance management. Please evaluate your own risk and keep regular backups.
