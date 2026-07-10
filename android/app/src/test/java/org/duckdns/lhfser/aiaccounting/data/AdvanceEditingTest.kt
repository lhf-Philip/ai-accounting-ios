package org.duckdns.lhfser.aiaccounting.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.runBlocking
import org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.CategoryKind
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.core.model.TransferSide
import org.duckdns.lhfser.aiaccounting.core.report.ReportAggregationRequest
import org.duckdns.lhfser.aiaccounting.core.report.ReportAggregationService
import org.duckdns.lhfser.aiaccounting.core.report.ReportConversion
import org.duckdns.lhfser.aiaccounting.core.report.ReportCurrencyConverting
import org.duckdns.lhfser.aiaccounting.core.report.ReportCurrencyTotal
import org.duckdns.lhfser.aiaccounting.core.report.ReportEstimateStatus
import org.duckdns.lhfser.aiaccounting.core.report.ReportFlow
import org.duckdns.lhfser.aiaccounting.core.report.ReportGroupingMode
import org.duckdns.lhfser.aiaccounting.core.report.ReportTransactionSnapshot
import org.duckdns.lhfser.aiaccounting.data.db.AIAccountingDatabase
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.TagEntity
import org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceInitialMetadataEditDraft
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceCaseStructuralEditDraft
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceParticipantStructuralDraft
import org.duckdns.lhfser.aiaccounting.data.repository.AdvancePaymentLegStructuralDraft
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceRepaymentStructuralDraft
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceParticipantInput
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceRepaymentCreateDraft
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceRepaymentEditDraft
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceSelfExpenseEditDraft
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
class AdvanceEditingTest {
    private lateinit var database: AIAccountingDatabase
    private lateinit var repository: AccountingRepository
    private lateinit var wallet: AccountEntity
    private lateinit var bank: AccountEntity
    private lateinit var friend: AccountEntity
    private lateinit var incomeCategory: CategoryEntity
    private lateinit var expenseCategory: CategoryEntity
    private lateinit var editedTag: TagEntity

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
        incomeCategory = category("Repayment received", CategoryKind.Income)
        expenseCategory = category("Repayment paid", CategoryKind.Expense)
        editedTag = TagEntity(UUID.randomUUID(), "Edited")
        repository.upsertAccount(wallet)
        repository.upsertAccount(bank)
        repository.upsertAccount(friend)
        repository.upsertCategory(incomeCategory)
        repository.upsertCategory(expenseCategory)
        repository.upsertTag(editedTag)
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun initialEntry_supportsActualPaymentCurrencySeparateFromDebtCurrency() = runBlocking {
        val renamedDebtAccount = account("TKL", AccountType.Debt, 3)
        repository.upsertAccount(renamedDebtAccount)
        val caseId = repository.createAdvanceCase(
            title = "LUUP",
            date = Instant.parse("2026-06-10T10:00:00Z"),
            currencyCode = "JPY",
            myShareAmount = BigDecimal.ZERO,
            note = "",
            payerAccount = bank,
            expenseCategory = null,
            tagIds = emptyList(),
            participants = listOf(AdvanceParticipantInput(friend, BigDecimal("710")))
        )
        val participant = requireNotNull(repository.getAdvanceCase(caseId)).participants.single()

        repository.updateAdvanceParticipantOwedAmount(
            participantId = participant.id,
            newOwedAmount = BigDecimal("710"),
            participantName = "TKL",
            debtAccountId = renamedDebtAccount.id,
            paymentAccountId = bank.id,
            paymentAmount = BigDecimal("34.86"),
            paymentCurrencyCode = "HKD"
        )

        val group = database.transactionDao().getTransferGroup(
            requireNotNull(participant.initialTransferGroupId)
        ).map { it.transaction }
        val asset = group.single { it.advanceEntryRole == "InitialAsset" }
        val debt = group.single { it.advanceEntryRole == "InitialDebt" }
        assertEquals("-34.86", asset.amount.toPlainString())
        assertEquals("HKD", asset.currencyCode)
        assertEquals("710", debt.amount.toPlainString())
        assertEquals("JPY", debt.currencyCode)
        assertEquals(bank.id, asset.accountId)
        assertEquals(renamedDebtAccount.id, debt.accountId)
        assertEquals(caseId, asset.advanceCaseId)
        assertEquals(participant.id, debt.advanceParticipantId)
        val updatedParticipant = requireNotNull(repository.getAdvanceCase(caseId)).participants.single()
        assertEquals("TKL", updatedParticipant.name)
        assertEquals(renamedDebtAccount.id, updatedParticipant.debtAccountId)
    }

    @Test
    fun crossCurrencyRepaymentEdit_preservesExplicitSettlementAndMovesMetadataToIncomingOwnLeg() = runBlocking {
        val caseId = repository.createAdvanceCase(
            title = "Japan trip",
            date = Instant.parse("2026-06-01T10:00:00Z"),
            currencyCode = "JPY",
            myShareAmount = BigDecimal.ZERO,
            note = "",
            payerAccount = wallet,
            expenseCategory = null,
            tagIds = emptyList(),
            participants = listOf(AdvanceParticipantInput(friend, BigDecimal("2000")))
        )
        val caseData = requireNotNull(repository.getAdvanceCase(caseId))
        val participant = caseData.participants.single()
        repository.recordAdvanceRepayment(
            advanceCase = caseData.advanceCase,
            participant = participant,
            amount = BigDecimal("50"),
            normalizedAmount = BigDecimal("1000"),
            currencyCode = "HKD",
            date = Instant.parse("2026-06-02T10:00:00Z"),
            note = "First",
            receiveAccount = wallet,
            category = null,
            tagIds = emptyList()
        )
        val repayment = requireNotNull(repository.getAdvanceCase(caseId)).repayments.single()

        repository.updateAdvanceRepayment(
            AdvanceRepaymentEditDraft(
                repaymentId = repayment.id,
                receiveAccountId = bank.id,
                amount = BigDecimal("60"),
                currencyCode = "HKD",
                normalizedAmount = BigDecimal("900"),
                date = Instant.parse("2026-06-03T10:00:00Z"),
                note = "Edited",
                categoryId = incomeCategory.id,
                tagIds = listOf(editedTag.id)
            )
        )

        val updatedCase = requireNotNull(repository.getAdvanceCase(caseId))
        val updatedRepayment = updatedCase.repayments.single()
        assertEquals(BigDecimal("60"), updatedRepayment.amount)
        assertEquals(BigDecimal("900"), updatedRepayment.normalizedAmount)
        assertEquals(BigDecimal("900"), updatedCase.participants.single().repaidAmount)
        assertEquals(bank.id, updatedRepayment.receivedAccountId)

        val group = repository.getTransferGroup(requireNotNull(updatedRepayment.linkedTransferGroupId))
        val ownIncoming = group.single { it.transaction.transferSide == TransferSide.Incoming }
        val debtOutgoing = group.single { it.transaction.transferSide == TransferSide.Outgoing }
        assertEquals(bank.id, ownIncoming.transaction.accountId)
        assertEquals(incomeCategory.id, ownIncoming.transaction.categoryId)
        assertEquals(listOf(editedTag.id), ownIncoming.tags.map { it.id })
        assertEquals(null, debtOutgoing.transaction.categoryId)
        assertTrue(debtOutgoing.tags.isEmpty())
    }

    @Test
    fun othersAdvancedMeRepaymentEdit_tagsOutgoingOwnLegAndRollbackRestoresParticipant() = runBlocking {
        val caseId = repository.createAdvanceCase(
            title = "Dinner",
            date = Instant.parse("2026-06-01T10:00:00Z"),
            currencyCode = "HKD",
            myShareAmount = BigDecimal.ZERO,
            note = "",
            payerAccount = null,
            expenseCategory = expenseCategory,
            tagIds = emptyList(),
            participants = listOf(AdvanceParticipantInput(friend, BigDecimal("100"))),
            isBorrowedByMe = true
        )
        val caseData = requireNotNull(repository.getAdvanceCase(caseId))
        repository.recordAdvanceRepayment(
            advanceCase = caseData.advanceCase,
            participant = caseData.participants.single(),
            amount = BigDecimal("40"),
            normalizedAmount = BigDecimal("40"),
            currencyCode = "HKD",
            date = Instant.parse("2026-06-02T10:00:00Z"),
            note = "",
            receiveAccount = wallet,
            category = null,
            tagIds = emptyList()
        )
        val repayment = requireNotNull(repository.getAdvanceCase(caseId)).repayments.single()

        repository.updateAdvanceRepayment(
            AdvanceRepaymentEditDraft(
                repaymentId = repayment.id,
                receiveAccountId = wallet.id,
                amount = BigDecimal("35"),
                currencyCode = "HKD",
                normalizedAmount = BigDecimal("35"),
                date = Instant.parse("2026-06-03T10:00:00Z"),
                note = "Paid",
                categoryId = expenseCategory.id,
                tagIds = listOf(editedTag.id)
            )
        )

        val updatedRepayment = requireNotNull(repository.getAdvanceCase(caseId)).repayments.single()
        val groupId = requireNotNull(updatedRepayment.linkedTransferGroupId)
        val group = repository.getTransferGroup(groupId)
        val ownOutgoing = group.single { it.transaction.transferSide == TransferSide.Outgoing }
        assertEquals(wallet.id, ownOutgoing.transaction.accountId)
        assertEquals(expenseCategory.id, ownOutgoing.transaction.categoryId)
        assertEquals(listOf(editedTag.id), ownOutgoing.tags.map { it.id })

        repository.rollbackAdvanceRepayment(updatedRepayment.id)

        val rolledBack = requireNotNull(repository.getAdvanceCase(caseId))
        assertTrue(rolledBack.repayments.isEmpty())
        assertEquals(BigDecimal.ZERO, rolledBack.participants.single().repaidAmount)
        assertTrue(repository.getTransferGroup(groupId).isEmpty())
    }

    @Test
    fun participantCorrection_updatesBorrowedInitialExpenseAtomically() = runBlocking {
        val caseId = repository.createAdvanceCase(
            title = "Taxi",
            date = Instant.parse("2026-06-01T10:00:00Z"),
            currencyCode = "JPY",
            myShareAmount = BigDecimal.ZERO,
            note = "",
            payerAccount = null,
            expenseCategory = expenseCategory,
            tagIds = listOf(editedTag.id),
            participants = listOf(AdvanceParticipantInput(friend, BigDecimal("1000"))),
            isBorrowedByMe = true
        )
        val caseData = requireNotNull(repository.getAdvanceCase(caseId))
        val participant = caseData.participants.single()

        repository.updateAdvanceParticipantOwedAmount(participant.id, BigDecimal("1200"))

        val updated = requireNotNull(repository.getAdvanceCase(caseId))
        assertEquals(BigDecimal("1200"), updated.participants.single().owedAmount)
        val initial = repository.getTransferGroup(requireNotNull(participant.initialTransferGroupId)).single()
        assertEquals(TransactionType.Expense, initial.transaction.type)
        assertEquals(BigDecimal("-1200"), initial.transaction.amount)
        assertEquals("JPY", initial.transaction.currencyCode)
        assertEquals(expenseCategory.id, initial.transaction.categoryId)
        assertEquals(listOf(editedTag.id), initial.tags.map { it.id })

        val report = ReportAggregationService.aggregate(
            request = ReportAggregationRequest(
                transactions = listOf(
                    ReportTransactionSnapshot(
                        id = initial.transaction.id,
                        amount = initial.transaction.amount,
                        currencyCode = initial.transaction.currencyCode,
                        date = initial.transaction.date,
                        type = initial.transaction.type,
                        categoryId = initial.transaction.categoryId,
                        categoryName = expenseCategory.name,
                        categoryColorHex = expenseCategory.colorHex,
                        tagNames = initial.tags.map { it.name }
                    )
                ),
                flow = ReportFlow.Expense,
                grouping = ReportGroupingMode.Category
            ),
            currencyConverter = object : ReportCurrencyConverting {
                override val mainCurrency = "JPY"

                override fun estimateInMainCurrency(
                    amount: BigDecimal,
                    currencyCode: String
                ): ReportConversion? {
                    if (!currencyCode.equals(mainCurrency, ignoreCase = true)) return null
                    return ReportConversion(amount, ReportEstimateStatus.Exact)
                }
            }
        )

        val slice = report.slices.single()
        assertEquals("Repayment paid", slice.name)
        assertEquals(0, BigDecimal("1200").compareTo(slice.estimatedAmount))
        assertEquals(
            listOf(ReportCurrencyTotal("JPY", BigDecimal("1200"))),
            slice.originalCurrencyTotals
        )
        assertEquals(listOf(initial.transaction.id), slice.transactionIds)
    }

    @Test
    fun initialMetadataEdit_updatesEveryParticipantGroup() = runBlocking {
        val friendB = account("Friend B", AccountType.Debt, 3)
        repository.upsertAccount(friendB)
        val caseId = repository.createAdvanceCase(
            title = "Japan trip",
            date = Instant.parse("2026-06-01T10:00:00Z"),
            currencyCode = "JPY",
            myShareAmount = BigDecimal.ZERO,
            note = "Original",
            payerAccount = wallet,
            expenseCategory = null,
            tagIds = emptyList(),
            participants = listOf(
                AdvanceParticipantInput(friend, BigDecimal("100")),
                AdvanceParticipantInput(friendB, BigDecimal("200"))
            )
        )
        val editedDate = Instant.parse("2026-06-03T10:00:00Z")

        repository.updateAdvanceInitialMetadata(
            AdvanceInitialMetadataEditDraft(
                caseId = caseId,
                title = "Japan trip updated",
                payerAccountId = bank.id,
                date = editedDate,
                note = "Edited",
                categoryId = null,
                tagIds = emptyList()
            )
        )

        val updated = requireNotNull(repository.getAdvanceCase(caseId))
        assertEquals("Japan trip updated", updated.advanceCase.title)
        assertEquals(wallet.id, updated.advanceCase.payerAccountId)
        assertEquals(editedDate, updated.advanceCase.date)
        assertEquals("Edited", updated.advanceCase.note)
        updated.participants.forEach { participant ->
            val group = repository.getTransferGroup(requireNotNull(participant.initialTransferGroupId))
            val outgoing = group.single { it.transaction.transferSide == TransferSide.Outgoing }
            val incoming = group.single { it.transaction.transferSide == TransferSide.Incoming }
            assertEquals(wallet.id, outgoing.transaction.accountId)
            assertEquals(editedDate, outgoing.transaction.date)
            assertEquals(editedDate, incoming.transaction.date)
            assertTrue(incoming.transaction.note.contains(wallet.name))
            assertEquals(participant.owedAmount.negate(), outgoing.transaction.amount)
            assertEquals(participant.owedAmount, incoming.transaction.amount)
        }
    }

    @Test
    fun sequentialRepayments_refreshParticipantInsideTransaction() = runBlocking {
        val caseId = repository.createAdvanceCase(
            title = "Split repayment",
            date = Instant.parse("2026-06-01T10:00:00Z"),
            currencyCode = "HKD",
            myShareAmount = BigDecimal.ZERO,
            note = "",
            payerAccount = wallet,
            expenseCategory = null,
            tagIds = emptyList(),
            participants = listOf(AdvanceParticipantInput(friend, BigDecimal("100")))
        )
        val staleCase = requireNotNull(repository.getAdvanceCase(caseId))
        val staleParticipant = staleCase.participants.single()

        repository.recordAdvanceRepayment(
            advanceCase = staleCase.advanceCase,
            participant = staleParticipant,
            amount = BigDecimal("30"),
            normalizedAmount = BigDecimal("30"),
            currencyCode = "HKD",
            date = Instant.parse("2026-06-02T10:00:00Z"),
            note = "First leg",
            receiveAccount = wallet,
            category = incomeCategory,
            tagIds = emptyList()
        )
        repository.recordAdvanceRepayment(
            advanceCase = staleCase.advanceCase,
            participant = staleParticipant,
            amount = BigDecimal("40"),
            normalizedAmount = BigDecimal("40"),
            currencyCode = "HKD",
            date = Instant.parse("2026-06-02T10:01:00Z"),
            note = "Second leg",
            receiveAccount = bank,
            category = incomeCategory,
            tagIds = emptyList()
        )

        val updated = requireNotNull(repository.getAdvanceCase(caseId))
        assertEquals(BigDecimal("70"), updated.participants.single().repaidAmount)
        assertEquals(2, updated.repayments.size)
    }

    @Test
    fun repaymentBatch_rollsBackEveryLegWhenOneLegIsInvalid() = runBlocking {
        val caseId = repository.createAdvanceCase(
            title = "Atomic split repayment",
            date = Instant.parse("2026-06-01T10:00:00Z"),
            currencyCode = "HKD",
            myShareAmount = BigDecimal.ZERO,
            note = "",
            payerAccount = wallet,
            expenseCategory = null,
            tagIds = emptyList(),
            participants = listOf(AdvanceParticipantInput(friend, BigDecimal("100")))
        )
        val participant = requireNotNull(repository.getAdvanceCase(caseId)).participants.single()

        try {
            repository.recordAdvanceRepayments(
                advanceCaseId = caseId,
                participantId = participant.id,
                drafts = listOf(
                    AdvanceRepaymentCreateDraft(
                        receiveAccountId = wallet.id,
                        amount = BigDecimal("30"),
                        normalizedAmount = BigDecimal("30"),
                        currencyCode = "HKD",
                        date = Instant.parse("2026-06-02T10:00:00Z"),
                        note = "First",
                        categoryId = incomeCategory.id,
                        tagIds = emptyList()
                    ),
                    AdvanceRepaymentCreateDraft(
                        receiveAccountId = bank.id,
                        amount = BigDecimal("80"),
                        normalizedAmount = BigDecimal("80"),
                        currencyCode = "HKD",
                        date = Instant.parse("2026-06-02T10:01:00Z"),
                        note = "Second",
                        categoryId = incomeCategory.id,
                        tagIds = emptyList()
                    )
                )
            )
            fail("Expected the overpayment leg to roll back the whole batch.")
        } catch (error: IllegalArgumentException) {
            assertTrue(error.message.orEmpty().contains("超過"))
        }

        val unchanged = requireNotNull(repository.getAdvanceCase(caseId))
        assertTrue(unchanged.repayments.isEmpty())
        assertEquals(BigDecimal.ZERO, unchanged.participants.single().repaidAmount)
    }

    @Test
    fun accountDeletion_rollsBackMultipleRepaymentsForSameParticipantWithoutLeavingResidualTotal() = runBlocking {
        val caseId = repository.createAdvanceCase(
            title = "Multiple repayments",
            date = Instant.parse("2026-06-01T10:00:00Z"),
            currencyCode = "HKD",
            myShareAmount = BigDecimal.ZERO,
            note = "",
            payerAccount = wallet,
            expenseCategory = null,
            tagIds = emptyList(),
            participants = listOf(AdvanceParticipantInput(friend, BigDecimal("100")))
        )
        val caseData = requireNotNull(repository.getAdvanceCase(caseId))
        val participant = caseData.participants.single()
        repository.recordAdvanceRepayment(
            advanceCase = caseData.advanceCase,
            participant = participant,
            amount = BigDecimal("30"),
            normalizedAmount = BigDecimal("30"),
            currencyCode = "HKD",
            date = Instant.parse("2026-06-02T10:00:00Z"),
            note = "First",
            receiveAccount = bank,
            category = incomeCategory,
            tagIds = emptyList()
        )
        repository.recordAdvanceRepayment(
            advanceCase = caseData.advanceCase,
            participant = participant,
            amount = BigDecimal("40"),
            normalizedAmount = BigDecimal("40"),
            currencyCode = "HKD",
            date = Instant.parse("2026-06-02T11:00:00Z"),
            note = "Second",
            receiveAccount = bank,
            category = incomeCategory,
            tagIds = emptyList()
        )

        repository.deleteAccount(bank.id, deleteRelatedBookkeeping = true)

        val updated = requireNotNull(repository.getAdvanceCase(caseId))
        assertTrue(updated.repayments.isEmpty())
        assertEquals(BigDecimal.ZERO, updated.participants.single().repaidAmount)
    }

    @Test
    fun selfExpenseEdit_preservesActualCurrencyAndNormalizedCaseShare() = runBlocking {
        val caseId = repository.createAdvanceCase(
            title = "Japan trip",
            date = Instant.parse("2026-06-01T10:00:00Z"),
            currencyCode = "JPY",
            myShareAmount = BigDecimal("1000"),
            note = "",
            payerAccount = wallet,
            expenseCategory = expenseCategory,
            tagIds = emptyList(),
            participants = listOf(AdvanceParticipantInput(friend, BigDecimal("2000")))
        )

        repository.updateAdvanceSelfExpense(
            AdvanceSelfExpenseEditDraft(
                caseId = caseId,
                accountId = wallet.id,
                amount = BigDecimal("35.59"),
                currencyCode = "CHF",
                normalizedAmount = BigDecimal("725"),
                date = Instant.parse("2026-06-02T10:00:00Z"),
                note = "LUUP",
                categoryId = expenseCategory.id,
                tagIds = listOf(editedTag.id)
            )
        )

        val updatedCase = requireNotNull(repository.getAdvanceCase(caseId))
        val transactionId = requireNotNull(updatedCase.advanceCase.selfExpenseTransactionId)
        val transaction = requireNotNull(repository.getTransaction(transactionId))
        assertEquals(BigDecimal("-35.59"), transaction.transaction.amount)
        assertEquals("CHF", transaction.transaction.currencyCode)
        assertEquals(BigDecimal("725"), updatedCase.advanceCase.myShareAmount)
        assertEquals(expenseCategory.id, transaction.transaction.categoryId)
        assertEquals(listOf(editedTag.id), transaction.tags.map { it.id })

        val report = ReportAggregationService.aggregate(
            request = ReportAggregationRequest(
                transactions = listOf(
                    ReportTransactionSnapshot(
                        id = transaction.transaction.id,
                        amount = transaction.transaction.amount,
                        currencyCode = transaction.transaction.currencyCode,
                        date = transaction.transaction.date,
                        type = transaction.transaction.type,
                        categoryId = transaction.transaction.categoryId,
                        categoryName = expenseCategory.name,
                        categoryColorHex = expenseCategory.colorHex,
                        tagNames = transaction.tags.map { it.name }
                    )
                ),
                flow = ReportFlow.Expense,
                grouping = ReportGroupingMode.Category
            ),
            currencyConverter = object : ReportCurrencyConverting {
                override val mainCurrency = "CHF"

                override fun estimateInMainCurrency(
                    amount: BigDecimal,
                    currencyCode: String
                ): ReportConversion? {
                    if (!currencyCode.equals(mainCurrency, ignoreCase = true)) return null
                    return ReportConversion(amount, ReportEstimateStatus.Exact)
                }
            }
        )

        val slice = report.slices.single()
        assertEquals(0, BigDecimal("35.59").compareTo(slice.estimatedAmount))
        assertEquals(
            listOf(ReportCurrencyTotal("CHF", BigDecimal("35.59"))),
            slice.originalCurrencyTotals
        )
    }

    @Test
    fun repaymentEdit_rejectsCategoryForWrongSettlementDirection() = runBlocking {
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
        val caseData = requireNotNull(repository.getAdvanceCase(caseId))
        repository.recordAdvanceRepayment(
            advanceCase = caseData.advanceCase,
            participant = caseData.participants.single(),
            amount = BigDecimal("40"),
            normalizedAmount = BigDecimal("40"),
            currencyCode = "HKD",
            date = Instant.parse("2026-06-02T10:00:00Z"),
            note = "",
            receiveAccount = wallet,
            category = null,
            tagIds = emptyList()
        )
        val repayment = requireNotNull(repository.getAdvanceCase(caseId)).repayments.single()

        try {
            repository.updateAdvanceRepayment(
                AdvanceRepaymentEditDraft(
                    repaymentId = repayment.id,
                    receiveAccountId = wallet.id,
                    amount = BigDecimal("35"),
                    currencyCode = "HKD",
                    normalizedAmount = BigDecimal("35"),
                    date = Instant.parse("2026-06-03T10:00:00Z"),
                    note = "",
                    categoryId = expenseCategory.id,
                    tagIds = emptyList()
                )
            )
            fail("Expected repayment category validation to reject an expense category.")
        } catch (error: IllegalArgumentException) {
            assertTrue(error.message.orEmpty().contains("分類"))
        }

        val unchanged = requireNotNull(repository.getAdvanceCase(caseId))
        assertEquals(BigDecimal("40"), unchanged.repayments.single().amount)
        assertEquals(BigDecimal("40"), unchanged.participants.single().repaidAmount)
    }

    @Test
    fun structuralEdit_rebuildsDirectionAndRepaymentEntries() = runBlocking {
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
        val original = requireNotNull(repository.getAdvanceCase(caseId))
        repository.recordAdvanceRepayment(
            advanceCase = original.advanceCase,
            participant = original.participants.single(),
            amount = BigDecimal("40"),
            normalizedAmount = BigDecimal("40"),
            currencyCode = "HKD",
            date = Instant.parse("2026-06-02T10:00:00Z"),
            note = "Paid",
            receiveAccount = wallet,
            category = null,
            tagIds = emptyList()
        )
        val current = requireNotNull(repository.getAdvanceCase(caseId))
        val participant = current.participants.single()
        val repayment = current.repayments.single()
        val draft = AdvanceCaseStructuralEditDraft(
            caseId = caseId,
            title = "Changed",
            date = current.advanceCase.date,
            direction = org.duckdns.lhfser.aiaccounting.core.advance.AdvanceSettlementDirection.OthersAdvancedMe,
            currencyCode = "HKD",
            note = "",
            categoryId = expenseCategory.id,
            tagIds = emptyList(),
            share = null,
            participants = listOf(
                AdvanceParticipantStructuralDraft(
                    participantId = participant.id,
                    name = participant.name,
                    debtAccountId = friend.id,
                    owedAmount = BigDecimal("100"),
                    paymentLegs = emptyList()
                )
            ),
            repayments = listOf(
                AdvanceRepaymentStructuralDraft(
                    repaymentId = repayment.id,
                    receiveAccountId = wallet.id,
                    amount = BigDecimal("40"),
                    currencyCode = "HKD",
                    normalizedAmount = BigDecimal("40"),
                    date = repayment.date,
                    note = repayment.note,
                    categoryId = expenseCategory.id,
                    tagIds = emptyList()
                )
            )
        )

        val preview = repository.previewAdvanceCaseStructuralEdit(draft)
        assertTrue(preview.changesDirection)
        repository.applyAdvanceCaseStructuralEdit(draft)

        val updated = requireNotNull(repository.getAdvanceCase(caseId))
        assertEquals("OthersAdvancedMe", updated.advanceCase.direction)
        assertEquals(null, updated.advanceCase.payerAccountId)
        val initial = database.transactionDao()
            .getTransferGroup(requireNotNull(updated.participants.single().initialTransferGroupId))
            .single()
            .transaction
        assertEquals(TransactionType.Expense, initial.type)
        assertEquals(friend.id, initial.accountId)
        assertEquals("InitialDebt", initial.advanceEntryRole)
        val repaymentGroup = database.transactionDao()
            .getTransferGroup(requireNotNull(updated.repayments.single().linkedTransferGroupId))
            .map { it.transaction }
        assertEquals(
            wallet.id,
            repaymentGroup.single { it.transferSide == TransferSide.Outgoing }.accountId
        )
        assertEquals(
            friend.id,
            repaymentGroup.single { it.transferSide == TransferSide.Incoming }.accountId
        )
        assertTrue(repaymentGroup.all { it.advanceRepaymentId == repayment.id })
    }

    @Test
    fun structuralEdit_supportsSplitLegsAndNewParticipant() = runBlocking {
        val friendB = account("Friend B", AccountType.Debt, 3)
        repository.upsertAccount(friendB)
        val caseId = repository.createAdvanceCase(
            title = "Japan",
            date = Instant.parse("2026-06-01T10:00:00Z"),
            currencyCode = "JPY",
            myShareAmount = BigDecimal.ZERO,
            note = "",
            payerAccount = wallet,
            expenseCategory = null,
            tagIds = emptyList(),
            participants = listOf(AdvanceParticipantInput(friend, BigDecimal("1000")))
        )
        val current = requireNotNull(repository.getAdvanceCase(caseId))
        val participant = current.participants.single()
        val existingAsset = database.transactionDao()
            .getTransferGroup(requireNotNull(participant.initialTransferGroupId))
            .single { it.transaction.advanceEntryRole == "InitialAsset" }
            .transaction

        repository.applyAdvanceCaseStructuralEdit(
            AdvanceCaseStructuralEditDraft(
                caseId = caseId,
                title = current.advanceCase.title,
                date = current.advanceCase.date,
                direction = org.duckdns.lhfser.aiaccounting.core.advance.AdvanceSettlementDirection.IAdvancedOthers,
                currencyCode = "JPY",
                note = "",
                categoryId = null,
                tagIds = emptyList(),
                share = null,
                participants = listOf(
                    AdvanceParticipantStructuralDraft(
                        participantId = participant.id,
                        name = participant.name,
                        debtAccountId = friend.id,
                        owedAmount = BigDecimal("1200"),
                        paymentLegs = listOf(
                            AdvancePaymentLegStructuralDraft(
                                transactionId = existingAsset.id,
                                accountId = wallet.id,
                                amount = BigDecimal("500"),
                                currencyCode = "HKD"
                            ),
                            AdvancePaymentLegStructuralDraft(
                                accountId = bank.id,
                                amount = BigDecimal("30"),
                                currencyCode = "USD"
                            )
                        )
                    ),
                    AdvanceParticipantStructuralDraft(
                        name = "Friend B",
                        debtAccountId = friendB.id,
                        owedAmount = BigDecimal("800"),
                        paymentLegs = listOf(
                            AdvancePaymentLegStructuralDraft(
                                accountId = bank.id,
                                amount = BigDecimal("40"),
                                currencyCode = "USD"
                            )
                        )
                    )
                ),
                repayments = emptyList()
            )
        )

        val updated = requireNotNull(repository.getAdvanceCase(caseId))
        assertEquals(2, updated.participants.size)
        assertEquals(null, updated.advanceCase.payerAccountId)
        val updatedA = updated.participants.single { it.debtAccountId == friend.id }
        val group = database.transactionDao()
            .getTransferGroup(requireNotNull(updatedA.initialTransferGroupId))
            .map { it.transaction }
        assertEquals(3, group.size)
        assertEquals(2, group.count { it.advanceEntryRole == "InitialAsset" })
        assertEquals(
            setOf("HKD", "USD"),
            group.filter { it.advanceEntryRole == "InitialAsset" }.map { it.currencyCode }.toSet()
        )
    }

    @Test
    fun structuralEdit_invalidCurrencyAmountsRollBackWholeTransaction() = runBlocking {
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
        val initial = requireNotNull(repository.getAdvanceCase(caseId))
        repository.recordAdvanceRepayment(
            advanceCase = initial.advanceCase,
            participant = initial.participants.single(),
            amount = BigDecimal("40"),
            normalizedAmount = BigDecimal("40"),
            currencyCode = "HKD",
            date = Instant.parse("2026-06-02T10:00:00Z"),
            note = "",
            receiveAccount = wallet,
            category = null,
            tagIds = emptyList()
        )
        val current = requireNotNull(repository.getAdvanceCase(caseId))
        val participant = current.participants.single()
        val repayment = current.repayments.single()

        try {
            repository.applyAdvanceCaseStructuralEdit(
                AdvanceCaseStructuralEditDraft(
                    caseId = caseId,
                    title = current.advanceCase.title,
                    date = current.advanceCase.date,
                    direction = org.duckdns.lhfser.aiaccounting.core.advance.AdvanceSettlementDirection.IAdvancedOthers,
                    currencyCode = "JPY",
                    note = "",
                    categoryId = null,
                    tagIds = emptyList(),
                    share = null,
                    participants = listOf(
                        AdvanceParticipantStructuralDraft(
                            participantId = participant.id,
                            name = participant.name,
                            debtAccountId = friend.id,
                            owedAmount = BigDecimal("499"),
                            paymentLegs = listOf(
                                AdvancePaymentLegStructuralDraft(
                                    accountId = wallet.id,
                                    amount = BigDecimal("25"),
                                    currencyCode = "HKD"
                                )
                            )
                        )
                    ),
                    repayments = listOf(
                        AdvanceRepaymentStructuralDraft(
                            repaymentId = repayment.id,
                            receiveAccountId = wallet.id,
                            amount = BigDecimal("40"),
                            currencyCode = "HKD",
                            normalizedAmount = BigDecimal("500"),
                            date = repayment.date,
                            note = "",
                            categoryId = null,
                            tagIds = emptyList()
                        )
                    )
                )
            )
            fail("Expected invalid settled amount to reject the whole edit.")
        } catch (error: IllegalArgumentException) {
            assertTrue(error.message.orEmpty().contains("低於"))
        }

        val unchanged = requireNotNull(repository.getAdvanceCase(caseId))
        assertEquals("HKD", unchanged.advanceCase.currencyCode)
        assertEquals(BigDecimal("100"), unchanged.participants.single().owedAmount)
        assertEquals(BigDecimal("40"), unchanged.participants.single().repaidAmount)
    }

    @Test
    fun structuralEditPreview_doesNotMutateStoredCase() = runBlocking {
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
        val current = requireNotNull(repository.getAdvanceCase(caseId))
        val participant = current.participants.single()

        repository.previewAdvanceCaseStructuralEdit(
            AdvanceCaseStructuralEditDraft(
                caseId = caseId,
                title = "Changed",
                date = current.advanceCase.date,
                direction = org.duckdns.lhfser.aiaccounting.core.advance.AdvanceSettlementDirection.OthersAdvancedMe,
                currencyCode = "HKD",
                note = "Preview only",
                categoryId = expenseCategory.id,
                tagIds = listOf(editedTag.id),
                share = null,
                participants = listOf(
                    AdvanceParticipantStructuralDraft(
                        participantId = participant.id,
                        name = participant.name,
                        debtAccountId = friend.id,
                        owedAmount = BigDecimal("120"),
                        paymentLegs = emptyList()
                    )
                ),
                repayments = emptyList()
            )
        )

        val unchanged = requireNotNull(repository.getAdvanceCase(caseId))
        assertEquals("Dinner", unchanged.advanceCase.title)
        assertEquals("HKD", unchanged.advanceCase.currencyCode)
        assertEquals("IAdvancedOthers", unchanged.advanceCase.direction)
        assertEquals(BigDecimal("100"), unchanged.participants.single().owedAmount)
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

    private fun category(name: String, kind: CategoryKind): CategoryEntity {
        return CategoryEntity(
            id = UUID.randomUUID(),
            name = name,
            icon = "tag",
            colorHex = "#123456",
            kind = kind
        )
    }
}
