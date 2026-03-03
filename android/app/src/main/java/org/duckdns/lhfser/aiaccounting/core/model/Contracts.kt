package org.duckdns.lhfser.aiaccounting.core.model

import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

enum class AccountType(val rawValue: String) {
    Cash("Cash"),
    Bank("Bank"),
    CreditCard("Credit Card"),
    Debt("Debt")
}

enum class TransactionType(val rawValue: String) {
    Income("Income"),
    Expense("Expense"),
    Transfer("Transfer")
}

enum class TransferSide(val rawValue: String) {
    Outgoing("Outgoing"),
    Incoming("Incoming")
}

enum class CategoryKind(val rawValue: String) {
    Expense("Expense"),
    Income("Income"),
    Both("Both");

    companion object {
        fun fromRawOrDefault(rawValue: String?): CategoryKind {
            return entries.firstOrNull { it.rawValue == rawValue } ?: Both
        }
    }
}

data class Account(
    val id: UUID = UUID.randomUUID(),
    val name: String,
    val currency: String,
    val type: AccountType,
    val baseBalance: BigDecimal,
    val sortOrder: Int,
    val isArchived: Boolean = false
)

data class Category(
    val id: UUID = UUID.randomUUID(),
    val name: String,
    val icon: String,
    val colorHex: String,
    val kind: CategoryKind = CategoryKind.Both
)

data class Tag(
    val id: UUID = UUID.randomUUID(),
    val name: String
)

data class FinancialTransaction(
    val id: UUID = UUID.randomUUID(),
    val amount: BigDecimal,
    val currencyCode: String,
    val date: Instant,
    val note: String = "",
    val photoPath: String? = null,
    val type: TransactionType,
    val linkedTransactionId: UUID? = null,
    val transferGroupId: UUID? = null,
    val transferSide: TransferSide? = null,
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now(),
    val accountId: UUID? = null,
    val categoryId: UUID? = null,
    val tagIds: List<UUID> = emptyList()
)

data class AdvanceParticipant(
    val id: UUID = UUID.randomUUID(),
    val name: String,
    val owedAmount: BigDecimal,
    val repaidAmount: BigDecimal
)
