# Data Migration And Recovery

Status: Active
Last reviewed: 2026-06-20
Applies to: iOS, Android, backup JSON
Source of truth: [`specs/data-model.md`](./specs/data-model.md), iOS `DataModels.swift` / `BackupManager.swift`, Android `AIAccountingDatabase.kt` / `AccountingRepository.kt`

This runbook defines how to change persisted data without losing user records. Financial data compatibility takes priority over implementation convenience.

## Compatibility Layers

The project has three independent compatibility layers:

1. **iOS SwiftData store**
   - Store: `AI_Accounting_v3.store` and its `-wal` / `-shm` companions.
   - The current model is declared in `AI___App.swift`.
   - Startup creates a protected copy of the store family before SwiftData opens an existing store.
   - Legacy SQLite repairs run before `ModelContainer` creation; safe model backfills run after the container opens.

2. **Android Room database**
   - Database: `ai_accounting.db`.
   - Current Room schema version: `6`.
   - Every released schema step must have an explicit migration registered in `AppContainer`.
   - Destructive fallback is prohibited.

3. **Cross-platform backup JSON**
   - Current backup contract version: `1.9`.
   - The JSON contract is shared by iOS and Android but is independent from the SwiftData and Room schema versions.
   - Older backups remain importable through optional fields and documented defaults.

Changing one layer does not automatically migrate the other two. Every persisted-data PR must evaluate all three.

## Non-Negotiable Safety Rules

- Never delete or rename the production store to make startup succeed.
- Never add `fallbackToDestructiveMigration()` to Room.
- Never uninstall the app or instruct the user to delete it as a migration step.
- Never report clear, import, repair, or migration success after swallowing an error.
- Never mutate a real user backup to create a committed test fixture.
- Never infer exchange rates, debt direction, or transaction ownership when legacy data is ambiguous.
- Never reuse a backup field with a different meaning. Add a new optional field or introduce a new backup version.
- Preserve stable UUIDs across export, import, repair, and migration.
- Validate and decode a backup before deleting existing records.

## Choosing A Migration Strategy

### Additive optional field

Use an optional persisted field when old rows have no valid value.

- iOS: declare the new property optional or provide a migration-safe default that SwiftData can materialise.
- Android: add a nullable column in a new Room migration.
- JSON: add an optional field and document its import default.
- After opening/importing, a safe backfill may normalise `nil` to the canonical value.

Example: `AdvanceCase.tagIDs` must accept missing legacy values before being normalised to an empty array.

### Additive required field

Only use a required field when a deterministic value exists for every historical record.

- Add the storage column in a compatible form first.
- Backfill using explicit, testable rules.
- Enforce the required invariant only after all supported legacy data can be upgraded.
- If the value cannot be derived without guessing, keep the field optional and surface a data-health issue.

### Enum change

- Persisted raw values are part of the data contract.
- Adding a value requires both platforms, backup codecs, UI handling, and tests.
- Renaming or removing a value requires a repair/mapping rule before model decoding.
- Unknown legacy values must use the documented safe fallback and be reported when the fallback can change accounting meaning.

### Relationship or ownership change

- Add explicit identifiers before removing marker- or group-based inference.
- Backfill only when the relationship is unambiguous.
- Preserve unresolved legacy rows and expose them through Data Health Check.
- Delete child records before parents when clearing relational data.

### Destructive or semantic change

Do not silently reinterpret existing financial records.

- Write an ADR describing the old and new semantics.
- Provide previewable repair or migration behaviour.
- Keep a rollback path.
- Bump the backup version when old and new readers cannot safely share the same payload.

## iOS SwiftData Procedure

1. Update the model and all construction, edit, query, export, and import paths.
2. Confirm startup order remains:
   - create pre-migration store-family backup;
   - run narrowly scoped pre-open legacy repairs;
   - create `ModelContainer`;
   - run safe post-open backfills.
3. Add a migration regression test using generated or anonymised legacy data.
4. Verify first launch and second launch. The second launch must not repeat a destructive repair or crash.
5. Verify record counts, important balances, and `PRAGMA quick_check` when testing a copied SQLite store.

`StoreMigrationSafetyService` reuses a complete backup created within the previous 24 hours. A backup failure stops store opening; it must not fall through to an empty database.

Pre-open SQLite repair is reserved for values that would crash SwiftData decoding. It must:

- check that tables and columns exist;
- update only invalid legacy rows;
- be idempotent;
- have a focused regression test;
- leave the original store family recoverable.

## Android Room Procedure

1. Increment `AIAccountingDatabase.version`.
2. Add one explicit `Migration(oldVersion, newVersion)`.
3. Register it in `AppContainer`.
4. Update entities, DAO queries, repository mappings, backup models, and JSON import/export.
5. Add migration tests for the previous released version and a fresh-database test.
6. Run unit tests, debug assembly, and relevant instrumentation tests.

Migration SQL must be idempotent where SQLite permits it and must preserve IDs and relationship rows. Cross-reference tables require their own migration and roundtrip tests.

## Backup JSON Versioning

The top-level `version` describes the backup contract, not the app release.

Keep the current version when:

- a field is additive and optional;
- old imports have a deterministic default;
- both platforms can read old and new payloads safely.

Bump the version when:

- an existing field changes meaning or type;
- a required field cannot be reconstructed from old data;
- a supported reader would produce materially incorrect balances;
- import requires a staged transformation rather than defaults.

For every backup-field change:

- update [`specs/data-model.md`](./specs/data-model.md);
- update iOS and Android codecs;
- add old-payload and roundtrip fixtures;
- verify missing, `null`, and populated values where applicable;
- preserve object IDs and references.

## Merge Versus Replace Import

### Merge import

- Retains existing data.
- Inserts records whose IDs do not already exist.
- Some mutable support records may be updated by their stable key.
- It is not suitable for correcting an existing record with the same ID.

Use merge only when combining non-overlapping datasets.

### Replace import

- Decode and validate the selected JSON first.
- Capture an in-memory recovery backup of current data.
- Clear records in relationship-safe order and verify the database is empty.
- Restore the selected backup.
- If restore fails, clear partial records and restore the recovery backup.
- Report the original and recovery errors if both operations fail.

Use replace for full-device recovery and reconciliation backups that correct existing IDs.

Android performs replace import inside one Room transaction. iOS uses verified deletion plus recovery restore because SwiftData does not provide the same transaction boundary for this workflow.

## Recovery Runbooks

### SwiftData store fails to open

1. Stop changing the app or store.
2. Capture the full error including nested Core Data reasons.
3. Copy the current `.store`, `.store-wal`, and `.store-shm` files together.
4. Locate the latest complete directory under `MigrationBackups`.
5. Reproduce against a copy on the same iOS runtime before touching the device.
6. Fix the schema or pre-open repair and verify two launches.
7. Install over the existing app. Do not uninstall it.

If no safe migration exists, keep the store and restore from a user-confirmed JSON backup. Do not create an empty store as an automatic fallback.

### JSON replace import fails

1. Keep the app installed.
2. Record whether automatic recovery succeeded.
3. If recovery succeeded, export a fresh JSON before retrying.
4. Validate the selected JSON structure and reference integrity.
5. Retry only after fixing the importer or backup.
6. If recovery also failed, stop all edits and preserve the app container for diagnosis.

### Data appears duplicated after import

This usually means merge import was used for a reconciliation backup.

1. Export the current state for safety.
2. Confirm the intended backup contains corrected records with reused IDs.
3. Use **Replace import**, not Merge import.
4. Verify account balances and record counts after restore.

### Data Health Check reports unresolved legacy records

- Prefer the provided previewable repair action.
- Export JSON before applying repair.
- Do not edit SQLite directly unless the model cannot open and a tested pre-open repair is required.
- If matching is ambiguous, leave the record unchanged and document the manual correction.

## Required Validation

Every persisted-data change must cover:

- fresh install;
- upgrade from the previous supported store schema;
- first and second launch;
- old JSON import;
- export → import → export roundtrip;
- merge and replace behaviour when affected;
- relationship/reference integrity;
- account balances and report exclusion rules;
- iOS/Android parity for shared fields;
- failure rollback.

The PR must state the source schema/version, target schema/version, backup version decision, rollback strategy, and exact fixtures used.

## Recoverable startup (#170)

Production startup now enters a recovery screen when the Documents directory, pre-migration backup, or model-container open fails. Normal ledger views are constructed only after a container is ready. Retry uses the same `AI_Accounting_v3.store` path; it does not reset, delete, rename or silently replace an existing store. Once ready, repeated startup/retry requests do not reopen the store.

Recovery provides diagnostics and read-only discovery/export of an existing pre-migration snapshot. Discovery retains the existing completeness rule (a nonempty store file); this is not proof that the snapshot can be restored. Export uses Apple's [NSFileCoordinator.forUploading](https://developer.apple.com/documentation/foundation/nsfilecoordinator/readingoptions/foruploading) to produce a ZIP and copies its temporary result for sharing. No automatic restore is attempted.

The existing legacy compatibility repairs still run after backup and before opening, so an attempted repair may change the live store before a later open failure. The pre-repair snapshot remains available. Fault-injection tests use synthetic store/WAL/SHM files with no-op repairs to verify that the startup controller itself preserves files, stops before repair/open if backup fails, and retries safely. Schema/migration redesign remains tracked separately in #169.

Apple's [error-handling guidance](https://developer.apple.com/tutorials/develop-in-swift/navigate-sample-data) recommends presenting an error or allowing retry for recoverable errors. UI tests verify that the recovery screen has diagnostics/retry and no normal ledger before recovery. Physical-device tests of locked storage and real historical migrations remain release checks.
