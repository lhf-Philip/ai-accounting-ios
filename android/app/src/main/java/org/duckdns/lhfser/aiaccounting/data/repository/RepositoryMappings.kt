package org.duckdns.lhfser.aiaccounting.data.repository

import org.duckdns.lhfser.aiaccounting.core.model.Account
import org.duckdns.lhfser.aiaccounting.core.model.AdvanceParticipant
import org.duckdns.lhfser.aiaccounting.core.model.Category
import org.duckdns.lhfser.aiaccounting.core.model.FinancialTransaction
import org.duckdns.lhfser.aiaccounting.core.model.Tag
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceParticipantEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.TagEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails

fun AccountEntity.toDomain(): Account = Account(
    id = id,
    name = name,
    currency = currency,
    type = type,
    baseBalance = baseBalance,
    sortOrder = sortOrder,
    isArchived = isArchived
)

fun CategoryEntity.toDomain(): Category = Category(
    id = id,
    name = name,
    icon = icon,
    colorHex = colorHex,
    kind = kind
)

fun TagEntity.toDomain(): Tag = Tag(
    id = id,
    name = name
)

fun TransactionWithDetails.toDomain(): FinancialTransaction = FinancialTransaction(
    id = transaction.id,
    amount = transaction.amount,
    currencyCode = transaction.currencyCode,
    date = transaction.date,
    note = transaction.note,
    photoPath = transaction.photoPath,
    type = transaction.type,
    linkedTransactionId = transaction.linkedTransactionId,
    transferGroupId = transaction.transferGroupId,
    transferSide = transaction.transferSide,
    createdAt = transaction.createdAt,
    updatedAt = transaction.updatedAt,
    accountId = transaction.accountId,
    categoryId = transaction.categoryId,
    tagIds = tags.map { it.id }
)

fun AdvanceParticipantEntity.toDomain(): AdvanceParticipant = AdvanceParticipant(
    id = id,
    name = name,
    owedAmount = owedAmount,
    repaidAmount = repaidAmount
)
