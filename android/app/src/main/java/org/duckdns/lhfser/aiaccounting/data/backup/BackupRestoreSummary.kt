package org.duckdns.lhfser.aiaccounting.data.backup

enum class BackupRestoreMode {
    Merge,
    Replace,
    ClearOnly
}

data class BackupRecordCounts(
    val accounts: Int,
    val categories: Int,
    val tags: Int,
    val transactions: Int,
    val shortcuts: Int,
    val recurringRules: Int,
    val recurringOccurrences: Int,
    val budgets: Int,
    val budgetHistory: Int,
    val budgetSettings: Int,
    val advanceCases: Int,
    val advanceParticipants: Int,
    val advanceRepayments: Int
) {
    val total: Int
        get() = accounts + categories + tags + transactions + shortcuts + recurringRules +
            recurringOccurrences + budgets + budgetHistory + budgetSettings +
            advanceCases + advanceParticipants + advanceRepayments

    fun summaryText(): String = listOf(
        "帳戶 $accounts",
        "分類 $categories",
        "標籤 $tags",
        "交易 $transactions",
        "捷徑 $shortcuts",
        "定期記帳 $recurringRules",
        "定期項目 $recurringOccurrences",
        "預算 $budgets",
        "預算歷史 $budgetHistory",
        "預算設定 $budgetSettings",
        "代墊案件 $advanceCases",
        "代墊對象 $advanceParticipants",
        "代墊還款 $advanceRepayments"
    ).joinToString("、")

    companion object {
        val Zero = BackupRecordCounts(
            accounts = 0,
            categories = 0,
            tags = 0,
            transactions = 0,
            shortcuts = 0,
            recurringRules = 0,
            recurringOccurrences = 0,
            budgets = 0,
            budgetHistory = 0,
            budgetSettings = 0,
            advanceCases = 0,
            advanceParticipants = 0,
            advanceRepayments = 0
        )

        fun fromBackup(data: FullBackupData): BackupRecordCounts = BackupRecordCounts(
            accounts = data.accounts.size,
            categories = data.categories.size,
            tags = data.tags.size,
            transactions = data.transactions.size,
            shortcuts = data.shortcuts.size,
            recurringRules = data.recurringRules.orEmpty().size,
            recurringOccurrences = data.recurringOccurrences.orEmpty().size,
            budgets = data.budgets.orEmpty().size,
            budgetHistory = data.budgetHistory.orEmpty().size,
            budgetSettings = data.budgetSettings.orEmpty().size,
            advanceCases = data.advanceCases.orEmpty().size,
            advanceParticipants = data.advanceParticipants.orEmpty().size,
            advanceRepayments = data.advanceRepayments.orEmpty().size
        )
    }
}

data class BackupRestoreSummary(
    val mode: BackupRestoreMode,
    val beforeCounts: BackupRecordCounts,
    val backupCounts: BackupRecordCounts,
    val afterClearCounts: BackupRecordCounts?,
    val afterRestoreCounts: BackupRecordCounts
) {
    fun localizedSummary(): String = when (mode) {
        BackupRestoreMode.ClearOnly ->
            "資料已清除並完成驗證。清除前 ${beforeCounts.total} 筆，清除後 ${afterRestoreCounts.total} 筆。"
        BackupRestoreMode.Merge ->
            "合併匯入完成並完成基本驗證。匯入檔案：${backupCounts.summaryText()}。匯入後：${afterRestoreCounts.summaryText()}。"
        BackupRestoreMode.Replace ->
            "覆蓋匯入完成並完成驗證，舊帳務資料已清除。匯入檔案：${backupCounts.summaryText()}。匯入後：${afterRestoreCounts.summaryText()}。"
    }
}

class BackupRestoreVerificationException(
    mismatches: List<String>
) : IllegalStateException("資料還原後的數量驗證失敗：${mismatches.joinToString("；")}")
