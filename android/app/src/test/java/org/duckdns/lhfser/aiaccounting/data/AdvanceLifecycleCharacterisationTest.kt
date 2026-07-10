package org.duckdns.lhfser.aiaccounting.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.runBlocking
import org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.CategoryKind
import org.duckdns.lhfser.aiaccounting.data.db.AIAccountingDatabase
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryMonthlyBudgetEntity
import org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceParticipantInput
import org.junit.After
import org.junit.Assert.assertEquals
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
class AdvanceLifecycleCharacterisationTest {
    private lateinit var database: AIAccountingDatabase
    private lateinit var repository: AccountingRepository

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, AIAccountingDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        repository = AccountingRepository(database, CurrencyService(context))
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun borrowedAdvanceLifecycle_keepsBudgetHistoryConsistent() = runBlocking {
        val ownAccount = account("Wallet", AccountType.Cash, 0)
        val debtAccount = account("Friend", AccountType.Debt, 1)
        val category = CategoryEntity(
            id = UUID.randomUUID(),
            name = "Dining",
            icon = "fork.knife",
            colorHex = "#123456",
            kind = CategoryKind.Expense
        )
        repository.upsertAccount(ownAccount)
        repository.upsertAccount(debtAccount)
        repository.upsertCategory(category)
        repository.upsertBudget(
            CategoryMonthlyBudgetEntity(
                id = UUID.randomUUID(),
                monthKey = "2026-06",
                amount = BigDecimal("500"),
                currencyCode = "HKD",
                isEnabled = true,
                createdAt = Instant.parse("2026-06-01T00:00:00Z"),
                updatedAt = Instant.parse("2026-06-01T00:00:00Z"),
                categoryId = category.id
            )
        )

        val caseId = repository.createAdvanceCase(
            title = "Dinner",
            date = Instant.parse("2026-06-10T10:00:00Z"),
            currencyCode = "HKD",
            myShareAmount = BigDecimal.ZERO,
            note = "",
            payerAccount = null,
            expenseCategory = category,
            tagIds = emptyList(),
            participants = listOf(AdvanceParticipantInput(debtAccount, BigDecimal("150"))),
            isBorrowedByMe = true
        )

        val createdHistory = database.budgetDao().getAllHistory().single()
        assertEquals(BigDecimal("150"), createdHistory.spentAmount)
        assertEquals(BigDecimal("350"), createdHistory.remainingAmount)
        assertEquals(
            listOf(BigDecimal("-150")),
            database.transactionDao().getAll()
                .filter { it.advanceCaseId == caseId }
                .map { it.amount }
        )

        repository.deleteAccount(debtAccount.id, deleteRelatedBookkeeping = true)

        val deletedHistory = database.budgetDao().getAllHistory().single()
        assertEquals(BigDecimal.ZERO, deletedHistory.spentAmount)
        assertEquals(BigDecimal("500"), deletedHistory.remainingAmount)
        assertNull(repository.getAdvanceCase(caseId))
        assertTrue(database.transactionDao().getAll().none { it.advanceCaseId == caseId })
    }

    private fun account(name: String, type: AccountType, order: Int): AccountEntity {
        return AccountEntity(
            id = UUID.randomUUID(),
            name = name,
            currency = "HKD",
            type = type,
            baseBalance = BigDecimal.ZERO,
            sortOrder = order,
            isArchived = false
        )
    }
}
