package org.duckdns.lhfser.aiaccounting.data.db

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.CategoryKind
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.core.model.TransferSide
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

@Entity(tableName = "accounts")
data class AccountEntity(
    @PrimaryKey val id: UUID,
    val name: String,
    val currency: String,
    val type: AccountType,
    val baseBalance: BigDecimal,
    val sortOrder: Int,
    val isArchived: Boolean
)

@Entity(tableName = "categories")
data class CategoryEntity(
    @PrimaryKey val id: UUID,
    val name: String,
    val icon: String,
    val colorHex: String,
    val kind: CategoryKind
)

@Entity(tableName = "tags")
data class TagEntity(
    @PrimaryKey val id: UUID,
    val name: String
)

@Entity(
    tableName = "transactions",
    indices = [
        Index("accountId"),
        Index("categoryId"),
        Index("transferGroupId")
    ]
)
data class TransactionEntity(
    @PrimaryKey val id: UUID,
    val amount: BigDecimal,
    val currencyCode: String,
    val date: Instant,
    val note: String,
    val photoPath: String?,
    val type: TransactionType,
    val linkedTransactionId: UUID?,
    val transferGroupId: UUID?,
    val transferSide: TransferSide?,
    val createdAt: Instant,
    val updatedAt: Instant,
    val accountId: UUID?,
    val categoryId: UUID?
)

@Entity(
    tableName = "transaction_tag_cross_ref",
    primaryKeys = ["transactionId", "tagId"],
    indices = [Index("tagId")]
)
data class TransactionTagCrossRef(
    val transactionId: UUID,
    val tagId: UUID
)

@Entity(
    tableName = "shortcuts",
    indices = [Index("accountId"), Index("categoryId")]
)
data class ShortcutEntity(
    @PrimaryKey val id: UUID,
    val name: String,
    val icon: String,
    val amount: BigDecimal,
    val currencyCode: String,
    val type: TransactionType,
    val note: String,
    val accountId: UUID?,
    val categoryId: UUID?
)

@Entity(
    tableName = "shortcut_tag_cross_ref",
    primaryKeys = ["shortcutId", "tagId"],
    indices = [Index("tagId")]
)
data class ShortcutTagCrossRef(
    val shortcutId: UUID,
    val tagId: UUID
)

@Entity(
    tableName = "category_monthly_budgets",
    indices = [Index("monthKey"), Index("categoryId")]
)
data class CategoryMonthlyBudgetEntity(
    @PrimaryKey val id: UUID,
    val monthKey: String,
    val amount: BigDecimal,
    val currencyCode: String,
    val isEnabled: Boolean,
    val createdAt: Instant,
    val updatedAt: Instant,
    val categoryId: UUID?
)

@Entity(
    tableName = "budget_monthly_history",
    indices = [
        Index("monthKey"),
        Index("categoryId"),
        Index(value = ["historyKey"], unique = true)
    ]
)
data class BudgetMonthlyHistoryEntity(
    @PrimaryKey val id: UUID,
    val historyKey: String,
    val monthKey: String,
    val categoryId: UUID,
    val categoryNameSnapshot: String,
    val budgetAmount: BigDecimal,
    val spentAmount: BigDecimal,
    val remainingAmount: BigDecimal,
    val usageRatio: BigDecimal,
    val isOverBudget: Boolean,
    val currencyCode: String,
    val updatedAt: Instant
)

@Entity(tableName = "budget_settings")
data class BudgetSettingsEntity(
    @PrimaryKey val id: String = "global",
    val carryOverMode: String = "None",
    val alertThresholdPercent: BigDecimal = BigDecimal("85"),
    val forecastMode: String = "SpendingPace",
    val updatedAt: Instant = Instant.now()
)

@Entity(
    tableName = "advance_cases",
    indices = [Index("payerAccountId"), Index("expenseCategoryId")]
)
data class AdvanceCaseEntity(
    @PrimaryKey val id: UUID,
    val title: String,
    val date: Instant,
    val currencyCode: String,
    val myShareAmount: BigDecimal,
    val note: String,
    val selfExpenseTransactionId: UUID?,
    val createdAt: Instant,
    val updatedAt: Instant,
    val payerAccountId: UUID?,
    val expenseCategoryId: UUID?
)

@Entity(
    tableName = "advance_participants",
    indices = [Index("advanceCaseId"), Index("debtAccountId")]
)
data class AdvanceParticipantEntity(
    @PrimaryKey val id: UUID,
    val name: String,
    val owedAmount: BigDecimal,
    val repaidAmount: BigDecimal,
    val initialTransferGroupId: UUID?,
    val createdAt: Instant,
    val updatedAt: Instant,
    val advanceCaseId: UUID?,
    val debtAccountId: UUID?
)

@Entity(
    tableName = "advance_repayments",
    indices = [Index("advanceCaseId"), Index("participantId"), Index("receivedAccountId")]
)
data class AdvanceRepaymentEntity(
    @PrimaryKey val id: UUID,
    val amount: BigDecimal,
    val currencyCode: String,
    val normalizedAmount: BigDecimal,
    val date: Instant,
    val note: String,
    val linkedTransferGroupId: UUID?,
    val createdAt: Instant,
    val advanceCaseId: UUID?,
    val participantId: UUID?,
    val receivedAccountId: UUID?
)
