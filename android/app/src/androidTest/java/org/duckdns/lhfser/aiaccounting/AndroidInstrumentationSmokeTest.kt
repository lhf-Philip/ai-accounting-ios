package org.duckdns.lhfser.aiaccounting

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.runBlocking
import org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.CategoryKind
import org.duckdns.lhfser.aiaccounting.data.db.AIAccountingDatabase
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceParticipantInput
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AndroidInstrumentationSmokeTest {
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
    fun repositoryAndRoomWorkOnInstrumentedDevice() = runBlocking {
        val wallet = account("Instrumented Cash", AccountType.Cash, 0)
        val friend = account("Instrumented Friend", AccountType.Debt, 1)
        val category = category("Instrumented Food")

        repository.upsertAccount(wallet)
        repository.upsertAccount(friend)
        repository.upsertCategory(category)

        val caseId = repository.createAdvanceCase(
            title = "Instrumented advance smoke",
            date = Instant.parse("2026-06-01T10:00:00Z"),
            currencyCode = "HKD",
            myShareAmount = BigDecimal("10"),
            note = "Smoke test",
            payerAccount = wallet,
            expenseCategory = category,
            tagIds = emptyList(),
            participants = listOf(AdvanceParticipantInput(friend, BigDecimal("20")))
        )

        val loaded = repository.getAdvanceCase(caseId)
        assertNotNull(loaded)
        assertEquals("Instrumented advance smoke", loaded?.advanceCase?.title)
        assertEquals(1, loaded?.participants?.size)
    }

    private fun account(name: String, type: AccountType, sortOrder: Int): AccountEntity {
        return AccountEntity(
            id = UUID.randomUUID(),
            name = name,
            currency = "HKD",
            type = type,
            baseBalance = BigDecimal.ZERO,
            sortOrder = sortOrder,
            isArchived = false
        )
    }

    private fun category(name: String): CategoryEntity {
        return CategoryEntity(
            id = UUID.randomUUID(),
            name = name,
            icon = "circle",
            colorHex = "336699",
            kind = CategoryKind.Expense
        )
    }
}
