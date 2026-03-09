# Android Scaffold

This folder contains the Android app baseline for AI Accounting.

## Current Scope

- Compose app shell with 4 tabs: Overview / Transactions / Reports / Settings
- First-launch behavior: open Overview on first launch, default to Transactions afterward
- Widget with app-driven preview content and refresh hook (`SummaryWidgetProvider`)
- Kotlin parity core for cross-platform data behavior
- Unit tests for parity vectors from `/docs/specs/parity-test-vectors.md`

## Implemented Core Modules

- `core/model`: canonical enums and entities aligned with `/docs/specs/data-model.md`
- `core/report`: income/expense totals, transfer exclusion, category-kind filtering
- `core/advance`: participant repayment progress and outstanding totals
- `core/backup`: legacy backup defaults compatibility helpers

## Build & Test

Use Gradle wrapper from this folder:

```bash
cd android
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest
```

## Release Signing

To create a Play-uploadable release bundle, add a local `android/keystore.properties`
file with:

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=your-store-password
keyAlias=your-key-alias
keyPassword=your-key-password
```

The release signing config is only activated when this file exists, so CI and local
debug builds stay unaffected.

## Environment Prerequisite

If Android SDK is not auto-detected, set one of:

- `ANDROID_HOME` environment variable, or
- `android/local.properties` with:

```properties
sdk.dir=/Users/<your-user>/Library/Android/sdk
```
