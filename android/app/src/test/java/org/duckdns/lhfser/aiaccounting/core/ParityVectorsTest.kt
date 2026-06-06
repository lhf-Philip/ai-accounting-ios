package org.duckdns.lhfser.aiaccounting.core

import org.duckdns.lhfser.aiaccounting.core.advance.AdvanceProgressCalculator
import org.duckdns.lhfser.aiaccounting.core.backup.BackupAccountInput
import org.duckdns.lhfser.aiaccounting.core.backup.BackupAdvanceCaseInput
import org.duckdns.lhfser.aiaccounting.core.backup.BackupAdvanceRepaymentInput
import org.duckdns.lhfser.aiaccounting.core.backup.BackupBudgetInput
import org.duckdns.lhfser.aiaccounting.core.backup.BackupCategoryInput
import org.duckdns.lhfser.aiaccounting.core.backup.BackupDefaults
import org.duckdns.lhfser.aiaccounting.core.backup.BackupShortcutInput
import org.duckdns.lhfser.aiaccounting.core.model.AdvanceParticipant
import org.duckdns.lhfser.aiaccounting.core.model.Category
import org.duckdns.lhfser.aiaccounting.core.model.CategoryKind
import org.duckdns.lhfser.aiaccounting.core.model.FinancialTransaction
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.core.report.CategoryFilter
import org.duckdns.lhfser.aiaccounting.core.report.IncomeExpenseCalculator
import org.duckdns.lhfser.aiaccounting.core.report.transferGroupNet
import org.duckdns.lhfser.aiaccounting.core.transactions.DebtForgivenessDirection
import org.duckdns.lhfser.aiaccounting.core.transactions.TransactionSemantics
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

class ParityVectorsTest {

    private val fxRates = mapOf(
        "HKD" to BigDecimal("1.00"),
        "USD" to BigDecimal("7.80"),
        "CNY" to BigDecimal("1.08")
    )

    @Test
    fun vector1_mixedCurrency_incomeExpenseTransfer() {
        val calculator = IncomeExpenseCalculator(baseCurrencyCode = "HKD", fxRatesToBase = fxRates)
        val now = Instant.parse("2026-03-01T00:00:00Z")

        val transactions = listOf(
            FinancialTransaction(amount = BigDecimal("1000"), currencyCode = "HKD", date = now, type = TransactionType.Income),
            FinancialTransaction(amount = BigDecimal("-100"), currencyCode = "HKD", date = now, type = TransactionType.Expense),
            FinancialTransaction(amount = BigDecimal("-50"), currencyCode = "USD", date = now, type = TransactionType.Expense),
            FinancialTransaction(amount = BigDecimal("-200"), currencyCode = "HKD", date = now, type = TransactionType.Transfer),
            FinancialTransaction(amount = BigDecimal("200"), currencyCode = "HKD", date = now, type = TransactionType.Transfer)
        )

        val totals = calculator.totals(transactions)

        assertMoneyEquals("1000.00", totals.incomeBase)
        assertMoneyEquals("490.00", totals.expenseBase)
        assertMoneyEquals("510.00", totals.netBase)
    }

    @Test
    fun vector2_groupedTransfer_oneToMany() {
        val now = Instant.parse("2026-03-01T00:00:00Z")
        val groupId = UUID.fromString("11111111-1111-1111-1111-111111111111")

        val group = listOf(
            FinancialTransaction(amount = BigDecimal("-300"), currencyCode = "HKD", date = now, type = TransactionType.Transfer, transferGroupId = groupId),
            FinancialTransaction(amount = BigDecimal("100"), currencyCode = "HKD", date = now, type = TransactionType.Transfer, transferGroupId = groupId),
            FinancialTransaction(amount = BigDecimal("200"), currencyCode = "HKD", date = now, type = TransactionType.Transfer, transferGroupId = groupId)
        )

        assertMoneyEquals("0.00", transferGroupNet(group, groupId))
        assertTrue(group.all { it.transferGroupId == groupId })
    }

    @Test
    fun vector3_categoryKindFiltering() {
        val categories = listOf(
            Category(name = "Food", icon = "fork.knife", colorHex = "#FF0000", kind = CategoryKind.Expense),
            Category(name = "Salary", icon = "banknote", colorHex = "#00FF00", kind = CategoryKind.Income),
            Category(name = "Adjustment", icon = "equal", colorHex = "#0000FF", kind = CategoryKind.Both)
        )

        val income = CategoryFilter.forTransactionType(categories, TransactionType.Income)
        val expense = CategoryFilter.forTransactionType(categories, TransactionType.Expense)

        assertEquals(listOf("Salary", "Adjustment"), income.map { it.name })
        assertEquals(listOf("Food", "Adjustment"), expense.map { it.name })
    }

    @Test
    fun vector4_advanceLifecycle() {
        val participants = listOf(
            AdvanceParticipant(name = "A", owedAmount = BigDecimal("50"), repaidAmount = BigDecimal("20")),
            AdvanceParticipant(name = "B", owedAmount = BigDecimal("50"), repaidAmount = BigDecimal("50"))
        )

        val progress = AdvanceProgressCalculator.compute(participants)

        assertMoneyEquals("30.00", progress.participants.first { it.name == "A" }.remainingAmount)
        assertMoneyEquals("0.00", progress.participants.first { it.name == "B" }.remainingAmount)
        assertMoneyEquals("30.00", progress.outstandingTotal)
    }

    @Test
    fun vector5_legacyBackupDefaults() {
        assertEquals(false, BackupDefaults.accountIsArchived(BackupAccountInput(isArchived = null)))
        assertEquals(CategoryKind.Both, BackupDefaults.categoryKind(BackupCategoryInput(kind = null)))
        assertEquals("HKD", BackupDefaults.shortcutCurrency(BackupShortcutInput(currencyCode = null), accountCurrency = null))
        assertEquals("USD", BackupDefaults.shortcutCurrency(BackupShortcutInput(currencyCode = null), accountCurrency = "USD"))
        assertEquals(true, BackupDefaults.budgetIsEnabled(BackupBudgetInput(isEnabled = null)))
        assertMoneyEquals("0.00", BackupDefaults.myShareAmount(BackupAdvanceCaseInput(myShareAmount = null)).setScale(2))
        assertMoneyEquals(
            "12.34",
            BackupDefaults.normalizedAmount(
                BackupAdvanceRepaymentInput(
                    amount = BigDecimal("12.34"),
                    normalizedAmount = null
                )
            ).setScale(2)
        )
    }

    @Test
    fun vector6_crossCurrencyRepayment_usesNormalizedAmountForOutstanding() {
        val progress = AdvanceProgressCalculator.compute(
            listOf(
                AdvanceParticipant(
                    name = "Friend A",
                    owedAmount = BigDecimal("1000"),
                    repaidAmount = BigDecimal("900")
                )
            )
        )

        assertMoneyEquals("100.00", progress.outstandingTotal)
    }

    @Test
    fun vector7_iAdvancedOthers_reportsOnlyUserShare() {
        val calculator = IncomeExpenseCalculator(baseCurrencyCode = "HKD", fxRatesToBase = fxRates)
        val now = Instant.parse("2026-03-01T00:00:00Z")
        val transactions = listOf(
            FinancialTransaction(amount = BigDecimal("-50"), currencyCode = "HKD", date = now, type = TransactionType.Expense),
            FinancialTransaction(amount = BigDecimal("-100"), currencyCode = "HKD", date = now, type = TransactionType.Transfer),
            FinancialTransaction(amount = BigDecimal("100"), currencyCode = "HKD", date = now, type = TransactionType.Transfer)
        )
        val progress = AdvanceProgressCalculator.compute(
            listOf(
                AdvanceParticipant(
                    name = "Friend A",
                    owedAmount = BigDecimal("100"),
                    repaidAmount = BigDecimal.ZERO
                )
            )
        )

        val totals = calculator.totals(transactions)

        assertMoneyEquals("50.00", totals.expenseBase)
        assertMoneyEquals("0.00", totals.incomeBase)
        assertMoneyEquals("100.00", progress.outstandingTotal)
    }

    @Test
    fun vector8_othersAdvancedMe_repaymentDoesNotDoubleCountExpense() {
        val calculator = IncomeExpenseCalculator(baseCurrencyCode = "HKD", fxRatesToBase = fxRates)
        val now = Instant.parse("2026-03-01T00:00:00Z")
        val transactions = listOf(
            FinancialTransaction(amount = BigDecimal("-150"), currencyCode = "HKD", date = now, type = TransactionType.Expense),
            FinancialTransaction(amount = BigDecimal("-150"), currencyCode = "HKD", date = now, type = TransactionType.Transfer),
            FinancialTransaction(amount = BigDecimal("150"), currencyCode = "HKD", date = now, type = TransactionType.Transfer)
        )
        val progress = AdvanceProgressCalculator.compute(
            listOf(
                AdvanceParticipant(
                    name = "Friend A",
                    owedAmount = BigDecimal("150"),
                    repaidAmount = BigDecimal("150")
                )
            )
        )

        val totals = calculator.totals(transactions)

        assertMoneyEquals("150.00", totals.expenseBase)
        assertMoneyEquals("0.00", totals.incomeBase)
        assertMoneyEquals("0.00", progress.outstandingTotal)
    }

    @Test
    fun vector13_settlementRecordsAreExcludedFromReports() {
        val calculator = IncomeExpenseCalculator(baseCurrencyCode = "HKD", fxRatesToBase = fxRates)
        val now = Instant.parse("2026-03-01T00:00:00Z")
        val forgivenessNote = TransactionSemantics.debtForgivenessNote(
            baseNote = "",
            debtAccountName = "Friend A",
            direction = DebtForgivenessDirection.ForgivenByOthers
        )
        val transactions = listOf(
            FinancialTransaction(amount = BigDecimal("-20"), currencyCode = "HKD", date = now, type = TransactionType.Expense),
            FinancialTransaction(amount = BigDecimal("-40"), currencyCode = "HKD", date = now, type = TransactionType.Transfer),
            FinancialTransaction(amount = BigDecimal("40"), currencyCode = "HKD", date = now, type = TransactionType.Transfer),
            FinancialTransaction(amount = BigDecimal("40"), currencyCode = "HKD", date = now, note = forgivenessNote, type = TransactionType.Transfer),
            FinancialTransaction(amount = BigDecimal("-100"), currencyCode = "HKD", date = now, type = TransactionType.Transfer),
            FinancialTransaction(amount = BigDecimal("92"), currencyCode = "CNY", date = now, type = TransactionType.Transfer),
            FinancialTransaction(
                amount = BigDecimal("1000"),
                currencyCode = "JPY",
                date = now,
                note = "${TransactionSemantics.ASSET_ADJUSTMENT_MARKER} JPY",
                type = TransactionType.Transfer
            )
        )

        val totals = calculator.totals(transactions)

        assertTrue(TransactionSemantics.isDebtForgiveness(forgivenessNote))
        assertMoneyEquals("20.00", totals.expenseBase)
        assertMoneyEquals("0.00", totals.incomeBase)
    }

    private fun assertMoneyEquals(expected: String, actual: BigDecimal) {
        val expectedValue = BigDecimal(expected)
        assertEquals(0, expectedValue.compareTo(actual))
    }
}
