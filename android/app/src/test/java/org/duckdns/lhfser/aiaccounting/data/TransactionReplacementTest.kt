package org.duckdns.lhfser.aiaccounting.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.runBlocking
import org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.db.AIAccountingDatabase
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionEntity
import org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
class TransactionReplacementTest {
    private lateinit var database: AIAccountingDatabase
    private lateinit var repository: AccountingRepository
    private lateinit var account: AccountEntity

    @Before
    fun setUp() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, AIAccountingDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        repository = AccountingRepository(database, CurrencyService(context))
        account = AccountEntity(
            id = UUID.randomUUID(),
            name = "Wallet",
            currency = "HKD",
            type = AccountType.Cash,
            baseBalance = BigDecimal.ZERO,
            sortOrder = 0,
            isArchived = false
        )
        repository.upsertAccount(account)
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun replacingOrdinaryTransaction_preservesReceiptAndCreatedAt() = runBlocking {
        val transactionId = UUID.randomUUID()
        val createdAt = Instant.parse("2026-05-01T10:00:00Z")
        repository.upsertTransaction(
            transaction = ordinaryTransaction(
                id = transactionId,
                amount = BigDecimal("-725"),
                currencyCode = "JPY",
                photoPath = "/receipts/luup.jpg",
                createdAt = createdAt
            ),
            tagIds = emptyList()
        )

        repository.replaceOrdinaryTransactions(
            originalTransactionId = transactionId,
            replacements = listOf(
                ordinaryTransaction(
                    id = transactionId,
                    amount = BigDecimal("-35.59"),
                    currencyCode = "HKD",
                    photoPath = null,
                    createdAt = Instant.now()
                )
            ),
            tagIds = emptyList()
        )

        val updated = repository.getTransaction(transactionId)?.transaction
        assertNotNull(updated)
        assertEquals("/receipts/luup.jpg", updated?.photoPath)
        assertEquals(createdAt, updated?.createdAt)
        assertEquals(BigDecimal("-35.59"), updated?.amount)
        assertEquals("HKD", updated?.currencyCode)
    }

    @Test
    fun invalidReplacement_leavesOriginalTransactionUntouched() = runBlocking {
        val transactionId = UUID.randomUUID()
        val original = ordinaryTransaction(
            id = transactionId,
            amount = BigDecimal("-100"),
            currencyCode = "HKD",
            photoPath = "/receipts/original.jpg",
            createdAt = Instant.parse("2026-05-02T10:00:00Z")
        )
        repository.upsertTransaction(original, emptyList())

        assertThrows(IllegalArgumentException::class.java) {
            runBlocking {
                repository.replaceOrdinaryTransactions(
                    originalTransactionId = transactionId,
                    replacements = listOf(original.copy(amount = BigDecimal.ZERO)),
                    tagIds = emptyList()
                )
            }
        }

        assertEquals(original, repository.getTransaction(transactionId)?.transaction)
    }

    @Test
    fun splitReplacement_removesOriginalAndCreatesEveryValidatedLeg() = runBlocking {
        val transactionId = UUID.randomUUID()
        val original = ordinaryTransaction(
            id = transactionId,
            amount = BigDecimal("-100"),
            currencyCode = "HKD",
            photoPath = "/receipts/split.jpg",
            createdAt = Instant.parse("2026-05-03T10:00:00Z")
        )
        repository.upsertTransaction(original, emptyList())
        val firstID = UUID.randomUUID()
        val secondID = UUID.randomUUID()

        repository.replaceOrdinaryTransactions(
            originalTransactionId = transactionId,
            replacements = listOf(
                ordinaryTransaction(firstID, BigDecimal("-40"), "HKD"),
                ordinaryTransaction(secondID, BigDecimal("-60"), "HKD")
            ),
            tagIds = emptyList()
        )

        assertEquals(null, repository.getTransaction(transactionId))
        assertEquals("/receipts/split.jpg", repository.getTransaction(firstID)?.transaction?.photoPath)
        assertNotNull(repository.getTransaction(secondID))
    }

    private fun ordinaryTransaction(
        id: UUID,
        amount: BigDecimal,
        currencyCode: String,
        photoPath: String? = null,
        createdAt: Instant = Instant.now()
    ): TransactionEntity {
        return TransactionEntity(
            id = id,
            amount = amount,
            currencyCode = currencyCode,
            date = Instant.parse("2026-06-10T10:00:00Z"),
            note = "LUUP",
            photoPath = photoPath,
            type = TransactionType.Expense,
            linkedTransactionId = null,
            transferGroupId = null,
            transferSide = null,
            createdAt = createdAt,
            updatedAt = createdAt,
            accountId = account.id,
            categoryId = null
        )
    }
}
