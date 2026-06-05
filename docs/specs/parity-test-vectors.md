# Cross-Platform Parity Test Vectors

Status: Active  
Last updated: 2026-03-03

This document defines deterministic input/output vectors for iOS and Android parity checks.

## Test Harness Rules

- Use fixed FX rates for tests (do not call live rate services).
- Parse decimals with exact decimal arithmetic.
- Treat transfer records as excluded from income/expense totals.
- Use values from `docs/specs/data-model.md` enum contract exactly.

## Fixed FX Table (for vectors in this document)

- `HKD -> HKD = 1.00`
- `USD -> HKD = 7.80`
- `CNY -> HKD = 1.08`

## Vector 1: Mixed-Currency Income/Expense + Transfer

Input transactions:
- Income: `+1000 HKD`
- Expense: `-100 HKD`
- Expense: `-50 USD`
- Transfer: `-200 HKD` (outgoing)
- Transfer: `+200 HKD` (incoming)

Expected:
- Total income (HKD): `1000.00`
- Total expense (HKD): `490.00` (`100 + 50*7.8`)
- Net income/expense (HKD): `510.00`
- Transfer contribution to income/expense totals: `0`

## Vector 2: Grouped Transfer (1-to-many)

Input transfer group `G1`:
- Outgoing leg: `-300 HKD` from A
- Incoming leg: `+100 HKD` to B
- Incoming leg: `+200 HKD` to C

Expected:
- Group sum by amount: `0`
- Group ID preserved on all legs: `G1`
- Income/expense reports: unaffected by this group

## Vector 3: CategoryKind Filtering

Categories:
- Food (`Expense`)
- Salary (`Income`)
- Adjustment (`Both`)

Input:
- Expense on Food: `-80 HKD`
- Income on Salary: `+500 HKD`
- Expense on Adjustment: `-20 HKD`
- Income on Adjustment: `+30 HKD`

Expected:
- Expense picker includes: Food, Adjustment
- Income picker includes: Salary, Adjustment
- Expense-only category never accepted for income transaction
- Income-only category never accepted for expense transaction

## Vector 4: Advance Lifecycle

Input:
- Advance case total: `150 HKD` (self share `50`, participant A `50`, participant B `50`)
- Repayment A: `20 HKD`
- Repayment B: `50 HKD`

Expected:
- Participant A remaining: `30`
- Participant B remaining: `0`
- Case outstanding total: `30`

## Vector 5: Legacy Backup Optional Fields

Input backup omissions:
- Missing `accounts[].isArchived`
- Missing `categories[].kind`
- Missing `shortcuts[].currencyCode`
- Missing `budgets[].isEnabled`
- Missing `advanceCases[].myShareAmount`
- Missing `advanceRepayments[].normalizedAmount`

Expected import defaults:
- `isArchived = false`
- `kind = Both`
- `currencyCode = account.currency`, fallback `HKD`
- `isEnabled = true`
- `myShareAmount = 0`
- `normalizedAmount = amount`

## Vector 6: Cross-Currency Advance Repayment Settlement Balance

Input:
- Advance case currency: `JPY`
- Participant A owes: `1000 JPY`
- Repayment actual amount: `50 HKD`
- Repayment normalized amount: `900 JPY`

Expected:
- Participant A remaining amount: `100 JPY`
- Settlement center / debt account semantic balance for A: `+100 JPY`
- The actual `50 HKD` repayment remains visible in repayment history / timeline.
- The actual `50 HKD` repayment must not appear as a separate reverse debt balance.
- Raw linked advance transfer legs are implementation details and must not drive settlement summary balances.

## CI Gate Recommendation

When Android data layer is ready, run these vectors in both platforms and compare:
- Per-vector normalized JSON output snapshot
- Numeric totals (income/expense/net/outstanding)
- Category filter result sets
