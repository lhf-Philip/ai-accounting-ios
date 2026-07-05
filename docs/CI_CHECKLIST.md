# CI Checklist (iOS + Android)

Status: Active  
Last reviewed: 2026-07-05
Applies to: iOS, Android, developer documentation
Sources of truth: [Testing Guide](./TESTING.md), [GitHub workflows](../.github/workflows/)

This checklist is the baseline for PR quality gates for dual-platform delivery. Treat Android as a maintained implementation when deciding affected-platform validation.

## 1. Required GitHub Checks

- iOS CI (`.github/workflows/ios-ci.yml`)
- Android CI (`.github/workflows/android-ci.yml`)
- Docs CI (`.github/workflows/docs-ci.yml`)

## 2. Pull Request Gate (Must Pass)

- Required checks must run; a path-filtered skip is not equivalent to a pass.
- Build success on every affected platform.
- No sensitive data committed (keys, tokens, real personal backup data).
- Data contract impact evaluated against `docs/specs/data-model.md`.
- If data contract changed: migration/compatibility section completed in PR template.

## 3. Local Pre-PR Commands

### iOS
```bash
IOS_SIMULATOR_ID="$(python3 scripts/select-ios-simulator.py)"

xcodebuild -project 'AI 記帳.xcodeproj' \
  -scheme 'AI 記帳' \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

```bash
xcodebuild -project 'AI 記帳.xcodeproj' \
  -scheme 'AI 記帳' \
  -destination "platform=iOS Simulator,id=$IOS_SIMULATOR_ID" \
  CODE_SIGNING_ALLOWED=NO \
  test
```

### String catalog sanity
```bash
python3 -m json.tool Localizable.xcstrings > /dev/null
xcrun xcstringstool compile --dry-run --output-directory /tmp/xcstrings-build Localizable.xcstrings
```

### Android
```bash
cd android
./gradlew :app:testDebugUnitTest :app:assembleDebug
./gradlew :app:connectedDebugAndroidTest
```

### Developer documentation
```bash
python3 scripts/check-docs.py
```


### Regression infrastructure
When touching `.github/workflows/**`, `.github/scripts/**`, or `scripts/run-*regression.sh`, also confirm workflow path filters include the changed dependency and the intended GitHub checks appear on the PR.

## 4. Manual Validation (Minimum)

- Add transaction (income/expense) and verify report totals.
- Transfer flow (including grouped transfer) and verify it does not affect income/expense totals.
- Backup export/import with `android/app/src/test/resources/fixtures/legacy_bidirectional_advances.json`.
- Legacy repair regression with:
  - `android/app/src/test/resources/fixtures/legacy_bidirectional_advances.json`
  - `android/app/src/test/resources/fixtures/legacy_debt_income_repair.json`
- Advance tracking flow (create case, repayment, remaining amount).
- Follow the cross-platform matrix in `docs/VALIDATION_MATRIX.md`.

## 5. Data Regression Guard

When a PR changes backup format, repair rules, or model semantics:
- Add or update at least one legacy fixture.
- Run `restore -> health check -> repair -> re-check -> export` on the affected fixture set.
- Confirm iOS and Android both accept the supported legacy backups.

## 6. Release Gate

Before creating a release tag:
- Confirm all required checks are green.
- Confirm open PR count is zero.
- Confirm release notes include data-model compatibility statement.
- Confirm backup import from previous stable release still works.
- Follow the complete checklist in [`RELEASING.md`](./RELEASING.md).
