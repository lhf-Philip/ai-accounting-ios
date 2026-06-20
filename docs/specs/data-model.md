# Cross-Platform Data Model Contract

Status: Active
Last reviewed: 2026-06-20
Applies to: iOS, Android, backup JSON
Current backup JSON version: `1.9`

## Purpose

This document defines the canonical data contract that iOS and Android must share.
UI can differ by platform, but data meaning, import/export behavior, and core calculations must remain compatible.

## Canonical Enum Values

All enum raw values are case-sensitive and must be persisted exactly as below.

### `AccountType`
- `Cash`
- `Bank`
- `Credit Card`
- `Debt`

### `TransactionType`
- `Income`
- `Expense`
- `Transfer`

### `TransferSide`
- `Outgoing`
- `Incoming`

### `CategoryKind`
- `Expense`
- `Income`
- `Both`

### `AdvanceDirection`
- `IAdvancedOthers`
- `OthersAdvancedMe`

### `AdvanceEntryRole`
- `SelfExpense`
- `InitialAsset`
- `InitialDebt`
- `RepaymentAsset`
- `RepaymentDebt`

### `RecurringFrequency`
- `Daily`
- `Weekly`
- `Monthly`

### `RecurringOccurrenceStatus`
- `Pending`
- `Confirmed`
- `Skipped`

### `BudgetCarryOverMode`
- `None`
- `UnusedOnly`
- `OverspendOnly`
- `NetBalance`

### `BudgetForecastMode`
- `SpendingPace`

## Entity Contract

### `Account`
- `id: UUID` (unique)
- `name: String`
- `currency: String` (ISO code, e.g. `HKD`)
- `type: AccountType`
- `baseBalance: Decimal`
- `sortOrder: Int`
- `isArchived: Bool` (default `false`)

Invariants:
- `id` must be stable across backup/restore.
- `sortOrder` is presentation ordering only.

### `Category`
- `id: UUID` (unique)
- `name: String`
- `icon: String`
- `colorHex: String`
- `kind: CategoryKind` (default `Both`)

### `Tag`
- `id: UUID` (unique)
- `name: String`

### `FinancialTransaction`
- `id: UUID` (unique)
- `amount: Decimal`
- `currencyCode: String`
- `date: Date`
- `note: String`
- `photoPath: String?`
- `type: TransactionType`
- `linkedTransactionID: UUID?` (legacy paired transfer link)
- `transferGroupID: UUID?` (group key for merged/split transfers)
- `transferSide: TransferSide?`
- `advanceCaseID: UUID?`
- `advanceParticipantID: UUID?`
- `advanceRepaymentID: UUID?`
- `advanceEntryRole: AdvanceEntryRole?`
- `createdAt: Date`
- `updatedAt: Date`
- `accountID: UUID?`
- `categoryID: UUID?`
- `tagIDs: [UUID]`

Invariants:
- Income should be positive amount.
- Expense should be negative amount.
- Transfer should not be counted as income/expense.
- For transfer groups, legs should share `transferGroupID`.
- New advance bookkeeping rows must use explicit case, participant, repayment, and role links.
- Refund semantics are not represented by a dedicated persisted type yet. Until a future schema is defined, refund domain logic must treat refunds as expense reversals, never ordinary income.
- Report aggregation may receive a non-persisted semantic snapshot that marks a transaction-like record as a refund. That snapshot is a UI/domain adapter only; it must not be exported as a new backup field until a persisted refund schema is explicitly added.

### `Shortcut`
- `id: UUID` (unique)
- `name: String`
- `icon: String`
- `amount: Decimal`
- `currencyCode: String`
- `type: TransactionType`
- `note: String`
- `accountID: UUID?`
- `categoryID: UUID?`
- `tagIDs: [UUID]`

### `CategoryMonthlyBudget`
- `id: UUID` (unique)
- `monthKey: String` (`yyyy-MM`)
- `amount: Decimal`
- `currencyCode: String`
- `isEnabled: Bool`
- `createdAt: Date`
- `updatedAt: Date`
- `categoryID: UUID?`

### `RecurringRule`
- `id: UUID` (unique)
- `title: String`
- `amount: Decimal`
- `currencyCode: String`
- `type: TransactionType`
- `note: String`
- `frequency: Daily | Weekly | Monthly`
- `intervalCount: Int` (minimum `1`)
- `nextDueDate: Date`
- `isPaused: Bool`
- `accountID: UUID?`
- `categoryID: UUID?`
- `tagIDs: [UUID]`
- `createdAt: Date`
- `updatedAt: Date`

### `RecurringOccurrence`
- `id: UUID` (unique)
- `dueDate: Date`
- `status: Pending | Confirmed | Skipped`
- `createdTransactionID: UUID?`
- `ruleID: UUID?`
- `createdAt: Date`
- `updatedAt: Date`

### `BudgetMonthlyHistory`
- `id: UUID` (unique)
- `historyKey: String` (unique)
- `monthKey: String`
- `categoryID: UUID`
- `categoryNameSnapshot: String`
- `budgetAmount: Decimal`
- `spentAmount: Decimal`
- `remainingAmount: Decimal`
- `usageRatio: Decimal`
- `isOverBudget: Bool`
- `currencyCode: String`
- `updatedAt: Date`

### `BudgetSettings`
- `id: String` (current global key: `global`)
- `carryOverMode: None | UnusedOnly | OverspendOnly | NetBalance`
- `alertThresholdPercent: Decimal`
- `forecastMode: SpendingPace`
- `updatedAt: Date`

### `AdvanceCase`
- `id: UUID` (unique)
- `title: String`
- `date: Date`
- `currencyCode: String`
- `myShareAmount: Decimal`
- `note: String`
- `selfExpenseTransactionID: UUID?`
- `direction: IAdvancedOthers | OthersAdvancedMe | nil` for legacy data
- `tagIDs: [UUID]?` (`nil` is a legacy empty array)
- `payerAccountID: UUID?`
- `expenseCategoryID: UUID?`
- `createdAt: Date`
- `updatedAt: Date`

### `AdvanceParticipant`
- `id: UUID` (unique)
- `name: String`
- `owedAmount: Decimal`
- `repaidAmount: Decimal`
- `initialTransferGroupID: UUID?`
- `advanceCaseID: UUID?`
- `debtAccountID: UUID?`
- `createdAt: Date`
- `updatedAt: Date`

### `AdvanceRepayment`
- `id: UUID` (unique)
- `amount: Decimal`
- `currencyCode: String`
- `normalizedAmount: Decimal`
- `date: Date`
- `note: String`
- `linkedTransferGroupID: UUID?`
- `advanceCaseID: UUID?`
- `participantID: UUID?`
- `receivedAccountID: UUID?`
- `createdAt: Date`

### Structural Advance Editing

- Every structural edit follows `validate -> preview -> atomic apply -> rollback`.
- Direction changes rebuild initial entries and ordinary repayment entries from explicit draft values.
- Case currency changes never infer exchange rates. The user must explicitly confirm the normalized case-currency amount for the user's share, every participant, and every repayment.
- A participant's new owed amount must not be lower than the sum of retained normalized repayments.
- Multiple payment sources are represented by multiple `FinancialTransaction` rows with role `InitialAsset`, one shared `transferGroupID`, and explicit `advanceCaseID` / `advanceParticipantID` links. The matching debt leg uses role `InitialDebt`.
- Adding a participant creates the participant and all linked initial entries in the same atomic operation.
- Removing a participant removes that participant's ordinary repayments and all explicitly linked entries in the same atomic operation.
- Mutual debt offsets and manual debt settlements cannot be edited as individual repayments. They must be rolled back as a whole group before structural editing.
- New data must use explicit advance links. Note markers remain legacy/special-settlement compatibility signals only.

## Backup JSON Contract (`FullBackupData`)

Top-level fields:
- `version: String`
- `timestamp: Date` (ISO-8601)
- `accounts: []`
- `categories: []`
- `tags: []`
- `transactions: []`
- `shortcuts: []`
- `recurringRules: []?`
- `recurringOccurrences: []?`
- `budgets: []?`
- `budgetHistory: []?`
- `budgetSettings: []?`
- `advanceCases: []?`
- `advanceParticipants: []?`
- `advanceRepayments: []?`

Compatibility behavior currently implemented on import:
- `accounts[].isArchived` missing -> default `false`
- `categories[].kind` missing/invalid -> default `Both`
- `shortcuts[].currencyCode` missing -> fallback to account currency or `HKD`
- `budgets[].isEnabled` missing -> default `true`
- `advanceCases[].myShareAmount` missing -> default `0`
- `advanceCases[].direction` missing -> infer only when existing links make the direction unambiguous
- `advanceCases[].tagIDs` missing/`null` -> default `[]`
- `advanceRepayments[].normalizedAmount` missing -> fallback to `amount`
- explicit advance transaction links missing -> conservatively backfill from existing case/group identifiers when unambiguous

## Cross-Platform Behavior Rules

- Reports must exclude transfer transactions from income/expense totals.
- Currency conversion is based on each transaction's `currencyCode`, not account default currency.
- Asset-adjustment legacy records are represented as transfers and must not affect income/expense charts.
- Multi-leg transfer editing must preserve `transferGroupID`.
- Refunds are expense reversals. If a refund lands in an own account, the own account increases. If a refund lands with a debt account holder, the debt balance moves in the user's favour. Linked report reduction is capped at the remaining original expense amount.
- Refund-aware report aggregation must expose gross amount, refund reduction, settlement-only excess, and net amount for report drill-down. Income reports must ignore refund records.

## Change Policy

When changing data model behavior:
1. Update this file in the same PR.
2. If backward-compatible (additive optional fields), keep import compatibility.
3. If not backward-compatible, bump backup `version` and provide migrator rules.
4. Add or refresh parity test vectors for iOS and Android.
5. Follow [`DATA_MIGRATION_AND_RECOVERY.md`](../DATA_MIGRATION_AND_RECOVERY.md) for store migration, rollback, and device validation.

### Version boundaries

- SwiftData schema compatibility, Room schema version, and backup JSON version are separate decisions.
- The Room version must increase for every persisted SQLite schema change and must include an explicit registered migration.
- The backup JSON version changes only when old and new payloads cannot safely share the documented defaults.
- A SwiftData model change must be tested against an existing store copy or generated legacy fixture even when no explicit numeric SwiftData version exists.

### Optional fields and defaults

- New backup fields should be optional unless every legacy record has a deterministic value.
- Missing and `null` must have the same documented interpretation when both can occur.
- Import defaults must be implemented and tested on iOS and Android.
- A post-import backfill may normalise an optional value, but it must not guess financial meaning.

### Identity and roundtrip

- UUIDs are stable identities, not import-session identifiers.
- Export → import → export must preserve IDs, references, amounts, currencies, timestamps, and semantic roles.
- Merge import must not be used to overwrite corrected records that reuse an existing ID.
- Replace import must validate before clearing, verify the clear, and recover the pre-import state when restore fails.
- Removing or repurposing an exported field requires a backup-version decision and explicit migration rules.

## Required Parity Test Vectors

At minimum, both platforms must produce matching results for:
- Income + expense + transfer in mixed currencies.
- Grouped transfer (1-to-many and many-to-1).
- Category kinds (`Expense` / `Income` / `Both`) filtering.
- Advance lifecycle: create case -> participant repayment -> remaining amount.
- Import old backup missing optional fields listed above.
