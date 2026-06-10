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
    if (transaction.type != TransactionType.Transfer) {
        return TransactionEditDestination.Ordinary(transaction.id.toString())
    }
    if (TransactionSemantics.isDebtForgiveness(transaction.note)) {
        return TransactionEditDestination.Debt(transaction.id.toString())
    }

    val groupId = transaction.transferGroupId
        ?: return TransactionEditDestination.Ordinary(transaction.id.toString())
    val classification = repository.classifyTransferGroup(groupId)
    return when (classification?.semantic) {
        TransferGroupSemantic.Debt ->
            TransactionEditDestination.Debt(transaction.id.toString())
        TransferGroupSemantic.AdvanceInitial,
        TransferGroupSemantic.AdvanceRepayment -> {
            val caseId = requireNotNull(classification.advanceCaseId) {
                "代墊分錄缺少案件關聯。"
            }
            TransactionEditDestination.Advance(caseId.toString())
        }
        TransferGroupSemantic.Ordinary,
        null -> TransactionEditDestination.Transfer(groupId.toString())
    }
}
