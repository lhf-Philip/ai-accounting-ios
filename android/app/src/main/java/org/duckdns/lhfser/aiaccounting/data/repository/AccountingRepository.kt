package org.duckdns.lhfser.aiaccounting.data.repository

import androidx.room.withTransaction
import kotlinx.coroutines.flow.Flow
import org.duckdns.lhfser.aiaccounting.core.backup.BackupAccountInput
import org.duckdns.lhfser.aiaccounting.core.backup.BackupAdvanceCaseInput
import org.duckdns.lhfser.aiaccounting.core.backup.BackupAdvanceRepaymentInput
import org.duckdns.lhfser.aiaccounting.core.backup.BackupBudgetInput
import org.duckdns.lhfser.aiaccounting.core.backup.BackupCategoryInput
import org.duckdns.lhfser.aiaccounting.core.backup.BackupDefaults
import org.duckdns.lhfser.aiaccounting.core.backup.BackupShortcutInput
import org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService
import org.duckdns.lhfser.aiaccounting.core.health.DataHealthChecker
import org.duckdns.lhfser.aiaccounting.core.health.DataHealthReport
import org.duckdns.lhfser.aiaccounting.core.health.DataHealthSnapshot
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.core.model.TransferSide
import org.duckdns.lhfser.aiaccounting.core.transactions.TransactionSemantics
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseTagCrossRef
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceParticipantEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceRepaymentEntity
import org.duckdns.lhfser.aiaccounting.data.db.AIAccountingDatabase
import org.duckdns.lhfser.aiaccounting.data.db.BudgetDao
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryMonthlyBudgetEntity
import org.duckdns.lhfser.aiaccounting.data.db.BudgetMonthlyHistoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.BudgetSettingsEntity
import org.duckdns.lhfser.aiaccounting.data.db.RecurringOccurrenceEntity
import org.duckdns.lhfser.aiaccounting.data.db.RecurringRuleEntity
import org.duckdns.lhfser.aiaccounting.data.db.RecurringRuleTagCrossRef
import org.duckdns.lhfser.aiaccounting.data.db.ShortcutEntity
import org.duckdns.lhfser.aiaccounting.data.db.ShortcutTagCrossRef
import org.duckdns.lhfser.aiaccounting.data.db.TagEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionTagCrossRef
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.ShortcutWithDetails
import org.duckdns.lhfser.aiaccounting.data.backup.BackupJsonAdapter
import org.duckdns.lhfser.aiaccounting.data.backup.FullBackupData
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.ZoneId
import java.time.Instant
import java.util.UUID

data class AccountDeletionCounts(
    val transactionCount: Int,
    val advanceCaseCount: Int,
    val participantCount: Int,
    val repaymentCount: Int,
    val shortcutDetachCount: Int
) {
    val hasBookkeeping: Boolean
        get() = transactionCount > 0 || advanceCaseCount > 0 || participantCount > 0 || repaymentCount > 0
}

data class AccountDeletionImpact(
    val accountId: UUID,
    val accountName: String,
    val counts: AccountDeletionCounts
) {
    val isEmptyAccount: Boolean
        get() = !counts.hasBookkeeping
}

data class AccountEditDraft(
    val accountId: UUID?,
    val name: String,
    val requestedCurrency: String,
    val type: AccountType,
    val baseBalance: BigDecimal,
    val isArchived: Boolean
)

data class RecurringRuleEditorData(
    val rule: RecurringRuleEntity,
    val account: AccountEntity?,
    val category: CategoryEntity?,
    val tags: List<TagEntity>
)

enum class LedgerDeletionResult {
    Deleted,
    AdvanceInitialRequiresCase
}

enum class TransferGroupSemantic {
    Ordinary,
    Debt,
    AdvanceInitial,
    AdvanceRepayment
}

data class TransferGroupClassification(
    val semantic: TransferGroupSemantic,
    val advanceCaseId: UUID? = null,
    val advanceParticipantId: UUID? = null,
    val advanceRepaymentId: UUID? = null
)

data class TransferReplacementLeg(
    val accountId: UUID,
    val currencyCode: String,
    val amount: BigDecimal,
    val side: TransferSide
)

data class TransferGroupReplacementDraft(
    val groupId: UUID,
    val date: Instant,
    val note: String,
    val legs: List<TransferReplacementLeg>
)

enum class AdvanceSettlementDirection {
    IAdvancedOthers,
    OthersAdvancedMe
}

enum class AdvanceEntryRole {
    SelfExpense,
    InitialAsset,
    InitialDebt,
    RepaymentAsset,
    RepaymentDebt
}

data class AdvanceRepaymentEditDraft(
    val repaymentId: UUID,
    val receiveAccountId: UUID,
    val amount: BigDecimal,
    val currencyCode: String,
    val normalizedAmount: BigDecimal,
    val date: Instant,
    val note: String,
    val categoryId: UUID?,
    val tagIds: List<UUID>
)

data class AdvanceRepaymentCreateDraft(
    val receiveAccountId: UUID,
    val amount: BigDecimal,
    val normalizedAmount: BigDecimal,
    val currencyCode: String,
    val date: Instant,
    val note: String,
    val categoryId: UUID?,
    val tagIds: List<UUID>
)

data class AdvanceSelfExpenseEditDraft(
    val caseId: UUID,
    val accountId: UUID,
    val amount: BigDecimal,
    val currencyCode: String,
    val normalizedAmount: BigDecimal,
    val date: Instant,
    val note: String,
    val categoryId: UUID?,
    val tagIds: List<UUID>
)

data class AdvanceInitialMetadataEditDraft(
    val caseId: UUID,
    val payerAccountId: UUID?,
    val date: Instant,
    val note: String,
    val categoryId: UUID?,
    val tagIds: List<UUID>
)

data class LegacyBorrowedAdvanceRepairResult(
    val repairedParticipantCount: Int,
    val removedInflatedAccountTransactionCount: Int
)

data class MutualDebtOffsetCandidate(
    val debtAccount: AccountEntity,
    val currencyCode: String,
    val amount: BigDecimal,
    val receivableAmount: BigDecimal,
    val payableAmount: BigDecimal,
    val receivableParticipantCount: Int,
    val payableParticipantCount: Int
)

data class MutualDebtOffsetResult(
    val offsetGroupId: UUID,
    val amount: BigDecimal,
    val currencyCode: String,
    val repaymentCount: Int
)

enum class ManualDebtSettlementDirection {
    Receivable,
    Payable
}

data class ManualDebtSettlementResult(
    val settlementId: UUID,
    val amount: BigDecimal,
    val currencyCode: String,
    val repaymentCount: Int
)

private const val RECURRING_STATUS_PENDING = "Pending"
private const val RECURRING_STATUS_CONFIRMED = "Confirmed"
private const val RECURRING_STATUS_SKIPPED = "Skipped"
const val MUTUAL_DEBT_OFFSET_MARKER_PREFIX = "[債務抵銷:"
const val MANUAL_DEBT_SETTLEMENT_MARKER_PREFIX = "[跨幣種平賬:"

class AccountingRepository(
    private val database: AIAccountingDatabase,
    private val currencyService: CurrencyService
) {
    private val accountDao = database.accountDao()
    private val categoryDao = database.categoryDao()
    private val tagDao = database.tagDao()
    private val transactionDao = database.transactionDao()
    private val shortcutDao = database.shortcutDao()
    private val recurringDao = database.recurringDao()
    private val budgetDao: BudgetDao = database.budgetDao()
    private val advanceDao = database.advanceDao()

    val accounts: Flow<List<AccountEntity>> = accountDao.observeAccounts()
    val categories: Flow<List<CategoryEntity>> = categoryDao.observeCategories()
    val tags: Flow<List<TagEntity>> = tagDao.observeTags()
    val transactions: Flow<List<TransactionWithDetails>> = transactionDao.observeTransactions()
    val shortcuts: Flow<List<ShortcutWithDetails>> = shortcutDao.observeShortcuts()
    val recurringRules: Flow<List<RecurringRuleEntity>> = recurringDao.observeRules()
    val recurringOccurrences: Flow<List<RecurringOccurrenceEntity>> = recurringDao.observeOccurrences()
    val budgets: Flow<List<CategoryMonthlyBudgetEntity>> = budgetDao.observeBudgets()
    val budgetHistories: Flow<List<BudgetMonthlyHistoryEntity>> = budgetDao.observeBudgetHistory()
    val budgetSettings: Flow<BudgetSettingsEntity?> = budgetDao.observeBudgetSettings()
    val advanceCases: Flow<List<AdvanceCaseWithDetails>> = advanceDao.observeAdvanceCases()

    private data class AccountDeletionTargets(
        val impact: AccountDeletionImpact,
        val account: AccountEntity,
        val advanceCasesToDelete: List<AdvanceCaseWithDetails>,
        val repaymentsToRollback: List<AdvanceRepaymentEntity>,
        val directTransactionsToDelete: List<TransactionEntity>,
        val shortcutsToDetach: List<ShortcutEntity>
    )

    private data class OffsetParticipantEntry(
        val advanceCase: AdvanceCaseEntity,
        val participant: AdvanceParticipantEntity,
        val remaining: BigDecimal
    )

    private data class ResolvedTransferReplacementLeg(
        val account: AccountEntity,
        val currencyCode: String,
        val amount: BigDecimal,
        val side: TransferSide
    )

    suspend fun getTransaction(transactionId: UUID): TransactionWithDetails? {
        return transactionDao.getTransaction(transactionId)
    }

    suspend fun getTransferGroup(groupId: UUID): List<TransactionWithDetails> {
        return transactionDao.getTransferGroup(groupId)
    }

    suspend fun classifyTransferGroup(groupId: UUID): TransferGroupClassification? {
        return database.withTransaction {
            classifyTransferGroupLocked(groupId)
        }
    }

    suspend fun replaceTransferGroup(draft: TransferGroupReplacementDraft): TransferGroupClassification {
        validateTransferReplacementDraft(draft)

        return database.withTransaction {
            val existing = transactionDao.getTransferGroup(draft.groupId)
            require(existing.isNotEmpty()) { "找不到要編輯的轉帳。" }

            val classification = requireNotNull(classifyTransferGroupLocked(draft.groupId)) {
                "無法判斷轉帳類型。"
            }
            require(
                classification.semantic == TransferGroupSemantic.Ordinary ||
                    classification.semantic == TransferGroupSemantic.Debt
            ) {
                "代墊建立或還款分錄必須從代墊詳情編輯。"
            }

            val accountById = accountDao.getAll().associateBy { it.id }
            val resolvedLegs = draft.legs.map { leg ->
                val account = requireNotNull(accountById[leg.accountId]) { "找不到所選帳戶。" }
                ResolvedTransferReplacementLeg(
                    account = account,
                    currencyCode = leg.currencyCode.trim().uppercase(),
                    amount = leg.amount.abs(),
                    side = leg.side
                )
            }

            validateTransferSemantic(classification.semantic, existing, resolvedLegs)

            val existingBySide = existing.groupBy { effectiveTransferSide(it.transaction) }
            val outgoingCounterpart = counterpartSummary(
                resolvedLegs.filter { it.side == TransferSide.Incoming }.map { it.account }
            )
            val incomingCounterpart = counterpartSummary(
                resolvedLegs.filter { it.side == TransferSide.Outgoing }.map { it.account }
            )
            val memo = draft.note.trim().ifBlank {
                if (classification.semantic == TransferGroupSemantic.Debt) "借貸" else "轉帳"
            }
            val now = Instant.now()
            val prepared = mutableListOf<TransactionEntity>()
            val removed = mutableListOf<TransactionEntity>()

            TransferSide.values().forEach { side ->
                val desiredForSide = resolvedLegs.filter { it.side == side }
                val existingForSide = existingBySide[side]
                    .orEmpty()
                    .sortedWith(compareBy({ it.transaction.createdAt }, { it.transaction.id.toString() }))

                desiredForSide.forEachIndexed { index, leg ->
                    val current = existingForSide.getOrNull(index)?.transaction
                    prepared += TransactionEntity(
                        id = current?.id ?: UUID.randomUUID(),
                        amount = if (side == TransferSide.Outgoing) leg.amount.negate() else leg.amount,
                        currencyCode = leg.currencyCode,
                        date = draft.date,
                        note = transferReplacementNote(
                            semantic = classification.semantic,
                            side = side,
                            legAccount = leg.account,
                            allLegs = resolvedLegs,
                            memo = memo,
                            ordinaryCounterpart = if (side == TransferSide.Outgoing) {
                                outgoingCounterpart
                            } else {
                                incomingCounterpart
                            }
                        ),
                        photoPath = current?.photoPath,
                        type = TransactionType.Transfer,
                        linkedTransactionId = null,
                        transferGroupId = draft.groupId,
                        transferSide = side,
                        createdAt = current?.createdAt ?: now,
                        updatedAt = now,
                        accountId = leg.account.id,
                        categoryId = null
                    )
                }
                removed += existingForSide.drop(desiredForSide.size).map { it.transaction }
            }

            if (prepared.size == 2) {
                val outgoing = prepared.single { it.transferSide == TransferSide.Outgoing }
                val incoming = prepared.single { it.transferSide == TransferSide.Incoming }
                val outgoingIndex = prepared.indexOfFirst { it.id == outgoing.id }
                val incomingIndex = prepared.indexOfFirst { it.id == incoming.id }
                prepared[outgoingIndex] = outgoing.copy(linkedTransactionId = incoming.id)
                prepared[incomingIndex] = incoming.copy(linkedTransactionId = outgoing.id)
            }

            removed.forEach { transaction ->
                transactionDao.clearTransactionTags(transaction.id)
                transactionDao.delete(transaction)
            }
            transactionDao.upsertAll(prepared)
            syncAllBudgetHistory()
            classification
        }
    }

    suspend fun getAccount(accountId: UUID): AccountEntity? {
        return accountDao.getAccount(accountId)
    }

    suspend fun getAdvanceCase(caseId: UUID): AdvanceCaseWithDetails? {
        return advanceDao.getAdvanceCase(caseId)
    }

    suspend fun findAdvanceCaseIdBySelfExpense(transactionId: UUID): UUID? {
        return advanceDao.getAllCases()
            .firstOrNull { it.selfExpenseTransactionId == transactionId }
            ?.id
    }

    suspend fun mutualDebtOffsetCandidate(debtAccountId: UUID, currencyCode: String): MutualDebtOffsetCandidate? {
        val debtAccount = accountDao.getAccount(debtAccountId) ?: return null
        val offsetable = offsetableParticipants(debtAccountId, currencyCode, advanceDao.getAllCasesWithDetails())
        val receivableAmount = offsetable.receivable.fold(BigDecimal.ZERO) { acc, entry -> acc + entry.remaining }
        val payableAmount = offsetable.payable.fold(BigDecimal.ZERO) { acc, entry -> acc + entry.remaining }
        val amount = receivableAmount.min(payableAmount)
        if (amount <= BigDecimal.ZERO) return null
        return MutualDebtOffsetCandidate(
            debtAccount = debtAccount,
            currencyCode = currencyCode,
            amount = amount,
            receivableAmount = receivableAmount,
            payableAmount = payableAmount,
            receivableParticipantCount = offsetable.receivable.size,
            payableParticipantCount = offsetable.payable.size
        )
    }

    suspend fun recordMutualDebtOffset(
        debtAccountId: UUID,
        currencyCode: String,
        date: Instant = Instant.now(),
        note: String = ""
    ): MutualDebtOffsetResult {
        return database.withTransaction {
            val debtAccount = accountDao.getAccount(debtAccountId) ?: error("找不到債務對象")
            val offsetable = offsetableParticipants(debtAccountId, currencyCode, advanceDao.getAllCasesWithDetails())
            val receivableAmount = offsetable.receivable.fold(BigDecimal.ZERO) { acc, entry -> acc + entry.remaining }
            val payableAmount = offsetable.payable.fold(BigDecimal.ZERO) { acc, entry -> acc + entry.remaining }
            val offsetAmount = receivableAmount.min(payableAmount)
            require(offsetAmount > BigDecimal.ZERO) { "沒有可抵銷的同幣種互相代墊" }

            val now = Instant.now()
            val offsetGroupId = UUID.randomUUID()
            val trimmedNote = note.trim()
            val marker = "$MUTUAL_DEBT_OFFSET_MARKER_PREFIX$offsetGroupId]"
            val finalNote = if (trimmedNote.isBlank()) {
                "$marker 與 ${debtAccount.name} 互相代墊抵銷"
            } else {
                "$marker $trimmedNote"
            }

            val receivableCount = applyMutualDebtOffset(offsetAmount, offsetable.receivable, date, finalNote, now)
            val payableCount = applyMutualDebtOffset(offsetAmount, offsetable.payable, date, finalNote, now)

            MutualDebtOffsetResult(
                offsetGroupId = offsetGroupId,
                amount = offsetAmount,
                currencyCode = currencyCode,
                repaymentCount = receivableCount + payableCount
            )
        }
    }

    suspend fun rollbackMutualDebtOffset(offsetGroupId: UUID): Int {
        return database.withTransaction {
            val repayments = advanceDao.getAllRepayments()
                .filter { mutualDebtOffsetId(it.note) == offsetGroupId }
            rollbackRepayments(repayments)
            repayments.size
        }
    }

    suspend fun recordManualDebtSettlement(
        debtAccountId: UUID,
        currencyCode: String,
        direction: ManualDebtSettlementDirection,
        amount: BigDecimal,
        date: Instant = Instant.now(),
        note: String = ""
    ): ManualDebtSettlementResult {
        return database.withTransaction {
            val debtAccount = accountDao.getAccount(debtAccountId) ?: error("找不到債務對象")
            val normalizedAmount = amount.abs()
            require(normalizedAmount > BigDecimal.ZERO) { "請輸入有效平賬金額" }

            val offsetable = offsetableParticipants(debtAccountId, currencyCode, advanceDao.getAllCasesWithDetails())
            val entries = when (direction) {
                ManualDebtSettlementDirection.Receivable -> offsetable.receivable
                ManualDebtSettlementDirection.Payable -> offsetable.payable
            }
            val availableAmount = entries.fold(BigDecimal.ZERO) { acc, entry -> acc + entry.remaining }
            require(normalizedAmount <= availableAmount) { "平賬金額不能超過可結清金額" }

            val now = Instant.now()
            val settlementId = UUID.randomUUID()
            val trimmedNote = note.trim()
            val marker = "$MANUAL_DEBT_SETTLEMENT_MARKER_PREFIX$settlementId]"
            val defaultNote = when (direction) {
                ManualDebtSettlementDirection.Receivable -> "手動結清 ${debtAccount.name} 欠你的 $currencyCode 代墊餘額"
                ManualDebtSettlementDirection.Payable -> "手動結清你欠 ${debtAccount.name} 的 $currencyCode 代墊餘額"
            }
            val finalNote = if (trimmedNote.isBlank()) "$marker $defaultNote" else "$marker $trimmedNote"
            val repaymentCount = applyMutualDebtOffset(normalizedAmount, entries, date, finalNote, now)

            ManualDebtSettlementResult(
                settlementId = settlementId,
                amount = normalizedAmount,
                currencyCode = currencyCode,
                repaymentCount = repaymentCount
            )
        }
    }

    suspend fun rollbackManualDebtSettlement(settlementId: UUID): Int {
        return database.withTransaction {
            val repayments = advanceDao.getAllRepayments()
                .filter { manualDebtSettlementId(it.note) == settlementId }
            rollbackRepayments(repayments)
            repayments.size
        }
    }

    suspend fun buildDataHealthReport(): DataHealthReport {
        return DataHealthChecker.run(
            DataHealthSnapshot(
                transactions = transactionDao.getAllWithDetails(),
                categories = categoryDao.getAll(),
                budgets = budgetDao.getAll(),
                advanceCases = advanceDao.getAllCasesWithDetails(),
                advanceParticipants = advanceDao.getAllParticipants(),
                advanceRepayments = advanceDao.getAllRepayments(),
                shortcuts = shortcutDao.getAllWithDetails()
            )
        )
    }

    private fun offsetableParticipants(
        debtAccountId: UUID,
        currencyCode: String,
        advanceCases: List<AdvanceCaseWithDetails>
    ): OffsetableParticipants {
        val receivable = mutableListOf<OffsetParticipantEntry>()
        val payable = mutableListOf<OffsetParticipantEntry>()
        advanceCases
            .filter { it.advanceCase.currencyCode == currencyCode }
            .sortedBy { it.advanceCase.date }
            .forEach { caseDetails ->
                caseDetails.participants
                    .filter { it.debtAccountId == debtAccountId }
                    .forEach { participant ->
                        val remaining = (participant.owedAmount - participant.repaidAmount).max(BigDecimal.ZERO)
                        if (remaining > BigDecimal.ZERO) {
                            val entry = OffsetParticipantEntry(caseDetails.advanceCase, participant, remaining)
                            if (caseDetails.advanceCase.payerAccountId == null) {
                                payable += entry
                            } else {
                                receivable += entry
                            }
                        }
                    }
            }
        return OffsetableParticipants(receivable, payable)
    }

    private data class OffsetableParticipants(
        val receivable: List<OffsetParticipantEntry>,
        val payable: List<OffsetParticipantEntry>
    )

    private suspend fun applyMutualDebtOffset(
        amount: BigDecimal,
        entries: List<OffsetParticipantEntry>,
        date: Instant,
        note: String,
        now: Instant
    ): Int {
        var remaining = amount
        var count = 0
        entries.forEach { entry ->
            if (remaining <= BigDecimal.ZERO) return@forEach
            val allocation = entry.remaining.min(remaining)
            if (allocation <= BigDecimal.ZERO) return@forEach
            advanceDao.upsertRepayment(
                AdvanceRepaymentEntity(
                    id = UUID.randomUUID(),
                    amount = allocation,
                    currencyCode = entry.advanceCase.currencyCode,
                    normalizedAmount = allocation,
                    date = date,
                    note = note,
                    linkedTransferGroupId = null,
                    createdAt = now,
                    advanceCaseId = entry.advanceCase.id,
                    participantId = entry.participant.id,
                    receivedAccountId = null
                )
            )
            val updatedRepaid = (entry.participant.repaidAmount + allocation)
                .min(entry.participant.owedAmount)
            advanceDao.upsertParticipants(listOf(entry.participant.copy(repaidAmount = updatedRepaid, updatedAt = now)))
            advanceDao.upsertCase(entry.advanceCase.copy(updatedAt = now))
            remaining -= allocation
            count += 1
        }
        return count
    }

    companion object {
        fun isMutualDebtOffset(note: String): Boolean {
            return note.trim().startsWith(MUTUAL_DEBT_OFFSET_MARKER_PREFIX)
        }

        fun mutualDebtOffsetId(note: String): UUID? {
            val trimmed = note.trim()
            if (!trimmed.startsWith(MUTUAL_DEBT_OFFSET_MARKER_PREFIX)) return null
            val end = trimmed.indexOf(']')
            if (end <= MUTUAL_DEBT_OFFSET_MARKER_PREFIX.length) return null
            return runCatching {
                UUID.fromString(trimmed.substring(MUTUAL_DEBT_OFFSET_MARKER_PREFIX.length, end))
            }.getOrNull()
        }

        fun isManualDebtSettlement(note: String): Boolean {
            return note.trim().startsWith(MANUAL_DEBT_SETTLEMENT_MARKER_PREFIX)
        }

        fun manualDebtSettlementId(note: String): UUID? {
            val trimmed = note.trim()
            if (!trimmed.startsWith(MANUAL_DEBT_SETTLEMENT_MARKER_PREFIX)) return null
            val end = trimmed.indexOf(']')
            if (end <= MANUAL_DEBT_SETTLEMENT_MARKER_PREFIX.length) return null
            return runCatching {
                UUID.fromString(trimmed.substring(MANUAL_DEBT_SETTLEMENT_MARKER_PREFIX.length, end))
            }.getOrNull()
        }
    }

    suspend fun legacyDebtIncomeTransactions(): List<TransactionWithDetails> {
        return transactionDao.getAllWithDetails().filter(TransactionSemantics::isLegacyDebtIncome)
    }

    suspend fun legacyDebtIncomeShortcuts(): List<ShortcutWithDetails> {
        return shortcutDao.getAllWithDetails().filter(TransactionSemantics::isLegacyDebtIncome)
    }

    suspend fun convertLegacyDebtIncomeTransaction(transactionId: UUID): Boolean {
        return database.withTransaction {
            val existing = transactionDao.getTransaction(transactionId) ?: return@withTransaction false
            val account = existing.account ?: return@withTransaction false
            if (!TransactionSemantics.isLegacyDebtIncome(existing)) {
                return@withTransaction false
            }

            val direction = if (existing.transaction.amount >= BigDecimal.ZERO) {
                org.duckdns.lhfser.aiaccounting.core.transactions.DebtForgivenessDirection.ForgivenByOthers
            } else {
                org.duckdns.lhfser.aiaccounting.core.transactions.DebtForgivenessDirection.ForgiveOthers
            }

            val updated = existing.transaction.copy(
                amount = existing.transaction.amount.abs().multiply(direction.amountSign),
                note = TransactionSemantics.debtForgivenessNote(
                    baseNote = TransactionSemantics.debtForgivenessDisplayTitle(existing.transaction.note),
                    debtAccountName = account.name,
                    direction = direction
                ),
                type = TransactionType.Transfer,
                linkedTransactionId = null,
                transferGroupId = null,
                transferSide = null,
                updatedAt = Instant.now(),
                accountId = account.id,
                categoryId = null
            )
            transactionDao.upsert(updated)
            transactionDao.clearTransactionTags(updated.id)
            syncAllBudgetHistory()
            true
        }
    }

    suspend fun convertAllLegacyDebtIncomeTransactions(): Int {
        var converted = 0
        for (transaction in legacyDebtIncomeTransactions()) {
            if (convertLegacyDebtIncomeTransaction(transaction.transaction.id)) {
                converted += 1
            }
        }
        return converted
    }

    suspend fun detachLegacyDebtIncomeShortcut(shortcutId: UUID): Boolean {
        return database.withTransaction {
            val shortcut = shortcutDao.getAllWithDetails().firstOrNull { it.shortcut.id == shortcutId } ?: return@withTransaction false
            if (!TransactionSemantics.isLegacyDebtIncome(shortcut)) {
                return@withTransaction false
            }
            shortcutDao.upsert(shortcut.shortcut.copy(accountId = null))
            true
        }
    }

    suspend fun detachAllLegacyDebtIncomeShortcuts(): Int {
        val shortcuts = legacyDebtIncomeShortcuts()
        if (shortcuts.isEmpty()) return 0
        database.withTransaction {
            shortcutDao.upsertAll(shortcuts.map { it.shortcut.copy(accountId = null) })
        }
        return shortcuts.size
    }

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
                    val outgoing = group.firstOrNull { tx ->
                        tx.transaction.accountId == debtAccountId &&
                            (tx.transaction.transferSide == TransferSide.Outgoing || tx.transaction.amount < BigDecimal.ZERO)
                    } ?: continue
                    val inflatedIncoming = group.filter { tx ->
                        tx.transaction.id != outgoing.transaction.id &&
                            tx.transaction.amount > BigDecimal.ZERO &&
                            tx.account?.type != org.duckdns.lhfser.aiaccounting.core.model.AccountType.Debt
                    }
                    if (inflatedIncoming.isEmpty()) continue

                    val baseNote = caseDetails.advanceCase.note.ifBlank { caseDetails.advanceCase.title }
                    transactionDao.upsert(
                        outgoing.transaction.copy(
                            amount = outgoing.transaction.amount.abs().negate(),
                            note = "$baseNote (他人代墊我：${participant.name})",
                            type = TransactionType.Expense,
                            linkedTransactionId = null,
                            transferSide = TransferSide.Outgoing,
                            categoryId = caseDetails.advanceCase.expenseCategoryId,
                            updatedAt = Instant.now()
                        )
                    )

                    inflatedIncoming.forEach { tx ->
                        transactionDao.clearTransactionTags(tx.transaction.id)
                        transactionDao.delete(tx.transaction)
                        removedInflatedAccountTransactionCount += 1
                    }

                    advanceDao.upsertCase(
                        caseDetails.advanceCase.copy(
                            payerAccountId = null,
                            updatedAt = Instant.now()
                        )
                    )
                    advanceDao.upsertParticipants(
                        listOf(participant.copy(updatedAt = Instant.now()))
                    )
                    repairedParticipantCount += 1
                }
            }

            if (repairedParticipantCount > 0) {
                syncAllBudgetHistory()
            }
            LegacyBorrowedAdvanceRepairResult(
                repairedParticipantCount = repairedParticipantCount,
                removedInflatedAccountTransactionCount = removedInflatedAccountTransactionCount
            )
        }
    }

    suspend fun upsertAccount(account: AccountEntity) {
        accountDao.upsert(account)
    }

    suspend fun saveAccountEdit(draft: AccountEditDraft): UUID {
        require(draft.name.isNotBlank()) { "請輸入帳戶名稱。" }

        return database.withTransaction {
            val existing = draft.accountId?.let { accountId ->
                requireNotNull(accountDao.getAccount(accountId)) {
                    "找不到要編輯的帳戶。"
                }
            }
            if (existing == null) {
                require(draft.requestedCurrency.isNotBlank()) { "請選擇主幣種。" }
            }
            val accountId = existing?.id ?: draft.accountId ?: UUID.randomUUID()
            val account = AccountEntity(
                id = accountId,
                name = draft.name.trim(),
                currency = existing?.currency ?: draft.requestedCurrency.trim().uppercase(),
                type = draft.type,
                baseBalance = draft.baseBalance,
                sortOrder = existing?.sortOrder
                    ?: ((accountDao.getAll().maxOfOrNull { it.sortOrder } ?: -1) + 1),
                isArchived = draft.isArchived
            )
            accountDao.upsert(account)
            accountId
        }
    }

    suspend fun previewAccountDeletion(accountId: UUID): AccountDeletionImpact? {
        return buildAccountDeletionTargets(accountId)?.impact
    }

    suspend fun archiveAccount(accountId: UUID) {
        val account = accountDao.getAccount(accountId) ?: return
        accountDao.upsert(account.copy(isArchived = true))
    }

    suspend fun deleteAccount(accountId: UUID, deleteRelatedBookkeeping: Boolean = true) {
        database.withTransaction {
            val targets = buildAccountDeletionTargets(accountId) ?: return@withTransaction
            if (!deleteRelatedBookkeeping && targets.impact.counts.hasBookkeeping) {
                return@withTransaction
            }

            if (targets.shortcutsToDetach.isNotEmpty()) {
                shortcutDao.upsertAll(targets.shortcutsToDetach.map { it.copy(accountId = null) })
            }

            if (targets.repaymentsToRollback.isNotEmpty()) {
                rollbackRepayments(targets.repaymentsToRollback)
            }

            if (targets.advanceCasesToDelete.isNotEmpty()) {
                deleteAdvanceCases(targets.advanceCasesToDelete)
            }

            deleteTransactions(targets.directTransactionsToDelete)
            accountDao.delete(targets.account)
            syncAllBudgetHistory()
        }
    }

    suspend fun deleteAccount(account: AccountEntity) {
        deleteAccount(account.id)
    }

    suspend fun upsertCategory(category: CategoryEntity) {
        database.withTransaction {
            categoryDao.upsert(category)
            syncAllBudgetHistory()
        }
    }

    suspend fun deleteCategory(category: CategoryEntity) {
        database.withTransaction {
            categoryDao.delete(category)
            syncAllBudgetHistory()
        }
    }

    suspend fun upsertTag(tag: TagEntity) {
        tagDao.upsert(tag)
    }

    suspend fun deleteTag(tag: TagEntity) {
        tagDao.delete(tag)
    }

    suspend fun upsertTransaction(transaction: TransactionEntity, tagIds: List<UUID>) {
        database.withTransaction {
            transactionDao.upsert(transaction)
            transactionDao.clearTransactionTags(transaction.id)
            if (tagIds.isNotEmpty()) {
                val refs = tagIds.map { tagId ->
                    TransactionTagCrossRef(transactionId = transaction.id, tagId = tagId)
                }
                transactionDao.insertTransactionTags(refs)
            }
            syncAllBudgetHistory()
        }
    }

    suspend fun upsertTransactions(transactions: List<TransactionEntity>, tagIds: List<UUID> = emptyList()) {
        database.withTransaction {
            transactionDao.upsertAll(transactions)
            transactions.forEach { transaction ->
                transactionDao.clearTransactionTags(transaction.id)
            }
            if (tagIds.isNotEmpty()) {
                transactionDao.insertTransactionTags(
                    transactions.flatMap { transaction ->
                        tagIds.map { tagId -> TransactionTagCrossRef(transaction.id, tagId) }
                    }
                )
            }
            syncAllBudgetHistory()
        }
    }

    suspend fun replaceOrdinaryTransactions(
        originalTransactionId: UUID?,
        replacements: List<TransactionEntity>,
        tagIds: List<UUID> = emptyList()
    ): List<UUID> {
        require(replacements.isNotEmpty()) { "至少需要一筆交易。" }
        replacements.forEach(::validateOrdinaryReplacement)

        return database.withTransaction {
            val original = originalTransactionId?.let { transactionId ->
                requireNotNull(transactionDao.getTransaction(transactionId)?.transaction) {
                    "找不到要編輯的交易。"
                }
            }
            if (original != null) {
                validateOrdinaryReplacement(original)
            }

            val now = Instant.now()
            val prepared = replacements.mapIndexed { index, replacement ->
                when {
                    original == null -> replacement
                    replacements.size == 1 -> replacement.copy(
                        id = original.id,
                        photoPath = replacement.photoPath ?: original.photoPath,
                        createdAt = original.createdAt,
                        updatedAt = now
                    )
                    index == 0 -> replacement.copy(
                        photoPath = replacement.photoPath ?: original.photoPath,
                        createdAt = original.createdAt,
                        updatedAt = now
                    )
                    else -> replacement.copy(updatedAt = now)
                }
            }

            original?.let {
                transactionDao.clearTransactionTags(it.id)
                if (prepared.none { replacement -> replacement.id == it.id }) {
                    transactionDao.delete(it)
                }
            }

            prepared.forEach { transactionDao.clearTransactionTags(it.id) }
            transactionDao.upsertAll(prepared)
            if (tagIds.isNotEmpty()) {
                transactionDao.insertTransactionTags(
                    prepared.flatMap { transaction ->
                        tagIds.map { tagId -> TransactionTagCrossRef(transaction.id, tagId) }
                    }
                )
            }
            syncAllBudgetHistory()
            prepared.map { it.id }
        }
    }

    suspend fun deleteTransaction(transaction: TransactionEntity) {
        database.withTransaction {
            transactionDao.delete(transaction)
            transactionDao.clearTransactionTags(transaction.id)
            syncAllBudgetHistory()
        }
    }

    suspend fun deleteTransactionById(transactionId: UUID) {
        database.withTransaction {
            val existing = transactionDao.getTransaction(transactionId)
            if (existing != null) {
                transactionDao.delete(existing.transaction)
                transactionDao.clearTransactionTags(transactionId)
                syncAllBudgetHistory()
            }
        }
    }

    suspend fun deleteLedgerTransactionById(transactionId: UUID): LedgerDeletionResult {
        return database.withTransaction {
            val existing = transactionDao.getTransaction(transactionId)?.transaction
                ?: return@withTransaction LedgerDeletionResult.Deleted

            existing.transferGroupId?.let { groupId ->
                return@withTransaction deleteLedgerTransferGroupLocked(groupId)
            }

            val linkedId = existing.linkedTransactionId
            if (existing.type == TransactionType.Transfer && linkedId != null) {
                transactionDao.getTransaction(linkedId)?.transaction?.let { linked ->
                    transactionDao.delete(linked)
                    transactionDao.clearTransactionTags(linked.id)
                }
            }

            val isAdvanceSelfExpense = advanceDao.getAllCases()
                .any { it.selfExpenseTransactionId == existing.id }
            if (isAdvanceSelfExpense) {
                return@withTransaction LedgerDeletionResult.AdvanceInitialRequiresCase
            }

            transactionDao.delete(existing)
            transactionDao.clearTransactionTags(existing.id)
            syncAllBudgetHistory()
            LedgerDeletionResult.Deleted
        }
    }

    suspend fun deleteTransferGroup(groupId: UUID) {
        database.withTransaction {
            val existing = transactionDao.getTransferGroup(groupId)
            existing.forEach { tx ->
                transactionDao.delete(tx.transaction)
                transactionDao.clearTransactionTags(tx.transaction.id)
            }
            syncAllBudgetHistory()
        }
    }

    suspend fun deleteLedgerTransferGroup(groupId: UUID): LedgerDeletionResult {
        return database.withTransaction {
            deleteLedgerTransferGroupLocked(groupId)
        }
    }

    suspend fun upsertShortcut(shortcut: ShortcutEntity, tagIds: List<UUID>) {
        shortcutDao.upsert(shortcut)
        shortcutDao.clearShortcutTags(shortcut.id)
        if (tagIds.isNotEmpty()) {
            val refs = tagIds.map { tagId ->
                ShortcutTagCrossRef(shortcutId = shortcut.id, tagId = tagId)
            }
            shortcutDao.insertShortcutTags(refs)
        }
    }

    suspend fun deleteShortcut(shortcut: ShortcutEntity) {
        shortcutDao.delete(shortcut)
        shortcutDao.clearShortcutTags(shortcut.id)
    }

    suspend fun getRecurringRule(ruleId: UUID): RecurringRuleEntity? {
        return recurringDao.getRule(ruleId)
    }

    suspend fun getRecurringRuleTagIds(ruleId: UUID): List<UUID> {
        return recurringDao.getRuleTags(ruleId).map { it.tagId }
    }

    suspend fun getRecurringRuleEditorData(ruleId: UUID): RecurringRuleEditorData? {
        return database.withTransaction {
            val rule = recurringDao.getRule(ruleId) ?: return@withTransaction null
            val tagIds = recurringDao.getRuleTags(ruleId).mapTo(mutableSetOf()) { it.tagId }
            RecurringRuleEditorData(
                rule = rule,
                account = rule.accountId?.let { accountDao.getAccount(it) },
                category = rule.categoryId?.let { categoryDao.getCategory(it) },
                tags = tagDao.getAll().filter { it.id in tagIds }
            )
        }
    }

    suspend fun upsertRecurringRule(rule: RecurringRuleEntity, tagIds: List<UUID> = emptyList()) {
        database.withTransaction {
            recurringDao.upsertRule(rule)
            recurringDao.clearRuleTags(rule.id)
            if (tagIds.isNotEmpty()) {
                recurringDao.insertRuleTags(tagIds.map { RecurringRuleTagCrossRef(rule.id, it) })
            }
        }
    }

    suspend fun deleteRecurringRule(rule: RecurringRuleEntity) {
        database.withTransaction {
            recurringDao.deleteOccurrencesForRule(rule.id)
            recurringDao.clearRuleTags(rule.id)
            recurringDao.deleteRule(rule)
        }
    }

    suspend fun syncDueRecurringOccurrences(now: Instant = Instant.now()) {
        database.withTransaction {
            val existingKeys = recurringDao.getAllOccurrences()
                .mapNotNull { occurrence ->
                    val ruleId = occurrence.ruleId ?: return@mapNotNull null
                    "$ruleId|${occurrence.dueDate}"
                }
                .toMutableSet()
            val activeRules = recurringDao.getAllRules().filter { rule ->
                !rule.isPaused && (rule.type == TransactionType.Income || rule.type == TransactionType.Expense)
            }
            activeRules.forEach { rule ->
                var cursor = rule.nextDueDate
                var generated = 0
                val occurrences = mutableListOf<RecurringOccurrenceEntity>()
                while (!cursor.isAfter(now) && generated < 24) {
                    val key = "${rule.id}|$cursor"
                    if (key !in existingKeys) {
                        occurrences.add(
                            RecurringOccurrenceEntity(
                                id = UUID.randomUUID(),
                                dueDate = cursor,
                                status = RECURRING_STATUS_PENDING,
                                createdTransactionId = null,
                                createdAt = now,
                                updatedAt = now,
                                ruleId = rule.id
                            )
                        )
                        existingKeys.add(key)
                    }
                    cursor = nextRecurringDate(cursor, rule.frequency, rule.intervalCount)
                    generated += 1
                }
                if (cursor != rule.nextDueDate || occurrences.isNotEmpty()) {
                    if (occurrences.isNotEmpty()) {
                        recurringDao.upsertOccurrences(occurrences)
                    }
                    recurringDao.upsertRule(rule.copy(nextDueDate = cursor, updatedAt = now))
                }
            }
        }
    }

    suspend fun confirmRecurringOccurrence(occurrenceId: UUID): UUID? {
        return database.withTransaction {
            val occurrence = recurringDao.getOccurrence(occurrenceId) ?: return@withTransaction null
            val rule = occurrence.ruleId?.let { recurringDao.getRule(it) } ?: return@withTransaction null
            if (occurrence.status == RECURRING_STATUS_CONFIRMED) {
                return@withTransaction occurrence.createdTransactionId
            }
            if (rule.type != TransactionType.Income && rule.type != TransactionType.Expense) {
                return@withTransaction null
            }
            val accountId = rule.accountId ?: return@withTransaction null
            val now = Instant.now()
            val transactionId = occurrence.createdTransactionId ?: UUID.randomUUID()
            val signedAmount = if (rule.type == TransactionType.Expense) {
                rule.amount.abs().negate()
            } else {
                rule.amount.abs()
            }
            val transaction = TransactionEntity(
                id = transactionId,
                amount = signedAmount,
                currencyCode = rule.currencyCode,
                date = occurrence.dueDate,
                note = rule.note.ifBlank { rule.title },
                photoPath = null,
                type = rule.type,
                linkedTransactionId = null,
                transferGroupId = null,
                transferSide = null,
                createdAt = now,
                updatedAt = now,
                accountId = accountId,
                categoryId = rule.categoryId
            )
            transactionDao.upsert(transaction)
            val ruleTags = recurringDao.getRuleTags(rule.id)
            if (ruleTags.isNotEmpty()) {
                transactionDao.clearTransactionTags(transactionId)
                transactionDao.insertTransactionTags(
                    ruleTags.map { TransactionTagCrossRef(transactionId, it.tagId) }
                )
            }
            recurringDao.upsertOccurrence(
                occurrence.copy(
                    status = RECURRING_STATUS_CONFIRMED,
                    createdTransactionId = transactionId,
                    updatedAt = now
                )
            )
            syncAllBudgetHistory()
            transactionId
        }
    }

    suspend fun skipRecurringOccurrence(occurrenceId: UUID) {
        database.withTransaction {
            val occurrence = recurringDao.getOccurrence(occurrenceId) ?: return@withTransaction
            recurringDao.upsertOccurrence(
                occurrence.copy(
                    status = RECURRING_STATUS_SKIPPED,
                    updatedAt = Instant.now()
                )
            )
        }
    }

    suspend fun upsertBudget(budget: CategoryMonthlyBudgetEntity) {
        database.withTransaction {
            budgetDao.upsert(budget)
            syncAllBudgetHistory()
        }
    }

    suspend fun deleteBudget(budget: CategoryMonthlyBudgetEntity) {
        database.withTransaction {
            budgetDao.delete(budget)
            syncAllBudgetHistory()
        }
    }

    suspend fun upsertBudgetSettings(settings: BudgetSettingsEntity) {
        budgetDao.upsertSettings(settings)
    }

    suspend fun createTransferOneToOne(
        from: AccountEntity,
        to: AccountEntity,
        amountOut: BigDecimal,
        currencyOut: String,
        amountIn: BigDecimal,
        currencyIn: String,
        date: Instant,
        note: String
    ) {
        val transferGroupId = UUID.randomUUID()
        val outId = UUID.randomUUID()
        val inId = UUID.randomUUID()
        val memo = if (note.isBlank()) "轉帳" else note.trim()

        val outTx = TransactionEntity(
            id = outId,
            amount = amountOut.abs().negate(),
            currencyCode = currencyOut,
            date = date,
            note = "$memo (轉至 ${to.name})",
            photoPath = null,
            type = TransactionType.Transfer,
            linkedTransactionId = inId,
            transferGroupId = transferGroupId,
            transferSide = TransferSide.Outgoing,
            createdAt = Instant.now(),
            updatedAt = Instant.now(),
            accountId = from.id,
            categoryId = null
        )

        val inTx = TransactionEntity(
            id = inId,
            amount = amountIn.abs(),
            currencyCode = currencyIn,
            date = date,
            note = "$memo (來自 ${from.name})",
            photoPath = null,
            type = TransactionType.Transfer,
            linkedTransactionId = outId,
            transferGroupId = transferGroupId,
            transferSide = TransferSide.Incoming,
            createdAt = Instant.now(),
            updatedAt = Instant.now(),
            accountId = to.id,
            categoryId = null
        )

        transactionDao.upsertAll(listOf(outTx, inTx))
    }

    suspend fun createTransferOneToMany(
        source: AccountEntity,
        sourceAmount: BigDecimal,
        sourceCurrency: String,
        destinations: List<TransferLeg>,
        date: Instant,
        note: String
    ) {
        val transferGroupId = UUID.randomUUID()
        val memo = if (note.isBlank()) "轉帳" else note.trim()

        val outTx = TransactionEntity(
            id = UUID.randomUUID(),
            amount = sourceAmount.abs().negate(),
            currencyCode = sourceCurrency,
            date = date,
            note = "$memo (分拆轉至 ${destinations.size} 個帳戶)",
            photoPath = null,
            type = TransactionType.Transfer,
            linkedTransactionId = null,
            transferGroupId = transferGroupId,
            transferSide = TransferSide.Outgoing,
            createdAt = Instant.now(),
            updatedAt = Instant.now(),
            accountId = source.id,
            categoryId = null
        )

        val inTxs = destinations.map { leg ->
            TransactionEntity(
                id = UUID.randomUUID(),
                amount = leg.amount.abs(),
                currencyCode = leg.currency,
                date = date,
                note = "$memo (來自 ${source.name})",
                photoPath = null,
                type = TransactionType.Transfer,
                linkedTransactionId = null,
                transferGroupId = transferGroupId,
                transferSide = TransferSide.Incoming,
                createdAt = Instant.now(),
                updatedAt = Instant.now(),
                accountId = leg.account.id,
                categoryId = null
            )
        }

        transactionDao.upsertAll(listOf(outTx) + inTxs)
    }

    suspend fun createTransferManyToOne(
        destination: AccountEntity,
        destinationAmount: BigDecimal,
        destinationCurrency: String,
        sources: List<TransferLeg>,
        date: Instant,
        note: String
    ) {
        val transferGroupId = UUID.randomUUID()
        val memo = if (note.isBlank()) "轉帳" else note.trim()

        val outTxs = sources.map { leg ->
            TransactionEntity(
                id = UUID.randomUUID(),
                amount = leg.amount.abs().negate(),
                currencyCode = leg.currency,
                date = date,
                note = "$memo (轉至 ${destination.name})",
                photoPath = null,
                type = TransactionType.Transfer,
                linkedTransactionId = null,
                transferGroupId = transferGroupId,
                transferSide = TransferSide.Outgoing,
                createdAt = Instant.now(),
                updatedAt = Instant.now(),
                accountId = leg.account.id,
                categoryId = null
            )
        }

        val inTx = TransactionEntity(
            id = UUID.randomUUID(),
            amount = destinationAmount.abs(),
            currencyCode = destinationCurrency,
            date = date,
            note = "$memo (來自 ${sources.size} 個帳戶)",
            photoPath = null,
            type = TransactionType.Transfer,
            linkedTransactionId = null,
            transferGroupId = transferGroupId,
            transferSide = TransferSide.Incoming,
            createdAt = Instant.now(),
            updatedAt = Instant.now(),
            accountId = destination.id,
            categoryId = null
        )

        transactionDao.upsertAll(outTxs + inTx)
    }

    suspend fun createAdvanceCase(
        title: String,
        date: Instant,
        currencyCode: String,
        myShareAmount: BigDecimal,
        note: String,
        payerAccount: AccountEntity?,
        expenseCategory: CategoryEntity?,
        tagIds: List<UUID>,
        participants: List<AdvanceParticipantInput>,
        isBorrowedByMe: Boolean = false
    ): UUID {
        return database.withTransaction {
            val now = Instant.now()
            val caseId = UUID.randomUUID()
            val finalTitle = title.trim().ifBlank { "代墊" }
            val finalNote = note.trim()

            var selfExpenseTransactionId: UUID? = null
            if (!isBorrowedByMe && myShareAmount > BigDecimal.ZERO && payerAccount != null) {
                val expenseNote = if (finalNote.isBlank()) {
                    "$finalTitle (自己份額)"
                } else {
                    "$finalNote (自己份額)"
                }
                val txId = UUID.randomUUID()
                val expenseTx = TransactionEntity(
                    id = txId,
                    amount = myShareAmount.abs().negate(),
                    currencyCode = currencyCode,
                    date = date,
                    note = expenseNote,
                    photoPath = null,
                    type = TransactionType.Expense,
                    linkedTransactionId = null,
                    transferGroupId = null,
                    transferSide = null,
                    createdAt = now,
                    updatedAt = now,
                    accountId = payerAccount.id,
                    categoryId = expenseCategory?.id,
                    advanceCaseId = caseId,
                    advanceEntryRole = AdvanceEntryRole.SelfExpense.name
                )
                transactionDao.upsert(expenseTx)
                if (tagIds.isNotEmpty()) {
                    transactionDao.insertTransactionTags(
                        tagIds.map { tagId -> TransactionTagCrossRef(txId, tagId) }
                    )
                }
                selfExpenseTransactionId = txId
            }

            val advanceCase = AdvanceCaseEntity(
                id = caseId,
                title = finalTitle,
                date = date,
                currencyCode = currencyCode,
                myShareAmount = myShareAmount,
                note = finalNote,
                selfExpenseTransactionId = selfExpenseTransactionId,
                createdAt = now,
                updatedAt = now,
                payerAccountId = payerAccount?.id,
                expenseCategoryId = expenseCategory?.id,
                direction = if (isBorrowedByMe) {
                    AdvanceSettlementDirection.OthersAdvancedMe.name
                } else {
                    AdvanceSettlementDirection.IAdvancedOthers.name
                }
            )
            advanceDao.upsertCase(advanceCase)
            if (tagIds.isNotEmpty()) {
                advanceDao.insertCaseTags(
                    tagIds.distinct().map { tagId -> AdvanceCaseTagCrossRef(caseId, tagId) }
                )
            }

            val transferMemo = if (finalNote.isBlank()) finalTitle else finalNote
            val participantEntities = mutableListOf<AdvanceParticipantEntity>()
            val transferEntities = mutableListOf<TransactionEntity>()
            val deferredTagRefs = mutableListOf<TransactionTagCrossRef>()

            participants.forEach { input ->
                val transferGroupId = UUID.randomUUID()
                val outId = UUID.randomUUID()
                val inId = UUID.randomUUID()
                val participantId = UUID.randomUUID()

                participantEntities.add(
                    AdvanceParticipantEntity(
                        id = participantId,
                        name = input.debtAccount.name,
                        owedAmount = input.owedAmount.abs(),
                        repaidAmount = BigDecimal.ZERO,
                        initialTransferGroupId = transferGroupId,
                        createdAt = now,
                        updatedAt = now,
                        advanceCaseId = caseId,
                        debtAccountId = input.debtAccount.id
                    )
                )

                if (isBorrowedByMe) {
                    val expenseTx = TransactionEntity(
                        id = outId,
                        amount = input.owedAmount.abs().negate(),
                        currencyCode = currencyCode,
                        date = date,
                        note = "$transferMemo (他人代墊我：${input.debtAccount.name})",
                        photoPath = null,
                        type = TransactionType.Expense,
                        linkedTransactionId = null,
                        transferGroupId = transferGroupId,
                        transferSide = TransferSide.Outgoing,
                        createdAt = now,
                        updatedAt = now,
                        accountId = input.debtAccount.id,
                        categoryId = expenseCategory?.id,
                        advanceCaseId = caseId,
                        advanceParticipantId = participantId,
                        advanceEntryRole = AdvanceEntryRole.InitialDebt.name
                    )
                    transferEntities.add(expenseTx)
                    if (tagIds.isNotEmpty()) {
                        deferredTagRefs += tagIds.map { tagId -> TransactionTagCrossRef(outId, tagId) }
                    }
                } else {
                    val payer = requireNotNull(payerAccount) { "請選擇付款帳戶" }
                    val outTx = TransactionEntity(
                        id = outId,
                        amount = input.owedAmount.abs().negate(),
                        currencyCode = currencyCode,
                        date = date,
                        note = "$transferMemo (代墊給 ${input.debtAccount.name})",
                        photoPath = null,
                        type = TransactionType.Transfer,
                        linkedTransactionId = inId,
                        transferGroupId = transferGroupId,
                        transferSide = TransferSide.Outgoing,
                        createdAt = now,
                        updatedAt = now,
                        accountId = payer.id,
                        categoryId = null,
                        advanceCaseId = caseId,
                        advanceParticipantId = participantId,
                        advanceEntryRole = AdvanceEntryRole.InitialAsset.name
                    )
                    val inTx = TransactionEntity(
                        id = inId,
                        amount = input.owedAmount.abs(),
                        currencyCode = currencyCode,
                        date = date,
                        note = "$transferMemo (來自 ${payer.name})",
                        photoPath = null,
                        type = TransactionType.Transfer,
                        linkedTransactionId = outId,
                        transferGroupId = transferGroupId,
                        transferSide = TransferSide.Incoming,
                        createdAt = now,
                        updatedAt = now,
                        accountId = input.debtAccount.id,
                        categoryId = null,
                        advanceCaseId = caseId,
                        advanceParticipantId = participantId,
                        advanceEntryRole = AdvanceEntryRole.InitialDebt.name
                    )
                    transferEntities.add(outTx)
                    transferEntities.add(inTx)
                }
            }

            advanceDao.upsertParticipants(participantEntities)
            transactionDao.upsertAll(transferEntities)
            if (deferredTagRefs.isNotEmpty()) {
                transactionDao.insertTransactionTags(deferredTagRefs)
            }
            syncAllBudgetHistory()
            caseId
        }
    }

    suspend fun recordAdvanceRepayment(
        advanceCase: AdvanceCaseEntity,
        participant: AdvanceParticipantEntity,
        amount: BigDecimal,
        normalizedAmount: BigDecimal,
        currencyCode: String,
        date: Instant,
        note: String,
        receiveAccount: AccountEntity,
        category: CategoryEntity?,
        tagIds: List<UUID>
    ) {
        recordAdvanceRepayments(
            advanceCaseId = advanceCase.id,
            participantId = participant.id,
            drafts = listOf(
                AdvanceRepaymentCreateDraft(
                    receiveAccountId = receiveAccount.id,
                    amount = amount,
                    normalizedAmount = normalizedAmount,
                    currencyCode = currencyCode,
                    date = date,
                    note = note,
                    categoryId = category?.id,
                    tagIds = tagIds
                )
            )
        )
    }

    suspend fun recordAdvanceRepayments(
        advanceCaseId: UUID,
        participantId: UUID,
        drafts: List<AdvanceRepaymentCreateDraft>
    ) {
        require(drafts.isNotEmpty()) { "請至少提供一筆還款。" }
        database.withTransaction {
            drafts.forEach { draft ->
                recordAdvanceRepaymentLocked(advanceCaseId, participantId, draft)
            }
        }
    }

    private suspend fun recordAdvanceRepaymentLocked(
        advanceCaseId: UUID,
        participantId: UUID,
        draft: AdvanceRepaymentCreateDraft
    ) {
        require(draft.amount > BigDecimal.ZERO) { "還款金額必須大於 0。" }
        require(draft.normalizedAmount > BigDecimal.ZERO) { "沖銷金額必須大於 0。" }
        require(draft.currencyCode.isNotBlank()) { "請選擇還款幣種。" }

        val currentCase = requireNotNull(
            advanceDao.getAllCases().firstOrNull { it.id == advanceCaseId }
        ) { "找不到代墊案件。" }
        val currentParticipant = requireNotNull(
            advanceDao.getAllParticipants().firstOrNull { it.id == participantId }
        ) { "找不到還款對象。" }
        require(currentParticipant.advanceCaseId == currentCase.id) {
            "該還款對象不屬於此代墊案件。"
        }
        val currentReceiveAccount = requireNotNull(accountDao.getAccount(draft.receiveAccountId)) {
            "找不到所選帳戶。"
        }
        require(currentReceiveAccount.type != AccountType.Debt && !currentReceiveAccount.isArchived) {
            "請選擇未歸檔的非借貸帳戶。"
        }
        val direction = advanceSettlementDirectionLocked(currentParticipant)
        val currentCategory = draft.categoryId?.let {
            requireNotNull(categoryDao.getCategory(it)) { "找不到所選分類。" }
        }
        require(
            currentCategory == null ||
                currentCategory.kind.supports(
                    if (direction == AdvanceSettlementDirection.IAdvancedOthers) {
                        TransactionType.Income
                    } else {
                        TransactionType.Expense
                    }
                )
        ) { "所選分類與這筆還款方向不相符。" }

        val now = Instant.now()
        val normalized = draft.normalizedAmount.abs()
        val remaining = (currentParticipant.owedAmount - currentParticipant.repaidAmount)
            .max(BigDecimal.ZERO)
        require(normalized - remaining <= BigDecimal("0.0001")) {
            "沖銷金額超過未還餘額。"
        }
        val transferGroupId = UUID.randomUUID()
        val outId = UUID.randomUUID()
        val inId = UUID.randomUUID()
        val repaymentId = UUID.randomUUID()
        val amount = draft.amount.abs()
        val currency = draft.currencyCode.trim().uppercase()
        val transferMemo = draft.note.trim().ifBlank { currentCase.title }

        val outTx: TransactionEntity
        val inTx: TransactionEntity
        val taggedTxId: UUID
        if (direction == AdvanceSettlementDirection.OthersAdvancedMe) {
            outTx = TransactionEntity(
                id = outId,
                amount = amount.negate(),
                currencyCode = currency,
                date = draft.date,
                note = "$transferMemo (還款給 ${currentParticipant.name})",
                photoPath = null,
                type = TransactionType.Transfer,
                linkedTransactionId = inId,
                transferGroupId = transferGroupId,
                transferSide = TransferSide.Outgoing,
                createdAt = now,
                updatedAt = now,
                accountId = currentReceiveAccount.id,
                categoryId = currentCategory?.id,
                advanceCaseId = currentCase.id,
                advanceParticipantId = currentParticipant.id,
                advanceRepaymentId = repaymentId,
                advanceEntryRole = AdvanceEntryRole.RepaymentAsset.name
            )
            inTx = TransactionEntity(
                id = inId,
                amount = amount,
                currencyCode = currency,
                date = draft.date,
                note = "$transferMemo (來自 ${currentReceiveAccount.name})",
                photoPath = null,
                type = TransactionType.Transfer,
                linkedTransactionId = outId,
                transferGroupId = transferGroupId,
                transferSide = TransferSide.Incoming,
                createdAt = now,
                updatedAt = now,
                accountId = currentParticipant.debtAccountId,
                categoryId = null,
                advanceCaseId = currentCase.id,
                advanceParticipantId = currentParticipant.id,
                advanceRepaymentId = repaymentId,
                advanceEntryRole = AdvanceEntryRole.RepaymentDebt.name
            )
            taggedTxId = outId
        } else {
            outTx = TransactionEntity(
                id = outId,
                amount = amount.negate(),
                currencyCode = currency,
                date = draft.date,
                note = "$transferMemo (還款至 ${currentReceiveAccount.name})",
                photoPath = null,
                type = TransactionType.Transfer,
                linkedTransactionId = inId,
                transferGroupId = transferGroupId,
                transferSide = TransferSide.Outgoing,
                createdAt = now,
                updatedAt = now,
                accountId = currentParticipant.debtAccountId,
                categoryId = null,
                advanceCaseId = currentCase.id,
                advanceParticipantId = currentParticipant.id,
                advanceRepaymentId = repaymentId,
                advanceEntryRole = AdvanceEntryRole.RepaymentDebt.name
            )
            inTx = TransactionEntity(
                id = inId,
                amount = amount,
                currencyCode = currency,
                date = draft.date,
                note = "$transferMemo (來自 ${currentParticipant.name})",
                photoPath = null,
                type = TransactionType.Transfer,
                linkedTransactionId = outId,
                transferGroupId = transferGroupId,
                transferSide = TransferSide.Incoming,
                createdAt = now,
                updatedAt = now,
                accountId = currentReceiveAccount.id,
                categoryId = currentCategory?.id,
                advanceCaseId = currentCase.id,
                advanceParticipantId = currentParticipant.id,
                advanceRepaymentId = repaymentId,
                advanceEntryRole = AdvanceEntryRole.RepaymentAsset.name
            )
            taggedTxId = inId
        }

        transactionDao.upsertAll(listOf(outTx, inTx))
        if (draft.tagIds.isNotEmpty()) {
            transactionDao.insertTransactionTags(
                draft.tagIds.distinct().map { tagId -> TransactionTagCrossRef(taggedTxId, tagId) }
            )
        }
        advanceDao.upsertParticipants(
            listOf(
                currentParticipant.copy(
                    repaidAmount = (currentParticipant.repaidAmount + normalized)
                        .min(currentParticipant.owedAmount),
                    updatedAt = now
                )
            )
        )
        advanceDao.upsertCase(currentCase.copy(updatedAt = now))
        advanceDao.upsertRepayment(
            AdvanceRepaymentEntity(
                id = repaymentId,
                amount = amount,
                currencyCode = currency,
                normalizedAmount = normalized,
                date = draft.date,
                note = draft.note.trim(),
                linkedTransferGroupId = transferGroupId,
                createdAt = now,
                advanceCaseId = currentCase.id,
                participantId = currentParticipant.id,
                receivedAccountId = currentReceiveAccount.id
            )
        )
    }

    suspend fun updateAdvanceSelfExpense(draft: AdvanceSelfExpenseEditDraft) {
        require(draft.amount > BigDecimal.ZERO) { "實際扣款金額必須大於 0。" }
        require(draft.normalizedAmount > BigDecimal.ZERO) { "案件中的自己份額必須大於 0。" }
        require(draft.currencyCode.isNotBlank()) { "請選擇實際扣款幣種。" }

        database.withTransaction {
            val advanceCase = requireNotNull(
                advanceDao.getAllCases().firstOrNull { it.id == draft.caseId }
            ) { "找不到代墊案件。" }
            val transactionId = requireNotNull(advanceCase.selfExpenseTransactionId) {
                "找不到代墊案件對應的自己份額支出。"
            }
            val transaction = requireNotNull(transactionDao.getTransaction(transactionId)?.transaction) {
                "找不到代墊案件對應的自己份額支出。"
            }
            require(
                transaction.type == TransactionType.Expense &&
                    transaction.transferGroupId == null &&
                    transaction.linkedTransactionId == null
            ) { "自己份額支出結構不完整，無法安全編輯。" }

            val account = requireNotNull(accountDao.getAccount(draft.accountId)) {
                "找不到所選支出帳戶。"
            }
            require(account.type != AccountType.Debt && !account.isArchived) {
                "請選擇未歸檔的非借貸帳戶。"
            }
            val category = draft.categoryId?.let { categoryId ->
                requireNotNull(categoryDao.getCategory(categoryId)) { "找不到所選分類。" }
            }
            require(category == null || category.kind.supports(TransactionType.Expense)) {
                "自己的份額只能使用支出分類。"
            }

            val now = Instant.now()
            transactionDao.upsert(
                transaction.copy(
                    amount = draft.amount.abs().negate(),
                    currencyCode = draft.currencyCode.trim().uppercase(),
                    date = draft.date,
                    note = draft.note.trim(),
                    updatedAt = now,
                    accountId = account.id,
                    categoryId = category?.id
                )
            )
            transactionDao.clearTransactionTags(transaction.id)
            if (draft.tagIds.isNotEmpty()) {
                transactionDao.insertTransactionTags(
                    draft.tagIds.distinct().map { tagId ->
                        TransactionTagCrossRef(transaction.id, tagId)
                    }
                )
            }
            advanceDao.upsertCase(
                advanceCase.copy(
                    myShareAmount = draft.normalizedAmount.abs(),
                    expenseCategoryId = category?.id,
                    updatedAt = now
                )
            )
            syncAllBudgetHistory()
        }
    }

    suspend fun updateAdvanceRepayment(draft: AdvanceRepaymentEditDraft) {
        require(draft.amount > BigDecimal.ZERO) { "還款金額必須大於 0。" }
        require(draft.normalizedAmount > BigDecimal.ZERO) { "沖銷金額必須大於 0。" }
        require(draft.currencyCode.isNotBlank()) { "請選擇還款幣種。" }

        database.withTransaction {
            val repayment = requireNotNull(
                advanceDao.getAllRepayments().firstOrNull { it.id == draft.repaymentId }
            ) { "找不到還款紀錄。" }
            val participant = requireNotNull(
                repayment.participantId?.let { participantId ->
                    advanceDao.getAllParticipants().firstOrNull { it.id == participantId }
                }
            ) { "找不到還款對象。" }
            val advanceCase = requireNotNull(
                repayment.advanceCaseId?.let { caseId ->
                    advanceDao.getAllCases().firstOrNull { it.id == caseId }
                }
            ) { "找不到代墊案件。" }
            require(
                !isMutualDebtOffset(repayment.note) &&
                    !isManualDebtSettlement(repayment.note)
            ) {
                "債務抵銷或跨幣種平賬必須整組撤銷，不能當作普通還款編輯。"
            }
            val receiveAccount = requireNotNull(accountDao.getAccount(draft.receiveAccountId)) {
                "找不到所選帳戶。"
            }
            require(receiveAccount.type != AccountType.Debt && !receiveAccount.isArchived) {
                "請選擇未歸檔的非借貸帳戶。"
            }
            val direction = advanceSettlementDirectionLocked(participant)
            val category = draft.categoryId?.let { categoryId ->
                requireNotNull(categoryDao.getCategory(categoryId)) { "找不到所選分類。" }
            }
            require(
                category == null ||
                    category.kind.supports(
                        if (direction == AdvanceSettlementDirection.IAdvancedOthers) {
                            TransactionType.Income
                        } else {
                            TransactionType.Expense
                        }
                    )
            ) { "所選分類與這筆還款方向不相符。" }
            val groupId = requireNotNull(repayment.linkedTransferGroupId) { "此還款沒有可編輯的轉帳分錄。" }
            val group = transactionDao.getTransferGroup(groupId)
            require(group.size == 2) { "還款轉帳分錄不完整。" }

            val otherNormalized = advanceDao.getAllRepayments()
                .filter { it.participantId == participant.id && it.id != repayment.id }
                .fold(BigDecimal.ZERO) { total, item -> total + item.normalizedAmount }
            val updatedRepaid = otherNormalized + draft.normalizedAmount.abs()
            require(updatedRepaid - participant.owedAmount <= BigDecimal("0.0001")) {
                "沖銷金額超過未還餘額。"
            }

            val debtAccountId = requireNotNull(participant.debtAccountId) { "找不到債務對象帳戶。" }
            val existingBySide = group.associateBy { effectiveTransferSide(it.transaction) }
            val outgoing = requireNotNull(existingBySide[TransferSide.Outgoing]?.transaction)
            val incoming = requireNotNull(existingBySide[TransferSide.Incoming]?.transaction)
            val amount = draft.amount.abs()
            val currency = draft.currencyCode.trim().uppercase()
            val memo = draft.note.trim().ifBlank { advanceCase.title }
            val now = Instant.now()

            val updatedOutgoing: TransactionEntity
            val updatedIncoming: TransactionEntity
            val ownLegId: UUID
            when (direction) {
                AdvanceSettlementDirection.IAdvancedOthers -> {
                    updatedOutgoing = outgoing.copy(
                        amount = amount.negate(),
                        currencyCode = currency,
                        date = draft.date,
                        note = "$memo (還款至 ${receiveAccount.name})",
                        linkedTransactionId = incoming.id,
                        transferGroupId = groupId,
                        transferSide = TransferSide.Outgoing,
                        updatedAt = now,
                        accountId = debtAccountId,
                        categoryId = null
                    )
                    updatedIncoming = incoming.copy(
                        amount = amount,
                        currencyCode = currency,
                        date = draft.date,
                        note = "$memo (來自 ${participant.name})",
                        linkedTransactionId = outgoing.id,
                        transferGroupId = groupId,
                        transferSide = TransferSide.Incoming,
                        updatedAt = now,
                        accountId = receiveAccount.id,
                        categoryId = category?.id
                    )
                    ownLegId = incoming.id
                }
                AdvanceSettlementDirection.OthersAdvancedMe -> {
                    updatedOutgoing = outgoing.copy(
                        amount = amount.negate(),
                        currencyCode = currency,
                        date = draft.date,
                        note = "$memo (還款給 ${participant.name})",
                        linkedTransactionId = incoming.id,
                        transferGroupId = groupId,
                        transferSide = TransferSide.Outgoing,
                        updatedAt = now,
                        accountId = receiveAccount.id,
                        categoryId = category?.id
                    )
                    updatedIncoming = incoming.copy(
                        amount = amount,
                        currencyCode = currency,
                        date = draft.date,
                        note = "$memo (來自 ${receiveAccount.name})",
                        linkedTransactionId = outgoing.id,
                        transferGroupId = groupId,
                        transferSide = TransferSide.Incoming,
                        updatedAt = now,
                        accountId = debtAccountId,
                        categoryId = null
                    )
                    ownLegId = outgoing.id
                }
            }

            transactionDao.upsertAll(listOf(updatedOutgoing, updatedIncoming))
            group.forEach { transactionDao.clearTransactionTags(it.transaction.id) }
            if (draft.tagIds.isNotEmpty()) {
                transactionDao.insertTransactionTags(
                    draft.tagIds.distinct().map { tagId -> TransactionTagCrossRef(ownLegId, tagId) }
                )
            }
            advanceDao.upsertRepayment(
                repayment.copy(
                    amount = amount,
                    currencyCode = currency,
                    normalizedAmount = draft.normalizedAmount.abs(),
                    date = draft.date,
                    note = draft.note.trim(),
                    receivedAccountId = receiveAccount.id
                )
            )
            advanceDao.upsertParticipants(
                listOf(
                    participant.copy(
                        repaidAmount = updatedRepaid.min(participant.owedAmount),
                        updatedAt = now
                    )
                )
            )
            advanceDao.upsertCase(advanceCase.copy(updatedAt = now))
        }
    }

    suspend fun rollbackAdvanceRepayment(repaymentId: UUID) {
        database.withTransaction {
            val repayment = requireNotNull(
                advanceDao.getAllRepayments().firstOrNull { it.id == repaymentId }
            ) { "找不到還款紀錄。" }
            require(
                !isMutualDebtOffset(repayment.note) &&
                    !isManualDebtSettlement(repayment.note)
            ) {
                "債務抵銷或跨幣種平賬必須整組撤銷，不能當作普通還款單筆沖銷。"
            }
            rollbackRepayments(listOf(repayment))
            syncAllBudgetHistory()
        }
    }

    suspend fun updateAdvanceParticipantOwedAmount(
        participantId: UUID,
        newOwedAmount: BigDecimal,
        paymentAmount: BigDecimal? = null,
        paymentCurrencyCode: String? = null
    ) {
        require(newOwedAmount > BigDecimal.ZERO) { "欠款金額必須大於 0。" }

        database.withTransaction {
            val participant = requireNotNull(
                advanceDao.getAllParticipants().firstOrNull { it.id == participantId }
            ) { "找不到代墊對象。" }
            require(newOwedAmount + BigDecimal("0.0001") >= participant.repaidAmount) {
                "欠款金額不可低於已還金額。"
            }
            val advanceCase = requireNotNull(
                participant.advanceCaseId?.let { caseId ->
                    advanceDao.getAllCases().firstOrNull { it.id == caseId }
                }
            ) { "找不到代墊案件。" }
            val groupId = requireNotNull(participant.initialTransferGroupId) { "找不到初始代墊分錄。" }
            val group = transactionDao.getTransferGroup(groupId)
            require(group.isNotEmpty()) { "找不到初始代墊分錄。" }
            val amount = newOwedAmount.abs()
            val now = Instant.now()
            val direction = advanceSettlementDirectionLocked(participant)

            val updatedTransactions = when (direction) {
                AdvanceSettlementDirection.OthersAdvancedMe -> {
                    require(group.size == 1) { "他人代墊我的初始支出結構不完整。" }
                    listOf(
                        group.single().transaction.copy(
                            amount = amount.negate(),
                            currencyCode = advanceCase.currencyCode,
                            date = advanceCase.date,
                            type = TransactionType.Expense,
                            linkedTransactionId = null,
                            transferGroupId = groupId,
                            transferSide = TransferSide.Outgoing,
                            updatedAt = now,
                            accountId = participant.debtAccountId,
                            categoryId = advanceCase.expenseCategoryId
                        )
                    )
                }
                AdvanceSettlementDirection.IAdvancedOthers -> {
                    require(group.size == 2) { "我代墊他人的初始轉帳結構不完整。" }
                    group.map { item ->
                        val side = effectiveTransferSide(item.transaction)
                        val isAssetLeg = side == TransferSide.Outgoing
                        val actualAmount = if (isAssetLeg) {
                            paymentAmount?.abs() ?: item.transaction.amount.abs()
                        } else {
                            amount
                        }
                        item.transaction.copy(
                            amount = if (isAssetLeg) actualAmount.negate() else actualAmount,
                            currencyCode = if (isAssetLeg) {
                                paymentCurrencyCode?.trim()?.uppercase()
                                    ?.takeIf(String::isNotBlank)
                                    ?: item.transaction.currencyCode
                            } else {
                                advanceCase.currencyCode
                            },
                            date = advanceCase.date,
                            transferSide = side,
                            updatedAt = now,
                            advanceCaseId = advanceCase.id,
                            advanceParticipantId = participant.id,
                            advanceEntryRole = if (isAssetLeg) {
                                AdvanceEntryRole.InitialAsset.name
                            } else {
                                AdvanceEntryRole.InitialDebt.name
                            }
                        )
                    }
                }
            }

            transactionDao.upsertAll(updatedTransactions)
            advanceDao.upsertParticipants(
                listOf(
                    participant.copy(
                        owedAmount = amount,
                        repaidAmount = participant.repaidAmount.min(amount),
                        updatedAt = now
                    )
                )
            )
            advanceDao.upsertCase(advanceCase.copy(updatedAt = now))
            syncAllBudgetHistory()
        }
    }

    suspend fun updateAdvanceInitialMetadata(draft: AdvanceInitialMetadataEditDraft) {
        database.withTransaction {
            val advanceCase = requireNotNull(
                advanceDao.getAllCases().firstOrNull { it.id == draft.caseId }
            ) { "找不到代墊案件。" }
            val participants = advanceDao.getAllParticipants()
                .filter { it.advanceCaseId == advanceCase.id }
            require(participants.isNotEmpty()) { "代墊案件沒有可更新的對象。" }

            val direction = advanceSettlementDirectionLocked(participants.first())
            val payerAccount = draft.payerAccountId?.let { accountId ->
                requireNotNull(accountDao.getAccount(accountId)) { "找不到所選付款帳戶。" }
            }
            if (direction == AdvanceSettlementDirection.IAdvancedOthers) {
                require(payerAccount != null && payerAccount.type != AccountType.Debt && !payerAccount.isArchived) {
                    "請選擇未歸檔的非借貸付款帳戶。"
                }
            }
            val category = draft.categoryId?.let { categoryId ->
                requireNotNull(categoryDao.getCategory(categoryId)) { "找不到所選分類。" }
            }
            if (direction == AdvanceSettlementDirection.OthersAdvancedMe) {
                require(category == null || category.kind.supports(TransactionType.Expense)) {
                    "他人代墊我的初始分錄只能使用支出分類。"
                }
            }

            val entries = participants.map { participant ->
                require(advanceSettlementDirectionLocked(participant) == direction) {
                    "同一代墊案件含有不一致的方向。"
                }
                val groupId = requireNotNull(participant.initialTransferGroupId) {
                    "找不到初始代墊分錄。"
                }
                val group = transactionDao.getTransferGroup(groupId)
                when (direction) {
                    AdvanceSettlementDirection.IAdvancedOthers -> require(group.size == 2) {
                        "我代墊他人的初始轉帳結構不完整。"
                    }
                    AdvanceSettlementDirection.OthersAdvancedMe -> require(
                        group.size == 1 && participant.debtAccountId != null
                    ) {
                        "他人代墊我的初始支出結構不完整。"
                    }
                }
                participant to group
            }

            val memo = draft.note.trim()
            val baseMemo = memo.ifBlank { advanceCase.title }
            val now = Instant.now()
            entries.forEach { (participant, group) ->
                val amount = participant.owedAmount.abs()
                when (direction) {
                    AdvanceSettlementDirection.IAdvancedOthers -> {
                        val outgoing = requireNotNull(
                            group.firstOrNull {
                                effectiveTransferSide(it.transaction) == TransferSide.Outgoing
                            }?.transaction
                        )
                        val incoming = requireNotNull(
                            group.firstOrNull {
                                effectiveTransferSide(it.transaction) == TransferSide.Incoming
                            }?.transaction
                        )
                        transactionDao.upsertAll(
                            listOf(
                                outgoing.copy(
                                    amount = amount.negate(),
                                    currencyCode = advanceCase.currencyCode,
                                    date = draft.date,
                                    note = "$baseMemo (代墊給 ${participant.name})",
                                    linkedTransactionId = incoming.id,
                                    transferSide = TransferSide.Outgoing,
                                    updatedAt = now,
                                    accountId = requireNotNull(payerAccount).id,
                                    categoryId = null,
                                    advanceCaseId = advanceCase.id,
                                    advanceParticipantId = participant.id,
                                    advanceEntryRole = AdvanceEntryRole.InitialAsset.name
                                ),
                                incoming.copy(
                                    amount = amount,
                                    currencyCode = advanceCase.currencyCode,
                                    date = draft.date,
                                    note = "$baseMemo (來自 ${payerAccount.name})",
                                    linkedTransactionId = outgoing.id,
                                    transferSide = TransferSide.Incoming,
                                    updatedAt = now,
                                    accountId = participant.debtAccountId,
                                    categoryId = null,
                                    advanceCaseId = advanceCase.id,
                                    advanceParticipantId = participant.id,
                                    advanceEntryRole = AdvanceEntryRole.InitialDebt.name
                                )
                            )
                        )
                        group.forEach { transactionDao.clearTransactionTags(it.transaction.id) }
                    }
                    AdvanceSettlementDirection.OthersAdvancedMe -> {
                        val expense = group.single().transaction
                        transactionDao.upsert(
                            expense.copy(
                                amount = amount.negate(),
                                currencyCode = advanceCase.currencyCode,
                                date = draft.date,
                                note = "$baseMemo (他人代墊我：${participant.name})",
                                type = TransactionType.Expense,
                                linkedTransactionId = null,
                                transferSide = TransferSide.Outgoing,
                                updatedAt = now,
                                accountId = participant.debtAccountId,
                                categoryId = category?.id,
                                advanceCaseId = advanceCase.id,
                                advanceParticipantId = participant.id,
                                advanceEntryRole = AdvanceEntryRole.InitialDebt.name
                            )
                        )
                        transactionDao.clearTransactionTags(expense.id)
                        if (draft.tagIds.isNotEmpty()) {
                            transactionDao.insertTransactionTags(
                                draft.tagIds.distinct().map { tagId ->
                                    TransactionTagCrossRef(expense.id, tagId)
                                }
                            )
                        }
                    }
                }
            }
            advanceDao.upsertCase(
                advanceCase.copy(
                    date = draft.date,
                    note = memo,
                    updatedAt = now,
                    payerAccountId =
                        if (direction == AdvanceSettlementDirection.IAdvancedOthers) payerAccount?.id else null,
                    expenseCategoryId =
                        if (direction == AdvanceSettlementDirection.OthersAdvancedMe) category?.id
                        else advanceCase.expenseCategoryId,
                    direction = direction.name
                )
            )
            advanceDao.clearCaseTags(advanceCase.id)
            if (draft.tagIds.isNotEmpty()) {
                advanceDao.insertCaseTags(
                    draft.tagIds.distinct().map { tagId ->
                        AdvanceCaseTagCrossRef(advanceCase.id, tagId)
                    }
                )
            }
            syncAllBudgetHistory()
        }
    }

    suspend fun exportBackup(): FullBackupData {
        val accounts = accountDao.getAll()
        val categories = categoryDao.getAll()
        val tags = tagDao.getAll()
        val transactions = transactionDao.getAll()
        val transactionTags = transactionDao.getTransactionTags()
        val shortcuts = shortcutDao.getAll()
        val shortcutTags = shortcutDao.getShortcutTags()
        val recurringRules = recurringDao.getAllRules()
        val recurringRuleTags = recurringDao.getRuleTags()
        val recurringOccurrences = recurringDao.getAllOccurrences()
        val budgets = budgetDao.getAll()
        val budgetHistories = budgetDao.getAllHistory()
        val budgetSettings = budgetDao.getSettings()
        val advanceCases = advanceDao.getAllCases()
        val advanceCaseTags = advanceDao.getCaseTags()
        val advanceParticipants = advanceDao.getAllParticipants()
        val advanceRepayments = advanceDao.getAllRepayments()

        val transactionTagMap = transactionTags.groupBy { it.transactionId }
        val shortcutTagMap = shortcutTags.groupBy { it.shortcutId }
        val recurringRuleTagMap = recurringRuleTags.groupBy { it.ruleId }
        val advanceCaseTagMap = advanceCaseTags.groupBy { it.advanceCaseId }

        return FullBackupData(
            version = "1.9",
            timestamp = Instant.now(),
            accounts = accounts.map {
                FullBackupData.AccountCodable(
                    id = it.id,
                    name = it.name,
                    currency = it.currency,
                    type = it.type.rawValue,
                    baseBalance = it.baseBalance,
                    sortOrder = it.sortOrder,
                    isArchived = it.isArchived
                )
            },
            categories = categories.map {
                FullBackupData.CategoryCodable(
                    id = it.id,
                    name = it.name,
                    icon = it.icon,
                    colorHex = it.colorHex,
                    kind = it.kind.rawValue
                )
            },
            tags = tags.map { FullBackupData.TagCodable(id = it.id, name = it.name) },
            transactions = transactions.map { tx ->
                FullBackupData.TransactionCodable(
                    id = tx.id,
                    amount = tx.amount,
                    currencyCode = tx.currencyCode,
                    date = tx.date,
                    note = tx.note,
                    type = tx.type.rawValue,
                    linkedTransactionID = tx.linkedTransactionId,
                    transferGroupID = tx.transferGroupId,
                    transferSide = tx.transferSide?.rawValue,
                    photoPath = tx.photoPath,
                    createdAt = tx.createdAt,
                    updatedAt = tx.updatedAt,
                    accountID = tx.accountId,
                    categoryID = tx.categoryId,
                    tagIDs = transactionTagMap[tx.id]?.map { it.tagId } ?: emptyList(),
                    advanceCaseID = tx.advanceCaseId,
                    advanceParticipantID = tx.advanceParticipantId,
                    advanceRepaymentID = tx.advanceRepaymentId,
                    advanceEntryRole = tx.advanceEntryRole
                )
            },
            shortcuts = shortcuts.map { shortcut ->
                FullBackupData.ShortcutCodable(
                    id = shortcut.id,
                    name = shortcut.name,
                    icon = shortcut.icon,
                    amount = shortcut.amount,
                    type = shortcut.type.rawValue,
                    note = shortcut.note,
                    currencyCode = shortcut.currencyCode,
                    accountID = shortcut.accountId,
                    categoryID = shortcut.categoryId,
                    tagIDs = shortcutTagMap[shortcut.id]?.map { it.tagId } ?: emptyList()
                )
            },
            recurringRules = recurringRules.map { rule ->
                FullBackupData.RecurringRuleCodable(
                    id = rule.id,
                    title = rule.title,
                    amount = rule.amount,
                    currencyCode = rule.currencyCode,
                    type = rule.type.rawValue,
                    note = rule.note,
                    frequency = rule.frequency,
                    intervalCount = rule.intervalCount,
                    nextDueDate = rule.nextDueDate,
                    isPaused = rule.isPaused,
                    accountID = rule.accountId,
                    categoryID = rule.categoryId,
                    tagIDs = recurringRuleTagMap[rule.id]?.map { it.tagId } ?: emptyList(),
                    createdAt = rule.createdAt,
                    updatedAt = rule.updatedAt
                )
            },
            recurringOccurrences = recurringOccurrences.map { occurrence ->
                FullBackupData.RecurringOccurrenceCodable(
                    id = occurrence.id,
                    dueDate = occurrence.dueDate,
                    status = occurrence.status,
                    createdTransactionID = occurrence.createdTransactionId,
                    ruleID = occurrence.ruleId,
                    createdAt = occurrence.createdAt,
                    updatedAt = occurrence.updatedAt
                )
            },
            budgets = budgets.map { budget ->
                FullBackupData.BudgetCodable(
                    id = budget.id,
                    monthKey = budget.monthKey,
                    amount = budget.amount,
                    currencyCode = budget.currencyCode,
                    isEnabled = budget.isEnabled,
                    categoryID = budget.categoryId,
                    createdAt = budget.createdAt,
                    updatedAt = budget.updatedAt
                )
            },
            budgetHistory = budgetHistories.map { history ->
                FullBackupData.BudgetHistoryCodable(
                    id = history.id,
                    historyKey = history.historyKey,
                    monthKey = history.monthKey,
                    categoryID = history.categoryId,
                    categoryNameSnapshot = history.categoryNameSnapshot,
                    budgetAmount = history.budgetAmount,
                    spentAmount = history.spentAmount,
                    remainingAmount = history.remainingAmount,
                    usageRatio = history.usageRatio,
                    isOverBudget = history.isOverBudget,
                    currencyCode = history.currencyCode,
                    updatedAt = history.updatedAt
                )
            },
            budgetSettings = listOfNotNull(budgetSettings).map { settings ->
                FullBackupData.BudgetSettingsCodable(
                    id = settings.id,
                    carryOverMode = settings.carryOverMode,
                    alertThresholdPercent = settings.alertThresholdPercent,
                    forecastMode = settings.forecastMode,
                    updatedAt = settings.updatedAt
                )
            },
            advanceCases = advanceCases.map { case ->
                FullBackupData.AdvanceCaseCodable(
                    id = case.id,
                    title = case.title,
                    date = case.date,
                    currencyCode = case.currencyCode,
                    myShareAmount = case.myShareAmount,
                    note = case.note,
                    selfExpenseTransactionID = case.selfExpenseTransactionId,
                    payerAccountID = case.payerAccountId,
                    expenseCategoryID = case.expenseCategoryId,
                    createdAt = case.createdAt,
                    updatedAt = case.updatedAt,
                    direction = case.direction,
                    tagIDs = advanceCaseTagMap[case.id]?.map { it.tagId } ?: emptyList()
                )
            },
            advanceParticipants = advanceParticipants.map { participant ->
                FullBackupData.AdvanceParticipantCodable(
                    id = participant.id,
                    name = participant.name,
                    owedAmount = participant.owedAmount,
                    repaidAmount = participant.repaidAmount,
                    initialTransferGroupID = participant.initialTransferGroupId,
                    advanceCaseID = participant.advanceCaseId,
                    debtAccountID = participant.debtAccountId,
                    createdAt = participant.createdAt,
                    updatedAt = participant.updatedAt
                )
            },
            advanceRepayments = advanceRepayments.map { repayment ->
                FullBackupData.AdvanceRepaymentCodable(
                    id = repayment.id,
                    amount = repayment.amount,
                    currencyCode = repayment.currencyCode,
                    normalizedAmount = repayment.normalizedAmount,
                    date = repayment.date,
                    note = repayment.note,
                    linkedTransferGroupID = repayment.linkedTransferGroupId,
                    advanceCaseID = repayment.advanceCaseId,
                    participantID = repayment.participantId,
                    receivedAccountID = repayment.receivedAccountId,
                    createdAt = repayment.createdAt
                )
            }
        )
    }

    suspend fun exportBackupJson(): String {
        val data = exportBackup()
        return BackupJsonAdapter.gson.toJson(data)
    }

    suspend fun importBackupJson(json: String, replaceExisting: Boolean = true) {
        val data = BackupJsonAdapter.gson.fromJson(json, FullBackupData::class.java)

        val accountEntities = data.accounts.map {
            AccountEntity(
                id = it.id,
                name = it.name,
                currency = it.currency,
                type = org.duckdns.lhfser.aiaccounting.core.model.AccountType.entries
                    .firstOrNull { type -> type.rawValue == it.type }
                    ?: org.duckdns.lhfser.aiaccounting.core.model.AccountType.Cash,
                baseBalance = it.baseBalance,
                sortOrder = it.sortOrder,
                isArchived = BackupDefaults.accountIsArchived(BackupAccountInput(it.isArchived))
            )
        }

        val categoryEntities = data.categories.map {
            CategoryEntity(
                id = it.id,
                name = it.name,
                icon = it.icon,
                colorHex = it.colorHex,
                kind = BackupDefaults.categoryKind(BackupCategoryInput(it.kind))
            )
        }

        val tagEntities = data.tags.map { TagEntity(id = it.id, name = it.name) }

        val transactionEntities = data.transactions.map { tx ->
            TransactionEntity(
                id = tx.id,
                amount = tx.amount,
                currencyCode = tx.currencyCode,
                date = tx.date,
                note = tx.note,
                photoPath = tx.photoPath,
                type = org.duckdns.lhfser.aiaccounting.core.model.TransactionType.entries
                    .firstOrNull { type -> type.rawValue == tx.type }
                    ?: org.duckdns.lhfser.aiaccounting.core.model.TransactionType.Expense,
                linkedTransactionId = tx.linkedTransactionID,
                transferGroupId = tx.transferGroupID,
                transferSide = tx.transferSide?.let { side ->
                    org.duckdns.lhfser.aiaccounting.core.model.TransferSide.entries.firstOrNull { it.rawValue == side }
                },
                createdAt = tx.createdAt ?: Instant.now(),
                updatedAt = tx.updatedAt ?: Instant.now(),
                accountId = tx.accountID,
                categoryId = tx.categoryID,
                advanceCaseId = tx.advanceCaseID,
                advanceParticipantId = tx.advanceParticipantID,
                advanceRepaymentId = tx.advanceRepaymentID,
                advanceEntryRole = tx.advanceEntryRole
            )
        }
        val transactionTags = data.transactions.flatMap { tx ->
            tx.tagIDs.map { tagId -> TransactionTagCrossRef(tx.id, tagId) }
        }

        val shortcutEntities = data.shortcuts.map { shortcut ->
            ShortcutEntity(
                id = shortcut.id,
                name = shortcut.name,
                icon = shortcut.icon,
                amount = shortcut.amount,
                currencyCode = BackupDefaults.shortcutCurrency(
                    BackupShortcutInput(shortcut.currencyCode),
                    accountEntities.firstOrNull { it.id == shortcut.accountID }?.currency
                ),
                type = org.duckdns.lhfser.aiaccounting.core.model.TransactionType.entries
                    .firstOrNull { type -> type.rawValue == shortcut.type }
                    ?: org.duckdns.lhfser.aiaccounting.core.model.TransactionType.Expense,
                note = shortcut.note,
                accountId = shortcut.accountID,
                categoryId = shortcut.categoryID
            )
        }
        val shortcutTags = data.shortcuts.flatMap { shortcut ->
            shortcut.tagIDs.map { tagId -> ShortcutTagCrossRef(shortcut.id, tagId) }
        }

        val recurringRuleEntities = data.recurringRules?.map { rule ->
            RecurringRuleEntity(
                id = rule.id,
                title = rule.title,
                amount = rule.amount,
                currencyCode = rule.currencyCode,
                type = org.duckdns.lhfser.aiaccounting.core.model.TransactionType.entries
                    .firstOrNull { type -> type.rawValue == rule.type }
                    ?: org.duckdns.lhfser.aiaccounting.core.model.TransactionType.Expense,
                note = rule.note,
                frequency = rule.frequency,
                intervalCount = rule.intervalCount.coerceAtLeast(1),
                nextDueDate = rule.nextDueDate,
                isPaused = rule.isPaused,
                createdAt = rule.createdAt ?: Instant.now(),
                updatedAt = rule.updatedAt ?: Instant.now(),
                accountId = rule.accountID,
                categoryId = rule.categoryID
            )
        }.orEmpty()
        val recurringRuleTags = data.recurringRules?.flatMap { rule ->
            rule.tagIDs.map { tagId -> RecurringRuleTagCrossRef(rule.id, tagId) }
        }.orEmpty()

        val recurringOccurrenceEntities = data.recurringOccurrences?.map { occurrence ->
            RecurringOccurrenceEntity(
                id = occurrence.id,
                dueDate = occurrence.dueDate,
                status = occurrence.status,
                createdTransactionId = occurrence.createdTransactionID,
                createdAt = occurrence.createdAt ?: Instant.now(),
                updatedAt = occurrence.updatedAt ?: Instant.now(),
                ruleId = occurrence.ruleID
            )
        }.orEmpty()

        val budgetEntities = data.budgets?.map { budget ->
            CategoryMonthlyBudgetEntity(
                id = budget.id,
                monthKey = budget.monthKey,
                amount = budget.amount,
                currencyCode = budget.currencyCode,
                isEnabled = BackupDefaults.budgetIsEnabled(BackupBudgetInput(budget.isEnabled)),
                createdAt = budget.createdAt ?: Instant.now(),
                updatedAt = budget.updatedAt ?: Instant.now(),
                categoryId = budget.categoryID
            )
        }.orEmpty()

        val historyEntities = data.budgetHistory?.map { history ->
            BudgetMonthlyHistoryEntity(
                id = history.id,
                historyKey = history.historyKey,
                monthKey = history.monthKey,
                categoryId = history.categoryID,
                categoryNameSnapshot = history.categoryNameSnapshot,
                budgetAmount = history.budgetAmount,
                spentAmount = history.spentAmount,
                remainingAmount = history.remainingAmount,
                usageRatio = history.usageRatio,
                isOverBudget = history.isOverBudget,
                currencyCode = history.currencyCode,
                updatedAt = history.updatedAt ?: Instant.now()
            )
        }.orEmpty()

        val settingsEntities = data.budgetSettings?.map { settings ->
            BudgetSettingsEntity(
                id = settings.id,
                carryOverMode = settings.carryOverMode,
                alertThresholdPercent = settings.alertThresholdPercent,
                forecastMode = settings.forecastMode,
                updatedAt = settings.updatedAt ?: Instant.now()
            )
        }.orEmpty()

        val caseEntities = data.advanceCases?.map { case ->
            AdvanceCaseEntity(
                id = case.id,
                title = case.title,
                date = case.date,
                currencyCode = case.currencyCode,
                myShareAmount = BackupDefaults.myShareAmount(BackupAdvanceCaseInput(case.myShareAmount)),
                note = case.note ?: "",
                selfExpenseTransactionId = case.selfExpenseTransactionID,
                createdAt = case.createdAt ?: Instant.now(),
                updatedAt = case.updatedAt ?: Instant.now(),
                payerAccountId = case.payerAccountID,
                expenseCategoryId = case.expenseCategoryID,
                direction = case.direction
            )
        }.orEmpty()
        val caseTags = data.advanceCases?.flatMap { case ->
            case.tagIDs.orEmpty().map { tagId -> AdvanceCaseTagCrossRef(case.id, tagId) }
        }.orEmpty()

        val participantEntities = data.advanceParticipants?.map { participant ->
            AdvanceParticipantEntity(
                id = participant.id,
                name = participant.name,
                owedAmount = participant.owedAmount,
                repaidAmount = participant.repaidAmount ?: BigDecimal.ZERO,
                initialTransferGroupId = participant.initialTransferGroupID,
                createdAt = participant.createdAt ?: Instant.now(),
                updatedAt = participant.updatedAt ?: Instant.now(),
                advanceCaseId = participant.advanceCaseID,
                debtAccountId = participant.debtAccountID
            )
        }.orEmpty()

        val repaymentEntities = data.advanceRepayments?.map { repayment ->
            AdvanceRepaymentEntity(
                id = repayment.id,
                amount = repayment.amount,
                currencyCode = repayment.currencyCode,
                normalizedAmount = BackupDefaults.normalizedAmount(
                    BackupAdvanceRepaymentInput(repayment.amount, repayment.normalizedAmount ?: repayment.amount)
                ),
                date = repayment.date,
                note = repayment.note ?: "",
                linkedTransferGroupId = repayment.linkedTransferGroupID,
                createdAt = repayment.createdAt ?: Instant.now(),
                advanceCaseId = repayment.advanceCaseID,
                participantId = repayment.participantID,
                receivedAccountId = repayment.receivedAccountID
            )
        }.orEmpty()

        database.withTransaction {
            if (replaceExisting) {
                clearAllData()
            }

            accountDao.upsertAll(accountEntities)
            categoryDao.upsertAll(categoryEntities)
            tagDao.upsertAll(tagEntities)
            transactionDao.upsertAll(transactionEntities)
            if (transactionTags.isNotEmpty()) {
                transactionDao.insertTransactionTags(transactionTags)
            }
            shortcutDao.upsertAll(shortcutEntities)
            if (shortcutTags.isNotEmpty()) {
                shortcutDao.insertShortcutTags(shortcutTags)
            }
            if (recurringRuleEntities.isNotEmpty()) {
                recurringDao.upsertRules(recurringRuleEntities)
            }
            if (recurringRuleTags.isNotEmpty()) {
                recurringDao.insertRuleTags(recurringRuleTags)
            }
            if (recurringOccurrenceEntities.isNotEmpty()) {
                recurringDao.upsertOccurrences(recurringOccurrenceEntities)
            }
            if (budgetEntities.isNotEmpty()) {
                budgetDao.upsertAll(budgetEntities)
            }
            if (historyEntities.isNotEmpty()) {
                budgetDao.upsertAllHistory(historyEntities)
            }
            settingsEntities.forEach { budgetDao.upsertSettings(it) }
            caseEntities.forEach { advanceDao.upsertCase(it) }
            if (caseTags.isNotEmpty()) {
                advanceDao.insertCaseTags(caseTags)
            }
            if (participantEntities.isNotEmpty()) {
                advanceDao.upsertParticipants(participantEntities)
            }
            repaymentEntities.forEach { advanceDao.upsertRepayment(it) }
            backfillAdvanceLinksLocked()
            syncAllBudgetHistory()
        }
    }

    suspend fun backfillAdvanceLinks() {
        database.withTransaction {
            backfillAdvanceLinksLocked()
        }
    }

    private suspend fun backfillAdvanceLinksLocked() {
        val cases = advanceDao.getAllCases()
        val participants = advanceDao.getAllParticipants()
        val repayments = advanceDao.getAllRepayments()
        val participantsByCase = participants.groupBy { it.advanceCaseId }
        val repaymentsByCase = repayments.groupBy { it.advanceCaseId }

        cases.forEach { advanceCase ->
            val caseParticipants = participantsByCase[advanceCase.id].orEmpty()
            if (advanceCase.direction == null && caseParticipants.isNotEmpty()) {
                val direction = advanceSettlementDirectionLocked(caseParticipants.first())
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
                                    advanceEntryRole = if (transaction.accountId == participant.debtAccountId) {
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
                    val participant = participants.firstOrNull { it.id == repayment.participantId }
                    transactionDao.getTransferGroup(groupId).forEach { details ->
                        val transaction = details.transaction
                        if (transaction.advanceCaseId == null) {
                            transactionDao.upsert(
                                transaction.copy(
                                    advanceCaseId = advanceCase.id,
                                    advanceParticipantId = participant?.id,
                                    advanceRepaymentId = repayment.id,
                                    advanceEntryRole = if (transaction.accountId == participant?.debtAccountId) {
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

    private suspend fun syncAllBudgetHistory() {
        val budgets = budgetDao.getAll()
        val categoriesById = categoryDao.getAll().associateBy { it.id }
        val transactions = transactionDao.getAll()
        val existingHistory = budgetDao.getAllHistory()

        val desiredHistory = budgets
            .filter { it.isEnabled }
            .mapNotNull { budget ->
                val categoryId = budget.categoryId ?: return@mapNotNull null
                val category = categoriesById[categoryId] ?: return@mapNotNull null
                if (!category.kind.supports(TransactionType.Expense)) {
                    return@mapNotNull null
                }

                val spentAmount = transactions
                    .asSequence()
                    .filter { transaction ->
                        transaction.type == TransactionType.Expense &&
                            transaction.categoryId == categoryId &&
                            monthKeyFromInstant(transaction.date) == budget.monthKey
                    }
                    .fold(BigDecimal.ZERO) { partial, transaction ->
                        partial + currencyService.convert(
                            transaction.amount.abs(),
                            transaction.currencyCode,
                            budget.currencyCode
                        )
                    }

                val remainingAmount = budget.amount.subtract(spentAmount)
                val usageRatio = if (budget.amount > BigDecimal.ZERO) {
                    spentAmount.divide(budget.amount, 6, RoundingMode.HALF_UP)
                } else {
                    BigDecimal.ZERO
                }

                BudgetMonthlyHistoryEntity(
                    id = UUID.randomUUID(),
                    historyKey = budgetHistoryKey(budget.monthKey, categoryId),
                    monthKey = budget.monthKey,
                    categoryId = categoryId,
                    categoryNameSnapshot = category.name,
                    budgetAmount = budget.amount,
                    spentAmount = spentAmount,
                    remainingAmount = remainingAmount,
                    usageRatio = usageRatio,
                    isOverBudget = remainingAmount < BigDecimal.ZERO,
                    currencyCode = budget.currencyCode,
                    updatedAt = Instant.now()
                )
            }

        val existingByKey = existingHistory.associateBy { it.historyKey }
        val desiredByKey = desiredHistory.associateBy { it.historyKey }

        existingHistory
            .filter { it.historyKey !in desiredByKey }
            .forEach { budgetDao.deleteHistory(it) }

        desiredHistory.forEach { history ->
            val existing = existingByKey[history.historyKey]
            if (existing == null) {
                budgetDao.upsertHistory(history)
            } else {
                budgetDao.upsertHistory(
                    history.copy(id = existing.id)
                )
            }
        }
    }

    private suspend fun clearAllData() {
        transactionDao.deleteAllTransactionTags()
        shortcutDao.deleteAllShortcutTags()
        advanceDao.deleteAllRepayments()
        advanceDao.deleteAllParticipants()
        advanceDao.deleteAllCaseTags()
        advanceDao.deleteAllCases()
        budgetDao.deleteAllSettings()
        budgetDao.deleteAllHistory()
        budgetDao.deleteAll()
        recurringDao.deleteAllOccurrences()
        recurringDao.deleteAllRuleTags()
        recurringDao.deleteAllRules()
        shortcutDao.deleteAllShortcuts()
        transactionDao.deleteAllTransactions()
        tagDao.deleteAll()
        categoryDao.deleteAll()
        accountDao.deleteAll()
    }

    private suspend fun buildAccountDeletionTargets(accountId: UUID): AccountDeletionTargets? {
        val account = accountDao.getAccount(accountId) ?: return null
        val allTransactions = transactionDao.getAll()
        val allShortcuts = shortcutDao.getAll()
        val allCases = advanceDao.getAllCasesWithDetails()

        val advanceCasesToDelete = allCases.filter { advanceCase ->
            advanceCase.payerAccount?.id == accountId
                || advanceCase.participants.any { it.debtAccountId == accountId }
        }
        val advanceCaseIds = advanceCasesToDelete.map { it.advanceCase.id }.toSet()

        val repaymentsToRollback = allCases
            .flatMap { it.repayments }
            .filter { repayment ->
                repayment.receivedAccountId == accountId && repayment.advanceCaseId !in advanceCaseIds
            }

        val protectedGroupIds = (
            advanceCasesToDelete.flatMap { advanceCase ->
                advanceCase.participants.mapNotNull { it.initialTransferGroupId } +
                    advanceCase.repayments.mapNotNull { it.linkedTransferGroupId }
            } + repaymentsToRollback.mapNotNull { it.linkedTransferGroupId }
        ).toSet()

        val protectedTransactionIds = buildSet {
            addAll(advanceCasesToDelete.mapNotNull { it.advanceCase.selfExpenseTransactionId })
            addAll(
                allTransactions.filter { transaction ->
                    transaction.transferGroupId != null && transaction.transferGroupId in protectedGroupIds
                }.map { it.id }
            )
        }

        val accountTransactions = allTransactions.filter { it.accountId == accountId }
        val directGroupIds = accountTransactions
            .mapNotNull { it.transferGroupId }
            .filterNot { protectedGroupIds.contains(it) }
            .toSet()
        val linkedTransactionIds = accountTransactions
            .filter { it.linkedTransactionId != null && it.transferGroupId == null }
            .mapNotNull { it.linkedTransactionId }
            .toSet()

        val directTransactionsToDelete = allTransactions.filter { transaction ->
            if (transaction.id in protectedTransactionIds) {
                return@filter false
            }
            when {
                transaction.transferGroupId != null -> transaction.transferGroupId in directGroupIds
                transaction.accountId == accountId -> true
                transaction.id in linkedTransactionIds -> true
                else -> false
            }
        }

        val shortcutsToDetach = allShortcuts.filter { it.accountId == accountId }
        val counts = AccountDeletionCounts(
            transactionCount = directTransactionsToDelete.size,
            advanceCaseCount = advanceCasesToDelete.size,
            participantCount = advanceCasesToDelete.sumOf { it.participants.size },
            repaymentCount = advanceCasesToDelete.sumOf { it.repayments.size } + repaymentsToRollback.size,
            shortcutDetachCount = shortcutsToDetach.size
        )

        return AccountDeletionTargets(
            impact = AccountDeletionImpact(
                accountId = account.id,
                accountName = account.name,
                counts = counts
            ),
            account = account,
            advanceCasesToDelete = advanceCasesToDelete,
            repaymentsToRollback = repaymentsToRollback,
            directTransactionsToDelete = directTransactionsToDelete,
            shortcutsToDetach = shortcutsToDetach
        )
    }

    private suspend fun deleteLedgerTransferGroupLocked(groupId: UUID): LedgerDeletionResult {
        val repayment = advanceDao.getAllRepayments().firstOrNull { it.linkedTransferGroupId == groupId }
        if (repayment != null) {
            rollbackRepayments(listOf(repayment))
            syncAllBudgetHistory()
            return LedgerDeletionResult.Deleted
        }

        val isInitialAdvanceGroup = advanceDao.getAllParticipants().any { it.initialTransferGroupId == groupId }
        if (isInitialAdvanceGroup) {
            return LedgerDeletionResult.AdvanceInitialRequiresCase
        }

        val existing = transactionDao.getTransferGroup(groupId)
        existing.forEach { tx ->
            transactionDao.delete(tx.transaction)
            transactionDao.clearTransactionTags(tx.transaction.id)
        }
        syncAllBudgetHistory()
        return LedgerDeletionResult.Deleted
    }

    private suspend fun classifyTransferGroupLocked(groupId: UUID): TransferGroupClassification? {
        advanceDao.getAllRepayments()
            .firstOrNull { it.linkedTransferGroupId == groupId }
            ?.let { repayment ->
                return TransferGroupClassification(
                    semantic = TransferGroupSemantic.AdvanceRepayment,
                    advanceCaseId = repayment.advanceCaseId,
                    advanceParticipantId = repayment.participantId,
                    advanceRepaymentId = repayment.id
                )
            }

        advanceDao.getAllParticipants()
            .firstOrNull { it.initialTransferGroupId == groupId }
            ?.let { participant ->
                return TransferGroupClassification(
                    semantic = TransferGroupSemantic.AdvanceInitial,
                    advanceCaseId = participant.advanceCaseId,
                    advanceParticipantId = participant.id
                )
            }

        val group = transactionDao.getTransferGroup(groupId)
        if (group.isEmpty()) return null
        if (group.any { TransactionSemantics.isDebtForgiveness(it.transaction.note) }) {
            return TransferGroupClassification(TransferGroupSemantic.Debt)
        }
        return if (group.any { it.account?.type == AccountType.Debt }) {
            TransferGroupClassification(TransferGroupSemantic.Debt)
        } else {
            TransferGroupClassification(TransferGroupSemantic.Ordinary)
        }
    }

    private fun validateTransferReplacementDraft(draft: TransferGroupReplacementDraft) {
        require(draft.legs.any { it.side == TransferSide.Outgoing }) { "至少需要一筆轉出分錄。" }
        require(draft.legs.any { it.side == TransferSide.Incoming }) { "至少需要一筆轉入分錄。" }
        require(draft.legs.all { it.amount > BigDecimal.ZERO }) { "所有轉帳金額都必須大於 0。" }
        require(draft.legs.all { it.currencyCode.isNotBlank() }) { "所有轉帳分錄都必須有幣種。" }

        TransferSide.values().forEach { side ->
            val sideLegs = draft.legs.filter { it.side == side }
            val uniqueIdentities = sideLegs
                .map { it.accountId to it.currencyCode.trim().uppercase() }
                .toSet()
            require(uniqueIdentities.size == sideLegs.size) {
                "同一方向不可重複使用相同帳戶及幣種。"
            }
        }
    }

    private fun validateTransferSemantic(
        semantic: TransferGroupSemantic,
        existing: List<TransactionWithDetails>,
        desired: List<ResolvedTransferReplacementLeg>
    ) {
        when (semantic) {
            TransferGroupSemantic.Ordinary -> {
                require(desired.none { it.account.type == AccountType.Debt }) {
                    "一般轉帳不可直接改成債務紀錄，請使用債務管理。"
                }
            }
            TransferGroupSemantic.Debt -> {
                require(desired.size == 2) { "債務轉帳必須保持一進一出。" }
                require(desired.count { it.account.type == AccountType.Debt } == 1) {
                    "債務轉帳必須包含一個借貸對象與一個自己的帳戶。"
                }
                val existingDebtSide = existing
                    .singleOrNull { it.account?.type == AccountType.Debt }
                    ?.transaction
                    ?.let(::effectiveTransferSide)
                val desiredDebtSide = desired.single { it.account.type == AccountType.Debt }.side
                require(existingDebtSide != null && desiredDebtSide == existingDebtSide) {
                    "不可在編輯時翻轉借入／還款方向；請建立新的債務紀錄。"
                }
            }
            TransferGroupSemantic.AdvanceInitial,
            TransferGroupSemantic.AdvanceRepayment -> {
                error("代墊關聯轉帳不可使用一般替換。")
            }
        }
    }

    private fun counterpartSummary(accounts: List<AccountEntity>): String {
        val distinct = accounts.distinctBy { it.id }
        return when (distinct.size) {
            0 -> "帳戶"
            1 -> distinct.single().name
            else -> "${distinct.size} 個帳戶"
        }
    }

    private fun effectiveTransferSide(transaction: TransactionEntity): TransferSide {
        return transaction.transferSide
            ?: if (transaction.amount < BigDecimal.ZERO) TransferSide.Outgoing else TransferSide.Incoming
    }

    private suspend fun advanceSettlementDirectionLocked(
        participant: AdvanceParticipantEntity
    ): AdvanceSettlementDirection {
        val groupId = participant.initialTransferGroupId
            ?: return AdvanceSettlementDirection.IAdvancedOthers
        val group = transactionDao.getTransferGroup(groupId)
        val outgoing = group.firstOrNull {
            effectiveTransferSide(it.transaction) == TransferSide.Outgoing
        }?.transaction ?: return AdvanceSettlementDirection.IAdvancedOthers

        return if (
            outgoing.accountId == participant.debtAccountId ||
            outgoing.note.replace(" ", "").contains("(他人代墊我")
        ) {
            AdvanceSettlementDirection.OthersAdvancedMe
        } else {
            AdvanceSettlementDirection.IAdvancedOthers
        }
    }

    private fun transferReplacementNote(
        semantic: TransferGroupSemantic,
        side: TransferSide,
        legAccount: AccountEntity,
        allLegs: List<ResolvedTransferReplacementLeg>,
        memo: String,
        ordinaryCounterpart: String
    ): String {
        if (semantic == TransferGroupSemantic.Ordinary) {
            return if (side == TransferSide.Outgoing) {
                "$memo (轉至 $ordinaryCounterpart)"
            } else {
                "$memo (來自 $ordinaryCounterpart)"
            }
        }

        val debtLeg = allLegs.single { it.account.type == AccountType.Debt }
        val ownLeg = allLegs.single { it.account.type != AccountType.Debt }
        return when {
            debtLeg.side == TransferSide.Outgoing && legAccount.type == AccountType.Debt ->
                "$memo (借入至 ${ownLeg.account.name})"
            debtLeg.side == TransferSide.Outgoing ->
                "$memo (來自 ${debtLeg.account.name})"
            side == TransferSide.Outgoing ->
                "$memo (還款給 ${debtLeg.account.name})"
            else ->
                "$memo (來自 ${ownLeg.account.name})"
        }
    }

    private suspend fun rollbackRepayments(repayments: List<AdvanceRepaymentEntity>) {
        if (repayments.isEmpty()) return

        val participantById = advanceDao.getAllParticipants().associateBy { it.id }
        val caseById = advanceDao.getAllCases().associateBy { it.id }
        val transactionByGroupId = transactionDao.getAll()
            .filter { it.transferGroupId != null }
            .groupBy { it.transferGroupId }

        val now = Instant.now()
        repayments.mapNotNull { it.linkedTransferGroupId }
            .distinct()
            .forEach { groupId ->
                deleteTransactions(transactionByGroupId[groupId].orEmpty())
            }

        repayments.mapNotNull { it.participantId }
            .distinct()
            .forEach { participantId ->
                val participant = participantById[participantId] ?: return@forEach
                val rollbackAmount = repayments
                    .filter { it.participantId == participantId }
                    .fold(BigDecimal.ZERO) { total, repayment ->
                        total + repayment.normalizedAmount
                    }
                advanceDao.upsertParticipants(
                    listOf(
                        participant.copy(
                            repaidAmount = (participant.repaidAmount - rollbackAmount).max(BigDecimal.ZERO),
                            updatedAt = now
                        )
                    )
                )
            }

        repayments.mapNotNull { it.advanceCaseId }
            .distinct()
            .forEach { caseId ->
                caseById[caseId]?.let { advanceCase ->
                    advanceDao.upsertCase(advanceCase.copy(updatedAt = now))
                }
            }

        repayments.forEach { repayment ->
            advanceDao.deleteRepayment(repayment)
        }
    }

    private suspend fun deleteAdvanceCases(cases: List<AdvanceCaseWithDetails>) {
        if (cases.isEmpty()) return

        val transactionsByGroupId = transactionDao.getAll()
            .filter { it.transferGroupId != null }
            .groupBy { it.transferGroupId }
        val transactionsById = transactionDao.getAll().associateBy { it.id }

        cases.forEach { advanceCase ->
            advanceCase.participants.forEach { participant ->
                participant.initialTransferGroupId?.let { groupId ->
                    deleteTransactions(transactionsByGroupId[groupId].orEmpty())
                }
            }

            advanceCase.repayments.forEach { repayment ->
                repayment.linkedTransferGroupId?.let { groupId ->
                    deleteTransactions(transactionsByGroupId[groupId].orEmpty())
                }
                advanceDao.deleteRepayment(repayment)
            }

            advanceCase.advanceCase.selfExpenseTransactionId?.let { transactionId ->
                transactionsById[transactionId]?.let { transaction ->
                    deleteTransactions(listOf(transaction))
                }
            }

            advanceCase.participants.forEach { participant ->
                advanceDao.deleteParticipant(participant)
            }
            advanceDao.deleteCase(advanceCase.advanceCase)
        }
    }

    private suspend fun deleteTransactions(transactions: List<TransactionEntity>) {
        transactions.forEach { transaction ->
            transactionDao.delete(transaction)
            transactionDao.clearTransactionTags(transaction.id)
        }
    }

    private fun validateOrdinaryReplacement(transaction: TransactionEntity) {
        require(transaction.amount.compareTo(BigDecimal.ZERO) != 0) {
            "交易金額不可為零。"
        }
        require(transaction.currencyCode.isNotBlank()) {
            "交易幣種不可留空。"
        }
        require(transaction.accountId != null) {
            "請選擇帳戶。"
        }
        require(transaction.type != TransactionType.Transfer) {
            "轉帳必須使用轉帳編輯流程。"
        }
        require(
            transaction.transferGroupId == null &&
                transaction.linkedTransactionId == null &&
                transaction.transferSide == null
        ) {
            "這筆交易包含轉帳或代墊關聯，必須使用對應的編輯流程。"
        }
    }

    private fun budgetHistoryKey(monthKey: String, categoryId: UUID): String {
        return "$monthKey|$categoryId"
    }

    private fun monthKeyFromInstant(instant: Instant): String {
        val date = instant.atZone(ZoneId.systemDefault()).toLocalDate()
        return "%04d-%02d".format(date.year, date.monthValue)
    }

    private fun nextRecurringDate(date: Instant, frequency: String, intervalCount: Int): Instant {
        val safeInterval = intervalCount.coerceAtLeast(1).toLong()
        val zonedDateTime = date.atZone(ZoneId.systemDefault())
        val next = when (frequency) {
            "Daily" -> zonedDateTime.plusDays(safeInterval)
            "Weekly" -> zonedDateTime.plusWeeks(safeInterval)
            else -> zonedDateTime.plusMonths(safeInterval)
        }
        return next.toInstant()
    }
}

data class TransferLeg(
    val account: AccountEntity,
    val currency: String,
    val amount: BigDecimal
)

data class AdvanceParticipantInput(
    val debtAccount: AccountEntity,
    val owedAmount: BigDecimal
)
