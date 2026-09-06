# Testing Guide

Status: Active
Last reviewed: 2026-07-05
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
- Test infrastructure changes must update the matching workflow trigger paths and this guide in the same PR.

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
  - ledger/budget atomicity, rollback of split entries and grouped deletion, and retry after injected synchronization failure;
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
  - deterministic emulator/device smoke covering Room and repository wiring;
  - app launch and a minimal advance-case persistence roundtrip.
- `.github/workflows/android-ci.yml`
  - debug APK assembly;
  - unit tests;
  - API 35 emulator instrumentation smoke;
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

### Full iOS regression runner

Use the runner when validating a PR locally. It runs documentation checks,
money-fixture checks, simulator build, unit tests, and focused structural UI
automation while storing logs and result bundles under `build/regression/`.

```bash
scripts/run-ios-regression.sh
```

If `xctrunner` fails to launch with a Simulator `Busy` or preflight error, the
runner terminates stale app/test-runner processes and retries once. A second
runner-launch failure exits with code `69` and should be reported as
environment-blocked, not as a product regression.

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
The CI wrapper also waits for `sys.boot_completed`, wakes and unlocks the
emulator, disables animations, and captures activity/window/UI diagnostics on
failure. Treat a first-test timeout differently from a product assertion:

- download the `android-instrumentation-failure-*` artifact from the failing run;
- inspect `TEST-*.xml` first for the failing gate or assertion;
- inspect `activity.txt`, `window.txt`, `uiautomator.xml`, and `failure.png` to
  confirm whether the app, test activity, or launcher was foregrounded;
- inspect `logcat.txt` for app crashes before changing test timeouts.

If `gh run view --log` cannot write to the default cache on a restricted
machine, use a writable cache directory:

```bash
XDG_CACHE_HOME=/private/tmp/codex-gh-cache gh run view <run-id> --log
```

The required instrumentation suite is intentionally a small environment and
data-wiring smoke test. Business semantics and structural advance editing
belong in JVM repository/service tests, where they are deterministic. Add a
Compose UI test only when it proves a user-visible interaction that cannot be
covered at a lower layer, and give it a stable semantic readiness condition.

Do not fix instrumentation flakiness by disabling the test, ignoring
`connectedDebugAndroidTest`, or only increasing timeouts. First classify the
failure using the captured artifacts:

- product failure: the app is foregrounded and a business assertion fails;
- test-harness failure: the test activity or Compose content is not mounted;
- emulator/infrastructure failure: the launcher, system process, or device is
  unhealthy.

Keep the original failing artifact when retrying. A retry may establish that a
failure is flaky, but it does not turn the first failure into a pass. Fix the
lowest-cost layer that owns the problem and add a regression check before
restoring broader UI coverage.

Changing test infrastructure requires the same discipline as product code: prefer precise readiness gates and diagnostics over sleeps; never merge a workflow/script change until the relevant local runner and GitHub check have both been observed or a documented environment block explains why not.

### Required-check interpretation

For a pull request, a required check is evidence only when it completed for
the latest commit or merge test commit. A skipped workflow caused by path
filters is not equivalent to running the check. If a workflow or runner path
changes, verify that the pull request triggers the intended check and record
any environment block explicitly. Administrative review bypasses do not waive
build, test, or data-safety checks.

### Full Android regression runner

Use the runner when validating Android locally. It runs documentation checks,
money-fixture checks, unit tests, debug APK assembly, and connected
instrumentation while storing logs under `build/regression/`.

The local runner is the source of truth for full Android regression scope. GitHub CI uses the narrower workflow stages plus `.github/scripts/run-android-instrumentation.sh`; when either runner or wrapper changes, update `.github/workflows/android-ci.yml` path filters so Android CI cannot be skipped by a scripts-only PR.

```bash
scripts/run-android-regression.sh
```

If no Android device is connected, the runner exits with code `69`. To launch
the default local AVD and clean it up afterwards:

```bash
START_ANDROID_EMULATOR=1 scripts/run-android-regression.sh
```

Override the AVD or SDK paths when needed:

```bash
ANDROID_AVD_NAME=Medium_Phone_API_36.1 \
ANDROID_HOME="$HOME/Library/Android/sdk" \
scripts/run-android-regression.sh
```

### CI and regression infrastructure changes

When changing `.github/workflows/**`, `.github/scripts/**`, or `scripts/run-*regression.sh`:

- update workflow path filters in the same PR when a path-filtered check depends on the changed file;
- run `python3 scripts/check-docs.py` and `python3 scripts/check-money-fixtures.py`;
- run the affected local regression runner, or record a concrete environment-blocked reason such as missing Simulator or emulator;
- confirm the opened PR triggers the intended GitHub checks;
- do not mark Android instrumentation as optional because unit tests passed.

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


### Exact Money Fixtures

Financial test fixtures must not use fractional floating-point literals for money. Swift `Decimal` values created from `35.59` can vary across compiler and SDK versions because the literal is first represented as binary floating point. Use `exactDecimal("35.59")` in iOS tests, or `Decimal(string: "35.59")!` when a helper is not available. Integer fixtures such as `Decimal(100)` are acceptable.

The repository enforces this with:

```bash
python3 scripts/check-money-fixtures.py
```


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

## Environment-Blocked Runs

Use `environment-blocked` only when the runner or device infrastructure prevents
the test from starting or collecting a meaningful assertion result. Examples:

- iOS Simulator refuses to launch `xctrunner` with `Application failed preflight checks`.
- Android has no connected device and no local AVD was requested.
- Android Emulator itself cannot boot or ADB never reports `sys.boot_completed=1`.

Do not use `environment-blocked` for product crashes, failed assertions, missing
UI nodes after the app is running, data mismatches, or migration failures. Those
are regressions until proven otherwise.

## Pull Request Evidence

The PR description should list:

- exact commands run;
- affected platforms;
- fixtures and source versions used;
- manual devices/OS versions used;
- accounting invariants checked;
- failures, retries, or tests not run and why.

## Ledger commit boundary (#166)

Ordinary add, scan, shortcut, edit and ledger deletion stage their ledger and budget-history changes in one context, then save once. Nested budget synchronization uses `save: false`; standalone callers retain the default save behavior. The operation owns pending changes in that synchronous context and temporarily disables autosave. On error, inserted inverse relationships or retained editor values are repaired before rollback, then the error reaches the view. This does not introduce a schema or backup-format change.

Apple documents [save](https://developer.apple.com/documentation/swiftdata/modelcontext/save()) as writing pending inserts, updates and deletes, and [includePendingChanges](https://developer.apple.com/documentation/swiftdata/fetchdescriptor/includependingchanges) as true by default. Integration tests verify that budget queries observe pending inserts, date/category moves and deletions before the commit. Failure tests inspect both the active context and a fresh reader, then retry to detect duplicate or leaked entries. UI tests cover ordinary, transfer and advance editing; physical-device upgrade/storage smoke remains a release check.

The ledger UI regression navigates from an advance-case summary to its repayment record and scrolls to the editor note field. The prior test expected a standalone repayment ledger row; the captured failure showed the existing case grouping with its outstanding balance intact.
