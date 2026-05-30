# Android App

This folder contains the Android implementation of AI Accounting. Android follows the iOS app as the product source of truth while using native Kotlin, Jetpack Compose, Room, WorkManager, and Android widget APIs.

## Current Scope

- Five main tabs aligned with iOS: Overview / Ledger / Reports / Accounts / Settings
- First-launch behaviour: open Overview on first launch, then default to Ledger for returning users
- Core bookkeeping flows for income, expense, transfer, debt, advances, budgets, reports, accounts, and backups
- Settlement centre, data health checks, recurring transactions, WebDAV backup with optional encryption, and local preferences
- Optional receipt scan review flow and Gemini API key settings
- Android-only summary widget with app-driven preview content and refresh hook (`SummaryWidgetProvider`)
- Unit tests for parity vectors from `../docs/specs/parity-test-vectors.md`

## Implemented Core Modules

- `core/model`: canonical enums and entities aligned with `../docs/specs/data-model.md`
- `core/report`: income/expense totals, transfer exclusion, category-kind filtering, and report summaries
- `core/advance`: participant repayment progress and outstanding totals
- `core/backup`: JSON backup compatibility and legacy defaults
- `core/currency`: currency formatting, conversion, and rate-source helpers
- `data`: Room database, DAO, repository, secure settings, and import/export support
- `ui`: Compose screens and parity UI components aligned with the iOS information architecture
- `widget`: Android summary widget provider and update plumbing

## Build & Test

Use the Gradle wrapper from this folder:

```bash
cd android
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest
```

Detailed APK build guide: [`../docs/ANDROID_APK_BUILD.md`](../docs/ANDROID_APK_BUILD.md)

WebDAV remote backup guide: [`../docs/REMOTE_BACKUP.md`](../docs/REMOTE_BACKUP.md)

## APK Location

After `assembleDebug`, the debug APK is written to:

```text
android/app/build/outputs/apk/debug/app-debug.apk
```

## Release Signing

To create a Play-uploadable release bundle, add a local `android/keystore.properties` file with:

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=your-store-password
keyAlias=your-key-alias
keyPassword=your-key-password
```

The release signing config is only activated when this file exists, so CI and local debug builds stay unaffected.

## Environment Prerequisite

If Android SDK is not auto-detected, set one of:

- `ANDROID_HOME` environment variable, or
- `android/local.properties` with:

```properties
sdk.dir=/Users/<your-user>/Library/Android/sdk
```

`local.properties` and `keystore.properties` are local-only files and must not be committed.
