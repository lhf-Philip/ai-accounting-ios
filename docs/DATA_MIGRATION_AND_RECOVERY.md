# Data Migration And Recovery

Status: Active
Last reviewed: 2026-09-14
Applies to: iOS, Android, backup JSON
Source of truth: [`specs/data-model.md`](./specs/data-model.md), iOS `DataModels.swift` / `BackupManager.swift`, Android `AIAccountingDatabase.kt` / `AccountingRepository.kt`

This runbook defines how to change persisted data without losing user records. Financial data compatibility takes priority over implementation convenience.

## Compatibility Layers

The project has three independent compatibility layers:

1. **iOS SwiftData store**
   - Store: `AI_Accounting_v3.store` and its `-wal` / `-shm` companions.
   - The live schema is `AccountingSchemaV3`; `StoreStartupService` supplies its migration plan.
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
- Capture a complete in-memory recovery backup of current data. Every required iOS model fetch must succeed before any clearing begins; a fetch error is not an empty collection.
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

## iOS Backup Failure Boundaries

Backup creation and restore preloading propagate required SwiftData fetch errors. Local export, WebDAV upload, and automatic backup share this throwing snapshot operation. Merge restore preloads every existing model collection before inserting or updating records. Replace restore cannot clear data until its recovery snapshot succeeds.

Automatic local backup writes JSON with Foundation `.atomic`, and records `lastBackupDate` only after the write succeeds. This protects destination replacement; it does not establish that arbitrary externally supplied JSON is complete or guarantee durability against every filesystem/device failure.

Backup JSON remains version 1.9 and its fields/defaults are unchanged. Android uses its existing throwing Room reads and transaction boundary, so this iOS error-propagation correction requires no Android codec or schema change. Synthetic tests cover all 13 required model reads, recovery-capture failure, merge preloading, write failure, and full graph IDs/relationships through export/import/export.

Authoritative references: [Apple ModelContext.fetch](https://developer.apple.com/documentation/swiftdata/modelcontext/fetch(_:)), [Apple atomic writing](https://developer.apple.com/documentation/foundation/nsdata/writingoptions/atomic).

## Recoverable startup (#170)

Production startup now enters a recovery screen when the Documents directory, pre-migration backup, or model-container open fails. Normal ledger views are constructed only after a container is ready. Retry uses the same `AI_Accounting_v3.store` path; it does not reset, delete, rename or silently replace an existing store. Once ready, repeated startup/retry requests do not reopen the store.

Recovery provides diagnostics and read-only discovery/export of an existing pre-migration snapshot. Discovery retains the existing completeness rule (a nonempty store file); this is not proof that the snapshot can be restored. Export uses Apple's [NSFileCoordinator.forUploading](https://developer.apple.com/documentation/foundation/nsfilecoordinator/readingoptions/foruploading) to produce a ZIP and copies its temporary result for sharing. No automatic restore is attempted.

The existing legacy compatibility repairs still run after backup and before opening, so an attempted repair may change the live store before a later open failure. The pre-repair snapshot remains available. Fault-injection tests use synthetic store/WAL/SHM files with no-op repairs to verify that the startup controller itself preserves files, stops before repair/open if backup fails, and retries safely. Schema/migration redesign remains tracked separately in #169.

Apple's [error-handling guidance](https://developer.apple.com/tutorials/develop-in-swift/navigate-sample-data) recommends presenting an error or allowing retry for recoverable errors. UI tests verify that the recovery screen has diagnostics/retry and no normal ledger before recovery. Physical-device tests of locked storage and real historical migrations remain release checks.


## Versioned-schema migration candidate (#169)

The explicit plan covers these schema identities; its version numbers are
internal SwiftData versions, independent of app releases and backup JSON:

| Schema | Frozen source / representation | Transition |
| --- | --- | --- |
| V1 (1.0.1) | v1.0.1 commit `9063807944d1b46e2125711338c73acfa20f32e9`, five models, no category kind | Lightweight through the ordered historical structures; do not read new required values |
| Historical 1.1.0–1.8.0 | Transfer, budget, advance, advance links, budget history/settings, recurring, required advance tags; [pinned source matrix](../AI%20記帳Tests/Fixtures/SwiftData/Historical/README.md) | Ordered lightweight stages to V2; no intermediate getter reads |
| V2 (2.0.0) | main `2b829a5507bced8e1e810a2fd577d27484d25f30`, thirteen models, required kind | Custom to V3; nullable stored kind maps from `kind`, then only missing values become `Both` |
| V3 (3.0.0) | Live models with nullable `storedKind` and non-optional computed `kind` | New stores start here; existing valid values are retained |

Frozen historical model declarations retain the original persisted properties and
relationships. Their unchanged enum types are shared. Do not alter historical
raw values or frozen model definitions. Before the next persisted-model change,
freeze V3's live definitions and append a new schema/stage; do not mutate a
released schema in place. Compatibility with these unversioned source stores is
verified by actual opens, rather than assumed from the wrapper names.

Why a nullable target is necessary: a main-version automatic open can complete
and persist a current-schema store before a `Category.kind` getter crashes. A
migration stage only from V1 cannot repair such a V2 store. V3 can materialize a
missing kind safely, and its custom stage persists `Both` only for missing values.
The application API and backup JSON enum values remain Expense/Income/Both.
All existing kind queries filter materialized models; a future store predicate
must use the persisted property rather than computed `kind`.

Startup still creates its pre-migration store-family backup before repairs and
container opening. Fetch/save errors in the new migration stage propagate to
startup recovery. The same production store path is retained. Backup JSON stays
at 1.9; there is no Android schema, JSON codec or accounting-semantic change.

The existing raw repairs remain a compatibility bridge in this candidate. No new
raw SQL is added, and these fixtures do not justify removing every legacy repair.
Retire each repair separately only after confirmed source/runtime coverage proves
it unnecessary. Never expand private-table mutations based on guessed layouts.

### Verified scenarios and release limits

- Frozen v1.0.1 empty/populated fixtures use exact historical model bytes with
  recorded Xcode/runtime/source/store hashes. Tests open copies twice and verify
  IDs, precise balances, relationships and JSON export/import/reopen.
- A previous automatic V1-to-V2 open, without reading kind, recreates the missing
  value case; the candidate then opens/reopens with a persisted `Both` value.
- Unversioned V2 stores generated from frozen model definitions cover all thirteen
  models, Expense/Income/Both preservation, UUIDs and relationship references.
- Eight populated intermediate-source fixtures cover distinct persisted structures
  in the inspected Git history. All opened with old main but were rejected by the
  original three-schema plan; the expanded plan is checked for era-specific data
  preservation, reopening and unchanged snapshots.
- Fresh V3 category creation/edit/save/reopen exercises the computed API and
  persisted backing field. Existing backup tests cover JSON compatibility.
- Injected open and custom-migration-stage failures preserve a byte-identical
  pre-repair snapshot that can be restored and opened twice. An unrecognized schema enters recovery and retains
  its snapshot instead of falling back to an empty or automatically migrated store.

The maintainer does not know which manual/TestFlight builds held data. The plan
now covers the distinct persisted structures found between v1.0.1 and frozen V2,
including the intermediate source eras; it is not a promise about unknown local
model edits or every previous automatic-migration/runtime combination. Generated
source fixtures are not original release-OS artifacts. Physical-device and
historical-runtime validation remain release checks. Keep #169 open until
compatibility coverage and repair retirement are reviewed; this candidate does
not finish the whole issue.

New migration cases run in the existing unit job; no extra CI layer is needed.
Apple documents the native Core Data store format as
[private](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreData/PersistentStoreFeatures.html).
Its [schema modeling session](https://developer.apple.com/videos/play/wwdc2023/10195/)
explains versioned schemas, custom stages and `originalName` mapping. These APIs
support the candidate's mechanism; the specific getter failure and migration
results above are experimental observations, not a claimed Apple guarantee about
automatic enum defaults.
