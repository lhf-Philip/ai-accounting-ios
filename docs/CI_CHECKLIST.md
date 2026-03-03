# CI Checklist (iOS + Android)

Status: Active  
Last updated: 2026-03-03

This checklist is the baseline for PR quality gates while the repository evolves from iOS-only to iOS + Android.

## 1. Required GitHub Checks

### Current required checks
- iOS CI build on pull requests to `main`
- `Localizable.xcstrings` validation

### Add when `/android` is created
- Android CI (`assembleDebug`)
- Android unit tests
- Android lint / static checks

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

### Android (enable after `/android` exists)
```bash
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest
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
