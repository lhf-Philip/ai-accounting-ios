# Testing Guide

Status: Active
Last reviewed: 2026-09-10
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
  - ledger edit performance flow;
  - startup recovery for store-open and pre-migration-backup failures, followed by a successful retry.
- `.github/workflows/ios-ci.yml`
  - string catalog validation;
  - simulator build;
  - unit tests on an available iPhone Simulator selected by UDID;
  - focused structural advance, inline-category-save, and startup-recovery UI tests.

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

The helper prefers iPhone 13 when it is installed and otherwise selects another available iPhone. This avoids Xcode interpreting a device name as `OS=latest` when that model only exists on an older installed runtime. The iOS workflow uses the same selector and explicitly sets `shell: bash` so `pipefail` propagates an `xcodebuild` failure through `tee`. Failed runs upload the unit/UI result bundles. A green check without an executed-test summary is not sufficient evidence; the previous name-only destination and default shell combination masked unavailable-destination errors. See [GitHub shell semantics](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idstepsshell).

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

### Focused iOS startup-recovery UI tests

`StoreStartupRecoveryUITests` injects store-open and pre-migration-backup
failures through DEBUG-only launch arguments. Both tests verify that recovery
appears before the ledger, the diagnostics action is available, and retry opens
the ledger and dismisses recovery. Retry uses an in-memory store; these fixtures
do not open or modify the production store. The tests check the diagnostics
entry point, not the share sheet or exported file contents.

```bash
xcodebuild \
  -project 'AI 記帳.xcodeproj' \
  -scheme 'AI 記帳 UI Automation' \
  -destination "platform=iOS Simulator,id=$IOS_SIMULATOR_ID" \
  -parallel-testing-enabled NO \
  -only-testing:'AI 記帳UITests/StoreStartupRecoveryUITests' \
  -testLanguage zh-Hant \
  CODE_SIGNING_ALLOWED=NO \
  test
```

iOS CI already includes this suite in its existing focused UI step. The local
full regression runner currently selects structural editing only; run the
command above when validating startup recovery locally. Recovery localization
changes also need a screen smoke check in a non-Chinese language, because the
existing tests assert the ledger tab using its Chinese label.

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

The local runner is the source of truth for full Android regression scope. GitHub CI uses the narrower workflow stages plus `.github/scripts/run-android-instrumentation.sh`; when either runner or wrapper changes, update `scripts/ci-scope.py` scope rules so Android CI cannot be skipped by a scripts-only PR.

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
## Unavailable FX (#167)

`CurrencyService.convert` delegates to the optional estimate path and throws when a required rate is missing, invalid, or outside Decimal's representable range. Same-currency values stay exact. Combined UI totals with any missing conversion expose partial/unavailable status and withhold the numeric total. Cached rates, including the existing stale-cache fallback, remain labeled as cached. No recorded transaction or explicit repayment conversion is re-priced.

Both full and affected-key budget-history synchronization calculate every desired snapshot before changing the context. The fault test first persists valid HKD/USD history, removes the usable USD rate, then checks that both synchronization APIs throw without dirtying or overwriting any previous snapshot, including after a subsequent save and fresh-context read. Budget status and AI input preparation propagate missing rates instead of supplying fabricated numbers. Model schema and backup version are unchanged; historical snapshots already affected by the old fallback require recomputation with valid rates.

Source of truth: [ADR 0003](./adr/0003-report-currency-estimates.md) and [CONTEXT](../CONTEXT.md). The production failure was reproduced with missing source/target rates. Currency tests are asynchronous because synchronous XCTest teardown on the installed Swift runtime hit the documented [Swift issue 87316](https://github.com/swiftlang/swift/issues/87316); no production runtime workaround was added.

The FX caller audit also found save-before-history sequences in advance creation/deletion, recurring confirmation, account deletion, and legacy borrowed-advance maintenance. These now use the ledger commit owner with staged history synchronization. New failure tests cover advance/recurring retries, account/case deletion, and budget batch rollback. Budget editing, carryover, deletion and AI suggestions use a budget mutation boundary that restores retained values and removes failed inserts. This prevents a newly explicit FX error from being reported after a primary write already committed.

Backup restore preserves imported ledger amounts and existing historical snapshots when current FX is unavailable; only optional history re-estimation is deferred. Other read/write errors still propagate through backup recovery. A combined #168/#167 regression imports a previously valid foreign-currency backup after removing its rate and verifies the original transaction IDs/amounts and snapshot value.

### Ledger context ownership

Committing ledger mutations require a clean ModelContext. The service checks
`hasChanges` before invoking mutation, synchronization, recovery, save or rollback;
an unrelated pending insert, edit or deletion causes a recoverable error and is
left untouched. The owner of the pending work must resolve it before retrying.
Do not pre-save or roll back a shared context just to pass this check.

Add/scan/edit views build value drafts. Creating a tag in the add form is its
own guarded commit, so it does not leave a pending insert for the ledger save.
Shortcuts only read their template, and
ledger deletion stages its changes inside the boundary. Their error handlers
show the error without saving or rolling back. Direct-bound editors elsewhere
can leave a dirty context; those operations are deliberately rejected rather than
silently absorbing their edits. This is an enforced clean-context contract, not
an isolated-context implementation that permits concurrent pending edits.

`LedgerMutationAtomicityTests` covers unrelated pending inserts/edits/deletions,
normal and throwing synchronization, edit/delete/shortcut entry points, and a
single successful retry after the pending-work owner explicitly saves.
See [Apple save](https://developer.apple.com/documentation/swiftdata/modelcontext/save())
and [rollback](https://developer.apple.com/documentation/swiftdata/modelcontext/rollback()).

Advance creation/deletion, recurring confirmation, budget mutations, account
deletion and legacy maintenance use the same outer clean-context guard. Nested
`commit: false` work remains staging-only inside its owner's boundary. The
advance creation view leaves recovery to the service and commits newly created
tags as separate guarded actions. Test seed/fixture owners commit their setup
before invoking domain operations; production code must not pre-save shared work.

Required advance-deletion reads are injectable for failure testing. All transfer
groups and the self-expense row are fetched before deletion begins. Tests fail
each of three reads in turn, preserving case, participant, repayment, transaction
IDs and budget history, then verify a successful retry removes the target once.

### CI scope and superseded runs

Main requires the existing GitHub Actions checks `build` (Android),
`build-and-test` (iOS), and `validate` (Docs), including for administrators.
Platform workflows always report a check. After checkout, `scripts/ci-scope.py`
selects heavy work from the full PR
merge-base diff (or the push before/after diff). Ordinary documentation changes
run Docs CI only; iOS and Android changes run their respective platform stages.
Shared `docs/specs/` changes, scope-rule changes, and unknown paths run both.
Renames include both paths; invalid diffs fail the check instead of skipping tests.
The job summary explicitly distinguishes unaffected platforms from executed tests.
A lightweight platform job still starts, but skips SDK setup, builds and simulators.

New commits cancel older runs for the same PR and workflow. Running `main` workflows
are not cancelled; while one is active, GitHub concurrency may replace an older
pending `main` run with a newer one. Existing unit, UI, fixture and localization
checks remain intact. iOS retains explicit Bash/pipefail and available-simulator
UDID selection so failed test commands cannot be masked by `tee`.

During development, run affected tests first; use one final CI run for the
reviewed revision. Re-run only for changed code, a failure, or unresolved evidence.

### Inline creation and repayment rollback follow-up

Creating a category commits through the guarded ledger boundary before notifying
its parent or closing the sheet. It is a separate explicit action: cancelling the
transaction later keeps the category. Save failure keeps the sheet open, drops
the failed insertion, and permits retry. A dirty context is rejected unchanged.
Inline tag creation in transaction/advance/repayment forms and debt-account
creation in the advance form also use guarded commits.

The repayment rollback path propagates required linked-transfer read failures
before changing repayment totals or deleting rows. Fault injection enters via
`LedgerDeletionService.delete`, verifies the current context and an independent
reader, and retries once. Category tests cover commit/cancellation semantics,
commit failure, retry and unrelated pending edits. The iOS CI includes the focused
`testInlineCategoryThenImmediateTransactionSave` UI smoke in its existing UI step.
The workflow retains main's platform scope, concurrency and full-history checkout.

## WebDAV HTTPS boundary (#171)

On iOS, validate a WebDAV URL before saving settings or constructing an
`Authorization` header. Test/list/upload/download all reject non-HTTPS URLs;
download destinations and redirects must also retain the configured host and
port. A default HTTPS port and explicit port 443 are equivalent. Custom HTTPS
ports remain supported. No ATS exception is added. A refused redirect returns
the original 3xx response as an error; configure the server's final HTTPS URL.

`RemoteBackupTransportTests` uses a recording transport and synthetic credentials
to assert that invalid endpoints produce zero transport calls. It also checks
PROPFIND depth, plain and encrypted PUT/GET roundtrips, escaped paths, custom
ports, and the actual redirect delegate's allow/refuse callback. These fixtures
do not contact a real WebDAV server or establish a TLS session. Existing
`BackupCompatibilityTests` continues to cover local restore semantics.

For changes to this boundary, run these two unit suites and check that the
WebDAV screen rejects an HTTP URL without offering a continue override. Existing
saved HTTP settings remain visible for correction, but cannot be used; edited
URLs are saved only after validation when a WebDAV action is requested. Before
release, exercise HTTPS test/list/upload/download/restore on a controlled server
and physical device, including a same-origin redirect and a refused downgrade.

HTTPS protects credentials and data in transit. Optional `.aibackup` encryption
protects the stored payload; it cannot protect a Basic authentication header on
an insecure connection. See [Apple ATS](https://developer.apple.com/documentation/security/preventing-insecure-network-connections),
[Apple redirect delegate](https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/urlsession(_:task:willperformhttpredirection:newrequest:completionhandler:)),
and [RFC 7617](https://www.rfc-editor.org/rfc/rfc7617).
