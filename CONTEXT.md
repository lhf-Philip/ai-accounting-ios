# AI Accounting Domain Context

Status: Active
Last updated: 2026-06-05

This file is the shared domain glossary for the iOS and Android apps. It explains the accounting language that agents should use when changing code, docs, tests, or GitHub issues.

The canonical data contract lives in `docs/specs/data-model.md`. Android/iOS UI parity lives in `docs/specs/android-ios-parity.md`. Deterministic cross-platform behaviour checks live in `docs/specs/parity-test-vectors.md`.

## Product Boundary

AI Accounting is a personal ledger app. It tracks the user's own accounts, debt accounts, transfers, advances, reports, budgets, backups, and data health checks.

The app is not a double-entry accounting system. It still needs strict semantic rules because the same real-world event can be represented as an income/expense transaction, a transfer-only ledger event, or an advance/debt settlement event.

## Core Entities

- **Own account**: A cash, bank, or credit-card account that represents the user's assets or liabilities. Income and expense entry points must only target own accounts unless a flow explicitly says otherwise.
- **Debt account**: An account of type `Debt`. It represents money owed between the user and another person. Debt accounts are not own accounts and should not appear in normal income account pickers.
- **Financial transaction**: A persisted ledger record. It is one of `Income`, `Expense`, or `Transfer`.
- **Transfer group**: One or more transfer legs sharing `transferGroupID`. Transfer groups support ordinary transfers, split transfers, merged transfers, repayments, debt forgiveness markers, and some legacy repair flows.
- **Category**: A classification for income and/or expense reporting. `CategoryKind` controls whether it is valid for expense, income, or both.
- **Tag**: A user-defined label that can cross-cut categories.
- **Shortcut**: A quick-entry template. It may create a transaction faster, but must obey the same account/category validity rules as the full editor.

## Ledger Inclusion Rules

- **Income** counts toward income reports and budgets only when the flow is true income into an own account.
- **Expense** counts toward expense reports and budgets when the flow represents consumption or a cost incurred by the user.
- **Transfer** does not count toward income or expense reports. It moves value between accounts or records settlement semantics.
- **Asset adjustment** is represented as transfer-like bookkeeping and must not affect income/expense charts.
- **Debt forgiveness** and **mutual debt offset** are not regular income/expense. They settle debt semantics without changing own-account cash flow.
- **Refund / rebate** is not regular income. It reverses or reduces a previously recorded expense. If the refund is received by an own account, the own account increases. If the refund is received by a debt account holder, that person's debt balance moves in the user's favour.

## Advances

- **Advance case**: A case-based record of someone paying for someone else. The ledger page shows initial advance creation as one summary row per case, not one row per underlying leg.
- **Advance participant**: A person involved in an advance case. The participant stores owed amount, repaid amount, and optional debt-account linkage.
- **I advanced others (`我代墊他人`)**: The user paid from an own account. The user's own share is an expense. Other people owe the user for their shares.
- **Others advanced me (`他人代墊我`)**: Another person paid for the user. The user's own account does not move at creation time. The cost is still the user's expense on the advance date, recorded against the other person's debt account.
- **Advance repayment**: A settlement record for a participant. If real money moves, it may link to a transfer group. If it is a ledger-only offset, it can exist without a received account or transfer group.
- **Cross-currency advance repayment**: The amount actually received or paid can use a different currency from the advance case. The repayment stores the actual currency amount and a normalized amount in the case currency for remaining-balance calculations.
- **Mutual debt offset (`債務抵銷`)**: Ledger-only settlement between opposing advance balances for the same person and currency. It is not repayment by cash and not debt forgiveness.
- **Refund on an advance (`退款`)**: A merchant or provider returns value related to a prior expense or advance. It reduces net expense for the linked category/tag up to the remaining original expense amount. Any excess is settlement-only, not income.

## Debt Management

- **Borrow (`借入`)**: The user receives value and owes another person.
- **Repay (`還款`)**: The user pays down an amount owed, or records collection from someone who owes the user, depending on direction.
- **Debt forgiveness (`免除債務`)**: A debt amount is reduced without cash movement. It is transfer/settlement semantics, not ordinary income.
- **Debt direction**: Positive settlement summaries mean the user is waiting to receive money. Negative summaries mean the user is waiting to pay money.

## Reports And Estimates

- **Main currency**: The user's primary display currency.
- **Original currency total**: Totals grouped by the transaction's original currency before conversion.
- **Estimated main-currency total**: A report display amount converted into the main currency using the current rate system. It is a display estimate, not a stored historical FX snapshot.
- **Estimate status**: Report UI should make clear whether conversion used live, cached, partial, or unavailable rates.
- **Report drill-down**: Category/tag detail sheets should show both estimated main-currency totals and original-currency breakdowns so users can audit the estimate.
- **Gross expense** is the original spending before refunds.
- **Net expense** is gross expense minus refund reductions. Refunds must not be displayed as income to make net expense look better.

## Backup Roundtrip

- **Backup roundtrip** means export -> import -> export should preserve the meaning of accounts, transactions, categories, tags, budgets, advance cases, participants, repayments, and semantic markers.
- Backward-compatible import defaults are documented in `docs/specs/data-model.md`.
- Changes that alter persisted meaning must update data-model docs and parity vectors in the same PR.

## Architecture Expectations

- iOS remains the product source of truth for screen structure and flow semantics.
- Android should match iOS semantics and user-facing flow unless `docs/specs/android-ios-parity.md` explicitly allows a difference.
- Domain logic should move toward small testable services/modules rather than screen-level recalculation.
- New agent work should prefer documented vocabulary from this file over ad-hoc synonyms.

## Architecture Decision Records

Current ADRs:

- `docs/adr/0001-ledger-classification.md`
- `docs/adr/0002-advance-and-debt-settlement.md`
- `docs/adr/0003-report-currency-estimates.md`
- `docs/adr/0004-refund-semantics.md`
