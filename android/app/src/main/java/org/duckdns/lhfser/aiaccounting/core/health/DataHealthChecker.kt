package org.duckdns.lhfser.aiaccounting.core.health

import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.core.model.TransferSide
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceParticipantEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceRepaymentEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryMonthlyBudgetEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.ShortcutWithDetails
import org.duckdns.lhfser.aiaccounting.core.transactions.TransactionSemantics
import java.math.BigDecimal
import java.time.Instant
import java.util.Locale
import java.util.UUID

enum class HealthSeverity(val label: String) {
    Error("錯誤"),
    Warning("警告"),
    Info("資訊")
}

data class HealthIssue(
    val severity: HealthSeverity,
    val title: String,
    val detail: String,
    val recommendation: String
)

data class DataHealthReport(
    val generatedAt: Instant,
    val issues: List<HealthIssue>
) {
    val errorCount: Int get() = issues.count { it.severity == HealthSeverity.Error }
    val warningCount: Int get() = issues.count { it.severity == HealthSeverity.Warning }
    val infoCount: Int get() = issues.count { it.severity == HealthSeverity.Info }
}

data class DataHealthSnapshot(
    val transactions: List<TransactionWithDetails>,
    val categories: List<CategoryEntity>,
    val budgets: List<CategoryMonthlyBudgetEntity>,
    val advanceCases: List<AdvanceCaseWithDetails>,
    val advanceParticipants: List<AdvanceParticipantEntity>,
    val advanceRepayments: List<AdvanceRepaymentEntity>,
    val shortcuts: List<ShortcutWithDetails>
)

object DataHealthChecker {
    fun run(snapshot: DataHealthSnapshot, now: Instant = Instant.now()): DataHealthReport {
        val issues = mutableListOf<HealthIssue>()

        checkTransactionBasics(snapshot.transactions, now, issues)
        checkLegacyDebtIncome(snapshot.transactions, snapshot.shortcuts, issues)
        checkLinkedTransfers(snapshot.transactions, issues)
        checkTransferGroups(snapshot.transactions, issues)
        checkCategories(snapshot.categories, snapshot.transactions, snapshot.budgets, snapshot.advanceCases, issues)
        checkBudgets(snapshot.budgets, issues)
        checkAdvances(
            cases = snapshot.advanceCases,
            participants = snapshot.advanceParticipants,
            repayments = snapshot.advanceRepayments,
            transactions = snapshot.transactions,
            issues = issues
        )

        if (issues.isEmpty()) {
            issues += HealthIssue(
                severity = HealthSeverity.Info,
                title = "資料健康",
                detail = "未發現結構性問題。",
                recommendation = "維持定期 JSON 備份即可。"
            )
        }

        return DataHealthReport(
            generatedAt = now,
            issues = issues
        )
    }

    private fun checkTransactionBasics(
        transactions: List<TransactionWithDetails>,
        now: Instant,
        issues: MutableList<HealthIssue>
    ) {
        val expenseSignErrors = transactions.filter {
            it.transaction.type == TransactionType.Expense && it.transaction.amount > BigDecimal.ZERO
        }
        if (expenseSignErrors.isNotEmpty()) {
            issues += HealthIssue(
                severity = HealthSeverity.Warning,
                title = "支出金額符號異常",
                detail = "共有 ${expenseSignErrors.size} 筆支出為正數。",
                recommendation = "建議打開交易檢查金額方向，支出應為負數。"
            )
        }

        val incomeSignErrors = transactions.filter {
            it.transaction.type == TransactionType.Income && it.transaction.amount < BigDecimal.ZERO
        }
        if (incomeSignErrors.isNotEmpty()) {
            issues += HealthIssue(
                severity = HealthSeverity.Warning,
                title = "收入金額符號異常",
                detail = "共有 ${incomeSignErrors.size} 筆收入為負數。",
                recommendation = "建議打開交易檢查金額方向，收入應為正數。"
            )
        }

        val missingAccounts = transactions.filter { it.transaction.accountId == null }
        if (missingAccounts.isNotEmpty()) {
            issues += HealthIssue(
                severity = HealthSeverity.Error,
                title = "交易缺少帳戶",
                detail = "共有 ${missingAccounts.size} 筆交易沒有帳戶。",
                recommendation = "請手動補上帳戶，避免報表與餘額失真。"
            )
        }

        val emptyCurrency = transactions.filter { it.transaction.currencyCode.isBlank() }
        if (emptyCurrency.isNotEmpty()) {
            issues += HealthIssue(
                severity = HealthSeverity.Error,
                title = "交易幣種遺失",
                detail = "共有 ${emptyCurrency.size} 筆交易缺少 currencyCode。",
                recommendation = "請修正幣種後再匯出報表。"
            )
        }

        val futureTransactions = transactions.filter {
            it.transaction.date.isAfter(now.plusSeconds(60L * 60L * 24L))
        }
        if (futureTransactions.isNotEmpty()) {
            issues += HealthIssue(
                severity = HealthSeverity.Warning,
                title = "交易日期在未來",
                detail = "共有 ${futureTransactions.size} 筆交易日期晚於現在 24 小時以上。",
                recommendation = "請確認是否誤設日期。"
            )
        }
    }

    private fun checkLegacyDebtIncome(
        transactions: List<TransactionWithDetails>,
        shortcuts: List<ShortcutWithDetails>,
        issues: MutableList<HealthIssue>
    ) {
        val legacyTransactions = transactions.filter { TransactionSemantics.isLegacyDebtIncome(it) }
        if (legacyTransactions.isNotEmpty()) {
            issues += HealthIssue(
                severity = HealthSeverity.Warning,
                title = "收入交易記到了借貸帳戶",
                detail = "共有 ${legacyTransactions.size} 筆收入交易仍記在借貸帳戶，建議改為債務管理或免除債務。",
                recommendation = "請逐筆檢查這些舊資料，避免收入與債務語義混在一起。"
            )
        }

        val legacyShortcuts = shortcuts.filter { TransactionSemantics.isLegacyDebtIncome(it) }
        if (legacyShortcuts.isNotEmpty()) {
            issues += HealthIssue(
                severity = HealthSeverity.Warning,
                title = "收入捷徑綁到了借貸帳戶",
                detail = "共有 ${legacyShortcuts.size} 個收入捷徑仍綁定借貸帳戶。",
                recommendation = "建議改綁自己的帳戶，或改由債務管理入口處理。"
            )
        }
    }

    private fun checkLinkedTransfers(
        transactions: List<TransactionWithDetails>,
        issues: MutableList<HealthIssue>
    ) {
        val txById = transactions.associateBy { it.transaction.id }
        val brokenLinks = transactions.filter {
            it.transaction.type == TransactionType.Transfer &&
                it.transaction.linkedTransactionId != null &&
                txById[it.transaction.linkedTransactionId] == null
        }

        if (brokenLinks.isNotEmpty()) {
            issues += HealthIssue(
                severity = HealthSeverity.Error,
                title = "轉帳雙向連結損壞",
                detail = "共有 ${brokenLinks.size} 筆轉帳找不到 linkedTransactionID 對應記錄。",
                recommendation = "建議在『資料健康檢查』後手動修正或刪除該組轉帳。"
            )
        }
    }

    private fun checkTransferGroups(
        transactions: List<TransactionWithDetails>,
        issues: MutableList<HealthIssue>
    ) {
        val groupedTransfers = transactions
            .filter { it.transaction.type == TransactionType.Transfer && it.transaction.transferGroupId != null }
            .groupBy { it.transaction.transferGroupId!! }

        val brokenGroups = groupedTransfers.count { (_, group) ->
            val outgoingCount = group.count {
                it.transaction.transferSide == TransferSide.Outgoing || it.transaction.amount < BigDecimal.ZERO
            }
            val incomingCount = group.count {
                it.transaction.transferSide == TransferSide.Incoming || it.transaction.amount > BigDecimal.ZERO
            }
            outgoingCount == 0 || incomingCount == 0
        }

        if (brokenGroups > 0) {
            issues += HealthIssue(
                severity = HealthSeverity.Warning,
                title = "轉帳群組不完整",
                detail = "共有 $brokenGroups 個 transferGroup 缺少轉出或轉入側。",
                recommendation = "建議檢查該群組交易是否被不完整刪除。"
            )
        }
    }

    private fun checkCategories(
        categories: List<CategoryEntity>,
        transactions: List<TransactionWithDetails>,
        budgets: List<CategoryMonthlyBudgetEntity>,
        advanceCases: List<AdvanceCaseWithDetails>,
        issues: MutableList<HealthIssue>
    ) {
        val duplicates = categories
            .groupBy { "${it.name.lowercase(Locale.ROOT)}::${it.kind.rawValue}" }
            .filterValues { it.size > 1 }

        if (duplicates.isNotEmpty()) {
            val duplicateCount = duplicates.values.sumOf { it.size }
            issues += HealthIssue(
                severity = HealthSeverity.Warning,
                title = "分類重複",
                detail = "共有 $duplicateCount 個分類名稱與類型重複。",
                recommendation = "建議合併重複分類，避免預算與圖表分散。"
            )
        }

        val referencedCategoryIds = buildSet<UUID> {
            transactions.mapNotNullTo(this) { it.transaction.categoryId }
            budgets.mapNotNullTo(this) { it.categoryId }
            advanceCases.mapNotNullTo(this) { it.advanceCase.expenseCategoryId }
        }
        val unusedCategories = categories.count { it.id !in referencedCategoryIds }
        if (unusedCategories > 0) {
            issues += HealthIssue(
                severity = HealthSeverity.Info,
                title = "未使用分類",
                detail = "共有 $unusedCategories 個分類尚未被交易、預算或代墊使用。",
                recommendation = "可保留作未來使用，或清理不再需要的分類。"
            )
        }
    }

    private fun checkBudgets(
        budgets: List<CategoryMonthlyBudgetEntity>,
        issues: MutableList<HealthIssue>
    ) {
        val orphanBudgets = budgets.filter { it.categoryId == null }
        if (orphanBudgets.isNotEmpty()) {
            issues += HealthIssue(
                severity = HealthSeverity.Warning,
                title = "預算缺少分類",
                detail = "共有 ${orphanBudgets.size} 筆預算沒有綁定分類。",
                recommendation = "請為預算補上分類或刪除該筆預算。"
            )
        }

        val duplicates = budgets.groupBy { "${it.monthKey}::${it.categoryId}" }
            .filterValues { it.size > 1 }
        if (duplicates.isNotEmpty()) {
            val duplicateCount = duplicates.values.sumOf { it.size }
            issues += HealthIssue(
                severity = HealthSeverity.Warning,
                title = "月預算重複",
                detail = "共有 $duplicateCount 筆重複的「分類 + 月份」預算。",
                recommendation = "同一分類同月份建議只保留一筆，避免提醒重複。"
            )
        }
    }

    private fun checkAdvances(
        cases: List<AdvanceCaseWithDetails>,
        participants: List<AdvanceParticipantEntity>,
        repayments: List<AdvanceRepaymentEntity>,
        transactions: List<TransactionWithDetails>,
        issues: MutableList<HealthIssue>
    ) {
        val orphanParticipants = participants.filter { it.advanceCaseId == null }
        if (orphanParticipants.isNotEmpty()) {
            issues += HealthIssue(
                severity = HealthSeverity.Warning,
                title = "代墊對象缺少主檔",
                detail = "共有 ${orphanParticipants.size} 筆代墊對象未連結到代墊主檔。",
                recommendation = "請檢查備份匯入完整性，必要時重建該筆代墊。"
            )
        }

        val participantsWithoutDebtAccount = participants.filter { it.debtAccountId == null }
        if (participantsWithoutDebtAccount.isNotEmpty()) {
            issues += HealthIssue(
                severity = HealthSeverity.Warning,
                title = "代墊對象缺少借貸帳戶",
                detail = "共有 ${participantsWithoutDebtAccount.size} 位代墊對象缺少借貸帳戶連結。",
                recommendation = "建議補上借貸帳戶，避免還款入帳時無法建立轉帳。"
            )
        }

        val overRepaidParticipants = participants.filter { it.repaidAmount > it.owedAmount }
        if (overRepaidParticipants.isNotEmpty()) {
            issues += HealthIssue(
                severity = HealthSeverity.Error,
                title = "代墊對象已還金額異常",
                detail = "共有 ${overRepaidParticipants.size} 位對象出現已還金額大於欠款金額。",
                recommendation = "請檢查還款紀錄是否重複，並修正對象欠款。"
            )
        }

        val orphanRepayments = repayments.filter { it.advanceCaseId == null || it.participantId == null }
        if (orphanRepayments.isNotEmpty()) {
            issues += HealthIssue(
                severity = HealthSeverity.Error,
                title = "還款紀錄缺少關聯",
                detail = "共有 ${orphanRepayments.size} 筆還款未連結代墊主檔或對象。",
                recommendation = "建議回溯該筆還款並重新建立。"
            )
        }

        val invalidNormalizedRepayments = repayments.filter { it.normalizedAmount <= BigDecimal.ZERO }
        if (invalidNormalizedRepayments.isNotEmpty()) {
            issues += HealthIssue(
                severity = HealthSeverity.Warning,
                title = "還款折算金額異常",
                detail = "共有 ${invalidNormalizedRepayments.size} 筆還款折算值小於等於 0。",
                recommendation = "請檢查該筆還款幣種與匯率設定。"
            )
        }

        val emptyCurrencyCases = cases.filter { it.advanceCase.currencyCode.isBlank() }
        if (emptyCurrencyCases.isNotEmpty()) {
            issues += HealthIssue(
                severity = HealthSeverity.Warning,
                title = "代墊主檔缺少幣種",
                detail = "共有 ${emptyCurrencyCases.size} 筆代墊主檔未設定幣種。",
                recommendation = "建議補上幣種，確保還款折算與統計正確。"
            )
        }

        val casesMissingSelfExpenseLink = cases.filter {
            it.advanceCase.myShareAmount > BigDecimal.ZERO && it.advanceCase.selfExpenseTransactionId == null
        }
        if (casesMissingSelfExpenseLink.isNotEmpty()) {
            issues += HealthIssue(
                severity = HealthSeverity.Info,
                title = "代墊主檔缺少自己份額連結",
                detail = "共有 ${casesMissingSelfExpenseLink.size} 筆代墊主檔無 selfExpenseTransactionID。",
                recommendation = "舊資料可正常使用，但整單連動刪除時可能無法刪到自己份額交易。"
            )
        }

        val participantsMissingInitialTransferLink = participants.filter { it.initialTransferGroupId == null }
        if (participantsMissingInitialTransferLink.isNotEmpty()) {
            issues += HealthIssue(
                severity = HealthSeverity.Info,
                title = "代墊對象缺少初始轉帳連結",
                detail = "共有 ${participantsMissingInitialTransferLink.size} 位對象無 initialTransferGroupID。",
                recommendation = "舊資料可正常使用，但整單連動刪除時可能無法完整刪除初始代墊轉帳。"
            )
        }

        checkAdvanceTransferMappings(cases, participants, repayments, transactions, issues)
    }

    private fun checkAdvanceTransferMappings(
        cases: List<AdvanceCaseWithDetails>,
        participants: List<AdvanceParticipantEntity>,
        repayments: List<AdvanceRepaymentEntity>,
        transactions: List<TransactionWithDetails>,
        issues: MutableList<HealthIssue>
    ) {
        val groupedTransfers = transactions
            .filter { it.transaction.type == TransactionType.Transfer && it.transaction.transferGroupId != null }
            .groupBy { it.transaction.transferGroupId!! }
        val payerAccountByCaseId = cases.associate { it.advanceCase.id to it.advanceCase.payerAccountId }
        val participantById = participants.associateBy { it.id }

        var malformedInitialGroups = 0
        var initialMappingMismatches = 0

        participants.forEach { participant ->
            val groupId = participant.initialTransferGroupId ?: return@forEach
            val group = groupedTransfers[groupId]
            if (group == null) {
                malformedInitialGroups += 1
                return@forEach
            }

            val outgoingAccountIds = group.accountIdsFor(TransferSide.Outgoing)
            val incomingAccountIds = group.accountIdsFor(TransferSide.Incoming)
            if (outgoingAccountIds.isEmpty() || incomingAccountIds.isEmpty()) {
                malformedInitialGroups += 1
                return@forEach
            }

            val debtAccountId = participant.debtAccountId
            val payerAccountId = participant.advanceCaseId?.let { payerAccountByCaseId[it] }
            if (debtAccountId == null || payerAccountId == null) {
                return@forEach
            }

            val iAdvancedOthersPattern = outgoingAccountIds == setOf(payerAccountId) &&
                incomingAccountIds == setOf(debtAccountId)
            val othersAdvancedMePattern = outgoingAccountIds == setOf(debtAccountId) &&
                incomingAccountIds == setOf(payerAccountId)

            if (!iAdvancedOthersPattern && !othersAdvancedMePattern) {
                initialMappingMismatches += 1
            }
        }

        if (malformedInitialGroups > 0) {
            issues += HealthIssue(
                severity = HealthSeverity.Warning,
                title = "代墊初始轉帳群組不完整",
                detail = "共有 $malformedInitialGroups 位代墊對象的 initialTransferGroup 缺少有效轉出/轉入。",
                recommendation = "建議檢查匯入資料或手動重建該筆代墊。"
            )
        }

        if (initialMappingMismatches > 0) {
            issues += HealthIssue(
                severity = HealthSeverity.Warning,
                title = "代墊初始轉帳方向不一致",
                detail = "共有 $initialMappingMismatches 位代墊對象的轉出/轉入帳戶與付款帳戶或借貸帳戶不一致。",
                recommendation = "請檢查該筆代墊是否被手動改動為錯誤帳戶。"
            )
        }

        var malformedRepaymentGroups = 0
        var repaymentMappingMismatches = 0

        repayments.forEach { repayment ->
            val groupId = repayment.linkedTransferGroupId ?: return@forEach
            val group = groupedTransfers[groupId]
            if (group == null) {
                malformedRepaymentGroups += 1
                return@forEach
            }

            val outgoingAccountIds = group.accountIdsFor(TransferSide.Outgoing)
            val incomingAccountIds = group.accountIdsFor(TransferSide.Incoming)
            if (outgoingAccountIds.isEmpty() || incomingAccountIds.isEmpty()) {
                malformedRepaymentGroups += 1
                return@forEach
            }

            val debtAccountId = repayment.participantId?.let { participantById[it]?.debtAccountId }
            val receivedAccountId = repayment.receivedAccountId
            if (debtAccountId == null || receivedAccountId == null) {
                return@forEach
            }

            val iAdvancedOthersPattern = outgoingAccountIds == setOf(debtAccountId) &&
                incomingAccountIds == setOf(receivedAccountId)
            val othersAdvancedMePattern = outgoingAccountIds == setOf(receivedAccountId) &&
                incomingAccountIds == setOf(debtAccountId)

            if (!iAdvancedOthersPattern && !othersAdvancedMePattern) {
                repaymentMappingMismatches += 1
            }
        }

        if (malformedRepaymentGroups > 0) {
            issues += HealthIssue(
                severity = HealthSeverity.Warning,
                title = "代墊還款轉帳群組不完整",
                detail = "共有 $malformedRepaymentGroups 筆還款的 linkedTransferGroup 缺少有效轉出/轉入。",
                recommendation = "建議檢查該筆還款是否被不完整刪除。"
            )
        }

        if (repaymentMappingMismatches > 0) {
            issues += HealthIssue(
                severity = HealthSeverity.Warning,
                title = "代墊還款方向不一致",
                detail = "共有 $repaymentMappingMismatches 筆還款的轉出/轉入帳戶與對象/入帳帳戶不一致。",
                recommendation = "請檢查還款方向與收款帳戶是否設定正確。"
            )
        }
    }

    private fun List<TransactionWithDetails>.accountIdsFor(side: TransferSide): Set<UUID> {
        return filter {
            when (side) {
                TransferSide.Outgoing -> {
                    it.transaction.transferSide == TransferSide.Outgoing || it.transaction.amount < BigDecimal.ZERO
                }

                TransferSide.Incoming -> {
                    it.transaction.transferSide == TransferSide.Incoming || it.transaction.amount > BigDecimal.ZERO
                }
            }
        }.mapNotNullTo(linkedSetOf()) { it.transaction.accountId }
    }
}
