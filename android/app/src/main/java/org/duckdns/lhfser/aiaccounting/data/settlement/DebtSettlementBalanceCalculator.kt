package org.duckdns.lhfser.aiaccounting.data.settlement

import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import java.math.BigDecimal

private val ZERO = BigDecimal.ZERO

data class DebtSettlementCurrencyBalance(
    val currencyCode: String,
    val amount: BigDecimal
)

object DebtSettlementBalanceCalculator {
    fun balancesFor(
        account: AccountEntity,
        transactions: List<TransactionWithDetails>,
        advanceCases: List<AdvanceCaseWithDetails>
    ): List<DebtSettlementCurrencyBalance> {
        return if (account.type == AccountType.Debt) {
            semanticDebtBalancesFor(account, transactions, advanceCases)
        } else {
            rawBalancesFor(account, transactions)
        }
    }

    fun rawBalancesFor(
        account: AccountEntity,
        transactions: List<TransactionWithDetails>
    ): List<DebtSettlementCurrencyBalance> {
        val totals = linkedMapOf<String, BigDecimal>()
        if (account.baseBalance != ZERO) {
            totals[account.currency] = account.baseBalance
        }
        transactions
            .filter { it.transaction.accountId == account.id }
            .forEach { tx ->
                val currency = tx.transaction.currencyCode
                totals[currency] = totals.getOrDefault(currency, ZERO) + tx.transaction.amount
            }
        return totals.toBalances()
    }

    fun semanticDebtBalancesFor(
        account: AccountEntity,
        transactions: List<TransactionWithDetails>,
        advanceCases: List<AdvanceCaseWithDetails>
    ): List<DebtSettlementCurrencyBalance> {
        val totals = linkedMapOf<String, BigDecimal>()
        if (account.baseBalance != ZERO) {
            totals[account.currency] = account.baseBalance
        }

        val advanceGroupIds = advanceCases
            .flatMap { advanceCase ->
                advanceCase.participants.mapNotNull { it.initialTransferGroupId } +
                    advanceCase.repayments.mapNotNull { it.linkedTransferGroupId }
            }
            .toSet()

        transactions
            .filter { it.transaction.accountId == account.id }
            .filterNot { tx -> tx.transaction.transferGroupId?.let { it in advanceGroupIds } == true }
            .forEach { tx ->
                val currency = tx.transaction.currencyCode
                totals[currency] = totals.getOrDefault(currency, ZERO) + tx.transaction.amount
            }

        advanceCases.forEach { advanceCase ->
            advanceCase.participants
                .filter { it.debtAccountId == account.id }
                .forEach { participant ->
                    val remaining = (participant.owedAmount - participant.repaidAmount).max(ZERO)
                    if (remaining > ZERO) {
                        val signedRemaining = if (advanceCase.advanceCase.payerAccountId != null) {
                            remaining
                        } else {
                            remaining.negate()
                        }
                        val currency = advanceCase.advanceCase.currencyCode
                        totals[currency] = totals.getOrDefault(currency, ZERO) + signedRemaining
                    }
                }
        }

        return totals.toBalances()
    }

    private fun Map<String, BigDecimal>.toBalances(): List<DebtSettlementCurrencyBalance> {
        return entries
            .filter { it.value.compareTo(ZERO) != 0 }
            .sortedBy { it.key }
            .map { DebtSettlementCurrencyBalance(currencyCode = it.key, amount = it.value) }
    }
}
