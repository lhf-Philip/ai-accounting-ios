# Android Scaffold

This folder contains the initial Android scaffold for AI Accounting.

## Current Scope

- Compose app shell
- Widget provider stub (`SummaryWidgetProvider`)
- Basic unit test scaffold
- Ready for data-layer implementation based on `docs/specs/data-model.md`

## Local Build (without wrapper)

This scaffold currently uses system Gradle in CI and local development.

```bash
gradle -p android :app:assembleDebug
gradle -p android :app:testDebugUnitTest
```

A Gradle wrapper can be added in a later PR.
