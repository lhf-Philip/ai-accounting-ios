# Roadmap: Multi-Leg Transfer, Income Charts, Budget Alerts, Data Health Check

Status: Historical roadmap. Most items through PR-5 are now implemented; keep this doc for architecture context.

## Objectives

1. Support transfer groups with multiple source/destination accounts in a single transfer event:
   - one-to-many
   - many-to-one
   - many-to-many (implicitly supported by same model)
2. Add income charts parallel to current expense charts.
3. Add monthly category budget + overspend alerts.
4. Add in-app data health check and repair tooling.
5. Keep JSON backup import compatibility for existing users.

## Constraints

- Keep current app stable during migration.
- Do not break existing JSON backup files.
- Continue using SwiftData as primary local store.

## Proposed Data Storage Evolution

### Current pain points

- Transfer uses pair linkage (`linkedTransactionID`) and sign-based inference.
- Hard to represent one-to-many / many-to-one transfers.
- Health checks are difficult because transfer integrity rules are implicit.

### Proposed schema direction

- Keep `FinancialTransaction` as journal source of truth.
- Add transfer group semantics:
  - `transferGroupID: UUID?`
  - `transferSide: TransferSide?` (`outgoing` / `incoming`)
  - keep `linkedTransactionID` as legacy field for backward compatibility only.
- Add audit fields for future sync and repair:
  - `createdAt: Date`
  - `updatedAt: Date`
- Add optional `Budget` model:
  - `id`, `categoryID`, `monthKey(YYYY-MM)`, `limitAmount`, `currencyCode`, `createdAt`, `updatedAt`

This allows any number of legs in one transfer group while preserving list/chart behavior built on transactions.

## PR Plan

### PR-1: Storage Foundation + Migration Guardrails

Scope:

- Add new fields (`transferGroupID`, `transferSide`, timestamps).
- Add `Budget` model skeleton.
- Add migration adapter from legacy pair-transfer records.
- Add compatibility parser in JSON restore (v1.x -> v2).

Acceptance:

- Existing data opens without crash.
- Existing transfer pairs are readable and editable.
- Existing JSON backups still import.

---

### PR-2: Multi-Leg Transfer Engine + UI

Scope:

- Replace pair-based transfer editor with group-based editor.
- Support N outgoing legs + M incoming legs in one transfer group.
- Validation rules:
  - at least 1 outgoing and 1 incoming leg
  - all amounts > 0
  - same account cannot appear duplicated on same side unless explicitly merged
  - optional imbalance handling (fee/rounding) with explicit warning
- Keep old transfer entries viewable/editable.

Acceptance:

- One-to-many and many-to-one flows fully usable.
- Legacy transfer still editable safely.
- No negative/positive invariant regressions.

---

### PR-3: Income Chart (Parallel to Expense Chart)

Scope:

- Add chart mode toggle: `Expense / Income`.
- Keep category and tag breakdown parity for both modes.
- Keep currency conversion based on transaction currency.

Acceptance:

- Income chart matches existing expense UX level.
- Numbers consistent with filtered transaction totals.

---

### PR-4: Budget + Overspend Alerts (Category/Month)

Scope:

- Add monthly category budget CRUD.
- Compute used/remaining/overspent per category-month.
- Add local alert rules:
  - threshold (e.g., 80%, 100%, overspent)
  - throttle repeated notifications.

Acceptance:

- Budget list by month/category works.
- Overspend alerts trigger once per threshold crossing.
- Works under app restart.

---

### PR-5: Data Health Check + Repair Tool

Scope:

- New “Data Health” screen in Settings.
- Checks:
  - orphan transfer legs/group mismatches
  - invalid sign/side invariants
  - missing account/category references
  - invalid currency code
  - duplicate sortOrder collisions
- Repair actions:
  - auto-fix safe items
  - interactive fix for ambiguous records.

Acceptance:

- Produces deterministic report.
- Auto-fix is idempotent and logged.

---

### PR-6 (Optional): WebDAV Backup Storage

Scope:

- Add WebDAV remote backup provider (manual upload/download first).
- Credentials in Keychain.
- File-level encryption before upload (AES-GCM).
- Backup manifest with checksum.

Acceptance:

- Can list/upload/download backups from WebDAV.
- Restore verifies checksum before import.

## Suggested Delivery Order

1. PR-1
2. PR-2
3. PR-3
4. PR-4
5. PR-5
6. PR-6 (optional, after core data integrity is stable)

## Risks and Mitigations

- Migration risk: mitigate by keeping legacy field + one-way adapter.
- UI complexity risk (multi-leg editor): mitigate with small composable leg components.
- Alert noise risk: mitigate with threshold + cooldown.
- Data repair risk: provide preview + backup-before-fix safeguard.

## Definition of Done (Overall)

- Core flows pass manual QA on simulator + device.
- JSON import compatibility confirmed with existing backups.
- CI stays green.
- Health check reports zero critical issues on new data.
