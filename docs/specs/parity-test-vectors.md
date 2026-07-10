# Cross-Platform Parity Test Vectors

Status: Active  
Last updated: 2026-06-09

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

## Vector 7: 我代墊他人

Input:
- Own account A pays `150 HKD`.
- User share: `50 HKD`.
- Participant P owes: `100 HKD`.

Expected:
- Own account A ledger delta: `-150 HKD`.
- Expense report contribution: `50 HKD` only.
- Participant P outstanding receivable: `100 HKD`.
- The participant transfer legs contribute `0` to income/expense reports.

## Vector 8: 他人代墊我 + Repayment

Input:
- Participant P pays `150 HKD` for the user.
- No own account is selected at case creation.
- The user later repays `150 HKD` from own account A.

Expected after creation:
- Own account A ledger delta: `0`.
- Debt account P contains one `Expense -150 HKD`.
- Expense report contribution: `150 HKD`.
- Participant P outstanding payable: `150 HKD`.

Expected after repayment:
- Own account A repayment delta: `-150 HKD`.
- Participant P outstanding payable: `0`.
- Expense report contribution remains `150 HKD`; repayment does not count again.
- Income report contribution remains `0`.

## Vector 9: Mutual Debt Offset

Input for the same participant and currency:
- Participant P owes the user `100 HKD`.
- The user owes participant P `40 HKD`.

Expected after offset:
- Offset amount: `40 HKD`.
- Remaining receivable: `60 HKD`.
- Remaining payable: `0 HKD`.
- No `FinancialTransaction` is created.
- Income/expense reports are unchanged.
- Two auditable `AdvanceRepayment` records share one `[債務抵銷:<UUID>]` marker.

## Vector 10: Debt Forgiveness

Input:
- Forgiveness amount: `40 HKD`.
- Direction A: another person forgives what the user owes.
- Direction B: the user forgives what another person owes.

Expected:
- The debt balance decreases in the selected direction.
- No own cash/bank account moves.
- Transaction persistence uses `Transfer` semantics and the `[免除債務]` marker.
- Income report contribution: `0`.
- Expense report contribution: `0`.

## Vector 11: Same-Account Cross-Currency Transfer

Input transfer group `G2` on account A:
- Outgoing leg: `-100 HKD`.
- Incoming leg: `+92 CNY`.

Expected:
- Both legs reference account A and group `G2`.
- Linked transaction IDs and `Outgoing` / `Incoming` sides are preserved.
- Income/expense reports are unaffected.
- Backup export/import preserves both currencies, account ID, group ID, linked IDs, and transfer sides.

## Vector 12: Asset Adjustment

Input:
- Asset adjustment record: `+1000 JPY`.
- Persistence type: `Transfer`.
- Note begins with `[資產調整]`.

Expected:
- Account asset estimate includes the adjustment according to account-balance rules.
- Income report contribution: `0`.
- Expense report contribution: `0`.
- The ledger labels the record as an asset adjustment rather than ordinary income.

## Vector 13: Settlement Report Exclusion Set

Input:
- One ordinary expense: `-20 HKD`.
- One repayment transfer group.
- One debt-forgiveness transfer.
- One same-account cross-currency transfer group.
- One asset adjustment transfer.
- One mutual debt offset represented only by repayment markers.

Expected:
- Total expense: `20 HKD`.
- Total income: `0 HKD`.
- Settlement and transfer records remain auditable but never inflate income/expense totals.

## Vector 14: Refund To Own Account

Input:
- Original linked expense remaining: `20650 JPY`.
- Refund amount: `2550 JPY`.
- Refund destination: own account A.

Expected:
- Own account A ledger delta: `+2550 JPY`.
- Debt balance delta: `0`.
- Expense report reduction: `2550 JPY`.
- Net expense delta: `-2550 JPY`.
- Report drill-down shows gross expense, refund reduction, and net expense separately.
- Income report contribution: `0`.

## Vector 15: Refund To Debt Account Holder

Input:
- Original linked expense remaining: `20650 JPY`.
- Refund amount: `2550 JPY`.
- Refund destination: debt account Colin.

Expected:
- Own account ledger delta: `0`.
- Colin debt balance delta: `+2550 JPY` in the user's favour.
- If the user still owes Colin, payable decreases by `2550 JPY`.
- If the case is already settled, Colin now owes the user `2550 JPY`.
- Expense report reduction: `2550 JPY`.
- Report drill-down shows gross expense `20650 JPY`, refund reduction `2550 JPY`, and net expense `18100 JPY`.
- Income report contribution: `0`.

## Vector 16: Refund Larger Than Remaining Expense

Input:
- Original linked expense remaining: `2000 JPY`.
- Refund amount: `2550 JPY`.
- Refund destination: debt account Colin.

Expected:
- Colin debt balance delta: `+2550 JPY` in the user's favour.
- Expense report reduction is capped at `2000 JPY`.
- Settlement-only amount: `550 JPY`.
- Report drill-down shows refund reduction `2000 JPY` separately from settlement-only `550 JPY`.
- Income report contribution: `0`.

## Vector 17: Cross-Currency Advance Repayment Edit

Input:
- Case currency: `JPY`.
- Existing actual repayment: `50 HKD`.
- Existing normalized settlement: `1000 JPY`.
- Edit actual repayment to `60 HKD`.
- Explicitly edit normalized settlement to `900 JPY`.

Expected:
- Actual repayment remains `60 HKD` on both transfer legs.
- Participant repaid total becomes `900 JPY`; no current exchange rate is applied during save.
- For `我代墊他人`, income category/tags are stored on the incoming own-account leg.
- For `他人代墊我`, expense category/tags are stored on the outgoing own-account leg.
- Creation timestamp and transfer-group identity remain unchanged.

## Vector 18: Advance Own Share And Participant Correction

Input:
- Case currency: `JPY`.
- Existing own-share expense: `725 JPY`.
- Edit actual own-account debit to `35.59 CHF`, normalized case share to `725 JPY`.
- Correct one participant owed amount from `1000 JPY` to `1200 JPY`.

Expected:
- The own-account expense stores `-35.59 CHF`.
- The case summary continues to store the explicitly entered `725 JPY` share.
- The participant and its initial transfer/expense bookkeeping both store `1200 JPY`.
- Case-wide metadata edits update every participant's initial record atomically.
- Reports use the edited expense category/tags without detaching the record from its advance case.

## Vector 19: Special Settlement Group Rollback

Input:
- A mutual debt offset creates multiple repayments sharing `[債務抵銷:<UUID>]`.
- A manual settlement creates one or more repayments sharing `[跨幣種平賬:<UUID>]`.

Expected:
- Generic single-repayment edit and rollback APIs reject both marker types.
- The dedicated rollback API deletes every repayment with the matching marker.
- Every affected participant's repaid total is reduced by the full grouped allocation.
- No financial transaction is created or deleted by these marker-only rollbacks.
- The advance detail UI labels these records as offset/settlement rather than ordinary repayment.

## Vector 20: Advance Lifecycle And Budget History Consistency

Input:
- Expense budget: `500 HKD` for category `Dining` in `2026-06`.
- `他人代墊我` case: participant pays `150 HKD` on `2026-06-10`.
- The case is later deleted together with its linked bookkeeping.

Expected after creation:
- One advance case and one linked debt-account expense exist.
- Budget history spent amount: `150 HKD`.
- Budget history remaining amount: `350 HKD`.

Expected after deletion:
- The advance case and linked expense no longer exist.
- Budget history spent amount: `0 HKD`.
- Budget history remaining amount: `500 HKD`.
- A failed lifecycle mutation must leave the case, linked bookkeeping, and budget history at their pre-operation values.

## Automated Coverage

| Vector | iOS | Android |
|---|---|---|
| 1-5 | `BackupCompatibilityTests`, `LedgerSemanticVectorsTests` | `ParityVectorsTest`, `BackupRoundTripTest` |
| 6 | `testCrossCurrencyAdvanceRepayment_semanticDebtBalanceUsesCaseCurrencyRemainingOnly` | `crossCurrencyAdvanceRepayment_semanticDebtBalanceUsesCaseCurrencyRemainingOnly` |
| 7 | `testAdvancedOthersCreation_recordsFullOutflowAndOnlySelfShareExpense`, `LedgerSemanticVectorsTests.testVector7_iAdvancedOthers_reportsOnlyUserShare` | `advancedOthersCreation_recordsFullOutflowAndOnlySelfShareExpense`, `ParityVectorsTest.vector7_iAdvancedOthers_reportsOnlyUserShare` |
| 8 | `testBorrowedAdvanceCreation_recordsDebtExpenseWithoutInflatingOwnAccount` | `borrowedAdvanceCreation_recordsDebtExpenseWithoutInflatingOwnAccount` |
| 9 | `testMutualDebtOffset_settlesBidirectionalAdvancesWithoutTransactions` | `mutualDebtOffset_settlesBidirectionalAdvancesWithoutTransactions` |
| 10, 12, 13 | `LedgerSemanticVectorsTests.testVector13_settlementRecordsAreExcludedFromReports` | `ParityVectorsTest.vector13_settlementRecordsAreExcludedFromReports` |
| 11 | `testExportImport_preservesSameAccountCrossCurrencyTransferAndBudgetHistory_excludesUIPreferences` | `backupRoundTrip_preservesSameAccountCrossCurrencyTransferAndBudgetHistory` |
| 14-16 | `RefundSemanticsServiceTests`, `ReportAggregationServiceTests.testRefundAggregation_reducesExpenseWithoutCountingIncome`, `ReportAggregationServiceTests.testRefundAggregation_capsExpenseReductionAndKeepsExcessSettlementOnly` | `RefundSemanticsTest`, `ReportAggregationTest.refundAggregation_reducesExpenseWithoutCountingIncome`, `ReportAggregationTest.refundAggregation_capsExpenseReductionAndKeepsExcessSettlementOnly` |
| 17 | `AdvanceEditingTests.testCrossCurrencyRepaymentEditPreservesExplicitNormalizedAmountAndIncomingMetadata`, `AdvanceEditingTests.testOthersAdvancedMeEditTagsOutgoingOwnLegAndRollbackRestoresParticipant` | `AdvanceEditingTest.crossCurrencyRepaymentEdit_preservesExplicitSettlementAndMovesMetadataToIncomingOwnLeg`, `AdvanceEditingTest.othersAdvancedMeRepaymentEdit_tagsOutgoingOwnLegAndRollbackRestoresParticipant` |
| 18 | `AdvanceEditingTests.testSelfExpenseEditPreservesActualCurrencyAndNormalisedCaseShare`, `AdvanceEditingTests.testParticipantCorrectionUpdatesBorrowedInitialExpense`, `AdvanceEditingTests.testInitialEntryEditUpdatesCaseMetadataAcrossEveryParticipant` | `AdvanceEditingTest.selfExpenseEdit_preservesActualCurrencyAndNormalizedCaseShare`, `AdvanceEditingTest.participantCorrection_updatesBorrowedInitialExpenseAtomically`, `AdvanceEditingTest.initialMetadataEdit_updatesEveryParticipantGroup` |
| 19 | `BackupCompatibilityTests.testMutualDebtOffset_settlesBidirectionalAdvancesWithoutTransactions`, `BackupCompatibilityTests.testManualDebtSettlement_closesSingleCurrencyAdvanceWithoutTransactions` | `BackupRoundTripTest.mutualDebtOffset_settlesBidirectionalAdvancesWithoutTransactions`, `BackupRoundTripTest.manualDebtSettlement_closesSingleCurrencyAdvanceWithoutTransactions` |
| 20 | `AdvanceLifecycleCharacterisationTests.testBorrowedAdvanceLifecycleKeepsBudgetHistoryConsistent` | `AdvanceLifecycleCharacterisationTest.borrowedAdvanceLifecycle_keepsBudgetHistoryConsistent` |

## CI Gate Recommendation

When Android data layer is ready, run these vectors in both platforms and compare:
- Per-vector normalized JSON output snapshot
- Numeric totals (income/expense/net/outstanding)
- Category filter result sets
