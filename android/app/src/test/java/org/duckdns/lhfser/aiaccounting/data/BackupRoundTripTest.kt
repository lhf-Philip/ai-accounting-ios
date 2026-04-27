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
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.RecurringRuleEntity
import org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository
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
        assertEquals(0, initialReport.warningCount)

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
            assertEquals(0, secondReport.warningCount)

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
