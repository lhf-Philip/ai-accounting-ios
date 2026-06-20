# Development Guide

Status: Active
Last reviewed: 2026-06-20
Applies to: iOS, Android
Required reading: [`ARCHITECTURE.md`](./ARCHITECTURE.md), [`CONTEXT.md`](../CONTEXT.md), [`specs/data-model.md`](./specs/data-model.md)

This guide describes how to change AI Accounting without duplicating accounting logic or breaking cross-platform data compatibility.

## Before Editing

Classify the change:

| Change | Required work |
|---|---|
| Copy, spacing, local presentation | Affected UI and UI/snapshot smoke tests |
| New screen or route | Platform navigation, source-of-truth UI docs, accessibility and keyboard behaviour |
| Accounting semantic change | `CONTEXT`, ADR, both platforms, parity vectors, report/ledger tests |
| Persisted field or relationship | Models/entities, migration, backup codecs, roundtrip tests, recovery plan |
| Backup behaviour | Both codecs/importers, old fixtures, merge/replace tests, data-model docs |
| External integration | Service boundary, secret handling, offline/error behaviour, troubleshooting docs |

Do not start in a screen when the change affects how money is classified, grouped, settled, deleted, or restored.

## Implementing A Shared Feature

1. Define the user-visible behaviour and accounting meaning.
2. Update or add the shared semantic source:
   - `CONTEXT.md` for vocabulary/invariants;
   - an ADR for a significant decision;
   - `specs/data-model.md` for persisted/backup shape;
   - `specs/parity-test-vectors.md` for deterministic results.
3. Implement a narrow testable domain API on iOS and Android.
4. Add UI that sends typed input to the domain API.
5. Add unit/integration tests before relying on manual UI verification.
6. Update backup compatibility when the feature persists data.
7. Verify both platforms or explicitly document why one is unaffected.
8. Update the in-app guide and public docs only when user flow changes.

Keep PRs as vertical slices: semantics, storage, UI, tests, and docs for one coherent behaviour. Avoid unrelated parity polish in a data-safety PR.

## iOS Implementation Rules

### State ownership

- Use local `@State` for temporary editor/presentation state.
- Use `@Query` for view-owned live collections where the query remains small and direct.
- Pass selected models or typed drafts into child views instead of introducing global mutable state.
- Use `@AppStorage` only for local preferences, never ledger records.
- Keep expensive filtering, grouping, and counterpart maps out of row bodies; calculate one render state per view update.

### Domain and persistence

- Single-record ordinary edits use the relevant edit service when semantic validation is needed.
- Multi-record operations belong in `Services/`, not SwiftUI button closures.
- Mark SwiftData write services `@MainActor`.
- Validate the complete draft before mutating models.
- On a failed multi-record operation, call `modelContext.rollback()` and return an actionable error.
- Do not retain or render a model after it has been deleted.
- Use stable IDs and explicit advance links; note markers are legacy/special-settlement compatibility only.

### Navigation and input

- Top-level navigation remains in `ContentView`.
- Feature-specific sheets/navigation remain near the owning screen unless they are global add flows.
- Input screens must scroll, keep the primary action above system chrome/keyboard, and use `standardKeyboardBehavior()`.
- Add accessibility identifiers for automated high-risk flows rather than coupling tests to translated labels.

## Android Implementation Rules

### State ownership

- Use `remember` / `rememberSaveable` for local presentation and draft state.
- Collect repository `Flow` values at the screen boundary.
- Keep reusable calculations in `core/`; do not recompute accounting semantics in composables.
- `UiPreferencesStore` is for local preferences, not ledger entities.

### Domain and persistence

- Screens call `AccountingRepository`; they do not call DAOs directly.
- Use pure core calculators for report, refund, currency, and transaction semantics.
- Wrap every multi-table write in `database.withTransaction`.
- Parse and validate backup input before entering a replace transaction.
- Add explicit Room migrations; destructive fallback is prohibited.
- Use `BigDecimal` for financial calculations and preserve scale-independent equality in tests.

### Navigation and input

- Add routes through `AIAccountingRoot`.
- Use parity components for app-owned controls; platform system pickers may remain native.
- Editors must be vertically scrollable and apply `imePadding()` where the keyboard can cover actions.
- Single-line fields use an appropriate IME action; multi-line fields retain newline but provide a screen-level dismissal path.

## Adding Or Changing Transaction Semantics

Do not encode a new financial meaning only in note text.

1. Define whether the event is income, expense, transfer, refund reduction, or settlement-only.
2. Define which own/debt accounts move.
3. Define report and budget inclusion.
4. Define delete, edit, rollback, and account-deletion behaviour.
5. Define cross-currency meaning:
   - actual amount/currency for cash movement;
   - normalized/case currency amount for settlement when applicable.
6. Add/update the ADR and parity vector.
7. Implement the classifier/service on both platforms.
8. Test ledger rows, account balances, reports, backup roundtrip, and semantic deletion.

## Adding A Persisted Field

Follow [`DATA_MIGRATION_AND_RECOVERY.md`](./DATA_MIGRATION_AND_RECOVERY.md).

Minimum change set:

- SwiftData model and initialisers;
- Room entity and explicit migration;
- repository/service mappings;
- iOS `FullBackupData` and Android backup model;
- export and merge/replace import;
- missing/`null` defaults;
- old fixture and roundtrip tests;
- `specs/data-model.md`;
- parity vector if the field affects behaviour.

If the field has no safe historical value, keep it optional and expose unresolved records to Data Health Check.

## Adding A Screen Or Editor

- Confirm whether it is top-level, a detail route, or a modal flow.
- Keep iOS as the information-architecture source of truth and update Android parity documentation.
- Route writes through an existing domain API or create one first.
- Support loading, empty, validation-error, persistence-error, and success states.
- Ensure all content is reachable on iPhone 13 and Samsung A53-sized screens.
- Ensure keyboard dismissal, safe-area spacing, and back/cancel behaviour.
- Add UI automation for destructive, migration-sensitive, or structurally complex flows.

## Accounting Invariants

These rules must remain true:

- Income is positive and targets an own account.
- Expense is negative and represents the user's consumption/cost.
- Transfers do not contribute to income or expense reports.
- Asset adjustments do not contribute to income or expense reports.
- Repayment does not count the original expense again.
- Debt forgiveness and mutual offset are settlement-only.
- `他人代墊我` records expense on the advance date without moving an own account at creation.
- Cross-currency repayment preserves actual payment amount/currency and normalized case-currency settlement.
- Refunds reverse expense up to the remaining original amount; excess is settlement-only.
- Reports convert from transaction currency and retain original-currency totals.
- Structural advance edits follow validate → preview → atomic apply → rollback.

## Error Handling

- Preserve the original state on validation or persistence failure.
- Show errors that tell the user what can be corrected.
- Log enough nested detail for diagnosis without including secrets or personal ledger content.
- Never convert a persistence failure into success UI.
- Never use deletion/reinstallation as an automatic recovery strategy.
- External services must have offline/fallback behaviour or a clear unavailable state.

## Documentation Update Matrix

| Change | Documentation |
|---|---|
| Accounting meaning | `CONTEXT.md` + ADR + parity vectors |
| Persisted/backup field | data model + migration/recovery |
| Screen hierarchy or parity | Android/iOS parity spec + in-app guide if user-facing |
| Build/test command | testing/CI docs |
| Release or compatibility policy | releasing + changelog |
| New external service/failure mode | architecture + troubleshooting/security |

## Definition Of Done

- The change is implemented on every affected platform.
- Shared semantics and persistence contracts agree.
- Tests cover happy path, failure rollback, and relevant legacy data.
- Build and CI commands pass.
- No personal data, local paths, credentials, signing IDs, or real backups are committed.
- Documentation describes current behaviour, not planned behaviour.
