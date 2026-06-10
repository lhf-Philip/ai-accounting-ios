package org.duckdns.lhfser.aiaccounting.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.runBlocking
import org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.TransferSide
import org.duckdns.lhfser.aiaccounting.data.db.AIAccountingDatabase
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionEntity
import org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceParticipantInput
import org.duckdns.lhfser.aiaccounting.data.repository.TransferGroupReplacementDraft
import org.duckdns.lhfser.aiaccounting.data.repository.TransferGroupSemantic
import org.duckdns.lhfser.aiaccounting.data.repository.TransferReplacementLeg
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.ui.routing.TransactionEditDestination
import org.duckdns.lhfser.aiaccounting.ui.routing.resolveTransactionEditDestination
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
class TransferGroupReplacementTest {
    private lateinit var database: AIAccountingDatabase
    private lateinit var repository: AccountingRepository
    private lateinit var wallet: AccountEntity
    private lateinit var bank: AccountEntity
    private lateinit var friend: AccountEntity

    @Before
    fun setUp() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, AIAccountingDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        repository = AccountingRepository(database, CurrencyService(context))
        wallet = account("Wallet", AccountType.Cash, 0)
        bank = account("Bank", AccountType.Bank, 1)
        friend = account("Friend", AccountType.Debt, 2)
        repository.upsertAccount(wallet)
        repository.upsertAccount(bank)
        repository.upsertAccount(friend)
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun ordinaryReplacement_isAtomicAndPreservesGroupIdentity() = runBlocking {
        repository.createTransferOneToOne(
            from = wallet,
            to = bank,
            amountOut = BigDecimal("100"),
            currencyOut = "HKD",
            amountIn = BigDecimal("100"),
            currencyIn = "HKD",
            date = Instant.parse("2026-06-01T10:00:00Z"),
            note = "Move"
        )
        val original = database.transactionDao().getAll()
        val groupId = requireNotNull(original.first().transferGroupId)

        repository.replaceTransferGroup(
            TransferGroupReplacementDraft(
                groupId = groupId,
                date = Instant.parse("2026-06-02T10:00:00Z"),
                note = "Updated",
                legs = listOf(
                    TransferReplacementLeg(wallet.id, "HKD", BigDecimal("80"), TransferSide.Outgoing),
                    TransferReplacementLeg(bank.id, "HKD", BigDecimal("80"), TransferSide.Incoming)
                )
            )
        )

        val updated = repository.getTransferGroup(groupId)
        assertEquals(2, updated.size)
        assertEquals(setOf(groupId), updated.map { it.transaction.transferGroupId }.toSet())
        assertEquals(setOf(BigDecimal("-80"), BigDecimal("80")), updated.map { it.transaction.amount }.toSet())
    }

    @Test
    fun invalidReplacement_leavesOriginalGroupUntouched() = runBlocking {
        repository.createTransferOneToOne(
            from = wallet,
            to = bank,
            amountOut = BigDecimal("100"),
            currencyOut = "HKD",
            amountIn = BigDecimal("100"),
            currencyIn = "HKD",
            date = Instant.parse("2026-06-01T10:00:00Z"),
            note = "Move"
        )
        val original = database.transactionDao().getAll()
        val groupId = requireNotNull(original.first().transferGroupId)

        assertThrows(IllegalArgumentException::class.java) {
            runBlocking {
                repository.replaceTransferGroup(
                    TransferGroupReplacementDraft(
                        groupId = groupId,
                        date = Instant.now(),
                        note = "Invalid",
                        legs = listOf(
                            TransferReplacementLeg(wallet.id, "HKD", BigDecimal.ZERO, TransferSide.Outgoing),
                            TransferReplacementLeg(bank.id, "HKD", BigDecimal("10"), TransferSide.Incoming)
                        )
                    )
                )
            }
        }

        assertEquals(original.toSet(), database.transactionDao().getAll().toSet())
    }

    @Test
    fun debtReplacement_preservesDebtDirection() = runBlocking {
        repository.createTransferOneToOne(
            from = friend,
            to = wallet,
            amountOut = BigDecimal("100"),
            currencyOut = "HKD",
            amountIn = BigDecimal("100"),
            currencyIn = "HKD",
            date = Instant.parse("2026-06-01T10:00:00Z"),
            note = "借入"
        )
        val groupId = requireNotNull(database.transactionDao().getAll().first().transferGroupId)
        assertEquals(TransferGroupSemantic.Debt, repository.classifyTransferGroup(groupId)?.semantic)
        val destination = resolveTransactionEditDestination(
            repository,
            repository.getTransferGroup(groupId).first()
        )
        assertEquals(
            TransactionEditDestination.Debt::class,
            destination::class
        )

        assertThrows(IllegalArgumentException::class.java) {
            runBlocking {
                repository.replaceTransferGroup(
                    TransferGroupReplacementDraft(
                        groupId = groupId,
                        date = Instant.now(),
                        note = "Wrong direction",
                        legs = listOf(
                            TransferReplacementLeg(wallet.id, "HKD", BigDecimal("100"), TransferSide.Outgoing),
                            TransferReplacementLeg(friend.id, "HKD", BigDecimal("100"), TransferSide.Incoming)
                        )
                    )
                )
            }
        }

        val unchanged = repository.getTransferGroup(groupId)
        assertEquals(friend.id, unchanged.first { it.transaction.transferSide == TransferSide.Outgoing }.transaction.accountId)
    }

    @Test
    fun legacyReplacement_infersMissingSidesWithoutDuplicatingLegs() = runBlocking {
        val groupId = UUID.randomUUID()
        val outgoingId = UUID.randomUUID()
        val incomingId = UUID.randomUUID()
        val createdAt = Instant.parse("2026-06-01T10:00:00Z")
        repository.upsertTransactions(
            listOf(
                transaction(
                    id = outgoingId,
                    amount = BigDecimal("-100"),
                    accountId = wallet.id,
                    groupId = groupId,
                    linkedTransactionId = incomingId,
                    createdAt = createdAt
                ),
                transaction(
                    id = incomingId,
                    amount = BigDecimal("100"),
                    accountId = bank.id,
                    groupId = groupId,
                    linkedTransactionId = outgoingId,
                    createdAt = createdAt
                )
            )
        )

        repository.replaceTransferGroup(
            TransferGroupReplacementDraft(
                groupId = groupId,
                date = Instant.parse("2026-06-02T10:00:00Z"),
                note = "Legacy updated",
                legs = listOf(
                    TransferReplacementLeg(wallet.id, "HKD", BigDecimal("80"), TransferSide.Outgoing),
                    TransferReplacementLeg(bank.id, "HKD", BigDecimal("80"), TransferSide.Incoming)
                )
            )
        )

        val updated = repository.getTransferGroup(groupId)
        assertEquals(2, updated.size)
        assertEquals(setOf(outgoingId, incomingId), updated.map { it.transaction.id }.toSet())
        assertEquals(
            setOf(TransferSide.Outgoing, TransferSide.Incoming),
            updated.mapNotNull { it.transaction.transferSide }.toSet()
        )
    }

    @Test
    fun advanceInitialAndRepaymentGroups_areProtectedFromGenericReplacement() = runBlocking {
        val caseId = repository.createAdvanceCase(
            title = "Dinner",
            date = Instant.parse("2026-06-01T10:00:00Z"),
            currencyCode = "HKD",
            myShareAmount = BigDecimal.ZERO,
            note = "",
            payerAccount = wallet,
            expenseCategory = null,
            tagIds = emptyList(),
            participants = listOf(AdvanceParticipantInput(friend, BigDecimal("100")))
        )
        val advanceCase = requireNotNull(repository.getAdvanceCase(caseId))
        val participant = advanceCase.participants.single()
        val initialGroupId = requireNotNull(participant.initialTransferGroupId)

        assertEquals(TransferGroupSemantic.AdvanceInitial, repository.classifyTransferGroup(initialGroupId)?.semantic)
        assertEquals(
            TransactionEditDestination.Advance(caseId.toString()),
            resolveTransactionEditDestination(
                repository,
                repository.getTransferGroup(initialGroupId).first()
            )
        )
        assertProtected(initialGroupId)

        repository.recordAdvanceRepayment(
            advanceCase = advanceCase.advanceCase,
            participant = participant,
            amount = BigDecimal("40"),
            normalizedAmount = BigDecimal("40"),
            currencyCode = "HKD",
            date = Instant.parse("2026-06-03T10:00:00Z"),
            note = "",
            receiveAccount = wallet,
            category = null,
            tagIds = emptyList()
        )
        val repaymentGroupId = requireNotNull(
            repository.getAdvanceCase(caseId)?.repayments?.single()?.linkedTransferGroupId
        )
        assertEquals(TransferGroupSemantic.AdvanceRepayment, repository.classifyTransferGroup(repaymentGroupId)?.semantic)
        assertProtected(repaymentGroupId)
    }

    @Test
    fun borrowedAdvanceExpense_routesToAdvanceEditorEvenThoughItIsNotATransfer() = runBlocking {
        val caseId = repository.createAdvanceCase(
            title = "Taxi",
            date = Instant.parse("2026-06-01T10:00:00Z"),
            currencyCode = "HKD",
            myShareAmount = BigDecimal.ZERO,
            note = "",
            payerAccount = null,
            expenseCategory = null,
            tagIds = emptyList(),
            participants = listOf(AdvanceParticipantInput(friend, BigDecimal("100"))),
            isBorrowedByMe = true
        )
        val participant = requireNotNull(repository.getAdvanceCase(caseId)).participants.single()
        val initialGroupId = requireNotNull(participant.initialTransferGroupId)
        val expense = repository.getTransferGroup(initialGroupId).single()

        assertEquals(TransactionType.Expense, expense.transaction.type)
        assertEquals(
            TransactionEditDestination.Advance(caseId.toString()),
            resolveTransactionEditDestination(repository, expense)
        )
    }

    @Test
    fun advanceSelfExpense_routesToAdvanceEditor() = runBlocking {
        val caseId = repository.createAdvanceCase(
            title = "Trip",
            date = Instant.parse("2026-06-01T10:00:00Z"),
            currencyCode = "JPY",
            myShareAmount = BigDecimal("500"),
            note = "",
            payerAccount = wallet,
            expenseCategory = null,
            tagIds = emptyList(),
            participants = listOf(AdvanceParticipantInput(friend, BigDecimal("1000")))
        )
        val advanceCase = requireNotNull(repository.getAdvanceCase(caseId))
        val selfExpenseId = requireNotNull(advanceCase.advanceCase.selfExpenseTransactionId)
        val selfExpense = requireNotNull(repository.getTransaction(selfExpenseId))

        assertEquals(
            TransactionEditDestination.Advance(caseId.toString()),
            resolveTransactionEditDestination(repository, selfExpense)
        )
    }

    private fun assertProtected(groupId: UUID) {
        assertThrows(IllegalArgumentException::class.java) {
            runBlocking {
                repository.replaceTransferGroup(
                    TransferGroupReplacementDraft(
                        groupId = groupId,
                        date = Instant.now(),
                        note = "Must fail",
                        legs = listOf(
                            TransferReplacementLeg(wallet.id, "HKD", BigDecimal("10"), TransferSide.Outgoing),
                            TransferReplacementLeg(friend.id, "HKD", BigDecimal("10"), TransferSide.Incoming)
                        )
                    )
                )
            }
        }
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

    private fun transaction(
        id: UUID,
        amount: BigDecimal,
        accountId: UUID,
        groupId: UUID,
        linkedTransactionId: UUID,
        createdAt: Instant
    ): TransactionEntity {
        return TransactionEntity(
            id = id,
            amount = amount,
            currencyCode = "HKD",
            date = createdAt,
            note = "Legacy transfer",
            photoPath = null,
            type = TransactionType.Transfer,
            linkedTransactionId = linkedTransactionId,
            transferGroupId = groupId,
            transferSide = null,
            createdAt = createdAt,
            updatedAt = createdAt,
            accountId = accountId,
            categoryId = null
        )
    }
}
