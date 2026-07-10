package org.duckdns.lhfser.aiaccounting.data.advance

import androidx.room.withTransaction
import org.duckdns.lhfser.aiaccounting.core.advance.AdvanceEntryRole
import org.duckdns.lhfser.aiaccounting.core.advance.AdvanceSemantics
import org.duckdns.lhfser.aiaccounting.core.advance.AdvanceSettlementDirection
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.core.model.TransferSide
import org.duckdns.lhfser.aiaccounting.data.db.AIAccountingDatabase
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceParticipantEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionEntity
import java.math.BigDecimal
import java.time.Instant

data class LegacyBorrowedAdvanceRepairResult(
    val repairedParticipantCount: Int,
    val removedInflatedAccountTransactionCount: Int
)

/**
 * Owns idempotent repair and link-backfill operations for the advance aggregate.
 *
 * Public operations establish their own Room transaction. The restore adapter may call
 * [backfillLinksInCurrentTransaction] only while it already owns the database transaction.
 */
class AdvanceMaintenance(
    private val database: AIAccountingDatabase,
    private val synchronizeBudgetHistory: suspend () -> Unit
) {
    private val advanceDao = database.advanceDao()
    private val transactionDao = database.transactionDao()

    suspend fun repairLegacyBorrowedAdvanceAccountInflation(): LegacyBorrowedAdvanceRepairResult {
        return database.withTransaction {
            val cases = advanceDao.getAllCasesWithDetails()
            var repairedParticipantCount = 0
            var removedInflatedAccountTransactionCount = 0

            for (caseDetails in cases) {
                for (participant in caseDetails.participants) {
                    val groupId = participant.initialTransferGroupId ?: continue
                    val debtAccountId = participant.debtAccountId ?: continue
                    val group = transactionDao.getTransferGroup(groupId)
                    val outgoing = group.firstOrNull { details ->
                        details.transaction.accountId == debtAccountId &&
                            (
                                details.transaction.transferSide == TransferSide.Outgoing ||
                                    details.transaction.amount < BigDecimal.ZERO
                                )
                    } ?: continue
                    val inflatedIncoming = group.filter { details ->
                        details.transaction.id != outgoing.transaction.id &&
                            details.transaction.amount > BigDecimal.ZERO &&
                            details.account?.type != AccountType.Debt
                    }
                    if (inflatedIncoming.isEmpty()) continue

                    val now = Instant.now()
                    val baseNote = caseDetails.advanceCase.note.ifBlank {
                        caseDetails.advanceCase.title
                    }
                    transactionDao.upsert(
                        outgoing.transaction.copy(
                            amount = outgoing.transaction.amount.abs().negate(),
                            note = "$baseNote (他人代墊我：${participant.name})",
                            type = TransactionType.Expense,
                            linkedTransactionId = null,
                            transferSide = TransferSide.Outgoing,
                            categoryId = caseDetails.advanceCase.expenseCategoryId,
                            updatedAt = now
                        )
                    )

                    inflatedIncoming.forEach { details ->
                        transactionDao.clearTransactionTags(details.transaction.id)
                        transactionDao.delete(details.transaction)
                        removedInflatedAccountTransactionCount += 1
                    }

                    advanceDao.upsertCase(
                        caseDetails.advanceCase.copy(
                            payerAccountId = null,
                            updatedAt = now
                        )
                    )
                    advanceDao.upsertParticipants(
                        listOf(participant.copy(updatedAt = now))
                    )
                    repairedParticipantCount += 1
                }
            }

            if (repairedParticipantCount > 0) {
                synchronizeBudgetHistory()
            }
            LegacyBorrowedAdvanceRepairResult(
                repairedParticipantCount = repairedParticipantCount,
                removedInflatedAccountTransactionCount = removedInflatedAccountTransactionCount
            )
        }
    }

    suspend fun backfillLinks() {
        database.withTransaction {
            backfillLinksInCurrentTransaction()
        }
    }

    /** The caller must already own the Room database transaction. */
    internal suspend fun backfillLinksInCurrentTransaction() {
        val cases = advanceDao.getAllCases()
        val participants = advanceDao.getAllParticipants()
        val repayments = advanceDao.getAllRepayments()
        val participantsByCase = participants.groupBy { it.advanceCaseId }
        val repaymentsByCase = repayments.groupBy { it.advanceCaseId }

        cases.forEach { advanceCase ->
            val caseParticipants = participantsByCase[advanceCase.id].orEmpty()
            if (advanceCase.direction == null && caseParticipants.isNotEmpty()) {
                val direction = settlementDirection(caseParticipants.first())
                advanceDao.upsertCase(advanceCase.copy(direction = direction.name))
            }

            advanceCase.selfExpenseTransactionId?.let { transactionId ->
                transactionDao.getTransaction(transactionId)?.transaction?.let { transaction ->
                    if (transaction.advanceCaseId == null) {
                        transactionDao.upsert(
                            transaction.copy(
                                advanceCaseId = advanceCase.id,
                                advanceEntryRole = AdvanceEntryRole.SelfExpense.name
                            )
                        )
                    }
                }
            }

            caseParticipants.forEach { participant ->
                participant.initialTransferGroupId?.let { groupId ->
                    transactionDao.getTransferGroup(groupId).forEach { details ->
                        val transaction = details.transaction
                        if (transaction.advanceCaseId == null) {
                            transactionDao.upsert(
                                transaction.copy(
                                    advanceCaseId = advanceCase.id,
                                    advanceParticipantId = participant.id,
                                    advanceEntryRole = if (
                                        transaction.accountId == participant.debtAccountId
                                    ) {
                                        AdvanceEntryRole.InitialDebt.name
                                    } else {
                                        AdvanceEntryRole.InitialAsset.name
                                    }
                                )
                            )
                        }
                    }
                }
            }

            repaymentsByCase[advanceCase.id].orEmpty().forEach { repayment ->
                repayment.linkedTransferGroupId?.let { groupId ->
                    val participant = participants.firstOrNull {
                        it.id == repayment.participantId
                    }
                    transactionDao.getTransferGroup(groupId).forEach { details ->
                        val transaction = details.transaction
                        if (transaction.advanceCaseId == null) {
                            transactionDao.upsert(
                                transaction.copy(
                                    advanceCaseId = advanceCase.id,
                                    advanceParticipantId = participant?.id,
                                    advanceRepaymentId = repayment.id,
                                    advanceEntryRole = if (
                                        transaction.accountId == participant?.debtAccountId
                                    ) {
                                        AdvanceEntryRole.RepaymentDebt.name
                                    } else {
                                        AdvanceEntryRole.RepaymentAsset.name
                                    }
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    private suspend fun settlementDirection(
        participant: AdvanceParticipantEntity
    ): AdvanceSettlementDirection {
        val groupId = participant.initialTransferGroupId
            ?: return AdvanceSettlementDirection.IAdvancedOthers
        val outgoing = transactionDao.getTransferGroup(groupId).firstOrNull { details ->
            effectiveTransferSide(details.transaction) == TransferSide.Outgoing
        }?.transaction ?: return AdvanceSettlementDirection.IAdvancedOthers

        return AdvanceSemantics.settlementDirection(
            debtAccountId = participant.debtAccountId,
            outgoingAccountId = outgoing.accountId,
            outgoingNote = outgoing.note
        )
    }

    private fun effectiveTransferSide(transaction: TransactionEntity): TransferSide {
        return transaction.transferSide
            ?: if (transaction.amount < BigDecimal.ZERO) {
                TransferSide.Outgoing
            } else {
                TransferSide.Incoming
            }
    }
}
