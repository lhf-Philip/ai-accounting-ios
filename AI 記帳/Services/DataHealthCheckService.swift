import Foundation
import SwiftData

enum HealthSeverity: String {
    case error = "錯誤"
    case warning = "警告"
    case info = "資訊"
}

struct HealthIssue: Identifiable {
    let id = UUID()
    let severity: HealthSeverity
    let title: String
    let detail: String
    let recommendation: String
}

struct HealthReport {
    let generatedAt: Date
    let issues: [HealthIssue]
    
    var errorCount: Int { issues.filter { $0.severity == .error }.count }
    var warningCount: Int { issues.filter { $0.severity == .warning }.count }
    var infoCount: Int { issues.filter { $0.severity == .info }.count }
}

enum DataHealthCheckService {
    @MainActor
    static func run(modelContext: ModelContext) -> HealthReport {
        let transactions = (try? modelContext.fetch(FetchDescriptor<FinancialTransaction>())) ?? []
        let categories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        let budgets = (try? modelContext.fetch(FetchDescriptor<CategoryMonthlyBudget>())) ?? []
        let shortcuts = (try? modelContext.fetch(FetchDescriptor<Shortcut>())) ?? []
        let advanceCases = (try? modelContext.fetch(FetchDescriptor<AdvanceCase>())) ?? []
        let advanceParticipants = (try? modelContext.fetch(FetchDescriptor<AdvanceParticipant>())) ?? []
        let advanceRepayments = (try? modelContext.fetch(FetchDescriptor<AdvanceRepayment>())) ?? []
        
        var issues: [HealthIssue] = []
        
        checkTransactionBasics(transactions, into: &issues)
        checkLinkedTransfers(transactions, into: &issues)
        checkTransferGroups(transactions, into: &issues)
        checkDebtIncomeConflicts(transactions: transactions, shortcuts: shortcuts, into: &issues)
        checkCategories(categories, into: &issues)
        checkBudgets(budgets, into: &issues)
        checkAdvances(
            cases: advanceCases,
            participants: advanceParticipants,
            repayments: advanceRepayments,
            transactions: transactions,
            into: &issues
        )
        
        if issues.isEmpty {
            issues.append(
                HealthIssue(
                    severity: .info,
                    title: "資料健康",
                    detail: "未發現結構性問題。",
                    recommendation: "維持定期 JSON 備份即可。"
                )
            )
        }
        
        return HealthReport(generatedAt: Date(), issues: issues)
    }
    
    private static func checkTransactionBasics(_ transactions: [FinancialTransaction], into issues: inout [HealthIssue]) {
        let expenseSignErrors = transactions.filter { $0.type == .expense && $0.amount > 0 }
        if !expenseSignErrors.isEmpty {
            issues.append(
                HealthIssue(
                    severity: .warning,
                    title: "支出金額符號異常",
                    detail: "共有 \(expenseSignErrors.count) 筆支出為正數。",
                    recommendation: "建議打開交易檢查金額方向，支出應為負數。"
                )
            )
        }
        
        let incomeSignErrors = transactions.filter { $0.type == .income && $0.amount < 0 }
        if !incomeSignErrors.isEmpty {
            issues.append(
                HealthIssue(
                    severity: .warning,
                    title: "收入金額符號異常",
                    detail: "共有 \(incomeSignErrors.count) 筆收入為負數。",
                    recommendation: "建議打開交易檢查金額方向，收入應為正數。"
                )
            )
        }
        
        let missingAccounts = transactions.filter { $0.account == nil }
        if !missingAccounts.isEmpty {
            issues.append(
                HealthIssue(
                    severity: .error,
                    title: "交易缺少帳戶",
                    detail: "共有 \(missingAccounts.count) 筆交易沒有帳戶。",
                    recommendation: "請手動補上帳戶，避免報表與餘額失真。"
                )
            )
        }
        
        let emptyCurrency = transactions.filter { $0.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !emptyCurrency.isEmpty {
            issues.append(
                HealthIssue(
                    severity: .error,
                    title: "交易幣種遺失",
                    detail: "共有 \(emptyCurrency.count) 筆交易缺少 currencyCode。",
                    recommendation: "請修正幣種後再匯出報表。"
                )
            )
        }
        
        let futureTransactions = transactions.filter { $0.date.timeIntervalSinceNow > 60 * 60 * 24 }
        if !futureTransactions.isEmpty {
            issues.append(
                HealthIssue(
                    severity: .warning,
                    title: "交易日期在未來",
                    detail: "共有 \(futureTransactions.count) 筆交易日期晚於現在 24 小時以上。",
                    recommendation: "請確認是否誤設日期。"
                )
            )
        }
    }
    
    private static func checkLinkedTransfers(_ transactions: [FinancialTransaction], into issues: inout [HealthIssue]) {
        let txByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        let linkedTransfers = transactions.filter { $0.type == .transfer && $0.linkedTransactionID != nil }
        
        let brokenLinks = linkedTransfers.filter { tx in
            guard let linkedID = tx.linkedTransactionID else { return false }
            return txByID[linkedID] == nil
        }
        
        if !brokenLinks.isEmpty {
            issues.append(
                HealthIssue(
                    severity: .error,
                    title: "轉帳雙向連結損壞",
                    detail: "共有 \(brokenLinks.count) 筆轉帳找不到 linkedTransactionID 對應記錄。",
                    recommendation: "建議在『資料健康檢查』後手動修正或刪除該組轉帳。"
                )
            )
        }
    }
    
    private static func checkTransferGroups(_ transactions: [FinancialTransaction], into issues: inout [HealthIssue]) {
        let groupedTransfers = Dictionary(grouping: transactions.filter { $0.type == .transfer && $0.transferGroupID != nil }) {
            $0.transferGroupID!
        }
        
        var brokenGroups = 0
        for (_, group) in groupedTransfers {
            let outgoingCount = group.filter { $0.transferSide == .outgoing || $0.amount < 0 }.count
            let incomingCount = group.filter { $0.transferSide == .incoming || $0.amount > 0 }.count
            if outgoingCount == 0 || incomingCount == 0 {
                brokenGroups += 1
            }
        }
        
        if brokenGroups > 0 {
            issues.append(
                HealthIssue(
                    severity: .warning,
                    title: "轉帳群組不完整",
                    detail: "共有 \(brokenGroups) 個 transferGroup 缺少轉出或轉入側。",
                    recommendation: "建議檢查該群組交易是否被不完整刪除。"
                )
            )
        }
    }

    private static func checkDebtIncomeConflicts(
        transactions: [FinancialTransaction],
        shortcuts: [Shortcut],
        into issues: inout [HealthIssue]
    ) {
        let incomeOnDebtAccount = transactions.filter { TransactionSemantics.isLegacyDebtIncome($0) }
        if !incomeOnDebtAccount.isEmpty {
            issues.append(
                HealthIssue(
                    severity: .warning,
                    title: "收入記到了借貸帳戶",
                    detail: "共有 \(incomeOnDebtAccount.count) 筆收入交易使用借貸帳戶，這類資料建議改為「免除債務」。",
                    recommendation: "請逐筆檢查，確認是否應改成債務管理內的「免除債務」，避免收入報表失真。"
                )
            )
        }

        let incomeShortcutsOnDebtAccount = shortcuts.filter { TransactionSemantics.isLegacyDebtIncome($0) }
        if !incomeShortcutsOnDebtAccount.isEmpty {
            issues.append(
                HealthIssue(
                    severity: .warning,
                    title: "收入捷徑綁到了借貸帳戶",
                    detail: "共有 \(incomeShortcutsOnDebtAccount.count) 個收入捷徑綁定借貸帳戶。",
                    recommendation: "請把這些捷徑改到自己的賬戶，或改走債務管理流程。"
                )
            )
        }
    }
    
    private static func checkCategories(_ categories: [Category], into issues: inout [HealthIssue]) {
        let duplicates = Dictionary(grouping: categories) { "\($0.name.lowercased())::\($0.kind.rawValue)" }
            .filter { $0.value.count > 1 }
        
        if !duplicates.isEmpty {
            let duplicateCount = duplicates.values.reduce(0) { $0 + $1.count }
            issues.append(
                HealthIssue(
                    severity: .warning,
                    title: "分類重複",
                    detail: "共有 \(duplicateCount) 個分類名稱與類型重複。",
                    recommendation: "建議合併重複分類，避免預算與圖表分散。"
                )
            )
        }
    }
    
    private static func checkBudgets(_ budgets: [CategoryMonthlyBudget], into issues: inout [HealthIssue]) {
        let orphanBudgets = budgets.filter { $0.category == nil }
        if !orphanBudgets.isEmpty {
            issues.append(
                HealthIssue(
                    severity: .warning,
                    title: "預算缺少分類",
                    detail: "共有 \(orphanBudgets.count) 筆預算沒有綁定分類。",
                    recommendation: "請為預算補上分類或刪除該筆預算。"
                )
            )
        }
        
        let duplicates = Dictionary(grouping: budgets) { budget in
            "\(budget.monthKey)::\(budget.category?.id.uuidString ?? "nil")"
        }.filter { $0.value.count > 1 }
        
        if !duplicates.isEmpty {
            let duplicateCount = duplicates.values.reduce(0) { $0 + $1.count }
            issues.append(
                HealthIssue(
                    severity: .warning,
                    title: "月預算重複",
                    detail: "共有 \(duplicateCount) 筆重複的「分類 + 月份」預算。",
                    recommendation: "同一分類同月份建議只保留一筆，避免提醒重複。"
                )
            )
        }
    }
    
    private static func checkAdvances(
        cases: [AdvanceCase],
        participants: [AdvanceParticipant],
        repayments: [AdvanceRepayment],
        transactions: [FinancialTransaction],
        into issues: inout [HealthIssue]
    ) {
        let orphanParticipants = participants.filter { $0.advanceCase == nil }
        if !orphanParticipants.isEmpty {
            issues.append(
                HealthIssue(
                    severity: .warning,
                    title: "代墊對象缺少主檔",
                    detail: "共有 \(orphanParticipants.count) 筆代墊對象未連結到代墊主檔。",
                    recommendation: "請檢查備份匯入完整性，必要時重建該筆代墊。"
                )
            )
        }
        
        let participantsWithoutDebtAccount = participants.filter { $0.debtAccount == nil }
        if !participantsWithoutDebtAccount.isEmpty {
            issues.append(
                HealthIssue(
                    severity: .warning,
                    title: "代墊對象缺少借貸帳戶",
                    detail: "共有 \(participantsWithoutDebtAccount.count) 位代墊對象缺少借貸帳戶連結。",
                    recommendation: "建議補上借貸帳戶，避免還款入帳時無法建立轉帳。"
                )
            )
        }
        
        let overRepaidParticipants = participants.filter { $0.repaidAmount > $0.owedAmount }
        if !overRepaidParticipants.isEmpty {
            issues.append(
                HealthIssue(
                    severity: .error,
                    title: "代墊對象已還金額異常",
                    detail: "共有 \(overRepaidParticipants.count) 位對象出現已還金額大於欠款金額。",
                    recommendation: "請檢查還款紀錄是否重複，並修正對象欠款。"
                )
            )
        }
        
        let orphanRepayments = repayments.filter { $0.advanceCase == nil || $0.participant == nil }
        if !orphanRepayments.isEmpty {
            issues.append(
                HealthIssue(
                    severity: .error,
                    title: "還款紀錄缺少關聯",
                    detail: "共有 \(orphanRepayments.count) 筆還款未連結代墊主檔或對象。",
                    recommendation: "建議回溯該筆還款並重新建立。"
                )
            )
        }
        
        let invalidNormalizedRepayments = repayments.filter { $0.normalizedAmount <= 0 }
        if !invalidNormalizedRepayments.isEmpty {
            issues.append(
                HealthIssue(
                    severity: .warning,
                    title: "還款折算金額異常",
                    detail: "共有 \(invalidNormalizedRepayments.count) 筆還款折算值小於等於 0。",
                    recommendation: "請檢查該筆還款幣種與匯率設定。"
                )
            )
        }
        
        let emptyCurrencyCases = cases.filter { $0.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !emptyCurrencyCases.isEmpty {
            issues.append(
                HealthIssue(
                    severity: .warning,
                    title: "代墊主檔缺少幣種",
                    detail: "共有 \(emptyCurrencyCases.count) 筆代墊主檔未設定幣種。",
                    recommendation: "建議補上幣種，確保還款折算與統計正確。"
                )
            )
        }
        
        let casesMissingSelfExpenseLink = cases.filter {
            $0.myShareAmount > 0 && $0.selfExpenseTransactionID == nil
        }
        if !casesMissingSelfExpenseLink.isEmpty {
            issues.append(
                HealthIssue(
                    severity: .info,
                    title: "代墊主檔缺少自己份額連結",
                    detail: "共有 \(casesMissingSelfExpenseLink.count) 筆代墊主檔無 selfExpenseTransactionID。",
                    recommendation: "舊資料可正常使用，但整單連動刪除時可能無法刪到自己份額交易。"
                )
            )
        }
        
        let participantsMissingInitialTransferLink = participants.filter { $0.initialTransferGroupID == nil }
        if !participantsMissingInitialTransferLink.isEmpty {
            issues.append(
                HealthIssue(
                    severity: .info,
                    title: "代墊對象缺少初始轉帳連結",
                    detail: "共有 \(participantsMissingInitialTransferLink.count) 位對象無 initialTransferGroupID。",
                    recommendation: "舊資料可正常使用，但整單連動刪除時可能無法完整刪除初始代墊轉帳。"
                )
            )
        }

        checkAdvanceTransferMappings(
            participants: participants,
            repayments: repayments,
            transactions: transactions,
            into: &issues
        )
    }

    private static func checkAdvanceTransferMappings(
        participants: [AdvanceParticipant],
        repayments: [AdvanceRepayment],
        transactions: [FinancialTransaction],
        into issues: inout [HealthIssue]
    ) {
        let groupedTransfers = Dictionary(grouping: transactions.filter { $0.type == .transfer && $0.transferGroupID != nil }) {
            $0.transferGroupID!
        }

        var malformedInitialGroups = 0
        var initialMappingMismatches = 0

        for participant in participants {
            guard let groupID = participant.initialTransferGroupID else { continue }
            guard let group = groupedTransfers[groupID] else {
                malformedInitialGroups += 1
                continue
            }

            let outgoing = group.filter { $0.transferSide == .outgoing || $0.amount < 0 }
            let incoming = group.filter { $0.transferSide == .incoming || $0.amount > 0 }
            guard !outgoing.isEmpty && !incoming.isEmpty else {
                malformedInitialGroups += 1
                continue
            }

            guard
                let debtAccountID = participant.debtAccount?.id,
                let payerAccountID = participant.advanceCase?.payerAccount?.id
            else {
                continue
            }

            let outgoingAccountIDs = Set(outgoing.compactMap { $0.account?.id })
            let incomingAccountIDs = Set(incoming.compactMap { $0.account?.id })
            guard !outgoingAccountIDs.isEmpty && !incomingAccountIDs.isEmpty else {
                malformedInitialGroups += 1
                continue
            }

            let iAdvancedOthersPattern = outgoingAccountIDs.isSubset(of: [payerAccountID]) &&
                incomingAccountIDs.isSubset(of: [debtAccountID])
            let othersAdvancedMePattern = outgoingAccountIDs.isSubset(of: [debtAccountID]) &&
                incomingAccountIDs.isSubset(of: [payerAccountID])

            if !(iAdvancedOthersPattern || othersAdvancedMePattern) {
                initialMappingMismatches += 1
            }
        }

        if malformedInitialGroups > 0 {
            issues.append(
                HealthIssue(
                    severity: .warning,
                    title: "代墊初始轉帳群組不完整",
                    detail: "共有 \(malformedInitialGroups) 位代墊對象的 initialTransferGroup 缺少有效轉出/轉入。",
                    recommendation: "建議檢查匯入資料或手動重建該筆代墊。"
                )
            )
        }

        if initialMappingMismatches > 0 {
            issues.append(
                HealthIssue(
                    severity: .warning,
                    title: "代墊初始轉帳方向不一致",
                    detail: "共有 \(initialMappingMismatches) 位代墊對象的轉出/轉入帳戶與付款帳戶或借貸帳戶不一致。",
                    recommendation: "請檢查該筆代墊是否被手動改動為錯誤帳戶。"
                )
            )
        }

        var malformedRepaymentGroups = 0
        var repaymentMappingMismatches = 0

        for repayment in repayments {
            guard let groupID = repayment.linkedTransferGroupID else { continue }
            guard let group = groupedTransfers[groupID] else {
                malformedRepaymentGroups += 1
                continue
            }

            let outgoing = group.filter { $0.transferSide == .outgoing || $0.amount < 0 }
            let incoming = group.filter { $0.transferSide == .incoming || $0.amount > 0 }
            guard !outgoing.isEmpty && !incoming.isEmpty else {
                malformedRepaymentGroups += 1
                continue
            }

            guard
                let debtAccountID = repayment.participant?.debtAccount?.id,
                let receivedAccountID = repayment.receivedAccount?.id
            else {
                continue
            }

            let outgoingAccountIDs = Set(outgoing.compactMap { $0.account?.id })
            let incomingAccountIDs = Set(incoming.compactMap { $0.account?.id })
            guard !outgoingAccountIDs.isEmpty && !incomingAccountIDs.isEmpty else {
                malformedRepaymentGroups += 1
                continue
            }

            let iAdvancedOthersPattern = outgoingAccountIDs.isSubset(of: [debtAccountID]) &&
                incomingAccountIDs.isSubset(of: [receivedAccountID])
            let othersAdvancedMePattern = outgoingAccountIDs.isSubset(of: [receivedAccountID]) &&
                incomingAccountIDs.isSubset(of: [debtAccountID])

            if !(iAdvancedOthersPattern || othersAdvancedMePattern) {
                repaymentMappingMismatches += 1
            }
        }

        if malformedRepaymentGroups > 0 {
            issues.append(
                HealthIssue(
                    severity: .warning,
                    title: "代墊還款轉帳群組不完整",
                    detail: "共有 \(malformedRepaymentGroups) 筆還款的 linkedTransferGroup 缺少有效轉出/轉入。",
                    recommendation: "建議檢查該筆還款是否被不完整刪除。"
                )
            )
        }

        if repaymentMappingMismatches > 0 {
            issues.append(
                HealthIssue(
                    severity: .warning,
                    title: "代墊還款方向不一致",
                    detail: "共有 \(repaymentMappingMismatches) 筆還款的轉出/轉入帳戶與對象/入帳帳戶不一致。",
                    recommendation: "請檢查還款方向與收款帳戶是否設定正確。"
                )
            )
        }
    }
}
