package org.duckdns.lhfser.aiaccounting.data.backup

import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.CategoryKind
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.core.model.TransferSide
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

enum class BackupValidationSeverity { Info, Warning, Error }

data class BackupValidationIssue(
    val severity: BackupValidationSeverity,
    val title: String,
    val detail: String
)

data class BackupCurrencyBalance(
    val currencyCode: String,
    val amount: BigDecimal
)

data class BackupAccountBalanceReport(
    val accountId: UUID,
    val accountName: String,
    val accountType: String,
    val accountCurrency: String,
    val balances: List<BackupCurrencyBalance>
)

data class BackupValidationReport(
    val version: String,
    val timestamp: Instant,
    val counts: BackupRecordCounts,
    val accountBalances: List<BackupAccountBalanceReport>,
    val issues: List<BackupValidationIssue>
) {
    val errorCount: Int get() = issues.count { it.severity == BackupValidationSeverity.Error }
    val warningCount: Int get() = issues.count { it.severity == BackupValidationSeverity.Warning }
    val infoCount: Int get() = issues.count { it.severity == BackupValidationSeverity.Info }
    val hasBlockingIssues: Boolean get() = errorCount > 0
    val statusTitle: String
        get() = when {
            hasBlockingIssues -> "備份有嚴重問題"
            warningCount > 0 -> "備份可匯入，但有警告"
            else -> "備份看起來正常"
        }
    val statusDetail: String
        get() = when {
            hasBlockingIssues -> "請先處理錯誤，避免覆蓋目前資料後無法完整還原。"
            warningCount > 0 -> "警告不一定代表錯誤，但建議先核對帳戶餘額與關聯資料。"
            else -> "未發現明顯結構問題，可按需要匯入。"
        }
}

object BackupValidationService {
    fun validate(backup: FullBackupData): BackupValidationReport {
        val accountIds = backup.accounts.map { it.id }.toSet()
        val categoryIds = backup.categories.map { it.id }.toSet()
        val tagIds = backup.tags.map { it.id }.toSet()
        val transactionIds = backup.transactions.map { it.id }.toSet()
        val transferGroupIds = backup.transactions.mapNotNull { it.transferGroupID }.toSet()
        val advanceCases = backup.advanceCases.orEmpty()
        val participants = backup.advanceParticipants.orEmpty()
        val repayments = backup.advanceRepayments.orEmpty()
        val advanceCaseIds = advanceCases.map { it.id }.toSet()
        val participantIds = participants.map { it.id }.toSet()
        val repaymentIds = repayments.map { it.id }.toSet()
        val issues = mutableListOf<BackupValidationIssue>()

        appendDuplicateIssues("帳戶", backup.accounts.map { it.id }, issues)
        appendDuplicateIssues("分類", backup.categories.map { it.id }, issues)
        appendDuplicateIssues("標籤", backup.tags.map { it.id }, issues)
        appendDuplicateIssues("交易", backup.transactions.map { it.id }, issues)
        appendDuplicateIssues("代墊案件", advanceCases.map { it.id }, issues)
        appendDuplicateIssues("代墊對象", participants.map { it.id }, issues)
        appendDuplicateIssues("代墊還款", repayments.map { it.id }, issues)

        backup.accounts.forEach { account ->
            if (AccountType.entries.none { it.rawValue == account.type }) {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "未知帳戶類型", "帳戶「${account.name}」使用未知類型「${account.type}」，匯入時會 fallback。")
            }
        }
        backup.categories.forEach { category ->
            val kind = category.kind
            if (kind != null && CategoryKind.entries.none { it.rawValue == kind }) {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "未知分類方向", "分類「${category.name}」使用未知方向「$kind」，匯入時會 fallback。")
            }
        }
        backup.transactions.forEach { tx ->
            if (TransactionType.entries.none { it.rawValue == tx.type }) {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "未知交易類型", "交易「${tx.note}」使用未知類型「${tx.type}」，匯入時會 fallback。")
            }
            val side = tx.transferSide
            if (side != null && TransferSide.entries.none { it.rawValue == side }) {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "未知轉帳方向", "交易「${tx.note}」使用未知轉帳方向「$side」。")
            }
            val accountId = tx.accountID
            if (accountId == null) {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "交易沒有帳戶", "交易「${tx.note}」沒有帳戶，匯入後可能無法在帳戶明細顯示。")
            } else if (accountId !in accountIds) {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "交易帳戶不存在", "交易「${tx.note}」指向不存在的帳戶 $accountId。")
            }
            tx.categoryID?.takeIf { it !in categoryIds }?.let {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "交易分類不存在", "交易「${tx.note}」指向不存在的分類 $it。")
            }
            tx.tagIDs.filter { it !in tagIds }.takeIf { it.isNotEmpty() }?.let {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "交易標籤不存在", "交易「${tx.note}」有 ${it.size} 個不存在的標籤。")
            }
            tx.linkedTransactionID?.takeIf { it !in transactionIds }?.let {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "連結交易不存在", "交易「${tx.note}」連到不存在的交易 $it。")
            }
            tx.advanceCaseID?.takeIf { it !in advanceCaseIds }?.let {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "交易代墊案件不存在", "交易「${tx.note}」指向不存在的代墊案件 $it。")
            }
            tx.advanceParticipantID?.takeIf { it !in participantIds }?.let {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "交易代墊對象不存在", "交易「${tx.note}」指向不存在的代墊對象 $it。")
            }
            tx.advanceRepaymentID?.takeIf { it !in repaymentIds }?.let {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "交易代墊還款不存在", "交易「${tx.note}」指向不存在的代墊還款 $it。")
            }
            tx.advanceEntryRole?.takeIf { it !in advanceEntryRoles }?.let {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "未知代墊分錄角色", "交易「${tx.note}」使用未知代墊角色「$it」。")
            }
        }

        backup.shortcuts.forEach { shortcut ->
            if (TransactionType.entries.none { it.rawValue == shortcut.type }) {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "捷徑交易類型未知", "捷徑「${shortcut.name}」使用未知類型「${shortcut.type}」。")
            }
            shortcut.accountID?.takeIf { it !in accountIds }?.let {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "捷徑帳戶不存在", "捷徑「${shortcut.name}」指向不存在的帳戶 $it。")
            }
            shortcut.categoryID?.takeIf { it !in categoryIds }?.let {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "捷徑分類不存在", "捷徑「${shortcut.name}」指向不存在的分類 $it。")
            }
            shortcut.tagIDs.filter { it !in tagIds }.takeIf { it.isNotEmpty() }?.let {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "捷徑標籤不存在", "捷徑「${shortcut.name}」有 ${it.size} 個不存在的標籤。")
            }
        }

        backup.recurringRules.orEmpty().forEach { rule ->
            if (TransactionType.entries.none { it.rawValue == rule.type }) {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "定期記帳交易類型未知", "定期記帳「${rule.title}」使用未知類型「${rule.type}」。")
            }
            if (rule.frequency !in recurringFrequencies) {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "定期記帳頻率未知", "定期記帳「${rule.title}」使用未知頻率「${rule.frequency}」。")
            }
            rule.accountID?.takeIf { it !in accountIds }?.let { issues += BackupValidationIssue(BackupValidationSeverity.Warning, "定期記帳帳戶不存在", "定期記帳「${rule.title}」指向不存在的帳戶 $it。") }
            rule.categoryID?.takeIf { it !in categoryIds }?.let { issues += BackupValidationIssue(BackupValidationSeverity.Warning, "定期記帳分類不存在", "定期記帳「${rule.title}」指向不存在的分類 $it。") }
        }

        val recurringRuleIds = backup.recurringRules.orEmpty().map { it.id }.toSet()
        backup.recurringOccurrences.orEmpty().forEach { occurrence ->
            if (occurrence.status !in recurringOccurrenceStatuses) {
                issues += BackupValidationIssue(BackupValidationSeverity.Warning, "定期項目狀態未知", "定期項目 ${occurrence.id} 使用未知狀態「${occurrence.status}」。")
            }
            occurrence.createdTransactionID?.takeIf { it !in transactionIds }?.let { issues += BackupValidationIssue(BackupValidationSeverity.Warning, "定期項目交易不存在", "定期項目 ${occurrence.id} 指向不存在的交易 $it。") }
            occurrence.ruleID?.takeIf { it !in recurringRuleIds }?.let { issues += BackupValidationIssue(BackupValidationSeverity.Warning, "定期項目規則不存在", "定期項目 ${occurrence.id} 指向不存在的規則 $it。") }
        }

        backup.budgets.orEmpty().forEach { budget ->
            budget.categoryID?.takeIf { it !in categoryIds }?.let { issues += BackupValidationIssue(BackupValidationSeverity.Warning, "預算分類不存在", "預算 ${budget.monthKey} 指向不存在的分類 $it。") }
        }
        backup.budgetHistory.orEmpty().forEach { history ->
            if (history.categoryID !in categoryIds) issues += BackupValidationIssue(BackupValidationSeverity.Warning, "預算歷史分類不存在", "預算歷史「${history.historyKey}」指向不存在的分類 ${history.categoryID}。")
        }
        backup.budgetSettings.orEmpty().forEach { settings ->
            if (settings.carryOverMode !in budgetCarryOverModes) issues += BackupValidationIssue(BackupValidationSeverity.Warning, "預算結轉規則未知", "預算設定使用未知結轉規則「${settings.carryOverMode}」。")
            if (settings.forecastMode !in budgetForecastModes) issues += BackupValidationIssue(BackupValidationSeverity.Warning, "預算預測規則未知", "預算設定使用未知預測規則「${settings.forecastMode}」。")
        }

        advanceCases.forEach { advanceCase ->
            advanceCase.direction?.takeIf { it !in advanceDirections }?.let { issues += BackupValidationIssue(BackupValidationSeverity.Warning, "代墊方向未知", "代墊案件「${advanceCase.title}」使用未知方向「$it」。") }
            advanceCase.selfExpenseTransactionID?.takeIf { it !in transactionIds }?.let { issues += BackupValidationIssue(BackupValidationSeverity.Warning, "代墊自己份額交易不存在", "代墊案件「${advanceCase.title}」指向不存在的交易 $it。") }
            advanceCase.payerAccountID?.takeIf { it !in accountIds }?.let { issues += BackupValidationIssue(BackupValidationSeverity.Warning, "代墊付款帳戶不存在", "代墊案件「${advanceCase.title}」指向不存在的帳戶 $it。") }
            advanceCase.expenseCategoryID?.takeIf { it !in categoryIds }?.let { issues += BackupValidationIssue(BackupValidationSeverity.Warning, "代墊分類不存在", "代墊案件「${advanceCase.title}」指向不存在的分類 $it。") }
            advanceCase.tagIDs.orEmpty().filter { it !in tagIds }.takeIf { it.isNotEmpty() }?.let { issues += BackupValidationIssue(BackupValidationSeverity.Warning, "代墊標籤不存在", "代墊案件「${advanceCase.title}」有 ${it.size} 個不存在的標籤。") }
        }

        participants.forEach { participant ->
            participant.advanceCaseID?.takeIf { it !in advanceCaseIds }?.let { issues += BackupValidationIssue(BackupValidationSeverity.Warning, "代墊對象案件不存在", "代墊對象「${participant.name}」指向不存在的案件 $it。") }
            participant.debtAccountID?.takeIf { it !in accountIds }?.let { issues += BackupValidationIssue(BackupValidationSeverity.Warning, "代墊對象債務帳戶不存在", "代墊對象「${participant.name}」指向不存在的帳戶 $it。") }
            participant.initialTransferGroupID?.takeIf { it !in transferGroupIds }?.let { issues += BackupValidationIssue(BackupValidationSeverity.Warning, "代墊初始分錄不存在", "代墊對象「${participant.name}」指向不存在的轉帳群組 $it。") }
        }

        repayments.forEach { repayment ->
            repayment.advanceCaseID?.takeIf { it !in advanceCaseIds }?.let { issues += BackupValidationIssue(BackupValidationSeverity.Warning, "還款案件不存在", "還款 ${repayment.id} 指向不存在的案件 $it。") }
            repayment.participantID?.takeIf { it !in participantIds }?.let { issues += BackupValidationIssue(BackupValidationSeverity.Warning, "還款對象不存在", "還款 ${repayment.id} 指向不存在的對象 $it。") }
            repayment.receivedAccountID?.takeIf { it !in accountIds }?.let { issues += BackupValidationIssue(BackupValidationSeverity.Warning, "還款收款帳戶不存在", "還款 ${repayment.id} 指向不存在的帳戶 $it。") }
            repayment.linkedTransferGroupID?.takeIf { it !in transferGroupIds }?.let { issues += BackupValidationIssue(BackupValidationSeverity.Warning, "還款轉帳分錄不存在", "還款 ${repayment.id} 指向不存在的轉帳群組 $it。") }
        }

        val accountBalances = buildAccountBalances(backup)
        val balanceWarningAccountTypes = setOf(AccountType.Cash.rawValue, AccountType.Bank.rawValue)
        backup.accounts.filter { it.type in balanceWarningAccountTypes }.forEach { account ->
            accountBalances.firstOrNull { it.accountId == account.id }?.balances.orEmpty()
                .filter { it.amount < BigDecimal.ZERO }
                .forEach { balance ->
                    issues += BackupValidationIssue(BackupValidationSeverity.Warning, "非債務帳戶出現負數餘額", "帳戶「${account.name}」的 ${balance.currencyCode} 餘額為 ${formatDecimal(balance.amount)}。")
                }
        }
        val anomalyBalances = accountBalances.flatMap { account ->
            account.balances.filter { it.currencyCode == "JPY" && it.amount.compareTo(BigDecimal("-221")) == 0 }
                .map { "${account.accountName}：${formatDecimal(it.amount)} JPY" }
        }
        if (anomalyBalances.isNotEmpty()) {
            issues += BackupValidationIssue(BackupValidationSeverity.Warning, "找到近期異常值 -221 JPY", anomalyBalances.joinToString("\n"))
        }
        if (issues.isEmpty()) {
            issues += BackupValidationIssue(BackupValidationSeverity.Info, "未發現結構問題", "備份可用於匯入前核對。")
        }

        return BackupValidationReport(
            version = backup.version,
            timestamp = backup.timestamp,
            counts = BackupRecordCounts.fromBackup(backup),
            accountBalances = accountBalances,
            issues = issues.sortedByDescending { severityRank(it.severity) }
        )
    }

    fun buildAccountBalances(backup: FullBackupData): List<BackupAccountBalanceReport> {
        val transactionsByAccount = backup.transactions.groupBy { it.accountID }
        return backup.accounts.sortedWith(compareBy<FullBackupData.AccountCodable> { it.sortOrder }.thenBy { it.name })
            .map { account ->
                val balances = linkedMapOf<String, BigDecimal>()
                balances[account.currency] = account.baseBalance
                transactionsByAccount[account.id].orEmpty().forEach { tx ->
                    balances[tx.currencyCode] = (balances[tx.currencyCode] ?: BigDecimal.ZERO).add(tx.amount)
                }
                BackupAccountBalanceReport(
                    accountId = account.id,
                    accountName = account.name,
                    accountType = account.type,
                    accountCurrency = account.currency,
                    balances = balances.map { BackupCurrencyBalance(it.key, it.value) }.sortedBy { it.currencyCode }
                )
            }
    }

    fun formatDecimal(value: BigDecimal): String = value.stripTrailingZeros().toPlainString()

    private fun appendDuplicateIssues(label: String, ids: List<UUID>, issues: MutableList<BackupValidationIssue>) {
        ids.groupingBy { it }.eachCount().filterValues { it > 1 }.forEach { (id, count) ->
            issues += BackupValidationIssue(BackupValidationSeverity.Error, "重複${label} ID", "ID $id 在備份中出現 $count 次，覆蓋匯入可能無法完整還原。")
        }
    }

    private fun severityRank(severity: BackupValidationSeverity): Int = when (severity) {
        BackupValidationSeverity.Error -> 3
        BackupValidationSeverity.Warning -> 2
        BackupValidationSeverity.Info -> 1
    }

    private val advanceDirections = setOf("IAdvancedOthers", "OthersAdvancedMe")
    private val advanceEntryRoles = setOf("SelfExpense", "InitialAsset", "InitialDebt", "RepaymentAsset", "RepaymentDebt")
    private val recurringFrequencies = setOf("Daily", "Weekly", "Monthly")
    private val recurringOccurrenceStatuses = setOf("Pending", "Confirmed", "Skipped")
    private val budgetCarryOverModes = setOf("None", "UnusedOnly", "OverspendOnly", "NetBalance")
    private val budgetForecastModes = setOf("SpendingPace")
}
