package org.duckdns.lhfser.aiaccounting.data.backup

import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

data class FullBackupData(
    val version: String,
    val timestamp: Instant,
    val accounts: List<AccountCodable>,
    val categories: List<CategoryCodable>,
    val tags: List<TagCodable>,
    val transactions: List<TransactionCodable>,
    val shortcuts: List<ShortcutCodable>,
    val recurringRules: List<RecurringRuleCodable>? = null,
    val recurringOccurrences: List<RecurringOccurrenceCodable>? = null,
    val budgets: List<BudgetCodable>?,
    val budgetHistory: List<BudgetHistoryCodable>?,
    val budgetSettings: List<BudgetSettingsCodable>? = null,
    val advanceCases: List<AdvanceCaseCodable>?,
    val advanceParticipants: List<AdvanceParticipantCodable>?,
    val advanceRepayments: List<AdvanceRepaymentCodable>?
) {
    data class AccountCodable(
        val id: UUID,
        val name: String,
        val currency: String,
        val type: String,
        val baseBalance: BigDecimal,
        val sortOrder: Int,
        val isArchived: Boolean?
    )

    data class CategoryCodable(
        val id: UUID,
        val name: String,
        val icon: String,
        val colorHex: String,
        val kind: String?
    )

    data class TagCodable(
        val id: UUID,
        val name: String
    )

    data class TransactionCodable(
        val id: UUID,
        val amount: BigDecimal,
        val currencyCode: String,
        val date: Instant,
        val note: String,
        val type: String,
        val linkedTransactionID: UUID?,
        val transferGroupID: UUID?,
        val transferSide: String?,
        val photoPath: String?,
        val createdAt: Instant?,
        val updatedAt: Instant?,
        val accountID: UUID?,
        val categoryID: UUID?,
        val tagIDs: List<UUID>
    )

    data class ShortcutCodable(
        val id: UUID,
        val name: String,
        val icon: String,
        val amount: BigDecimal,
        val type: String,
        val note: String,
        val currencyCode: String?,
        val accountID: UUID?,
        val categoryID: UUID?,
        val tagIDs: List<UUID>
    )

    data class RecurringRuleCodable(
        val id: UUID,
        val title: String,
        val amount: BigDecimal,
        val currencyCode: String,
        val type: String,
        val note: String,
        val frequency: String,
        val intervalCount: Int,
        val nextDueDate: Instant,
        val isPaused: Boolean,
        val accountID: UUID?,
        val categoryID: UUID?,
        val tagIDs: List<UUID>,
        val createdAt: Instant?,
        val updatedAt: Instant?
    )

    data class RecurringOccurrenceCodable(
        val id: UUID,
        val dueDate: Instant,
        val status: String,
        val createdTransactionID: UUID?,
        val ruleID: UUID?,
        val createdAt: Instant?,
        val updatedAt: Instant?
    )

    data class BudgetCodable(
        val id: UUID,
        val monthKey: String,
        val amount: BigDecimal,
        val currencyCode: String,
        val isEnabled: Boolean?,
        val categoryID: UUID?,
        val createdAt: Instant?,
        val updatedAt: Instant?
    )

    data class BudgetHistoryCodable(
        val id: UUID,
        val historyKey: String,
        val monthKey: String,
        val categoryID: UUID,
        val categoryNameSnapshot: String,
        val budgetAmount: BigDecimal,
        val spentAmount: BigDecimal,
        val remainingAmount: BigDecimal,
        val usageRatio: BigDecimal,
        val isOverBudget: Boolean,
        val currencyCode: String,
        val updatedAt: Instant?
    )

    data class BudgetSettingsCodable(
        val id: String,
        val carryOverMode: String,
        val alertThresholdPercent: BigDecimal,
        val forecastMode: String,
        val updatedAt: Instant?
    )

    data class AdvanceCaseCodable(
        val id: UUID,
        val title: String,
        val date: Instant,
        val currencyCode: String,
        val myShareAmount: BigDecimal?,
        val note: String?,
        val selfExpenseTransactionID: UUID?,
        val payerAccountID: UUID?,
        val expenseCategoryID: UUID?,
        val createdAt: Instant?,
        val updatedAt: Instant?
    )

    data class AdvanceParticipantCodable(
        val id: UUID,
        val name: String,
        val owedAmount: BigDecimal,
        val repaidAmount: BigDecimal?,
        val initialTransferGroupID: UUID?,
        val advanceCaseID: UUID?,
        val debtAccountID: UUID?,
        val createdAt: Instant?,
        val updatedAt: Instant?
    )

    data class AdvanceRepaymentCodable(
        val id: UUID,
        val amount: BigDecimal,
        val currencyCode: String,
        val normalizedAmount: BigDecimal?,
        val date: Instant,
        val note: String?,
        val linkedTransferGroupID: UUID?,
        val advanceCaseID: UUID?,
        val participantID: UUID?,
        val receivedAccountID: UUID?,
        val createdAt: Instant?
    )
}
