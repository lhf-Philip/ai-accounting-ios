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
import org.duckdns.lhfser.aiaccounting.core.health.DataHealthChecker
import org.duckdns.lhfser.aiaccounting.core.health.DataHealthReport
import org.duckdns.lhfser.aiaccounting.core.health.DataHealthSnapshot
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.core.model.TransferSide
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceParticipantEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceRepaymentEntity
import org.duckdns.lhfser.aiaccounting.data.db.AIAccountingDatabase
import org.duckdns.lhfser.aiaccounting.data.db.BudgetDao
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryMonthlyBudgetEntity
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

class AccountingRepository(private val database: AIAccountingDatabase) {
    private val accountDao = database.accountDao()
    private val categoryDao = database.categoryDao()
    private val tagDao = database.tagDao()
    private val transactionDao = database.transactionDao()
    private val shortcutDao = database.shortcutDao()
    private val budgetDao: BudgetDao = database.budgetDao()
    private val advanceDao = database.advanceDao()

    val accounts: Flow<List<AccountEntity>> = accountDao.observeAccounts()
    val categories: Flow<List<CategoryEntity>> = categoryDao.observeCategories()
    val tags: Flow<List<TagEntity>> = tagDao.observeTags()
    val transactions: Flow<List<TransactionWithDetails>> = transactionDao.observeTransactions()
    val shortcuts: Flow<List<ShortcutWithDetails>> = shortcutDao.observeShortcuts()
    val budgets: Flow<List<CategoryMonthlyBudgetEntity>> = budgetDao.observeBudgets()
    val advanceCases: Flow<List<AdvanceCaseWithDetails>> = advanceDao.observeAdvanceCases()

    private data class AccountDeletionTargets(
        val impact: AccountDeletionImpact,
        val account: AccountEntity,
        val advanceCasesToDelete: List<AdvanceCaseWithDetails>,
        val repaymentsToRollback: List<AdvanceRepaymentEntity>,
        val directTransactionsToDelete: List<TransactionEntity>,
        val shortcutsToDetach: List<ShortcutEntity>
    )

    suspend fun getTransaction(transactionId: UUID): TransactionWithDetails? {
        return transactionDao.getTransaction(transactionId)
    }

    suspend fun getTransferGroup(groupId: UUID): List<TransactionWithDetails> {
        return transactionDao.getTransferGroup(groupId)
    }

    suspend fun getAccount(accountId: UUID): AccountEntity? {
        return accountDao.getAccount(accountId)
    }

    suspend fun getAdvanceCase(caseId: UUID): AdvanceCaseWithDetails? {
        return advanceDao.getAdvanceCase(caseId)
    }

    suspend fun buildDataHealthReport(): DataHealthReport {
        return DataHealthChecker.run(
            DataHealthSnapshot(
                transactions = transactionDao.getAllWithDetails(),
                categories = categoryDao.getAll(),
                budgets = budgetDao.getAll(),
                advanceCases = advanceDao.getAllCasesWithDetails(),
                advanceParticipants = advanceDao.getAllParticipants(),
                advanceRepayments = advanceDao.getAllRepayments()
            )
        )
    }

    suspend fun upsertAccount(account: AccountEntity) {
        accountDao.upsert(account)
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
        }
    }

    suspend fun deleteAccount(account: AccountEntity) {
        deleteAccount(account.id)
    }

    suspend fun upsertCategory(category: CategoryEntity) {
        categoryDao.upsert(category)
    }

    suspend fun deleteCategory(category: CategoryEntity) {
        categoryDao.delete(category)
    }

    suspend fun upsertTag(tag: TagEntity) {
        tagDao.upsert(tag)
    }

    suspend fun deleteTag(tag: TagEntity) {
        tagDao.delete(tag)
    }

    suspend fun upsertTransaction(transaction: TransactionEntity, tagIds: List<UUID>) {
        transactionDao.upsert(transaction)
        transactionDao.clearTransactionTags(transaction.id)
        if (tagIds.isNotEmpty()) {
            val refs = tagIds.map { tagId ->
                TransactionTagCrossRef(transactionId = transaction.id, tagId = tagId)
            }
            transactionDao.insertTransactionTags(refs)
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
        }
    }

    suspend fun deleteTransaction(transaction: TransactionEntity) {
        transactionDao.delete(transaction)
        transactionDao.clearTransactionTags(transaction.id)
    }

    suspend fun deleteTransactionById(transactionId: UUID) {
        val existing = transactionDao.getTransaction(transactionId)
        if (existing != null) {
            transactionDao.delete(existing.transaction)
            transactionDao.clearTransactionTags(transactionId)
        }
    }

    suspend fun deleteTransferGroup(groupId: UUID) {
        val existing = transactionDao.getTransferGroup(groupId)
        existing.forEach { tx ->
            transactionDao.delete(tx.transaction)
            transactionDao.clearTransactionTags(tx.transaction.id)
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

    suspend fun upsertBudget(budget: CategoryMonthlyBudgetEntity) {
        budgetDao.upsert(budget)
    }

    suspend fun deleteBudget(budget: CategoryMonthlyBudgetEntity) {
        budgetDao.delete(budget)
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
        payerAccount: AccountEntity,
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
            if (myShareAmount > BigDecimal.ZERO) {
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
                    categoryId = expenseCategory?.id
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
                payerAccountId = payerAccount.id,
                expenseCategoryId = expenseCategory?.id
            )
            advanceDao.upsertCase(advanceCase)

            val transferMemo = if (finalNote.isBlank()) finalTitle else finalNote
            val participantEntities = mutableListOf<AdvanceParticipantEntity>()
            val transferEntities = mutableListOf<TransactionEntity>()

            participants.forEach { input ->
                val transferGroupId = UUID.randomUUID()
                val outId = UUID.randomUUID()
                val inId = UUID.randomUUID()

                participantEntities.add(
                    AdvanceParticipantEntity(
                        id = UUID.randomUUID(),
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

                val outTx: TransactionEntity
                val inTx: TransactionEntity
                if (isBorrowedByMe) {
                    outTx = TransactionEntity(
                        id = outId,
                        amount = input.owedAmount.abs().negate(),
                        currencyCode = currencyCode,
                        date = date,
                        note = "$transferMemo (代墊給我 ${payerAccount.name})",
                        photoPath = null,
                        type = TransactionType.Transfer,
                        linkedTransactionId = inId,
                        transferGroupId = transferGroupId,
                        transferSide = TransferSide.Outgoing,
                        createdAt = now,
                        updatedAt = now,
                        accountId = input.debtAccount.id,
                        categoryId = null
                    )
                    inTx = TransactionEntity(
                        id = inId,
                        amount = input.owedAmount.abs(),
                        currencyCode = currencyCode,
                        date = date,
                        note = "$transferMemo (來自 ${input.debtAccount.name})",
                        photoPath = null,
                        type = TransactionType.Transfer,
                        linkedTransactionId = outId,
                        transferGroupId = transferGroupId,
                        transferSide = TransferSide.Incoming,
                        createdAt = now,
                        updatedAt = now,
                        accountId = payerAccount.id,
                        categoryId = null
                    )
                } else {
                    outTx = TransactionEntity(
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
                        accountId = payerAccount.id,
                        categoryId = null
                    )
                    inTx = TransactionEntity(
                        id = inId,
                        amount = input.owedAmount.abs(),
                        currencyCode = currencyCode,
                        date = date,
                        note = "$transferMemo (來自 ${payerAccount.name})",
                        photoPath = null,
                        type = TransactionType.Transfer,
                        linkedTransactionId = outId,
                        transferGroupId = transferGroupId,
                        transferSide = TransferSide.Incoming,
                        createdAt = now,
                        updatedAt = now,
                        accountId = input.debtAccount.id,
                        categoryId = null
                    )
                }
                transferEntities.add(outTx)
                transferEntities.add(inTx)
            }

            advanceDao.upsertParticipants(participantEntities)
            transactionDao.upsertAll(transferEntities)
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
        tagIds: List<UUID>,
        isBorrowedByMe: Boolean = false
    ) {
        database.withTransaction {
            val now = Instant.now()
            val normalized = normalizedAmount.abs()
            val transferGroupId = UUID.randomUUID()
            val outId = UUID.randomUUID()
            val inId = UUID.randomUUID()

            val transferMemo = note.trim().ifBlank { advanceCase.title }

            val outTx: TransactionEntity
            val inTx: TransactionEntity
            val taggedTxId: UUID
            if (isBorrowedByMe) {
                outTx = TransactionEntity(
                    id = outId,
                    amount = amount.abs().negate(),
                    currencyCode = currencyCode,
                    date = date,
                    note = "$transferMemo (還款給 ${participant.name})",
                    photoPath = null,
                    type = TransactionType.Transfer,
                    linkedTransactionId = inId,
                    transferGroupId = transferGroupId,
                    transferSide = TransferSide.Outgoing,
                    createdAt = now,
                    updatedAt = now,
                    accountId = receiveAccount.id,
                    categoryId = category?.id
                )
                inTx = TransactionEntity(
                    id = inId,
                    amount = amount.abs(),
                    currencyCode = currencyCode,
                    date = date,
                    note = "$transferMemo (來自 ${receiveAccount.name})",
                    photoPath = null,
                    type = TransactionType.Transfer,
                    linkedTransactionId = outId,
                    transferGroupId = transferGroupId,
                    transferSide = TransferSide.Incoming,
                    createdAt = now,
                    updatedAt = now,
                    accountId = participant.debtAccountId,
                    categoryId = null
                )
                taggedTxId = outId
            } else {
                outTx = TransactionEntity(
                    id = outId,
                    amount = amount.abs().negate(),
                    currencyCode = currencyCode,
                    date = date,
                    note = "$transferMemo (還款至 ${receiveAccount.name})",
                    photoPath = null,
                    type = TransactionType.Transfer,
                    linkedTransactionId = inId,
                    transferGroupId = transferGroupId,
                    transferSide = TransferSide.Outgoing,
                    createdAt = now,
                    updatedAt = now,
                    accountId = participant.debtAccountId,
                    categoryId = null
                )
                inTx = TransactionEntity(
                    id = inId,
                    amount = amount.abs(),
                    currencyCode = currencyCode,
                    date = date,
                    note = "$transferMemo (來自 ${participant.name})",
                    photoPath = null,
                    type = TransactionType.Transfer,
                    linkedTransactionId = outId,
                    transferGroupId = transferGroupId,
                    transferSide = TransferSide.Incoming,
                    createdAt = now,
                    updatedAt = now,
                    accountId = receiveAccount.id,
                    categoryId = category?.id
                )
                taggedTxId = inId
            }

            transactionDao.upsertAll(listOf(outTx, inTx))
            if (tagIds.isNotEmpty()) {
                transactionDao.insertTransactionTags(
                    tagIds.map { tagId -> TransactionTagCrossRef(taggedTxId, tagId) }
                )
            }

            val updatedParticipant = participant.copy(
                repaidAmount = participant.repaidAmount + normalized,
                updatedAt = now
            )
            advanceDao.upsertParticipants(listOf(updatedParticipant))
            advanceDao.upsertCase(advanceCase.copy(updatedAt = now))

            val repayment = AdvanceRepaymentEntity(
                id = UUID.randomUUID(),
                amount = amount.abs(),
                currencyCode = currencyCode,
                normalizedAmount = normalized,
                date = date,
                note = note.trim(),
                linkedTransferGroupId = transferGroupId,
                createdAt = now,
                advanceCaseId = advanceCase.id,
                participantId = participant.id,
                receivedAccountId = receiveAccount.id
            )
            advanceDao.upsertRepayment(repayment)
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
        val budgets = budgetDao.getAll()
        val advanceCases = advanceDao.getAllCases()
        val advanceParticipants = advanceDao.getAllParticipants()
        val advanceRepayments = advanceDao.getAllRepayments()

        val transactionTagMap = transactionTags.groupBy { it.transactionId }
        val shortcutTagMap = shortcutTags.groupBy { it.shortcutId }

        return FullBackupData(
            version = "1.5",
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
                    tagIDs = transactionTagMap[tx.id]?.map { it.tagId } ?: emptyList()
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
                    updatedAt = case.updatedAt
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
                categoryId = tx.categoryID
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
                expenseCategoryId = case.expenseCategoryID
            )
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
            if (budgetEntities.isNotEmpty()) {
                budgetDao.upsertAll(budgetEntities)
            }
            caseEntities.forEach { advanceDao.upsertCase(it) }
            if (participantEntities.isNotEmpty()) {
                advanceDao.upsertParticipants(participantEntities)
            }
            repaymentEntities.forEach { advanceDao.upsertRepayment(it) }
        }
    }

    private suspend fun clearAllData() {
        transactionDao.deleteAllTransactionTags()
        shortcutDao.deleteAllShortcutTags()
        advanceDao.deleteAllRepayments()
        advanceDao.deleteAllParticipants()
        advanceDao.deleteAllCases()
        budgetDao.deleteAll()
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

    private suspend fun rollbackRepayments(repayments: List<AdvanceRepaymentEntity>) {
        if (repayments.isEmpty()) return

        val participantById = advanceDao.getAllParticipants().associateBy { it.id }
        val caseById = advanceDao.getAllCases().associateBy { it.id }
        val transactionByGroupId = transactionDao.getAll()
            .filter { it.transferGroupId != null }
            .groupBy { it.transferGroupId }

        val now = Instant.now()
        repayments.forEach { repayment ->
            repayment.linkedTransferGroupId?.let { groupId ->
                deleteTransactions(transactionByGroupId[groupId].orEmpty())
            }

            repayment.participantId?.let { participantId ->
                participantById[participantId]?.let { participant ->
                    advanceDao.upsertParticipants(
                        listOf(
                            participant.copy(
                                repaidAmount = (participant.repaidAmount - repayment.normalizedAmount).max(BigDecimal.ZERO),
                                updatedAt = now
                            )
                        )
                    )
                }
            }

            repayment.advanceCaseId?.let { caseId ->
                caseById[caseId]?.let { advanceCase ->
                    advanceDao.upsertCase(advanceCase.copy(updatedAt = now))
                }
            }

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
