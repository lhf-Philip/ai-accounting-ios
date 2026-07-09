import Foundation

struct BackupValidationReport: Identifiable, Equatable {
    let id = UUID()
    let version: String
    let timestamp: Date
    let counts: BackupRecordCounts
    let accountBalances: [BackupAccountBalanceReport]
    let issues: [BackupValidationIssue]

    var errorCount: Int { issues.filter { $0.severity == .error }.count }
    var warningCount: Int { issues.filter { $0.severity == .warning }.count }
    var infoCount: Int { issues.filter { $0.severity == .info }.count }
    var hasBlockingIssues: Bool { errorCount > 0 }

    var statusTitle: String {
        if hasBlockingIssues { return "備份有嚴重問題" }
        if warningCount > 0 { return "備份可匯入，但有警告" }
        return "備份看起來正常"
    }

    var statusDetail: String {
        if hasBlockingIssues { return "請先處理錯誤，避免覆蓋目前資料後無法完整還原。" }
        if warningCount > 0 { return "警告不一定代表錯誤，但建議先核對帳戶餘額與關聯資料。" }
        return "未發現明顯結構問題，可按需要匯入。"
    }

    var countsSummary: String { counts.summaryText }
}

struct BackupAccountBalanceReport: Identifiable, Equatable {
    let accountID: UUID
    let accountName: String
    let accountType: String
    let accountCurrency: String
    let balances: [BackupCurrencyBalance]

    var id: UUID { accountID }
}

struct BackupCurrencyBalance: Identifiable, Equatable {
    let currencyCode: String
    let amount: Decimal

    var id: String { currencyCode }
}

struct BackupValidationIssue: Identifiable, Equatable {
    enum Severity: String, Equatable {
        case info
        case warning
        case error
    }

    let id = UUID()
    let severity: Severity
    let title: String
    let detail: String
}

enum BackupValidationService {
    static func validate(_ backup: FullBackupData) -> BackupValidationReport {
        let accountIDs = Set(backup.accounts.map(\.id))
        let categoryIDs = Set(backup.categories.map(\.id))
        let tagIDs = Set(backup.tags.map(\.id))
        let transactionIDs = Set(backup.transactions.map(\.id))
        let transferGroupIDs = Set(backup.transactions.compactMap(\.transferGroupID))
        let advanceCases = backup.advanceCases ?? []
        let participants = backup.advanceParticipants ?? []
        let repayments = backup.advanceRepayments ?? []
        let advanceCaseIDs = Set(advanceCases.map(\.id))
        let participantIDs = Set(participants.map(\.id))
        let repaymentIDs = Set(repayments.map(\.id))
        var issues: [BackupValidationIssue] = []

        appendDuplicateIssues(label: "帳戶", ids: backup.accounts.map(\.id), issues: &issues)
        appendDuplicateIssues(label: "分類", ids: backup.categories.map(\.id), issues: &issues)
        appendDuplicateIssues(label: "標籤", ids: backup.tags.map(\.id), issues: &issues)
        appendDuplicateIssues(label: "交易", ids: backup.transactions.map(\.id), issues: &issues)
        appendDuplicateIssues(label: "代墊案件", ids: advanceCases.map(\.id), issues: &issues)
        appendDuplicateIssues(label: "代墊對象", ids: participants.map(\.id), issues: &issues)
        appendDuplicateIssues(label: "代墊還款", ids: repayments.map(\.id), issues: &issues)

        for account in backup.accounts {
            if AccountType(rawValue: account.type) == nil {
                issues.append(.init(severity: .warning, title: "未知帳戶類型", detail: "帳戶「\(account.name)」使用未知類型「\(account.type)」，匯入時會 fallback。"))
            }
        }

        for category in backup.categories {
            if let raw = category.kind, CategoryKind(rawValue: raw) == nil {
                issues.append(.init(severity: .warning, title: "未知分類方向", detail: "分類「\(category.name)」使用未知方向「\(raw)」，匯入時會 fallback。"))
            }
        }

        for transaction in backup.transactions {
            if TransactionType(rawValue: transaction.type) == nil {
                issues.append(.init(severity: .warning, title: "未知交易類型", detail: "交易「\(transaction.note)」使用未知類型「\(transaction.type)」，匯入時會 fallback。"))
            }
            if let rawSide = transaction.transferSide, TransferSide(rawValue: rawSide) == nil {
                issues.append(.init(severity: .warning, title: "未知轉帳方向", detail: "交易「\(transaction.note)」使用未知轉帳方向「\(rawSide)」。"))
            }
            if let accountID = transaction.accountID {
                if !accountIDs.contains(accountID) {
                    issues.append(.init(severity: .warning, title: "交易帳戶不存在", detail: "交易「\(transaction.note)」指向不存在的帳戶 \(accountID)。"))
                }
            } else {
                issues.append(.init(severity: .warning, title: "交易沒有帳戶", detail: "交易「\(transaction.note)」沒有帳戶，匯入後可能無法在帳戶明細顯示。"))
            }
            if let categoryID = transaction.categoryID, !categoryIDs.contains(categoryID) {
                issues.append(.init(severity: .warning, title: "交易分類不存在", detail: "交易「\(transaction.note)」指向不存在的分類 \(categoryID)。"))
            }
            let missingTags = transaction.tagIDs.filter { !tagIDs.contains($0) }
            if !missingTags.isEmpty {
                issues.append(.init(severity: .warning, title: "交易標籤不存在", detail: "交易「\(transaction.note)」有 \(missingTags.count) 個不存在的標籤。"))
            }
            if let linkedID = transaction.linkedTransactionID, !transactionIDs.contains(linkedID) {
                issues.append(.init(severity: .warning, title: "連結交易不存在", detail: "交易「\(transaction.note)」連到不存在的交易 \(linkedID)。"))
            }
            if let caseID = transaction.advanceCaseID, !advanceCaseIDs.contains(caseID) {
                issues.append(.init(severity: .warning, title: "交易代墊案件不存在", detail: "交易「\(transaction.note)」指向不存在的代墊案件 \(caseID)。"))
            }
            if let participantID = transaction.advanceParticipantID, !participantIDs.contains(participantID) {
                issues.append(.init(severity: .warning, title: "交易代墊對象不存在", detail: "交易「\(transaction.note)」指向不存在的代墊對象 \(participantID)。"))
            }
            if let repaymentID = transaction.advanceRepaymentID, !repaymentIDs.contains(repaymentID) {
                issues.append(.init(severity: .warning, title: "交易代墊還款不存在", detail: "交易「\(transaction.note)」指向不存在的代墊還款 \(repaymentID)。"))
            }
            if let rawRole = transaction.advanceEntryRole, AdvanceEntryRole(rawValue: rawRole) == nil {
                issues.append(.init(severity: .warning, title: "未知代墊分錄角色", detail: "交易「\(transaction.note)」使用未知代墊角色「\(rawRole)」。"))
            }
        }

        for shortcut in backup.shortcuts {
            if TransactionType(rawValue: shortcut.type) == nil {
                issues.append(.init(severity: .warning, title: "捷徑交易類型未知", detail: "捷徑「\(shortcut.name)」使用未知類型「\(shortcut.type)」。"))
            }
            if let accountID = shortcut.accountID, !accountIDs.contains(accountID) {
                issues.append(.init(severity: .warning, title: "捷徑帳戶不存在", detail: "捷徑「\(shortcut.name)」指向不存在的帳戶 \(accountID)。"))
            }
            if let categoryID = shortcut.categoryID, !categoryIDs.contains(categoryID) {
                issues.append(.init(severity: .warning, title: "捷徑分類不存在", detail: "捷徑「\(shortcut.name)」指向不存在的分類 \(categoryID)。"))
            }
            let missingTags = shortcut.tagIDs.filter { !tagIDs.contains($0) }
            if !missingTags.isEmpty {
                issues.append(.init(severity: .warning, title: "捷徑標籤不存在", detail: "捷徑「\(shortcut.name)」有 \(missingTags.count) 個不存在的標籤。"))
            }
        }

        for rule in backup.recurringRules ?? [] {
            if TransactionType(rawValue: rule.type) == nil {
                issues.append(.init(severity: .warning, title: "定期記帳交易類型未知", detail: "定期記帳「\(rule.title)」使用未知類型「\(rule.type)」。"))
            }
            if RecurringFrequency(rawValue: rule.frequency) == nil {
                issues.append(.init(severity: .warning, title: "定期記帳頻率未知", detail: "定期記帳「\(rule.title)」使用未知頻率「\(rule.frequency)」。"))
            }
            if let accountID = rule.accountID, !accountIDs.contains(accountID) {
                issues.append(.init(severity: .warning, title: "定期記帳帳戶不存在", detail: "定期記帳「\(rule.title)」指向不存在的帳戶 \(accountID)。"))
            }
            if let categoryID = rule.categoryID, !categoryIDs.contains(categoryID) {
                issues.append(.init(severity: .warning, title: "定期記帳分類不存在", detail: "定期記帳「\(rule.title)」指向不存在的分類 \(categoryID)。"))
            }
        }

        let recurringRuleIDs = Set((backup.recurringRules ?? []).map(\.id))
        for occurrence in backup.recurringOccurrences ?? [] {
            if RecurringOccurrenceStatus(rawValue: occurrence.status) == nil {
                issues.append(.init(severity: .warning, title: "定期項目狀態未知", detail: "定期項目 \(occurrence.id) 使用未知狀態「\(occurrence.status)」。"))
            }
            if let transactionID = occurrence.createdTransactionID, !transactionIDs.contains(transactionID) {
                issues.append(.init(severity: .warning, title: "定期項目交易不存在", detail: "定期項目 \(occurrence.id) 指向不存在的交易 \(transactionID)。"))
            }
            if let ruleID = occurrence.ruleID, !recurringRuleIDs.contains(ruleID) {
                issues.append(.init(severity: .warning, title: "定期項目規則不存在", detail: "定期項目 \(occurrence.id) 指向不存在的規則 \(ruleID)。"))
            }
        }

        for budget in backup.budgets ?? [] where budget.categoryID.map({ !categoryIDs.contains($0) }) == true {
            issues.append(.init(severity: .warning, title: "預算分類不存在", detail: "預算 \(budget.monthKey) 指向不存在的分類 \(budget.categoryID!)."))
        }
        for history in backup.budgetHistory ?? [] where !categoryIDs.contains(history.categoryID) {
            issues.append(.init(severity: .warning, title: "預算歷史分類不存在", detail: "預算歷史「\(history.historyKey)」指向不存在的分類 \(history.categoryID)。"))
        }
        for settings in backup.budgetSettings ?? [] {
            if BudgetCarryOverMode(rawValue: settings.carryOverMode) == nil {
                issues.append(.init(severity: .warning, title: "預算結轉規則未知", detail: "預算設定使用未知結轉規則「\(settings.carryOverMode)」。"))
            }
            if BudgetForecastMode(rawValue: settings.forecastMode) == nil {
                issues.append(.init(severity: .warning, title: "預算預測規則未知", detail: "預算設定使用未知預測規則「\(settings.forecastMode)」。"))
            }
        }

        for advanceCase in advanceCases {
            if let rawDirection = advanceCase.direction, AdvanceDirection(rawValue: rawDirection) == nil {
                issues.append(.init(severity: .warning, title: "代墊方向未知", detail: "代墊案件「\(advanceCase.title)」使用未知方向「\(rawDirection)」。"))
            }
            if let transactionID = advanceCase.selfExpenseTransactionID, !transactionIDs.contains(transactionID) {
                issues.append(.init(severity: .warning, title: "代墊自己份額交易不存在", detail: "代墊案件「\(advanceCase.title)」指向不存在的交易 \(transactionID)。"))
            }
            if let payerAccountID = advanceCase.payerAccountID, !accountIDs.contains(payerAccountID) {
                issues.append(.init(severity: .warning, title: "代墊付款帳戶不存在", detail: "代墊案件「\(advanceCase.title)」指向不存在的帳戶 \(payerAccountID)。"))
            }
            if let categoryID = advanceCase.expenseCategoryID, !categoryIDs.contains(categoryID) {
                issues.append(.init(severity: .warning, title: "代墊分類不存在", detail: "代墊案件「\(advanceCase.title)」指向不存在的分類 \(categoryID)。"))
            }
            let missingTags = (advanceCase.tagIDs ?? []).filter { !tagIDs.contains($0) }
            if !missingTags.isEmpty {
                issues.append(.init(severity: .warning, title: "代墊標籤不存在", detail: "代墊案件「\(advanceCase.title)」有 \(missingTags.count) 個不存在的標籤。"))
            }
        }

        for participant in participants {
            if let caseID = participant.advanceCaseID, !advanceCaseIDs.contains(caseID) {
                issues.append(.init(severity: .warning, title: "代墊對象案件不存在", detail: "代墊對象「\(participant.name)」指向不存在的案件 \(caseID)。"))
            }
            if let accountID = participant.debtAccountID, !accountIDs.contains(accountID) {
                issues.append(.init(severity: .warning, title: "代墊對象債務帳戶不存在", detail: "代墊對象「\(participant.name)」指向不存在的帳戶 \(accountID)。"))
            }
            if let groupID = participant.initialTransferGroupID, !transferGroupIDs.contains(groupID) {
                issues.append(.init(severity: .warning, title: "代墊初始分錄不存在", detail: "代墊對象「\(participant.name)」指向不存在的轉帳群組 \(groupID)。"))
            }
        }

        for repayment in repayments {
            if let caseID = repayment.advanceCaseID, !advanceCaseIDs.contains(caseID) {
                issues.append(.init(severity: .warning, title: "還款案件不存在", detail: "還款 \(repayment.id) 指向不存在的案件 \(caseID)。"))
            }
            if let participantID = repayment.participantID, !participantIDs.contains(participantID) {
                issues.append(.init(severity: .warning, title: "還款對象不存在", detail: "還款 \(repayment.id) 指向不存在的對象 \(participantID)。"))
            }
            if let accountID = repayment.receivedAccountID, !accountIDs.contains(accountID) {
                issues.append(.init(severity: .warning, title: "還款收款帳戶不存在", detail: "還款 \(repayment.id) 指向不存在的帳戶 \(accountID)。"))
            }
            if let groupID = repayment.linkedTransferGroupID, !transferGroupIDs.contains(groupID) {
                issues.append(.init(severity: .warning, title: "還款轉帳分錄不存在", detail: "還款 \(repayment.id) 指向不存在的轉帳群組 \(groupID)。"))
            }
        }

        let accountBalances = buildAccountBalances(backup: backup)
        let balanceWarningAccountTypes: Set<String> = [
            AccountType.cash.rawValue,
            AccountType.bank.rawValue
        ]
        for account in backup.accounts where balanceWarningAccountTypes.contains(account.type) {
            let balances = accountBalances.first { $0.accountID == account.id }?.balances ?? []
            for balance in balances where balance.amount < 0 {
                issues.append(.init(severity: .warning, title: "非債務帳戶出現負數餘額", detail: "帳戶「\(account.name)」的 \(balance.currencyCode) 餘額為 \(formatDecimal(balance.amount))。"))
            }
        }
        let anomalyBalances = accountBalances.flatMap { account in
            account.balances.filter { $0.currencyCode == "JPY" && $0.amount == Decimal(-221) }
                .map { "\(account.accountName)：\(formatDecimal($0.amount)) JPY" }
        }
        if !anomalyBalances.isEmpty {
            issues.append(.init(severity: .warning, title: "找到近期異常值 -221 JPY", detail: anomalyBalances.joined(separator: "\n")))
        }

        if issues.isEmpty {
            issues.append(.init(severity: .info, title: "未發現結構問題", detail: "備份可用於匯入前核對。"))
        }

        return BackupValidationReport(
            version: backup.version,
            timestamp: backup.timestamp,
            counts: BackupRecordCounts.fromBackup(backup),
            accountBalances: accountBalances,
            issues: issues.sorted { lhs, rhs in severityRank(lhs.severity) > severityRank(rhs.severity) },
        )
    }

    private static func appendDuplicateIssues(label: String, ids: [UUID], issues: inout [BackupValidationIssue]) {
        let duplicates = Dictionary(grouping: ids, by: { $0 }).filter { $0.value.count > 1 }
        for (id, values) in duplicates {
            issues.append(.init(severity: .error, title: "重複\(label) ID", detail: "ID \(id) 在備份中出現 \(values.count) 次，覆蓋匯入可能無法完整還原。"))
        }
    }

    private static func buildAccountBalances(backup: FullBackupData) -> [BackupAccountBalanceReport] {
        let transactionsByAccount = Dictionary(grouping: backup.transactions, by: \.accountID)
        return backup.accounts.sorted { $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder }
            .map { account in
                var balances: [String: Decimal] = [account.currency: account.baseBalance]
                for transaction in transactionsByAccount[account.id] ?? [] {
                    balances[transaction.currencyCode, default: 0] += transaction.amount
                }
                let currencyBalances = balances
                    .map { BackupCurrencyBalance(currencyCode: $0.key, amount: $0.value) }
                    .sorted { $0.currencyCode < $1.currencyCode }
                return BackupAccountBalanceReport(
                    accountID: account.id,
                    accountName: account.name,
                    accountType: account.type,
                    accountCurrency: account.currency,
                    balances: currencyBalances
                )
            }
    }

    private static func severityRank(_ severity: BackupValidationIssue.Severity) -> Int {
        switch severity {
        case .error: return 3
        case .warning: return 2
        case .info: return 1
        }
    }

    static func formatDecimal(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: number) ?? number.stringValue
    }
}
