# ADR 0004: Refund And Rebate Semantics

Status: Accepted
Date: 2026-06-09

## Context

Travel and shared-expense flows can receive refunds after the original expense has already been recorded. A refund can arrive in the user's own account, or it can arrive with a debt account holder such as a friend who paid or received money on the user's behalf.

Treating refunds as ordinary income makes reports misleading. Treating a refund received by another person as if it entered the user's own account inflates assets. Treating every refund as a debt settlement hides the fact that the original category's net expense changed.

## Decision

Refunds are expense reversals, not income.

### Refund received by an own account

- The own account increases by the actual refund amount.
- The linked category/tag net expense decreases by the refund amount.
- Income contribution is `0`.

### Refund received by a debt account holder

- The user's own account does not move.
- The debt balance moves in the user's favour by the refund amount.
  - If the user still owes that person, the payable decreases.
  - If nothing is owed, that person now owes the user.
- The linked category/tag net expense decreases by the refund amount.
- Income contribution is `0`.

### Refund cap and excess

When a refund is linked to a known original expense, report reduction is capped at the remaining original expense amount. Any excess is settlement-only and must not be counted as income.

## Consequences

- Refund forms should prefill as much as possible from the original expense or advance case.
- Refund records must be auditable and reversible, because they can alter both reports and debt balances.
- Report drill-down should show gross expense, refund reduction, net expense, original-currency totals, and estimate status.
- Cross-platform parity vectors must cover own-account refunds, debt-account refunds, capped reductions, and cross-currency display expectations.
- v1 does not require a SwiftData or Room schema migration; persistence can be designed in a later PR after this semantic seam is stable.

## Related Specs

- `CONTEXT.md`
- `docs/specs/data-model.md`
- `docs/specs/parity-test-vectors.md`
- `docs/adr/0001-ledger-classification.md`
- `docs/adr/0002-advance-and-debt-settlement.md`
- `docs/adr/0003-report-currency-estimates.md`
