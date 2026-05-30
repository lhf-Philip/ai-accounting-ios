# Validation Matrix

Status: Active  
Last updated: 2026-03-23

This matrix is the shared validation baseline before merging dual-platform work. Android is treated as an active app implementation, so validation should cover both parity behaviour and Android-specific surfaces such as the widget where relevant.

## Regression Fixture

- Fixture path: `android/app/src/test/resources/fixtures/legacy_bidirectional_advances.json`
- Coverage:
  - Existing income and expense data
  - Advance flow where I advanced others
  - Advance flow where others advanced me
  - Repayment split across two receive accounts
  - Repayment merge from two source accounts
  - Legacy-null fields for category kind, budget enable flag, case self share, repayment normalized amount

## Automated Validation

### Android
```bash
cd android
./gradlew testDebugUnitTest
./gradlew assembleDebug
```

### iOS
```bash
xcodebuild -project 'AI 記帳.xcodeproj' \
  -scheme 'AI 記帳' \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Manual Matrix

| Platform | Device | Flow | Expected Result |
| --- | --- | --- | --- |
| iOS | Simulator | Import fixture JSON | Data imports successfully with no crash |
| iOS | Simulator | Advance: I advanced others | Create -> edit -> repayment -> delete stays consistent |
| iOS | Simulator | Advance: others advanced me | Create -> edit -> repayment -> delete stays consistent |
| iOS | Physical device | Backup export/import | Exported JSON re-imports cleanly |
| Android | Emulator | Import fixture JSON | Data imports successfully with no crash |
| Android | Emulator | Main tabs parity smoke | Overview, Ledger, Reports, Accounts, and Settings open with the expected controls |
| Android | Emulator | Account delete | Predictable result with and without linked transactions |
| Android | Samsung A53 | Advance split repayment | Two receive accounts can be recorded and shown correctly |
| Android | Samsung A53 | Advance merge repayment | Two source accounts can be recorded and shown correctly |

## Minimum Flow Sequence

Every core flow should cover at least one full cycle:

- Add -> edit -> delete for income/expense
- Add -> edit -> delete for transfer group
- Add -> edit -> repayment or rollback for advance
- Import -> operate -> export -> re-import for backup safety
- WebDAV encrypted upload/restore and plain JSON upload/restore per [`docs/REMOTE_BACKUP.md`](./REMOTE_BACKUP.md)
