package org.duckdns.lhfser.aiaccounting.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.runBlocking
import org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.CategoryKind
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.db.AIAccountingDatabase
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.RecurringRuleEntity
import org.duckdns.lhfser.aiaccounting.data.db.TagEntity
import org.duckdns.lhfser.aiaccounting.data.repository.AccountEditDraft
import org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository
import org.duckdns.lhfser.aiaccounting.ui.screens.sanitizeSignedAmount
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
class EditorInvariantsTest {
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
    fun editingAccount_preservesCurrencyAndSortOrderButAllowsSignedBalance() = runBlocking {
        val account = AccountEntity(
            id = UUID.randomUUID(),
            name = "JPY bank",
            currency = "JPY",
            type = AccountType.Bank,
            baseBalance = BigDecimal("1000"),
            sortOrder = 7,
            isArchived = false
        )
        repository.upsertAccount(account)

        repository.saveAccountEdit(
            AccountEditDraft(
                accountId = account.id,
                name = "Renamed bank",
                requestedCurrency = "",
                type = AccountType.Bank,
                baseBalance = BigDecimal("-250"),
                isArchived = false
            )
        )

        val updated = repository.getAccount(account.id)
        assertEquals("Renamed bank", updated?.name)
        assertEquals("JPY", updated?.currency)
        assertEquals(7, updated?.sortOrder)
        assertEquals(BigDecimal("-250"), updated?.baseBalance)
    }

    @Test
    fun signedAmountInput_keepsOneLeadingSignAndDecimalPoint() {
        assertEquals("-250.5", sanitizeSignedAmount("--250..5"))
        assertEquals("250.5", sanitizeSignedAmount("250..5"))
        assertEquals("", sanitizeSignedAmount("-"))
    }

    @Test
    fun recurringRuleEditorData_loadsStableRuleRelationsAndTags() = runBlocking {
        val account = AccountEntity(
            id = UUID.randomUUID(),
            name = "Wallet",
            currency = "HKD",
            type = AccountType.Cash,
            baseBalance = BigDecimal.ZERO,
            sortOrder = 0,
            isArchived = false
        )
        val category = CategoryEntity(
            id = UUID.randomUUID(),
            name = "Transport",
            icon = "tram",
            colorHex = "#123456",
            kind = CategoryKind.Expense
        )
        val tag = TagEntity(UUID.randomUUID(), "Monthly")
        val rule = RecurringRuleEntity(
            id = UUID.randomUUID(),
            title = "Transit pass",
            amount = BigDecimal("500"),
            currencyCode = "HKD",
            type = TransactionType.Expense,
            note = "",
            frequency = "Monthly",
            intervalCount = 1,
            nextDueDate = Instant.parse("2026-07-01T00:00:00Z"),
            isPaused = false,
            createdAt = Instant.parse("2026-06-01T00:00:00Z"),
            updatedAt = Instant.parse("2026-06-01T00:00:00Z"),
            accountId = account.id,
            categoryId = category.id
        )
        repository.upsertAccount(account)
        repository.upsertCategory(category)
        repository.upsertTag(tag)
        repository.upsertRecurringRule(rule, listOf(tag.id))

        val editorData = repository.getRecurringRuleEditorData(rule.id)

        assertNotNull(editorData)
        assertEquals(rule, editorData?.rule)
        assertEquals(account, editorData?.account)
        assertEquals(category, editorData?.category)
        assertEquals(listOf(tag), editorData?.tags)
    }
}
