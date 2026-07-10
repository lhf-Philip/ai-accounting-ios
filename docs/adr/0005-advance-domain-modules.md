# ADR 0005: Advance Domain Module Boundaries

Status: Accepted
Date: 2026-07-10

## Context

Advance bookkeeping currently spans large platform-specific mutation surfaces. On iOS, `AdvanceService` and `AdvanceCaseEditingService` own creation, repayment, structural editing, settlement, repair, and derived-budget updates. On Android, the same responsibilities are concentrated in `AccountingRepository`.

The behaviour is well covered by scenario tests, but the implementation has weak locality: a change to one advance lifecycle operation can require reading unrelated settlement and maintenance code. This makes atomicity and cross-platform parity harder to review.

Android's official architecture guidance recommends a data layer with repositories and an optional domain layer when business logic is complex or reused. It also warns against over-fine-grained modularisation. The project therefore needs a small number of cohesive domain modules, not one type per operation and not a second persistence abstraction without a real adapter.

## Decision

Both platforms will converge on four matching advance domain modules:

- **AdvanceSemantics**: pure direction, totals, outstanding balance, repayment-kind, and marker parsing rules.
- **AdvanceCaseLifecycle**: create, load/preview/apply structural edit, record/rollback ordinary repayment, and delete a case.
- **AdvanceSettlement**: mutual debt offsets, manual settlements, candidate calculation, and grouped rollback.
- **AdvanceMaintenance**: legacy link backfill, account-inflation repair, and reconciliation.

The modules are concrete implementations. A Swift protocol or Kotlin interface is introduced only when a second real adapter or test seam requires it.

Typed drafts cross the UI/domain boundary using stable IDs and scalar values. SwiftData and Room model objects remain inside the persistence implementation wherever practical.

Every lifecycle mutation that changes primary bookkeeping and derived budget history is one atomic operation:

- iOS stages all SwiftData mutations and affected budget-history updates in one `ModelContext.transaction` before one save boundary.
- Android keeps the equivalent operation inside one Room `withTransaction` boundary.
- Validation completes before destructive replacement begins.
- Failure leaves both the advance case and derived budget history at their previous state.

## Migration Strategy

The extraction proceeds in vertical slices:

1. Lock existing observable behaviour with synthetic characterisation tests.
2. Extract pure semantics and maintenance operations.
3. Move basic lifecycle writes.
4. Move structural editing behind the lifecycle interface.
5. Move settlements and remove superseded mutation paths.

Each slice must keep iOS and Android tests green and must not change schema, backup format, navigation, or user-facing behaviour.

## Consequences

- Advance mutation code gains stronger locality and smaller review surfaces.
- Screens depend on typed lifecycle operations rather than reconstructing accounting rules.
- Budget-history consistency becomes part of the lifecycle transaction, rather than a best-effort follow-up save.
- The repository remains the Android data boundary, but delegates advance-specific orchestration to cohesive modules.
- Existing `AdvanceService` and `AdvanceCaseEditingService` entry points are temporary compatibility seams and must be removed after callers migrate; shallow permanent wrappers are not acceptable.

## References

- [Android architecture recommendations](https://developer.android.com/topic/architecture/recommendations)
- [Android domain layer guidance](https://developer.android.com/topic/architecture/domain-layer)
- [Android modularisation guidance](https://developer.android.com/topic/modularization)
- [Apple ModelContext](https://developer.apple.com/documentation/swiftdata/modelcontext)
- [`CONTEXT.md`](../../CONTEXT.md)
- [`docs/ARCHITECTURE.md`](../ARCHITECTURE.md)
- [`docs/adr/0002-advance-and-debt-settlement.md`](./0002-advance-and-debt-settlement.md)
