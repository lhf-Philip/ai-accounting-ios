package org.duckdns.lhfser.aiaccounting.ui.routing

import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.core.transactions.TransactionSemantics
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository
import org.duckdns.lhfser.aiaccounting.data.repository.TransferGroupSemantic

sealed interface TransactionEditDestination {
    data class Ordinary(val transactionId: String) : TransactionEditDestination
    data class Transfer(val groupId: String) : TransactionEditDestination
    data class Debt(val transactionId: String) : TransactionEditDestination
    data class Advance(val caseId: String) : TransactionEditDestination
}

suspend fun resolveTransactionEditDestination(
    repository: AccountingRepository,
    item: TransactionWithDetails
): TransactionEditDestination {
    val transaction = item.transaction
    if (TransactionSemantics.isDebtForgiveness(transaction.note)) {
        return TransactionEditDestination.Debt(transaction.id.toString())
    }

    transaction.advanceCaseId?.let { caseId ->
        return TransactionEditDestination.Advance(caseId.toString())
    }

    repository.findAdvanceCaseIdBySelfExpense(transaction.id)?.let { caseId ->
        return TransactionEditDestination.Advance(caseId.toString())
    }

    val groupId = transaction.transferGroupId
    if (groupId != null) {
        val classification = repository.classifyTransferGroup(groupId)
        when (classification?.semantic) {
            TransferGroupSemantic.Debt ->
                return TransactionEditDestination.Debt(transaction.id.toString())
            TransferGroupSemantic.AdvanceInitial,
            TransferGroupSemantic.AdvanceRepayment -> {
                val caseId = requireNotNull(classification.advanceCaseId) {
                    "代墊分錄缺少案件關聯。"
                }
                return TransactionEditDestination.Advance(caseId.toString())
            }
            TransferGroupSemantic.Ordinary,
            null -> Unit
        }
    }

    return if (transaction.type == TransactionType.Transfer && groupId != null) {
        TransactionEditDestination.Transfer(groupId.toString())
    } else {
        TransactionEditDestination.Ordinary(transaction.id.toString())
    }
}
