# ADR 0002: Advance And Debt Settlement Semantics

Status: Accepted
Date: 2026-06-05

## Context

Advance and debt flows are high-risk because they can describe real spending, cash movement, or ledger-only settlement. The most ambiguous cases are `他人代墊我`, `免除債務`, and `債務抵銷`.

## Decision

### 我代墊他人

When the user pays for others:

- The paying account is an own account.
- The user's own share is an expense on the advance date.
- Other participants' shares become amounts they owe the user.
- Initial advance creation appears as one case summary row in the ledger, not one row per participant leg.

### 他人代墊我

When someone else pays for the user:

- The user's own cash/bank/credit-card account does not move at creation time.
- The app must not create an incoming transfer into an own account.
- The cost is still the user's expense on the advance date.
- The expense is recorded through the other person's debt account so reports and budgets reflect the consumption date.
- Repayment later is a transfer/settlement event and must not double-count expense.

### Advance Repayment

A repayment can have an actual payment currency different from the advance case currency. Remaining balance calculations use `normalizedAmount` in the case currency. The actual amount/currency remain available for audit and display.

### 免除債務

Debt forgiveness reduces what one side owes without cash movement:

- It is not ordinary income.
- It is not ordinary expense.
- It is represented as settlement/transfer semantics using existing persistence.
- Ledger and account-detail UI should label it as `免除債務` instead of generic transfer when detected.

### 債務抵銷

Mutual debt offset is used when the same person and same currency has opposing outstanding advance balances:

- It does not touch own accounts.
- It does not create a regular `FinancialTransaction` for cash movement.
- It records auditable settlement through linked offset repayment markers.
- It is not repayment, not income, not expense, and not debt forgiveness.
- v1 does not offset across currencies.

## Consequences

- `他人代墊我` creation forms should not require an own account.
- Repayment forms should clearly distinguish actual payment currency from normalized settlement amount.
- Settlement center summaries should use directional language:待收 when others owe the user, 待還 when the user owes others.
- Data health checks should detect legacy `他人代墊我` data that increased an own account.
- Cross-platform tests should cover both ledger effects and report inclusion/exclusion.

## Related Specs

- `CONTEXT.md`
- `docs/specs/data-model.md`
- `docs/specs/parity-test-vectors.md`
- `docs/specs/android-ios-parity.md`
