package org.duckdns.lhfser.aiaccounting.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.runBlocking
import org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.CategoryKind
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.backup.BackupJsonAdapter
import org.duckdns.lhfser.aiaccounting.data.backup.FullBackupData
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.AIAccountingDatabase
import org.duckdns.lhfser.aiaccounting.data.db.CategoryMonthlyBudgetEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.RecurringRuleEntity
import org.duckdns.lhfser.aiaccounting.data.db.TagEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionEntity
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceParticipantInput
import org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository
import org.duckdns.lhfser.aiaccounting.data.settlement.DebtSettlementBalanceCalculator
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
class BackupRoundTripTest {

    private lateinit var database: AIAccountingDatabase
    private lateinit var repository: AccountingRepository
    private lateinit var currencyService: CurrencyService

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = buildDatabase()
        currencyService = CurrencyService(context)
        repository = AccountingRepository(database, currencyService)
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun legacyFixture_importExportReimport_preservesBidirectionalAdvanceData() = runBlocking {
        val fixtureJson = loadFixture("fixtures/legacy_bidirectional_advances.json")

        repository.importBackupJson(fixtureJson, replaceExisting = true)
        val initialReport = repository.buildDataHealthReport()
        assertEquals(0, initialReport.errorCount)
        assertEquals(1, initialReport.warningCount)
        assertTrue(initialReport.issues.any { it.title == "他人代墊我舊資料會虛增自己帳戶" })

        val exportedJson = repository.exportBackupJson()
        val exported = BackupJsonAdapter.gson.fromJson(exportedJson, FullBackupData::class.java)

        assertEquals(5, exported.accounts.size)
        assertEquals(2, exported.categories.size)
        assertEquals(16, exported.transactions.size)
        assertEquals(2, exported.advanceCases?.size)
        assertEquals(3, exported.advanceParticipants?.size)
        assertEquals(4, exported.advanceRepayments?.size)
        assertEquals(
            "Both",
            exported.categories.first { it.name == "Salary" }.kind
        )
        assertEquals(
            "0",
            exported.advanceCases?.first { it.id == UUID.fromString("88888888-8888-8888-8888-888888888882") }
                ?.myShareAmount
                ?.toPlainString()
        )

        val secondDatabase = buildDatabase()
        try {
            val secondRepository = AccountingRepository(secondDatabase, currencyService)
            secondRepository.importBackupJson(exportedJson, replaceExisting = true)

            val secondReport = secondRepository.buildDataHealthReport()
            assertEquals(0, secondReport.errorCount)
            assertEquals(1, secondReport.warningCount)
            assertTrue(secondReport.issues.any { it.title == "他人代墊我舊資料會虛增自己帳戶" })

            val dinnerCase = secondRepository.getAdvanceCase(UUID.fromString("88888888-8888-8888-8888-888888888881"))
            val taxiCase = secondRepository.getAdvanceCase(UUID.fromString("88888888-8888-8888-8888-888888888882"))

            assertNotNull(dinnerCase)
            assertNotNull(taxiCase)
            assertEquals(2, dinnerCase?.participants?.size)
            assertEquals(2, dinnerCase?.repayments?.size)
            assertEquals(1, taxiCase?.participants?.size)
            assertEquals(2, taxiCase?.repayments?.size)
        } finally {
            secondDatabase.close()
        }
    }

    @Test
    fun legacyDebtIncomeFixture_importRepairExport_reimportsCleanly() = runBlocking {
        val fixtureJson = loadFixture("fixtures/legacy_debt_income_repair.json")

        repository.importBackupJson(fixtureJson, replaceExisting = true)

        val initialReport = repository.buildDataHealthReport()
        assertTrue(initialReport.issues.any { it.title == "收入交易記到了借貸帳戶" })
        assertTrue(initialReport.issues.any { it.title == "收入捷徑綁到了借貸帳戶" })

        assertEquals(1, repository.convertAllLegacyDebtIncomeTransactions())
        assertEquals(1, repository.detachAllLegacyDebtIncomeShortcuts())

        val repairedReport = repository.buildDataHealthReport()
        assertFalse(repairedReport.issues.any { it.title == "收入交易記到了借貸帳戶" })
        assertFalse(repairedReport.issues.any { it.title == "收入捷徑綁到了借貸帳戶" })
        assertEquals(0, repairedReport.errorCount)

        val exportedJson = repository.exportBackupJson()
        val exported = BackupJsonAdapter.gson.fromJson(exportedJson, FullBackupData::class.java)

        assertEquals("Both", exported.categories.first { it.name == "Salary" }.kind)
        assertEquals(1, exported.budgetHistory?.size)
        assertNull(exported.shortcuts.first().accountID)
        assertEquals(
            "Transfer",
            exported.transactions.first { it.id == UUID.fromString("34343434-3434-3434-3434-343434343431") }.type
        )
        assertTrue(
            exported.transactions
                .first { it.id == UUID.fromString("34343434-3434-3434-3434-343434343431") }
                .note
                .contains("[免除債務]")
        )

        val secondDatabase = buildDatabase()
        try {
            val secondRepository = AccountingRepository(secondDatabase, currencyService)
            secondRepository.importBackupJson(exportedJson, replaceExisting = true)

            val secondReport = secondRepository.buildDataHealthReport()
            assertFalse(secondReport.issues.any { it.title == "收入交易記到了借貸帳戶" })
            assertFalse(secondReport.issues.any { it.title == "收入捷徑綁到了借貸帳戶" })
            assertEquals(0, secondReport.errorCount)
        } finally {
            secondDatabase.close()
        }
    }

    @Test
    fun borrowedAdvanceCreation_recordsDebtExpenseWithoutInflatingOwnAccount() = runBlocking {
        val ownAccount = AccountEntity(
            id = UUID.randomUUID(),
            name = "Wallet",
            currency = "HKD",
            type = AccountType.Cash,
            baseBalance = BigDecimal.ZERO,
            sortOrder = 0,
            isArchived = false
        )
        val debtAccount = AccountEntity(
            id = UUID.randomUUID(),
            name = "Friend A",
            currency = "HKD",
            type = AccountType.Debt,
            baseBalance = BigDecimal.ZERO,
            sortOrder = 1,
            isArchived = false
        )
        val category = CategoryEntity(
            id = UUID.randomUUID(),
            name = "Food",
            icon = "fork.knife",
            colorHex = "#FF8800",
            kind = CategoryKind.Expense
        )
        val tag = TagEntity(UUID.randomUUID(), "Dinner")
        database.accountDao().upsertAll(listOf(ownAccount, debtAccount))
        database.categoryDao().upsert(category)
        database.tagDao().upsert(tag)

        val caseId = repository.createAdvanceCase(
            title = "朋友代付晚餐",
            date = Instant.parse("2026-03-21T12:00:00Z"),
            currencyCode = "HKD",
            myShareAmount = BigDecimal.ZERO,
            note = "晚餐",
            payerAccount = null,
            expenseCategory = category,
            tagIds = listOf(tag.id),
            participants = listOf(AdvanceParticipantInput(debtAccount, BigDecimal("150"))),
            isBorrowedByMe = true
        )

        val advanceCase = checkNotNull(repository.getAdvanceCase(caseId))
        val transactions = database.transactionDao().getAllWithDetails()
        val ownAccountTransactions = transactions.filter { it.transaction.accountId == ownAccount.id }
        val debtTransactions = transactions.filter { it.transaction.accountId == debtAccount.id }
        val transactionTags = database.transactionDao().getTransactionTags()

        assertNull(advanceCase.payerAccount)
        assertEquals(BigDecimal.ZERO, advanceCase.advanceCase.myShareAmount)
        assertNull(advanceCase.advanceCase.selfExpenseTransactionId)
        assertTrue(ownAccountTransactions.isEmpty())
        assertEquals(1, debtTransactions.size)
        assertEquals(TransactionType.Expense, debtTransactions.single().transaction.type)
        assertEquals(BigDecimal("-150"), debtTransactions.single().transaction.amount)
        assertEquals(category.id, debtTransactions.single().transaction.categoryId)
        assertTrue(transactionTags.any { it.transactionId == debtTransactions.single().transaction.id && it.tagId == tag.id })

        val report = repository.buildDataHealthReport()
        assertEquals(0, report.errorCount)
        assertEquals(0, report.warningCount)
    }

    @Test
    fun mutualDebtOffset_settlesBidirectionalAdvancesWithoutTransactions() = runBlocking {
        val ownAccount = AccountEntity(
            id = UUID.randomUUID(),
            name = "Wallet",
            currency = "HKD",
            type = AccountType.Cash,
            baseBalance = BigDecimal.ZERO,
            sortOrder = 0,
            isArchived = false
        )
        val debtAccount = AccountEntity(
            id = UUID.randomUUID(),
            name = "Friend A",
            currency = "HKD",
            type = AccountType.Debt,
            baseBalance = BigDecimal.ZERO,
            sortOrder = 1,
            isArchived = false
        )
        database.accountDao().upsertAll(listOf(ownAccount, debtAccount))

        val date = Instant.parse("2026-03-21T12:00:00Z")
        val receivableCaseId = repository.createAdvanceCase(
            title = "我先付晚餐",
            date = date,
            currencyCode = "HKD",
            myShareAmount = BigDecimal.ZERO,
            note = "",
            payerAccount = ownAccount,
            expenseCategory = null,
            tagIds = emptyList(),
            participants = listOf(AdvanceParticipantInput(debtAccount, BigDecimal("100"))),
            isBorrowedByMe = false
        )
        val payableCaseId = repository.createAdvanceCase(
            title = "朋友先付車費",
            date = date.plusSeconds(60),
            currencyCode = "HKD",
            myShareAmount = BigDecimal.ZERO,
            note = "",
            payerAccount = null,
            expenseCategory = null,
            tagIds = emptyList(),
            participants = listOf(AdvanceParticipantInput(debtAccount, BigDecimal("40"))),
            isBorrowedByMe = true
        )

        val beforeTransactionCount = database.transactionDao().getAll().size
        val candidate = checkNotNull(repository.mutualDebtOffsetCandidate(debtAccount.id, "HKD"))
        assertEquals(BigDecimal("40"), candidate.amount)

        val result = repository.recordMutualDebtOffset(debtAccount.id, "HKD", date)

        assertEquals(BigDecimal("40"), result.amount)
        assertEquals(2, result.repaymentCount)
        assertEquals(beforeTransactionCount, database.transactionDao().getAll().size)

        val receivableCase = checkNotNull(repository.getAdvanceCase(receivableCaseId))
        val payableCase = checkNotNull(repository.getAdvanceCase(payableCaseId))
        assertEquals(BigDecimal("60"), receivableCase.participants.single().owedAmount - receivableCase.participants.single().repaidAmount)
        assertEquals(BigDecimal.ZERO, payableCase.participants.single().owedAmount - payableCase.participants.single().repaidAmount)

        val exported = BackupJsonAdapter.gson.fromJson(repository.exportBackupJson(), FullBackupData::class.java)
        assertEquals(2, exported.advanceRepayments?.count { it.note?.contains("[債務抵銷:") == true })

        val rollbackCount = repository.rollbackMutualDebtOffset(result.offsetGroupId)
        assertEquals(2, rollbackCount)
        val rolledBackReceivable = checkNotNull(repository.getAdvanceCase(receivableCaseId))
        val rolledBackPayable = checkNotNull(repository.getAdvanceCase(payableCaseId))
        assertEquals(BigDecimal("100"), rolledBackReceivable.participants.single().owedAmount - rolledBackReceivable.participants.single().repaidAmount)
        assertEquals(BigDecimal("40"), rolledBackPayable.participants.single().owedAmount - rolledBackPayable.participants.single().repaidAmount)
    }

    @Test
    fun crossCurrencyAdvanceRepayment_preservesActualCurrencyAndManualSettlementAmount() = runBlocking {
        val payerAccount = AccountEntity(
            id = UUID.randomUUID(),
            name = "HKD Wallet",
            currency = "HKD",
            type = AccountType.Cash,
            baseBalance = BigDecimal.ZERO,
            sortOrder = 0,
            isArchived = false
        )
        val receiveAccount = AccountEntity(
            id = UUID.randomUUID(),
            name = "CNY Wallet",
            currency = "CNY",
            type = AccountType.Cash,
            baseBalance = BigDecimal.ZERO,
            sortOrder = 1,
            isArchived = false
        )
        val debtAccount = AccountEntity(
            id = UUID.randomUUID(),
            name = "Friend A",
            currency = "HKD",
            type = AccountType.Debt,
            baseBalance = BigDecimal.ZERO,
            sortOrder = 2,
            isArchived = false
        )
        database.accountDao().upsertAll(listOf(payerAccount, receiveAccount, debtAccount))

        val date = Instant.parse("2026-03-21T12:00:00Z")
        val caseId = repository.createAdvanceCase(
            title = "晚餐代墊",
            date = date,
            currencyCode = "HKD",
            myShareAmount = BigDecimal.ZERO,
            note = "",
            payerAccount = payerAccount,
            expenseCategory = null,
            tagIds = emptyList(),
            participants = listOf(AdvanceParticipantInput(debtAccount, BigDecimal("100"))),
            isBorrowedByMe = false
        )
        val advanceCase = checkNotNull(repository.getAdvanceCase(caseId))
        val participant = advanceCase.participants.single()

        repository.recordAdvanceRepayment(
            advanceCase = advanceCase.advanceCase,
            participant = participant,
            amount = BigDecimal("90"),
            normalizedAmount = BigDecimal("100"),
            currencyCode = "CNY",
            date = date.plusSeconds(3600),
            note = "朋友用人民幣還款",
            receiveAccount = receiveAccount,
            category = null,
            tagIds = emptyList(),
            isBorrowedByMe = false
        )

        val updatedCase = checkNotNull(repository.getAdvanceCase(caseId))
        assertEquals(BigDecimal.ZERO, updatedCase.participants.single().owedAmount - updatedCase.participants.single().repaidAmount)

        val exported = BackupJsonAdapter.gson.fromJson(repository.exportBackupJson(), FullBackupData::class.java)
        val exportedRepayment = checkNotNull(exported.advanceRepayments?.single())
        assertEquals(BigDecimal("90"), exportedRepayment.amount)
        assertEquals("CNY", exportedRepayment.currencyCode)
        assertEquals(BigDecimal("100"), exportedRepayment.normalizedAmount)

        val linkedTransactions = database.transactionDao().getAll().filter { it.transferGroupId == exportedRepayment.linkedTransferGroupID }
        assertEquals(2, linkedTransactions.size)
        val incoming = checkNotNull(linkedTransactions.firstOrNull { it.accountId == receiveAccount.id })
        assertEquals(BigDecimal("90"), incoming.amount)
        assertEquals("CNY", incoming.currencyCode)
    }

    @Test
    fun crossCurrencyAdvanceRepayment_semanticDebtBalanceUsesCaseCurrencyRemainingOnly() = runBlocking {
        val payerAccount = AccountEntity(
            id = UUID.randomUUID(),
            name = "JPY Wallet",
            currency = "JPY",
            type = AccountType.Cash,
            baseBalance = BigDecimal.ZERO,
            sortOrder = 0,
            isArchived = false
        )
        val receiveAccount = AccountEntity(
            id = UUID.randomUUID(),
            name = "HKD Wallet",
            currency = "HKD",
            type = AccountType.Cash,
            baseBalance = BigDecimal.ZERO,
            sortOrder = 1,
            isArchived = false
        )
        val debtAccount = AccountEntity(
            id = UUID.randomUUID(),
            name = "Friend A",
            currency = "HKD",
            type = AccountType.Debt,
            baseBalance = BigDecimal.ZERO,
            sortOrder = 2,
            isArchived = false
        )
        database.accountDao().upsertAll(listOf(payerAccount, receiveAccount, debtAccount))

        val date = Instant.parse("2026-03-21T12:00:00Z")
        val caseId = repository.createAdvanceCase(
            title = "日本旅行代墊",
            date = date,
            currencyCode = "JPY",
            myShareAmount = BigDecimal.ZERO,
            note = "",
            payerAccount = payerAccount,
            expenseCategory = null,
            tagIds = emptyList(),
            participants = listOf(AdvanceParticipantInput(debtAccount, BigDecimal("1000"))),
            isBorrowedByMe = false
        )
        val advanceCase = checkNotNull(repository.getAdvanceCase(caseId))
        val participant = advanceCase.participants.single()

        repository.recordAdvanceRepayment(
            advanceCase = advanceCase.advanceCase,
            participant = participant,
            amount = BigDecimal("50"),
            normalizedAmount = BigDecimal("900"),
            currencyCode = "HKD",
            date = date.plusSeconds(3600),
            note = "朋友用港幣還款",
            receiveAccount = receiveAccount,
            category = null,
            tagIds = emptyList(),
            isBorrowedByMe = false
        )

        val updatedCase = checkNotNull(repository.getAdvanceCase(caseId))
        assertEquals(BigDecimal("100"), updatedCase.participants.single().owedAmount - updatedCase.participants.single().repaidAmount)

        val transactions = database.transactionDao().getAllWithDetails()
        val rawBalances = DebtSettlementBalanceCalculator.rawBalancesFor(debtAccount, transactions)
        assertEquals(BigDecimal("1000"), rawBalances.first { it.currencyCode == "JPY" }.amount)
        assertEquals(BigDecimal("-50"), rawBalances.first { it.currencyCode == "HKD" }.amount)

        val semanticBalances = DebtSettlementBalanceCalculator.balancesFor(
            debtAccount,
            transactions,
            listOf(updatedCase)
        )
        assertEquals(1, semanticBalances.size)
        assertEquals("JPY", semanticBalances.single().currencyCode)
        assertEquals(BigDecimal("100"), semanticBalances.single().amount)
    }

    @Test
    fun legacyBorrowedAdvanceRepair_removesInflatedIncomingLegAndReimportsCleanly() = runBlocking {
        val fixtureJson = loadFixture("fixtures/legacy_bidirectional_advances.json")

        repository.importBackupJson(fixtureJson, replaceExisting = true)
        val initialReport = repository.buildDataHealthReport()
        assertTrue(initialReport.issues.any { it.title == "他人代墊我舊資料會虛增自己帳戶" })

        val result = repository.repairLegacyBorrowedAdvanceAccountInflation()

        assertEquals(1, result.repairedParticipantCount)
        assertEquals(1, result.removedInflatedAccountTransactionCount)

        val repairedReport = repository.buildDataHealthReport()
        assertFalse(repairedReport.issues.any { it.title == "他人代墊我舊資料會虛增自己帳戶" })
        assertEquals(0, repairedReport.errorCount)
        assertEquals(0, repairedReport.warningCount)

        val exportedJson = repository.exportBackupJson()
        val secondDatabase = buildDatabase()
        try {
            val secondRepository = AccountingRepository(secondDatabase, currencyService)
            secondRepository.importBackupJson(exportedJson, replaceExisting = true)
            val secondReport = secondRepository.buildDataHealthReport()
            assertFalse(secondReport.issues.any { it.title == "他人代墊我舊資料會虛增自己帳戶" })
            assertEquals(0, secondReport.errorCount)
        } finally {
            secondDatabase.close()
        }
    }

    @Test
    fun sameAccountCrossCurrencyTransferAndBudgetHistory_exportReimport_preservesDataAndExcludesUiPreferences() = runBlocking {
        val accountId = UUID.fromString("aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa")
        val categoryId = UUID.fromString("bbbbbbbb-2222-2222-2222-bbbbbbbbbbbb")
        val expenseId = UUID.fromString("cccccccc-3333-3333-3333-cccccccccccc")
        val transferDate = Instant.parse("2026-03-15T12:34:00Z")
        val expenseDate = Instant.parse("2026-03-20T08:00:00Z")

        val account = AccountEntity(
            id = accountId,
            name = "Multi-currency bank",
            currency = "HKD",
            type = AccountType.Bank,
            baseBalance = BigDecimal.ZERO,
            sortOrder = 0,
            isArchived = false
        )
        val category = CategoryEntity(
            id = categoryId,
            name = "Food",
            icon = "fork.knife",
            colorHex = "#FF8800",
            kind = CategoryKind.Expense
        )
        database.accountDao().upsert(account)
        database.categoryDao().upsert(category)

        repository.createTransferOneToOne(
            from = account,
            to = account,
            amountOut = BigDecimal("100"),
            currencyOut = "HKD",
            amountIn = BigDecimal("92"),
            currencyIn = "CNY",
            date = transferDate,
            note = "同帳戶跨幣種兌換"
        )
        repository.upsertBudget(
            CategoryMonthlyBudgetEntity(
                id = UUID.randomUUID(),
                monthKey = "2026-03",
                amount = BigDecimal("3000"),
                currencyCode = "HKD",
                isEnabled = true,
                createdAt = transferDate,
                updatedAt = transferDate,
                categoryId = categoryId
            )
        )
        repository.upsertTransaction(
            TransactionEntity(
                id = expenseId,
                amount = BigDecimal("-128.50"),
                currencyCode = "HKD",
                date = expenseDate,
                note = "Budget history sample",
                photoPath = null,
                type = TransactionType.Expense,
                linkedTransactionId = null,
                transferGroupId = null,
                transferSide = null,
                createdAt = expenseDate,
                updatedAt = expenseDate,
                accountId = accountId,
                categoryId = categoryId
            ),
            tagIds = emptyList()
        )

        val exportedJson = repository.exportBackupJson()
        assertFalse(exportedJson.contains("sharedDateFilter"))
        assertFalse(exportedJson.contains("dateFilterType"))
        assertFalse(exportedJson.contains("pinLedgerControls"))

        val exported = BackupJsonAdapter.gson.fromJson(exportedJson, FullBackupData::class.java)
        val sameAccountTransfer = exported.transactions
            .filter { it.type == "Transfer" }
            .groupBy { it.transferGroupID }
            .values
            .single { it.size == 2 }
        assertEquals(setOf(accountId), sameAccountTransfer.mapNotNull { it.accountID }.toSet())
        assertEquals(setOf("HKD", "CNY"), sameAccountTransfer.map { it.currencyCode }.toSet())
        assertEquals(setOf("Outgoing", "Incoming"), sameAccountTransfer.mapNotNull { it.transferSide }.toSet())
        assertEquals(
            "128.50",
            exported.budgetHistory?.single()?.spentAmount?.setScale(2)?.toPlainString()
        )

        val secondDatabase = buildDatabase()
        try {
            val secondRepository = AccountingRepository(secondDatabase, currencyService)
            secondRepository.importBackupJson(exportedJson, replaceExisting = true)
            val roundTrip = BackupJsonAdapter.gson.fromJson(secondRepository.exportBackupJson(), FullBackupData::class.java)
            val roundTripTransfer = roundTrip.transactions
                .filter { it.type == "Transfer" }
                .groupBy { it.transferGroupID }
                .values
                .single { it.size == 2 }

            assertEquals(setOf(accountId), roundTripTransfer.mapNotNull { it.accountID }.toSet())
            assertEquals(setOf("HKD", "CNY"), roundTripTransfer.map { it.currencyCode }.toSet())
            assertEquals(
                "128.50",
                roundTrip.budgetHistory?.single()?.spentAmount?.setScale(2)?.toPlainString()
            )
        } finally {
            secondDatabase.close()
        }
    }

    @Test
    fun recurringRule_syncConfirmExport_reimportsCleanly() = runBlocking {
        val accountId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        val categoryId = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        val ruleId = UUID.fromString("cccccccc-cccc-cccc-cccc-cccccccccccc")

        database.accountDao().upsert(
            AccountEntity(
                id = accountId,
                name = "Wallet",
                currency = "HKD",
                type = AccountType.Cash,
                baseBalance = BigDecimal.ZERO,
                sortOrder = 0,
                isArchived = false
            )
        )
        database.categoryDao().upsert(
            CategoryEntity(
                id = categoryId,
                name = "Subscription",
                icon = "creditcard",
                colorHex = "#42A5F5",
                kind = CategoryKind.Expense
            )
        )
        repository.upsertRecurringRule(
            RecurringRuleEntity(
                id = ruleId,
                title = "Streaming",
                amount = BigDecimal("120"),
                currencyCode = "HKD",
                type = TransactionType.Expense,
                note = "Monthly plan",
                frequency = "Monthly",
                intervalCount = 1,
                nextDueDate = Instant.parse("2026-04-01T00:00:00Z"),
                isPaused = false,
                createdAt = Instant.parse("2026-03-01T00:00:00Z"),
                updatedAt = Instant.parse("2026-03-01T00:00:00Z"),
                accountId = accountId,
                categoryId = categoryId
            )
        )

        repository.syncDueRecurringOccurrences(Instant.parse("2026-04-27T00:00:00Z"))

        val occurrence = database.recurringDao().getAllOccurrences().single()
        assertEquals("Pending", occurrence.status)

        val transactionId = repository.confirmRecurringOccurrence(occurrence.id)
        assertNotNull(transactionId)

        val transaction = repository.getTransaction(transactionId!!)
        assertNotNull(transaction)
        assertEquals(TransactionType.Expense, transaction?.transaction?.type)
        assertEquals("-120", transaction?.transaction?.amount?.toPlainString())

        val exportedJson = repository.exportBackupJson()
        val exported = BackupJsonAdapter.gson.fromJson(exportedJson, FullBackupData::class.java)
        assertEquals("1.8", exported.version)
        assertEquals(1, exported.recurringRules?.size)
        assertEquals(1, exported.recurringOccurrences?.size)

        val secondDatabase = buildDatabase()
        try {
            val secondRepository = AccountingRepository(secondDatabase, currencyService)
            secondRepository.importBackupJson(exportedJson, replaceExisting = true)
            assertEquals(1, secondDatabase.recurringDao().getAllRules().size)
            assertEquals(1, secondDatabase.recurringDao().getAllOccurrences().size)
            assertNotNull(secondRepository.getTransaction(transactionId))
        } finally {
            secondDatabase.close()
        }
    }

    private fun buildDatabase(): AIAccountingDatabase {
        val context = ApplicationProvider.getApplicationContext<Context>()
        return Room.inMemoryDatabaseBuilder(context, AIAccountingDatabase::class.java)
            .allowMainThreadQueries()
            .build()
    }

    private fun loadFixture(path: String): String {
        return checkNotNull(javaClass.classLoader?.getResourceAsStream(path)) {
            "Missing fixture: $path"
        }.bufferedReader().use { it.readText() }
    }
}
