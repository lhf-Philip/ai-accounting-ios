# Troubleshooting

Status: Active
Last reviewed: 2026-06-20
Applies to: iOS, Android, local data, backup, Gemini, WebDAV, currency rates
Sources of truth: [Data Migration And Recovery](./DATA_MIGRATION_AND_RECOVERY.md), [Testing Guide](./TESTING.md), [Remote Backup](./REMOTE_BACKUP.md)

Use this runbook to diagnose failures without sacrificing user data. Each section follows: symptom, checks, safe action, and prohibited shortcuts.

## First Response

Before changing code or data:

1. Record the exact error, timestamp, device/runtime, app commit or build, and action that triggered it.
2. Stop repeated writes if data integrity may be involved.
3. Export a JSON backup when the app can still open.
4. Preserve relevant store files, logs, and CI artifacts.
5. Reproduce against a copy or synthetic fixture before touching the only user dataset.

## SwiftData Store Or Migration Failure

### Symptoms

- App crashes while creating `ModelContainer`.
- Core Data reports a missing column, incompatible model, or migration failure.
- A persisted enum/property getter crashes on old data.

### Checks

- Capture the full nested error, not only the top-level `SwiftDataError`.
- Confirm the current store family exists: `.store`, `.store-wal`, and `.store-shm`.
- Locate the latest complete `MigrationBackups` copy.
- Identify the model change and whether old rows have a deterministic value.
- Reproduce on the same iOS runtime using a copied store.

### Safe action

- Make the new field optional when old rows legitimately have no value.
- Add a narrow, idempotent pre-open repair only when invalid legacy values prevent decoding.
- Backfill after `ModelContainer` opens when the app can safely interpret `nil`.
- Verify record counts, balances, `PRAGMA quick_check`, and two consecutive launches.
- Install the fixed build over the existing app.

### Do not

- Delete or rename the store to let the app create an empty database.
- Uninstall the app as the first fix.
- Copy only the `.store` file while ignoring active WAL/SHM companions.
- Guess debt direction, currency, or account ownership.

See [Data Migration And Recovery](./DATA_MIGRATION_AND_RECOVERY.md#swiftdata-store-fails-to-open).

## JSON Import Does Not Correct Existing Data

### Symptoms

- Import reports success but old values remain.
- Records appear duplicated.
- A corrected backup does not overwrite records with the same UUID.

### Checks

- Confirm whether the user selected **Merge** or **Replace**.
- Validate the selected file and inspect its top-level backup version.
- Confirm corrected objects reuse the expected stable IDs.
- Check whether clear/restore reported an error or automatic recovery occurred.

### Safe action

- Use **Merge** only for non-overlapping datasets.
- Use **Replace** for full recovery or a corrected reconciliation backup.
- Export the current state before replace.
- After replace, verify account balances, record counts, advance cases, and a second export/import roundtrip.

### Do not

- Treat merge as an overwrite.
- Clear data before decoding and validating the replacement.
- Display success after a failed clear or restore.
- Repeatedly import the same backup while the failure cause is unknown.

## iOS Signing And Personal Team

### Symptoms

- `Signing requires a development team`.
- `No Accounts`.
- `No profiles for '<bundle-id>' were found`.
- A free-signed app stops launching after the provisioning period.

### Checks

- Xcode Settings > Accounts contains the intended personal Apple account.
- The app target uses Automatic Signing and the intended Team.
- The connected iPhone is trusted, Developer Mode is enabled, and the bundle ID can be registered.
- The selected run destination is the physical device, not a generic device.

### Safe action

1. Select the intended Team in Signing & Capabilities.
2. Keep Automatic Signing enabled for local development.
3. Run to the connected device with `Cmd + R`.
4. If Xcode cannot refresh the profile, remove stale local provisioning profiles only after preserving app data and confirming the signing identity.

Free Personal Team provisioning is temporary. Running again normally installs a newly signed build, but Xcode may reuse a still-valid profile. There is no supported way to force Apple to issue a longer free profile.

### Do not

- Change the production bundle ID casually; it creates a different app container.
- Delete the installed app when its local data has not been exported.
- Commit Team IDs, provisioning profiles, certificates, or private keys.

## Gradle, JDK, SDK, Or Emulator Failure

### Symptoms

- `SDK location not found`.
- Gradle uses an unsupported Java version.
- Emulator system image download is incomplete.
- Instrumentation hangs or an emulator fails to boot.

### Checks

```bash
java -version
cd android
./gradlew --version
adb devices
```

- JDK should be 17 for the current CI configuration.
- `android/local.properties` should point to an installed SDK.
- Required SDK packages are platform 35 and the configured build tools.
- For instrumentation, confirm the emulator is booted and unlocked.

### Safe action

- Correct local `sdk.dir` or `ANDROID_HOME`.
- Re-run the failed SDK package download; an EOF/ZLIB failure usually means a partial archive.
- Use the Gradle wrapper committed to the repository.
- Capture Android test results, logcat, and emulator details before retrying.
- Run `./gradlew :app:testDebugUnitTest :app:assembleDebug` to separate JVM/build failures from emulator failures.

### Do not

- Commit `local.properties`.
- Replace the Gradle wrapper or SDK levels merely to bypass a local setup error.
- Interpret a passed unit suite as proof that instrumentation passed.

## Android Instrumentation Failure

### Checks

- Inspect:
  - `android/app/build/outputs/androidTest-results/connected/`;
  - `android/app/build/reports/androidTests/connected/`;
  - CI artifact `android-instrumentation-failure-*`.
- Identify the failing test before rerunning the complete suite.
- Check for keyboard, animation, locale, and device-size assumptions.

### Safe action

- Prefer semantic selectors and state-based waits.
- Reproduce on the same API level/profile used by CI.
- If the emulator process itself crashed, separate infrastructure failure from app assertion failure in the PR.

## Gemini Failure

### Symptoms

- `GenerateContentError`.
- Budget advice or receipt analysis fails intermittently.
- Request succeeds only after network/VPN changes.

### Checks

- Network and DNS access to the Gemini endpoint.
- API key exists in Keychain/secure Android storage and is valid.
- AI Studio quota/rate-limit status for the selected model.
- Request payload size, model name, and JSON response parsing.
- Whether the error is authentication, quota, safety/policy, network, or malformed output.

### Safe action

- Show a user-facing error category without logging the API key or full financial prompt.
- Retry only transient network/server errors with bounded backoff.
- Preserve manual bookkeeping when AI is unavailable.
- Use synthetic data when reproducing a prompt failure.

### Do not

- Commit an API key.
- Treat VPN state as the only possible cause.
- Retry quota or validation failures in a tight loop.
- Upload more user history than the user selected.

## WebDAV Failure

### Symptoms

- Connection test fails.
- Remote list is empty.
- Upload/download succeeds but restore cannot decode.
- Encrypted backup rejects the passphrase.

### Checks

- URL includes the correct WebDAV collection path.
- Username/password are distinct from the backup passphrase.
- HTTP versus HTTPS warning state.
- File type: `.aibackup` is encrypted; `.json` is plain.
- Server status code and response body, without logging credentials.

### Safe action

- Test connection without requiring a passphrase.
- For encrypted files, verify the exact passphrase and keep the original remote object.
- Download and preview before restore.
- Export a local backup before replacing local data.
- Use HTTPS; if the user explicitly uses HTTP, retain the risk confirmation.

### Do not

- Send credentials or passphrases in query parameters or logs.
- Attempt to parse `.aibackup` as JSON before decryption.
- Convert or overwrite an old remote backup automatically.

See [Remote Backup](./REMOTE_BACKUP.md).

## Currency Rate Failure

### Symptoms

- Main-currency estimate is unavailable.
- Live rate request fails.
- Cross-currency editor shows a stale reference rate.

### Checks

- Transaction currency and main currency are valid ISO codes.
- The live endpoint is reachable.
- A cached rate exists for the same base/quote pair.
- UI distinguishes `live`, `cached`, and `unavailable`.
- User-entered transfer/repayment amounts are not being overwritten by a reference rate.

### Safe action

- Attempt the live rate first.
- Fall back to the last stored rate and label it as cached/stale.
- If neither exists, omit the estimate and preserve actual entered amounts.
- Keep settlement amount and payment amount distinct in cross-currency repayments.

### Do not

- Invent a rate.
- Rewrite historical transaction amounts from a new market rate.
- Count a repayment or transfer as income/expense because conversion failed.

## Reports Or Balances Look Wrong

### Checks

1. Identify the account, transaction date/time, currency, type, and UUID.
2. Check whether the record is a transfer, advance leg, repayment, refund, asset adjustment, or ordinary income/expense.
3. Compare account detail (actual cash flow) with ledger summary (case-level display).
4. Run Data Health Check.
5. Export a safety backup and reproduce with an anonymised fixture.

### Safe action

- Correct semantic links or roles through the relevant editor/repair flow.
- Use report drill-down to verify included original-currency amounts and main-currency estimates.
- Add a regression vector before changing aggregation.

### Do not

- Repair the report by hiding a transaction without fixing its semantic classification.
- Edit SQLite directly when the app can open.
- Convert debt repayment into ordinary income/expense to make a total match.

## Escalation Record

When a problem remains unresolved, record:

- exact commit/build and platform;
- device/OS/runtime;
- reproduction steps;
- expected and actual accounting effect;
- logs and non-sensitive screenshots;
- fixture or synthetic data used;
- recovery backup location outside the repository;
- actions already attempted and whether rollback succeeded.
