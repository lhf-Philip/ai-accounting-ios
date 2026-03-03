# CI Checklist (iOS + Android)

Status: Active  
Last updated: 2026-03-03

This checklist is the baseline for PR quality gates for dual-platform delivery.

## 1. Required GitHub Checks

- iOS CI (`.github/workflows/ios-ci.yml`)
- Android CI (`.github/workflows/android-ci.yml`)

## 2. Pull Request Gate (Must Pass)

- Build success on every affected platform.
- No sensitive data committed (keys, tokens, real personal backup data).
- Data contract impact evaluated against `docs/specs/data-model.md`.
- If data contract changed: migration/compatibility section completed in PR template.

## 3. Local Pre-PR Commands

### iOS
```bash
xcodebuild -project 'AI 記帳.xcodeproj' \
  -scheme 'AI 記帳' \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build
```

### String catalog sanity
```bash
python3 -m json.tool Localizable.xcstrings > /dev/null
xcrun xcstringstool compile --dry-run --output-directory /tmp/xcstrings-build Localizable.xcstrings
```

### Android (scaffold phase)
```bash
gradle -p android :app:assembleDebug
gradle -p android :app:testDebugUnitTest
```

## 4. Manual Validation (Minimum)

- Add transaction (income/expense) and verify report totals.
- Transfer flow (including grouped transfer) and verify it does not affect income/expense totals.
- Backup export/import with an existing JSON sample.
- Advance tracking flow (create case, repayment, remaining amount).

## 5. Release Gate

Before creating a release tag:
- Confirm all required checks are green.
- Confirm open PR count is zero.
- Confirm release notes include data-model compatibility statement.
- Confirm backup import from previous stable release still works.
