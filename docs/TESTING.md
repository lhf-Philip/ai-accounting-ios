# Testing Guide

Status: Active
Last reviewed: 2026-06-20
Applies to: iOS, Android, shared backup and accounting semantics
Sources of truth: [CI workflows](../.github/workflows/), [validation matrix](./VALIDATION_MATRIX.md), [parity vectors](./specs/parity-test-vectors.md), [data contract](./specs/data-model.md)

This guide defines what each test layer is responsible for and the minimum evidence required before merging or releasing financial-data changes.

## Testing Principles

- Test accounting meaning, not only view output.
- Prefer deterministic, synthetic fixtures. Never commit a real user backup.
- Every persisted-data change must test a supported old representation and a roundtrip.
- Shared semantics require matching iOS and Android coverage.
- UI automation proves navigation and wiring; unit and integration tests prove balances and invariants.
- A retry may classify a flaky test, but it does not erase the original failure.

## Test Layers

| Layer | Responsibility | Typical examples |
| --- | --- | --- |
| Pure unit | Deterministic calculations and classification without persistence or UI | report aggregation, refund classification, transfer exclusion, remaining advance amount |
| Service/repository integration | Atomic writes, relationship changes, rollback, import/export | transfer-group replacement, structural advance editing, backup roundtrip |
| Migration/compatibility | Opening or importing a supported older representation | SwiftData legacy fixture, Room migration, missing optional JSON fields |
| UI automation | Navigation, editor wiring, focus/keyboard behaviour, save/error surfaces | structural advance edit, transaction edit, Compose editor flows |
| Physical-device smoke | Signing, storage, performance, OS integration, vendor-specific behaviour | iPhone install/upgrade, Samsung A53 keyboard and scrolling |

## Current Automated Suites

### iOS

- `AI 記帳Tests/`
  - backup compatibility;
  - transaction and transfer editing;
  - advance structural editing;
  - report aggregation and refund semantics;
  - ledger semantic vectors.
- `AI 記帳UITests/`
  - structural advance editing;
  - ledger edit performance flow.
- `.github/workflows/ios-ci.yml`
  - string catalog validation;
  - simulator build;
  - unit tests on iPhone 13 Simulator;
  - focused structural advance UI tests.

### Android

- `android/app/src/test/`
  - backup roundtrip and data-health checks;
  - editor and transfer-group invariants;
  - advance editing;
  - report/refund semantics;
  - shared parity vectors.
- `android/app/src/androidTest/`
  - structural advance editing UI flow.
- `.github/workflows/android-ci.yml`
  - debug APK assembly;
  - unit tests;
  - API 35 emulator instrumentation;
  - failure diagnostics upload.

## Local Commands

Run commands from the repository root unless stated otherwise.

For local simulator tests, select an installed iPhone runtime first:

```bash
IOS_SIMULATOR_ID="$(python3 scripts/select-ios-simulator.py)"
```

The helper prefers iPhone 13 when it is installed and otherwise selects another available iPhone. This avoids Xcode interpreting a device name as `OS=latest` when that model only exists on an older installed runtime.

### iOS simulator build

```bash
xcodebuild \
  -project 'AI 記帳.xcodeproj' \
  -scheme 'AI 記帳' \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### iOS unit tests

```bash
xcodebuild \
  -project 'AI 記帳.xcodeproj' \
  -scheme 'AI 記帳' \
  -destination "platform=iOS Simulator,id=$IOS_SIMULATOR_ID" \
  CODE_SIGNING_ALLOWED=NO \
  test
```

### Focused iOS structural UI tests

```bash
xcodebuild \
  -project 'AI 記帳.xcodeproj' \
  -scheme 'AI 記帳 UI Automation' \
  -destination "platform=iOS Simulator,id=$IOS_SIMULATOR_ID" \
  -only-testing:'AI 記帳UITests/AdvanceStructuralEditingUITests' \
  test
```

### Android unit tests and debug APK

```bash
cd android
./gradlew :app:testDebugUnitTest :app:assembleDebug
```

### Android instrumentation

With an emulator or USB device available:

```bash
cd android
./gradlew :app:connectedDebugAndroidTest
```

CI uses `.github/scripts/run-android-instrumentation.sh` to add timeout handling and collect diagnostics.

### Documentation checks

```bash
python3 scripts/check-docs.py
```

## Fixture Rules

Committed fixtures must be:

- generated or irreversibly anonymised;
- minimal enough to explain the behaviour under test;
- free of names, account numbers, notes, photos, device paths, tokens, and production URLs;
- versioned with a short comment in the test describing the legacy condition;
- duplicated on both platforms when they define a shared backup contract.

Do not copy a phone database or user JSON into the repository and redact it later. Build a fixture from synthetic records instead.

## Required Financial Invariants

Tests must protect these rules whenever the affected code path changes:

- Income increases an own account and contributes to income reports.
- Expense decreases an own account and contributes to expense reports.
- Transfers move value between accounts but do not contribute to income or expense.
- Same-account cross-currency transfers preserve both actual currency amounts.
- Repayment changes assets and debt, but does not count the original expense twice.
- Debt forgiveness and mutual offset do not become ordinary income or expense.
- An advance case appears once in the ledger summary while account detail preserves actual cash-flow legs.
- Cross-currency repayment preserves payment currency, settlement currency, and normalised amount.
- Refund report reduction is capped at the remaining original expense; excess is settlement-only.
- Import/export preserves UUIDs, references, currencies, timestamps, and semantic roles.

Use [the parity vectors](./specs/parity-test-vectors.md) for deterministic cross-platform examples.

## Change-Specific Minimums

### UI-only change

- Build the affected platform.
- Exercise the changed screen and at least one error/empty state.
- Verify keyboard dismissal, scrolling, safe-area behaviour, and accessibility labels when input or navigation changed.

### Accounting or editor change

- Add a pure or service/repository regression test.
- Test create, edit, and delete/rollback.
- Confirm report inclusion/exclusion.
- Run the equivalent parity test on both platforms.

### Persisted model or backup change

- Follow [Data Migration And Recovery](./DATA_MIGRATION_AND_RECOVERY.md).
- Test fresh data and the previous supported representation.
- Test first launch/import and a second launch/import.
- Test export → import → export.
- Test failure rollback and reference integrity.

### External service change

- Unit-test request construction and response/error mapping where practical.
- Manually verify success, network failure, authentication failure, and unavailable-cache behaviour.
- Never require a real secret in CI.

## Physical-Device Smoke

Use physical devices before a release or when changing storage, signing, camera, keyboard, WebDAV, background work, or performance-sensitive editors.

Minimum devices:

- iPhone 13 or the currently supported iPhone used for development;
- Samsung A53, or another representative mid-range Android device.

For data migrations, install over the existing app. Do not uninstall first. Export a safety backup, verify the upgrade, relaunch twice, then check balances and an editable advance case.

## Failure Artifacts

Keep enough evidence to diagnose the first failure:

- iOS: `xcodebuild.log`, `xcodebuild-test.log`, `xcodebuild-ui-test.log`, result bundle when available, crash stack, simulator runtime.
- Android: JUnit XML, HTML report, instrumentation results, logcat, screenshot/UI hierarchy, emulator API and architecture.
- Data: fixture version, pre/post record counts, health-check output, and whether rollback succeeded.

Do not attach real backups or unredacted financial screenshots to public issues.

## Flaky-Test Policy

1. Preserve the original failure and artifact.
2. Re-run the same test once to classify deterministic versus intermittent behaviour.
3. If intermittent, record the suspected source and make the test deterministic or quarantine it with an owner and follow-up issue.
4. Do not merge solely because a retry passed.
5. Never add arbitrary sleeps when a state-based wait or deterministic clock can solve the problem.

## Pull Request Evidence

The PR description should list:

- exact commands run;
- affected platforms;
- fixtures and source versions used;
- manual devices/OS versions used;
- accounting invariants checked;
- failures, retries, or tests not run and why.
