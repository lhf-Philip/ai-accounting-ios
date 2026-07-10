package org.duckdns.lhfser.aiaccounting.core.advance

import org.junit.Assert.assertEquals
import org.junit.Test
import java.math.BigDecimal
import java.util.UUID

class AdvanceSemanticsTest {
    @Test
    fun totals_useExplicitScalarInputs() {
        assertEquals(
            BigDecimal("175"),
            AdvanceSemantics.totalAdvanced(
                myShareAmount = BigDecimal("25"),
                participantOwedAmounts = listOf(BigDecimal("100"), BigDecimal("50"))
            )
        )
        assertEquals(
            BigDecimal("90"),
            AdvanceSemantics.outstanding(listOf(BigDecimal("60"), BigDecimal("30")))
        )
    }

    @Test
    fun repaymentMarkerParsing_distinguishesValidAndInvalidSpecialRecords() {
        val offsetId = UUID.randomUUID()
        val settlementId = UUID.randomUUID()

        assertEquals(
            AdvanceRepaymentRecordKind.MutualDebtOffset(offsetId),
            AdvanceSemantics.repaymentRecordKind(
                "${AdvanceSemantics.mutualDebtOffsetMarker(offsetId)} offset"
            )
        )
        assertEquals(
            AdvanceRepaymentRecordKind.ManualDebtSettlement(settlementId),
            AdvanceSemantics.repaymentRecordKind(
                "${AdvanceSemantics.manualDebtSettlementMarker(settlementId)} settlement"
            )
        )
        assertEquals(
            AdvanceRepaymentRecordKind.InvalidSpecial,
            AdvanceSemantics.repaymentRecordKind("[債務抵銷:not-a-uuid]")
        )
        assertEquals(
            AdvanceRepaymentRecordKind.Ordinary,
            AdvanceSemantics.repaymentRecordKind("repayment")
        )
    }

    @Test
    fun legacyDirectionEvidence_prefersDebtAccountAndBorrowedMarker() {
        val debtAccountId = UUID.randomUUID()

        assertEquals(
            AdvanceSettlementDirection.OthersAdvancedMe,
            AdvanceSemantics.settlementDirection(debtAccountId, debtAccountId, "")
        )
        assertEquals(
            AdvanceSettlementDirection.OthersAdvancedMe,
            AdvanceSemantics.settlementDirection(
                debtAccountId,
                UUID.randomUUID(),
                "Dinner (他人代墊我：Friend)"
            )
        )
        assertEquals(
            AdvanceSettlementDirection.IAdvancedOthers,
            AdvanceSemantics.settlementDirection(
                debtAccountId,
                UUID.randomUUID(),
                "Dinner (代墊給 Friend)"
            )
        )
    }
}
