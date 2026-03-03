# Cross-Platform Data Model Contract

Status: Active  
Last updated: 2026-03-03  
Current backup JSON version: `1.5`

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

### `AdvanceCase`
- `id: UUID` (unique)
- `title: String`
- `date: Date`
- `currencyCode: String`
- `myShareAmount: Decimal`
- `note: String`
- `selfExpenseTransactionID: UUID?`
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

## Backup JSON Contract (`FullBackupData`)

Top-level fields:
- `version: String`
- `timestamp: Date` (ISO-8601)
- `accounts: []`
- `categories: []`
- `tags: []`
- `transactions: []`
- `shortcuts: []`
- `budgets: []?`
- `advanceCases: []?`
- `advanceParticipants: []?`
- `advanceRepayments: []?`

Compatibility behavior currently implemented on import:
- `accounts[].isArchived` missing -> default `false`
- `categories[].kind` missing/invalid -> default `Both`
- `shortcuts[].currencyCode` missing -> fallback to account currency or `HKD`
- `budgets[].isEnabled` missing -> default `true`
- `advanceCases[].myShareAmount` missing -> default `0`
- `advanceRepayments[].normalizedAmount` missing -> fallback to `amount`

## Cross-Platform Behavior Rules

- Reports must exclude transfer transactions from income/expense totals.
- Currency conversion is based on each transaction's `currencyCode`, not account default currency.
- Asset-adjustment legacy records are represented as transfers and must not affect income/expense charts.
- Multi-leg transfer editing must preserve `transferGroupID`.

## Change Policy

When changing data model behavior:
1. Update this file in the same PR.
2. If backward-compatible (additive optional fields), keep import compatibility.
3. If not backward-compatible, bump backup `version` and provide migrator rules.
4. Add or refresh parity test vectors for iOS and Android.

## Required Parity Test Vectors

At minimum, both platforms must produce matching results for:
- Income + expense + transfer in mixed currencies.
- Grouped transfer (1-to-many and many-to-1).
- Category kinds (`Expense` / `Income` / `Both`) filtering.
- Advance lifecycle: create case -> participant repayment -> remaining amount.
- Import old backup missing optional fields listed above.
