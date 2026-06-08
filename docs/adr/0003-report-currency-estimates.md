# ADR 0003: Report Currency Estimates And Drill-Down Totals

Status: Accepted
Date: 2026-06-05

## Context

The app supports accounts and transactions in multiple currencies. Users need reports in their main currency, but they also need to see the original currencies that produced the estimate. Exchange rates can be live, cached, partially available, or unavailable.

The app currently does not store historical FX snapshots for each transaction.

## Decision

Report totals should expose two layers:

- Original-currency totals grouped by transaction currency.
- Estimated main-currency totals converted using the current currency service and its fallback rules.

Report drill-down sheets should show the same information as the top-level report:

- estimated total in main currency;
- original currency breakdown;
- transaction count;
- estimate status when conversion is cached, partial, or unavailable.
- gross expense, refund reduction, and net expense when a report slice contains linked refunds.

Cross-currency advance repayments should preserve both actual payment currency and normalized case-currency amount. Reports should use transaction semantics for income/expense inclusion and should not treat repayment transfer movement as new spending.

## Consequences

- Main-currency report totals are estimates unless the transaction currency already equals the main currency.
- UI should avoid presenting converted totals as exact historical accounting facts.
- Refund-aware reports should not hide the original gross spending; users need both gross and net numbers to audit travel or shared-expense categories.
- Tests should use fixed exchange rates and exact decimal arithmetic.
- Future work that stores historical FX snapshots must update this ADR, the data model contract, backup compatibility, and parity vectors.

## Related Specs

- `CONTEXT.md`
- `docs/specs/data-model.md`
- `docs/specs/parity-test-vectors.md`
