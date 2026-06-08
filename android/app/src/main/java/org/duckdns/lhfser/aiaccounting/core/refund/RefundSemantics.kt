package org.duckdns.lhfser.aiaccounting.core.refund

import java.math.BigDecimal

enum class RefundDestinationKind {
    OwnAccount,
    DebtAccount
}

data class RefundSemanticInput(
    val amount: BigDecimal,
    val destination: RefundDestinationKind,
    val originalExpenseRemaining: BigDecimal? = null
)

data class RefundSemanticEffect(
    val ownAccountDelta: BigDecimal,
    val debtBalanceDelta: BigDecimal,
    val expenseReduction: BigDecimal,
    val incomeContribution: BigDecimal,
    val settlementOnlyAmount: BigDecimal
) {
    val reportNetExpenseDelta: BigDecimal = expenseReduction.negate()
}

object RefundSemantics {
    fun effect(input: RefundSemanticInput): RefundSemanticEffect {
        require(input.amount > BigDecimal.ZERO) { "Refund amount must be positive." }
        input.originalExpenseRemaining?.let { remaining ->
            require(remaining >= BigDecimal.ZERO) { "Original expense remaining must not be negative." }
        }

        val expenseReduction = input.originalExpenseRemaining
            ?.min(input.amount)
            ?: input.amount
        val settlementOnlyAmount = (input.amount - expenseReduction).max(BigDecimal.ZERO)

        val ownAccountDelta: BigDecimal
        val debtBalanceDelta: BigDecimal
        when (input.destination) {
            RefundDestinationKind.OwnAccount -> {
                ownAccountDelta = input.amount
                debtBalanceDelta = BigDecimal.ZERO
            }
            RefundDestinationKind.DebtAccount -> {
                ownAccountDelta = BigDecimal.ZERO
                debtBalanceDelta = input.amount
            }
        }

        return RefundSemanticEffect(
            ownAccountDelta = ownAccountDelta,
            debtBalanceDelta = debtBalanceDelta,
            expenseReduction = expenseReduction,
            incomeContribution = BigDecimal.ZERO,
            settlementOnlyAmount = settlementOnlyAmount
        )
    }
}
