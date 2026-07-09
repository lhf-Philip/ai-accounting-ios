package org.duckdns.lhfser.aiaccounting.data

import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.backup.BackupValidationService
import org.duckdns.lhfser.aiaccounting.data.backup.BackupValidationSeverity
import org.duckdns.lhfser.aiaccounting.data.backup.FullBackupData
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

class BackupValidationServiceTest {
    @Test
    fun validate_computesPerAccountCurrencyBalancesAndNoKnownAnomaly() {
        val accountId = UUID.randomUUID()
        val backup = makeBackup(
            accounts = listOf(
                FullBackupData.AccountCodable(
                    id = accountId,
                    name = "匯豐綜合戶口",
                    currency = "HKD",
                    type = AccountType.Bank.rawValue,
                    baseBalance = BigDecimal("100"),
                    sortOrder = 0,
                    isArchived = false
                )
            ),
            transactions = listOf(
                makeTransaction(BigDecimal("50"), "HKD", accountId),
                makeTransaction(BigDecimal("629"), "JPY", accountId)
            )
        )

        val report = BackupValidationService.validate(backup)
        val account = report.accountBalances.first { it.accountId == accountId }

        assertEquals(BigDecimal("150"), account.balances.first { it.currencyCode == "HKD" }.amount)
        assertEquals(BigDecimal("629"), account.balances.first { it.currencyCode == "JPY" }.amount)
        assertFalse(report.issues.any { it.title == "找到近期異常值 -221 JPY" })
        assertFalse(report.hasBlockingIssues)
    }

    @Test
    fun validate_flagsKnownNegativeJPYAnomaly() {
        val accountId = UUID.randomUUID()
        val backup = makeBackup(
            accounts = listOf(
                FullBackupData.AccountCodable(
                    id = accountId,
                    name = "日元戶口",
                    currency = "JPY",
                    type = AccountType.Bank.rawValue,
                    baseBalance = BigDecimal.ZERO,
                    sortOrder = 0,
                    isArchived = false
                )
            ),
            transactions = listOf(makeTransaction(BigDecimal("-221"), "JPY", accountId))
        )

        val report = BackupValidationService.validate(backup)

        assertTrue(report.issues.any { it.title == "找到近期異常值 -221 JPY" })
        assertTrue(report.issues.any { it.title == "非債務帳戶出現負數餘額" })
    }

    @Test
    fun validate_duplicateIdsAreBlocking() {
        val accountId = UUID.randomUUID()
        val backup = makeBackup(
            accounts = listOf(
                FullBackupData.AccountCodable(accountId, "A", "HKD", AccountType.Cash.rawValue, BigDecimal.ZERO, 0, false),
                FullBackupData.AccountCodable(accountId, "B", "HKD", AccountType.Cash.rawValue, BigDecimal.ZERO, 1, false)
            )
        )

        val report = BackupValidationService.validate(backup)

        assertTrue(report.hasBlockingIssues)
        assertTrue(report.issues.any { it.severity == BackupValidationSeverity.Error && it.title == "重複帳戶 ID" })
    }

    @Test
    fun validate_danglingReferencesAreWarnings() {
        val missingAccountId = UUID.randomUUID()
        val missingCategoryId = UUID.randomUUID()
        val backup = makeBackup(
            transactions = listOf(makeTransaction(BigDecimal.TEN, "HKD", missingAccountId, missingCategoryId))
        )

        val report = BackupValidationService.validate(backup)

        assertFalse(report.hasBlockingIssues)
        assertTrue(report.issues.any { it.severity == BackupValidationSeverity.Warning && it.title == "交易帳戶不存在" })
        assertTrue(report.issues.any { it.severity == BackupValidationSeverity.Warning && it.title == "交易分類不存在" })
    }

    private fun makeBackup(
        accounts: List<FullBackupData.AccountCodable> = emptyList(),
        categories: List<FullBackupData.CategoryCodable> = emptyList(),
        tags: List<FullBackupData.TagCodable> = emptyList(),
        transactions: List<FullBackupData.TransactionCodable> = emptyList()
    ): FullBackupData = FullBackupData(
        version = "1.9",
        timestamp = Instant.EPOCH,
        accounts = accounts,
        categories = categories,
        tags = tags,
        transactions = transactions,
        shortcuts = emptyList(),
        recurringRules = emptyList(),
        recurringOccurrences = emptyList(),
        budgets = emptyList(),
        budgetHistory = emptyList(),
        budgetSettings = emptyList(),
        advanceCases = emptyList(),
        advanceParticipants = emptyList(),
        advanceRepayments = emptyList()
    )

    private fun makeTransaction(
        amount: BigDecimal,
        currencyCode: String,
        accountId: UUID?,
        categoryId: UUID? = null
    ): FullBackupData.TransactionCodable = FullBackupData.TransactionCodable(
        id = UUID.randomUUID(),
        amount = amount,
        currencyCode = currencyCode,
        date = Instant.EPOCH,
        note = "Test transaction",
        type = TransactionType.Expense.rawValue,
        linkedTransactionID = null,
        transferGroupID = null,
        transferSide = null,
        photoPath = null,
        createdAt = null,
        updatedAt = null,
        accountID = accountId,
        categoryID = categoryId,
        tagIDs = emptyList(),
        advanceCaseID = null,
        advanceParticipantID = null,
        advanceRepaymentID = null,
        advanceEntryRole = null
    )
}
