package org.duckdns.lhfser.aiaccounting.core

import org.duckdns.lhfser.aiaccounting.core.refund.RefundDestinationKind
import org.duckdns.lhfser.aiaccounting.core.refund.RefundSemanticInput
import org.duckdns.lhfser.aiaccounting.core.refund.RefundSemantics
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.math.BigDecimal

class RefundSemanticsTest {
    @Test
    fun refundToOwnAccount_reducesExpenseWithoutIncome() {
        val effect = RefundSemantics.effect(
            RefundSemanticInput(
                amount = BigDecimal("2550"),
                destination = RefundDestinationKind.OwnAccount,
                originalExpenseRemaining = BigDecimal("20650")
            )
        )

        assertMoneyEquals("2550", effect.ownAccountDelta)
        assertMoneyEquals("0", effect.debtBalanceDelta)
        assertMoneyEquals("2550", effect.expenseReduction)
        assertMoneyEquals("-2550", effect.reportNetExpenseDelta)
        assertMoneyEquals("0", effect.incomeContribution)
        assertMoneyEquals("0", effect.settlementOnlyAmount)
    }

    @Test
    fun refundToDebtAccount_reducesExpenseAndCreatesReceivableOrReducesPayable() {
        val effect = RefundSemantics.effect(
            RefundSemanticInput(
                amount = BigDecimal("2550"),
                destination = RefundDestinationKind.DebtAccount,
                originalExpenseRemaining = BigDecimal("20650")
            )
        )

        assertMoneyEquals("0", effect.ownAccountDelta)
        assertMoneyEquals("2550", effect.debtBalanceDelta)
        assertMoneyEquals("2550", effect.expenseReduction)
        assertMoneyEquals("-2550", effect.reportNetExpenseDelta)
        assertMoneyEquals("0", effect.incomeContribution)
        assertMoneyEquals("0", effect.settlementOnlyAmount)
    }

    @Test
    fun refundReductionIsCappedAtOriginalExpenseRemaining() {
        val effect = RefundSemantics.effect(
            RefundSemanticInput(
                amount = BigDecimal("2550"),
                destination = RefundDestinationKind.DebtAccount,
                originalExpenseRemaining = BigDecimal("2000")
            )
        )

        assertMoneyEquals("2550", effect.debtBalanceDelta)
        assertMoneyEquals("2000", effect.expenseReduction)
        assertMoneyEquals("-2000", effect.reportNetExpenseDelta)
        assertMoneyEquals("0", effect.incomeContribution)
        assertMoneyEquals("550", effect.settlementOnlyAmount)
    }

    @Test
    fun refundAmountMustBePositive() {
        assertThrows(IllegalArgumentException::class.java) {
            RefundSemantics.effect(
                RefundSemanticInput(
                    amount = BigDecimal.ZERO,
                    destination = RefundDestinationKind.OwnAccount
                )
            )
        }
    }

    private fun assertMoneyEquals(expected: String, actual: BigDecimal) {
        assertEquals(0, BigDecimal(expected).compareTo(actual))
    }
}
