# ADR 0001: Ledger Classification And Report Inclusion

Status: Accepted
Date: 2026-06-05

## Context

The app stores financial records as `Income`, `Expense`, or `Transfer`. Several flows look like income or expense at the UI level but must not be counted in reports, including transfers, asset adjustments, debt forgiveness, mutual debt offsets, and refunds.

Without a written rule, future changes can accidentally inflate income, expense, or asset totals.

## Decision

Use the transaction type and flow marker semantics to decide report inclusion:

- `Income` counts in income reports only when it represents real income into an own account.
- `Expense` counts in expense reports when it represents a cost incurred by the user.
- `Transfer` never counts in income/expense reports.
- Asset-adjustment legacy records are transfer-like and excluded from income/expense reports.
- Debt forgiveness is a settlement event and excluded from income/expense reports.
- Mutual debt offset is a ledger-only settlement event and excluded from income/expense reports.
- Refunds are expense reversals, not income. A linked refund reduces net expense up to the remaining original expense amount; any excess is settlement-only and must not be counted as income.

Normal income entry points must only allow own accounts. Debt accounts are handled through debt or advance flows.

## Consequences

- Report code must not infer income/expense from note text alone.
- Transfer groups can carry settlement semantics but must remain excluded from income/expense totals.
- Report code that displays refunds should show enough gross/refund/net detail for users to understand why a category total changed.
- Data health checks should flag old data where normal income was recorded into a debt account.
- Shortcut creation and editing must obey the same own-account/debt-account boundary as full entry forms.

## Related Specs

- `CONTEXT.md`
- `docs/specs/data-model.md`
- `docs/specs/parity-test-vectors.md`
