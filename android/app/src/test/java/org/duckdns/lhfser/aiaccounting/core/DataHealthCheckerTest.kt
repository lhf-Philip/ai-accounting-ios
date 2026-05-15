package org.duckdns.lhfser.aiaccounting.core

import org.duckdns.lhfser.aiaccounting.core.health.DataHealthChecker
import org.duckdns.lhfser.aiaccounting.core.health.DataHealthSnapshot
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.CategoryKind
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.core.model.TransferSide
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceParticipantEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceRepaymentEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

class DataHealthCheckerTest {

    private val now = Instant.parse("2026-03-23T12:00:00Z")
    private val payerAccount = AccountEntity(UUID.randomUUID(), "Wallet", "HKD", AccountType.Cash, BigDecimal.ZERO, 0, false)
    private val debtAccount = AccountEntity(UUID.randomUUID(), "Friend A", "HKD", AccountType.Debt, BigDecimal.ZERO, 1, false)
    private val receiveAccount = AccountEntity(UUID.randomUUID(), "Bank", "HKD", AccountType.Bank, BigDecimal.ZERO, 2, false)
    private val foodCategory = CategoryEntity(UUID.randomUUID(), "Food", "fork.knife", "#FF6600", CategoryKind.Expense)

    @Test
    fun validBidirectionalAdvanceMappings_doNotCreateWarnings() {
        val initialGroup = UUID.randomUUID()
        val repaymentGroup = UUID.randomUUID()
        val caseId = UUID.randomUUID()
        val participantId = UUID.randomUUID()

        val snapshot = DataHealthSnapshot(
            transactions = listOf(
                transfer(initialGroup, payerAccount.id, BigDecimal("-50"), TransferSide.Outgoing),
                transfer(initialGroup, debtAccount.id, BigDecimal("50"), TransferSide.Incoming),
                transfer(repaymentGroup, debtAccount.id, BigDecimal("-20"), TransferSide.Outgoing),
                transfer(repaymentGroup, receiveAccount.id, BigDecimal("20"), TransferSide.Incoming)
            ),
            categories = listOf(foodCategory),
            budgets = emptyList(),
            advanceCases = listOf(
                AdvanceCaseWithDetails(
                    advanceCase = AdvanceCaseEntity(
                        id = caseId,
                        title = "Dinner",
                        date = now,
                        currencyCode = "HKD",
                        myShareAmount = BigDecimal("10"),
                        note = "",
                        selfExpenseTransactionId = UUID.randomUUID(),
                        createdAt = now,
                        updatedAt = now,
                        payerAccountId = payerAccount.id,
                        expenseCategoryId = foodCategory.id
                    ),
                    payerAccount = payerAccount,
                    expenseCategory = foodCategory,
                    participants = emptyList(),
                    repayments = emptyList()
                )
            ),
            advanceParticipants = listOf(
                AdvanceParticipantEntity(
                    id = participantId,
                    name = debtAccount.name,
                    owedAmount = BigDecimal("50"),
                    repaidAmount = BigDecimal("20"),
                    initialTransferGroupId = initialGroup,
                    createdAt = now,
                    updatedAt = now,
                    advanceCaseId = caseId,
                    debtAccountId = debtAccount.id
                )
            ),
            advanceRepayments = listOf(
                AdvanceRepaymentEntity(
                    id = UUID.randomUUID(),
                    amount = BigDecimal("20"),
                    currencyCode = "HKD",
                    normalizedAmount = BigDecimal("20"),
                    date = now,
                    note = "",
                    linkedTransferGroupId = repaymentGroup,
                    createdAt = now,
                    advanceCaseId = caseId,
                    participantId = participantId,
                    receivedAccountId = receiveAccount.id
                )
            ),
            shortcuts = emptyList()
        )

        val report = DataHealthChecker.run(snapshot, now)

        assertEquals(0, report.errorCount)
        assertEquals(0, report.warningCount)
        assertTrue(report.infoCount >= 1)
    }


    @Test
    fun borrowedByMeExpenseInitialRecord_doesNotCreateWarnings() {
        val initialGroup = UUID.randomUUID()
        val caseId = UUID.randomUUID()

        val snapshot = DataHealthSnapshot(
            transactions = listOf(
                expense(initialGroup, debtAccount.id, BigDecimal("-50"), TransferSide.Outgoing)
            ),
            categories = listOf(foodCategory),
            budgets = emptyList(),
            advanceCases = listOf(
                AdvanceCaseWithDetails(
                    advanceCase = AdvanceCaseEntity(
                        id = caseId,
                        title = "Taxi",
                        date = now,
                        currencyCode = "HKD",
                        myShareAmount = BigDecimal.ZERO,
                        note = "",
                        selfExpenseTransactionId = null,
                        createdAt = now,
                        updatedAt = now,
                        payerAccountId = null,
                        expenseCategoryId = foodCategory.id
                    ),
                    payerAccount = null,
                    expenseCategory = foodCategory,
                    participants = emptyList(),
                    repayments = emptyList()
                )
            ),
            advanceParticipants = listOf(
                AdvanceParticipantEntity(
                    id = UUID.randomUUID(),
                    name = debtAccount.name,
                    owedAmount = BigDecimal("50"),
                    repaidAmount = BigDecimal.ZERO,
                    initialTransferGroupId = initialGroup,
                    createdAt = now,
                    updatedAt = now,
                    advanceCaseId = caseId,
                    debtAccountId = debtAccount.id
                )
            ),
            advanceRepayments = emptyList(),
            shortcuts = emptyList()
        )

        val report = DataHealthChecker.run(snapshot, now)

        assertEquals(0, report.errorCount)
        assertEquals(0, report.warningCount)
    }

    @Test
    fun mismatchedInitialTransferDirection_reportsWarning() {
        val initialGroup = UUID.randomUUID()
        val caseId = UUID.randomUUID()

        val snapshot = DataHealthSnapshot(
            transactions = listOf(
                transfer(initialGroup, receiveAccount.id, BigDecimal("-50"), TransferSide.Outgoing),
                transfer(initialGroup, debtAccount.id, BigDecimal("50"), TransferSide.Incoming)
            ),
            categories = listOf(foodCategory),
            budgets = emptyList(),
            advanceCases = listOf(
                AdvanceCaseWithDetails(
                    advanceCase = AdvanceCaseEntity(
                        id = caseId,
                        title = "Mismatch",
                        date = now,
                        currencyCode = "HKD",
                        myShareAmount = BigDecimal.ZERO,
                        note = "",
                        selfExpenseTransactionId = null,
                        createdAt = now,
                        updatedAt = now,
                        payerAccountId = payerAccount.id,
                        expenseCategoryId = null
                    ),
                    payerAccount = payerAccount,
                    expenseCategory = null,
                    participants = emptyList(),
                    repayments = emptyList()
                )
            ),
            advanceParticipants = listOf(
                AdvanceParticipantEntity(
                    id = UUID.randomUUID(),
                    name = debtAccount.name,
                    owedAmount = BigDecimal("50"),
                    repaidAmount = BigDecimal.ZERO,
                    initialTransferGroupId = initialGroup,
                    createdAt = now,
                    updatedAt = now,
                    advanceCaseId = caseId,
                    debtAccountId = debtAccount.id
                )
            ),
            advanceRepayments = emptyList(),
            shortcuts = emptyList()
        )

        val report = DataHealthChecker.run(snapshot, now)

        assertTrue(report.issues.any { it.title == "代墊初始轉帳方向不一致" })
    }


    private fun expense(
        groupId: UUID,
        accountId: UUID,
        amount: BigDecimal,
        side: TransferSide
    ): TransactionWithDetails {
        return TransactionWithDetails(
            transaction = TransactionEntity(
                id = UUID.randomUUID(),
                amount = amount,
                currencyCode = "HKD",
                date = now,
                note = "",
                photoPath = null,
                type = TransactionType.Expense,
                linkedTransactionId = null,
                transferGroupId = groupId,
                transferSide = side,
                createdAt = now,
                updatedAt = now,
                accountId = accountId,
                categoryId = foodCategory.id
            ),
            account = null,
            category = foodCategory,
            tags = emptyList()
        )
    }

    private fun transfer(
        groupId: UUID,
        accountId: UUID,
        amount: BigDecimal,
        side: TransferSide
    ): TransactionWithDetails {
        return TransactionWithDetails(
            transaction = TransactionEntity(
                id = UUID.randomUUID(),
                amount = amount,
                currencyCode = "HKD",
                date = now,
                note = "",
                photoPath = null,
                type = TransactionType.Transfer,
                linkedTransactionId = null,
                transferGroupId = groupId,
                transferSide = side,
                createdAt = now,
                updatedAt = now,
                accountId = accountId,
                categoryId = null
            ),
            account = null,
            category = null,
            tags = emptyList()
        )
    }
}
