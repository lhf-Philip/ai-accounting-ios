package org.duckdns.lhfser.aiaccounting.core.report

import org.duckdns.lhfser.aiaccounting.core.model.Category
import org.duckdns.lhfser.aiaccounting.core.model.CategoryKind
import org.duckdns.lhfser.aiaccounting.core.model.FinancialTransaction
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import java.math.BigDecimal
import java.math.RoundingMode
import java.util.UUID

data class IncomeExpenseTotals(
    val incomeBase: BigDecimal,
    val expenseBase: BigDecimal,
    val netBase: BigDecimal
)

class IncomeExpenseCalculator(
    private val baseCurrencyCode: String,
    private val fxRatesToBase: Map<String, BigDecimal>
) {
    fun totals(transactions: List<FinancialTransaction>): IncomeExpenseTotals {
        var income = BigDecimal.ZERO
        var expense = BigDecimal.ZERO

        transactions.forEach { transaction ->
            if (transaction.type == TransactionType.Transfer) {
                return@forEach
            }

            val convertedAbs = convertToBase(transaction.amount, transaction.currencyCode).abs()
            when (transaction.type) {
                TransactionType.Income -> income = income + convertedAbs
                TransactionType.Expense -> expense = expense + convertedAbs
                TransactionType.Transfer -> Unit
            }
        }

        income = income.money()
        expense = expense.money()
        val net = (income - expense).money()
        return IncomeExpenseTotals(incomeBase = income, expenseBase = expense, netBase = net)
    }

    private fun convertToBase(amount: BigDecimal, currencyCode: String): BigDecimal {
        val rate = when {
            currencyCode == baseCurrencyCode -> BigDecimal.ONE
            else -> fxRatesToBase[currencyCode]
                ?: error("Missing FX rate for $currencyCode -> $baseCurrencyCode")
        }

        return amount.multiply(rate).setScale(6, RoundingMode.HALF_UP)
    }

    private fun BigDecimal.money(): BigDecimal = setScale(2, RoundingMode.HALF_UP)
}

object CategoryFilter {
    fun forTransactionType(categories: List<Category>, type: TransactionType): List<Category> {
        return categories.filter { category ->
            when (type) {
                TransactionType.Income -> category.kind == CategoryKind.Income || category.kind == CategoryKind.Both
                TransactionType.Expense -> category.kind == CategoryKind.Expense || category.kind == CategoryKind.Both
                TransactionType.Transfer -> true
            }
        }
    }
}

fun transferGroupNet(transactions: List<FinancialTransaction>, transferGroupId: UUID): BigDecimal {
    return transactions
        .filter { it.transferGroupId == transferGroupId }
        .fold(BigDecimal.ZERO) { acc, tx -> acc + tx.amount }
        .setScale(2, RoundingMode.HALF_UP)
}
