import Foundation
import SwiftData

enum AdvanceServiceError: LocalizedError {
    case invalidPayerAccount
    case noParticipants
    case duplicateParticipantAccount
    case invalidMyShare
    case invalidParticipantAmount
    case participantNotInCase
    case missingDebtAccount
    case invalidRepaymentAmount
    case repaymentExceedsRemaining
    case invalidAdjustedOwedAmount
    case adjustedOwedLowerThanRepaid
    case missingRepaymentParticipant
    case missingRepaymentLink
    case invalidRepaymentStructure
    case invalidSettlementAccount
    case invalidSettlementCategory
    case specialRepaymentRequiresGroupRollback
    case missingSelfExpense
    case cannotDeleteAdvanceCaseWithoutModelContext
    
    var errorDescription: String? {
        switch self {
        case .invalidPayerAccount:
            return "請選擇非借貸類型的付款帳戶。"
        case .noParticipants:
            return "請至少新增一位代墊對象。"
        case .duplicateParticipantAccount:
            return "代墊對象不可重複，請合併同一人的金額。"
        case .invalidMyShare:
            return "自己的份額不可小於 0。"
        case .invalidParticipantAmount:
            return "每位代墊對象的金額需大於 0。"
        case .participantNotInCase:
            return "該還款對象不屬於此代墊單。"
        case .missingDebtAccount:
            return "找不到對應的借貸帳戶，請先檢查資料。"
        case .invalidRepaymentAmount:
            return "還款金額需大於 0。"
        case .repaymentExceedsRemaining:
            return "還款金額超過未還餘額。"
        case .invalidAdjustedOwedAmount:
            return "更正後欠款金額需大於 0。"
        case .adjustedOwedLowerThanRepaid:
            return "更正後欠款不可低於已還金額。"
        case .missingRepaymentParticipant:
            return "找不到還款對應的對象資料。"
        case .missingRepaymentLink:
            return "找不到還款對應的轉帳分錄。"
        case .invalidRepaymentStructure:
            return "還款轉帳分錄不完整，無法安全編輯。"
        case .invalidSettlementAccount:
            return "請選擇未歸檔的非借貸帳戶作為付款或入帳帳戶。"
        case .invalidSettlementCategory:
            return "所選分類與這筆還款方向不相符。"
        case .specialRepaymentRequiresGroupRollback:
            return "債務抵銷或跨幣種平賬必須整組撤銷，不能當作普通還款單筆沖銷。"
        case .missingSelfExpense:
            return "找不到代墊案件對應的自己份額支出。"
        case .cannotDeleteAdvanceCaseWithoutModelContext:
            return "刪除代墊失敗：缺少可用資料上下文。"
        }
    }
}

enum AdvanceService {
    enum RepaymentRecordKind: Equatable {
        case ordinary
        case mutualDebtOffset(UUID)
        case manualDebtSettlement(UUID)
        case invalidSpecial
    }

    enum SettlementDirection {
        case iAdvancedOthers
        case othersAdvancedMe
    }

    struct ParticipantInput {
        let debtAccount: Account
        let owedAmount: Decimal
    }

    struct RepaymentEditDraft {
        let receiveAccount: Account
        let amount: Decimal
        let currencyCode: String
        let normalizedAmount: Decimal
        let date: Date
        let note: String
        let category: Category?
        let tags: [Tag]
    }

    struct SelfExpenseEditDraft {
        let account: Account
        let amount: Decimal
        let currencyCode: String
        let normalizedAmount: Decimal
        let date: Date
        let note: String
        let category: Category?
        let tags: [Tag]
    }

    struct InitialEntryEditDraft {
        let caseTitle: String?
        let participantName: String?
        let debtAccount: Account?
        let payerAccount: Account?
        let owedAmount: Decimal
        let paymentAmount: Decimal?
        let paymentCurrencyCode: String?
        let date: Date
        let note: String
        let category: Category?
        let tags: [Tag]

        init(
            caseTitle: String? = nil,
            participantName: String? = nil,
            debtAccount: Account? = nil,
            payerAccount: Account?,
            owedAmount: Decimal,
            paymentAmount: Decimal?,
            paymentCurrencyCode: String?,
            date: Date,
            note: String,
            category: Category?,
            tags: [Tag]
        ) {
            self.caseTitle = caseTitle
            self.participantName = participantName
            self.debtAccount = debtAccount
            self.payerAccount = payerAccount
            self.owedAmount = owedAmount
            self.paymentAmount = paymentAmount
            self.paymentCurrencyCode = paymentCurrencyCode
            self.date = date
            self.note = note
            self.category = category
            self.tags = tags
        }
    }
    
    struct DeleteAdvanceResult {
        let deletedTransactionCount: Int
        let missingLinkedRecordCount: Int
    }
    
    struct LegacyLinkRepairResult {
        let updatedCaseLinkCount: Int
        let unresolvedCaseLinkCount: Int
        let updatedParticipantLinkCount: Int
        let unresolvedParticipantLinkCount: Int
        
        var totalUpdated: Int {
            updatedCaseLinkCount + updatedParticipantLinkCount
        }
        
        var totalUnresolved: Int {
            unresolvedCaseLinkCount + unresolvedParticipantLinkCount
        }
    }

    struct ExplicitLinkBackfillResult {
        let linkedTransactionCount: Int
        let updatedCaseCount: Int
        let unresolvedRecordCount: Int
    }

    struct LegacyBorrowedAdvanceRepairResult {
        let repairedParticipantCount: Int
        let removedInflatedAccountTransactionCount: Int
    }

    struct RepaymentReconciliationResult {
        let checkedParticipantCount: Int
        let updatedParticipantCount: Int
    }

    struct MutualDebtOffsetCandidate: Identifiable {
        let id = UUID()
        let debtAccount: Account
        let currencyCode: String
        let amount: Decimal
        let receivableAmount: Decimal
        let payableAmount: Decimal
        let receivableParticipantCount: Int
        let payableParticipantCount: Int
    }

    struct MutualDebtOffsetResult {
        let offsetGroupID: UUID
        let amount: Decimal
        let currencyCode: String
        let repaymentCount: Int
    }

    enum ManualDebtSettlementDirection {
        case receivable
        case payable
    }

    struct ManualDebtSettlementResult {
        let settlementID: UUID
        let amount: Decimal
        let currencyCode: String
        let repaymentCount: Int
    }
    
    private static let roundingTolerance = Decimal(string: "0.0001") ?? 0.0001
    static let mutualDebtOffsetMarkerPrefix = "[債務抵銷:"
    static let manualDebtSettlementMarkerPrefix = "[跨幣種平賬:"
    
    static func totalAdvanced(for advanceCase: AdvanceCase) -> Decimal {
        advanceCase.myShareAmount + advanceCase.participants.reduce(Decimal.zero) { $0 + $1.owedAmount }
    }
    
    static func outstandingAmount(for advanceCase: AdvanceCase) -> Decimal {
        advanceCase.participants.reduce(Decimal.zero) { partial, participant in
            partial + participant.remainingAmount
        }
    }

    @MainActor
    static func reconcileUnderstatedRepaymentTotals(
        modelContext: ModelContext
    ) throws -> RepaymentReconciliationResult {
        let repayments = try modelContext.fetch(FetchDescriptor<AdvanceRepayment>())
        let groupedTotals = Dictionary(grouping: repayments.compactMap { repayment -> (UUID, Decimal)? in
            guard let participantID = repayment.participant?.id,
                  repayment.normalizedAmount > 0 else {
                return nil
            }
            return (participantID, repayment.normalizedAmount)
        }, by: \.0)
        .mapValues { entries in
            entries.reduce(Decimal.zero) { $0 + $1.1 }
        }

        guard !groupedTotals.isEmpty else {
            return RepaymentReconciliationResult(
                checkedParticipantCount: 0,
                updatedParticipantCount: 0
            )
        }

        let participants = try modelContext.fetch(FetchDescriptor<AdvanceParticipant>())
        var updatedCount = 0
        for participant in participants {
            guard let recordedTotal = groupedTotals[participant.id] else { continue }
            let expectedTotal = min(recordedTotal, participant.owedAmount)
            guard expectedTotal - participant.repaidAmount > roundingTolerance else { continue }
            participant.repaidAmount = expectedTotal
            participant.updatedAt = Date()
            participant.advanceCase?.updatedAt = Date()
            updatedCount += 1
        }

        if updatedCount > 0 {
            try modelContext.save()
        }
        return RepaymentReconciliationResult(
            checkedParticipantCount: groupedTotals.count,
            updatedParticipantCount: updatedCount
        )
    }

    static func isMutualDebtOffset(note: String) -> Bool {
        note.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(mutualDebtOffsetMarkerPrefix)
    }

    static func mutualDebtOffsetID(from note: String) -> UUID? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(mutualDebtOffsetMarkerPrefix),
              let closeIndex = trimmed.firstIndex(of: "]") else {
            return nil
        }
        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: mutualDebtOffsetMarkerPrefix.count)
        return UUID(uuidString: String(trimmed[startIndex..<closeIndex]))
    }

    static func isManualDebtSettlement(note: String) -> Bool {
        note.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(manualDebtSettlementMarkerPrefix)
    }

    static func manualDebtSettlementID(from note: String) -> UUID? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(manualDebtSettlementMarkerPrefix),
              let closeIndex = trimmed.firstIndex(of: "]") else {
            return nil
        }
        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: manualDebtSettlementMarkerPrefix.count)
        return UUID(uuidString: String(trimmed[startIndex..<closeIndex]))
    }

    static func repaymentRecordKind(note: String) -> RepaymentRecordKind {
        if let offsetID = mutualDebtOffsetID(from: note) {
            return .mutualDebtOffset(offsetID)
        }
        if isMutualDebtOffset(note: note) {
            return .invalidSpecial
        }
        if let settlementID = manualDebtSettlementID(from: note) {
            return .manualDebtSettlement(settlementID)
        }
        if isManualDebtSettlement(note: note) {
            return .invalidSpecial
        }
        return .ordinary
    }

    @MainActor
    static func mutualDebtOffsetCandidate(
        debtAccount: Account,
        currencyCode: String,
        advanceCases: [AdvanceCase],
        modelContext: ModelContext
    ) -> MutualDebtOffsetCandidate? {
        let offsetable = offsetableParticipants(
            debtAccount: debtAccount,
            currencyCode: currencyCode,
            advanceCases: advanceCases,
            modelContext: modelContext
        )
        let receivableAmount = offsetable.receivable.reduce(Decimal.zero) { $0 + $1.participant.remainingAmount }
        let payableAmount = offsetable.payable.reduce(Decimal.zero) { $0 + $1.participant.remainingAmount }
        let amount = min(receivableAmount, payableAmount)
        guard amount > roundingTolerance else { return nil }
        return MutualDebtOffsetCandidate(
            debtAccount: debtAccount,
            currencyCode: currencyCode,
            amount: amount,
            receivableAmount: receivableAmount,
            payableAmount: payableAmount,
            receivableParticipantCount: offsetable.receivable.count,
            payableParticipantCount: offsetable.payable.count
        )
    }

    @MainActor
    static func recordMutualDebtOffset(
        debtAccount: Account,
        currencyCode: String,
        date: Date = Date(),
        note: String = "",
        modelContext: ModelContext
    ) throws -> MutualDebtOffsetResult {
        let advanceCases = try modelContext.fetch(FetchDescriptor<AdvanceCase>())
        let offsetable = offsetableParticipants(
            debtAccount: debtAccount,
            currencyCode: currencyCode,
            advanceCases: advanceCases,
            modelContext: modelContext
        )
        let receivableAmount = offsetable.receivable.reduce(Decimal.zero) { $0 + $1.participant.remainingAmount }
        let payableAmount = offsetable.payable.reduce(Decimal.zero) { $0 + $1.participant.remainingAmount }
        let offsetAmount = min(receivableAmount, payableAmount)
        guard offsetAmount > roundingTolerance else {
            throw AdvanceServiceError.invalidRepaymentAmount
        }

        let offsetGroupID = UUID()
        let baseNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let marker = "\(mutualDebtOffsetMarkerPrefix)\(offsetGroupID.uuidString)]"
        let finalNote = baseNote.isEmpty ? "\(marker) 與 \(debtAccount.name) 互相代墊抵銷" : "\(marker) \(baseNote)"
        var repaymentCount = 0

        repaymentCount += applyMutualDebtOffset(
            amount: offsetAmount,
            entries: offsetable.receivable,
            date: date,
            note: finalNote,
            modelContext: modelContext
        )
        repaymentCount += applyMutualDebtOffset(
            amount: offsetAmount,
            entries: offsetable.payable,
            date: date,
            note: finalNote,
            modelContext: modelContext
        )

        try modelContext.save()
        return MutualDebtOffsetResult(
            offsetGroupID: offsetGroupID,
            amount: offsetAmount,
            currencyCode: currencyCode,
            repaymentCount: repaymentCount
        )
    }

    @MainActor
    static func rollbackMutualDebtOffset(
        offsetGroupID: UUID,
        modelContext: ModelContext
    ) throws -> Int {
        try rollbackSpecialRepaymentGroup(
            matching: { mutualDebtOffsetID(from: $0.note) == offsetGroupID },
            modelContext: modelContext
        )
    }

    @MainActor
    static func recordManualDebtSettlement(
        debtAccount: Account,
        currencyCode: String,
        direction: ManualDebtSettlementDirection,
        amount: Decimal,
        date: Date = Date(),
        note: String = "",
        modelContext: ModelContext
    ) throws -> ManualDebtSettlementResult {
        guard amount > roundingTolerance else {
            throw AdvanceServiceError.invalidRepaymentAmount
        }

        let advanceCases = try modelContext.fetch(FetchDescriptor<AdvanceCase>())
        let offsetable = offsetableParticipants(
            debtAccount: debtAccount,
            currencyCode: currencyCode,
            advanceCases: advanceCases,
            modelContext: modelContext
        )
        let entries = direction == .receivable ? offsetable.receivable : offsetable.payable
        let availableAmount = entries.reduce(Decimal.zero) { $0 + $1.participant.remainingAmount }
        guard amount <= availableAmount + roundingTolerance else {
            throw AdvanceServiceError.repaymentExceedsRemaining
        }

        let settlementID = UUID()
        let marker = "\(manualDebtSettlementMarkerPrefix)\(settlementID.uuidString)]"
        let baseNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultNote = direction == .receivable
            ? "手動結清 \(debtAccount.name) 欠你的 \(currencyCode) 代墊餘額"
            : "手動結清你欠 \(debtAccount.name) 的 \(currencyCode) 代墊餘額"
        let finalNote = baseNote.isEmpty ? "\(marker) \(defaultNote)" : "\(marker) \(baseNote)"

        let repaymentCount = applyManualDebtSettlement(
            amount: amount,
            entries: entries,
            date: date,
            note: finalNote,
            modelContext: modelContext
        )

        try modelContext.save()
        return ManualDebtSettlementResult(
            settlementID: settlementID,
            amount: amount,
            currencyCode: currencyCode,
            repaymentCount: repaymentCount
        )
    }

    @MainActor
    static func rollbackManualDebtSettlement(
        settlementID: UUID,
        modelContext: ModelContext
    ) throws -> Int {
        try rollbackSpecialRepaymentGroup(
            matching: { manualDebtSettlementID(from: $0.note) == settlementID },
            modelContext: modelContext
        )
    }
    
    @MainActor
    static func createAdvanceCase(
        title: String,
        date: Date,
        currencyCode: String,
        myShareAmount: Decimal,
        note: String,
        payerAccount: Account?,
        category: Category?,
        tags: [Tag],
        participants: [ParticipantInput],
        isBorrowedByMe: Bool = false,
        modelContext: ModelContext
    ) throws -> AdvanceCase {
        if !isBorrowedByMe, payerAccount == nil {
            throw AdvanceServiceError.invalidPayerAccount
        }
        if let payerAccount, payerAccount.type == .debt {
            throw AdvanceServiceError.invalidPayerAccount
        }
        guard !participants.isEmpty else {
            throw AdvanceServiceError.noParticipants
        }
        guard myShareAmount >= 0 else {
            throw AdvanceServiceError.invalidMyShare
        }
        
        var seenAccounts = Set<UUID>()
        for participant in participants {
            guard participant.owedAmount > 0 else {
                throw AdvanceServiceError.invalidParticipantAmount
            }
            if seenAccounts.contains(participant.debtAccount.id) {
                throw AdvanceServiceError.duplicateParticipantAccount
            }
            seenAccounts.insert(participant.debtAccount.id)
        }
        
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmedTitle.isEmpty ? "代墊" : trimmedTitle
        let finalNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        
        let advanceCase = AdvanceCase(
            title: finalTitle,
            date: date,
            currencyCode: currencyCode,
            myShareAmount: myShareAmount,
            note: finalNote,
            direction: isBorrowedByMe ? .othersAdvancedMe : .iAdvancedOthers,
            tagIDs: tags.map(\.id),
            createdAt: now,
            updatedAt: now,
            payerAccount: payerAccount,
            expenseCategory: category
        )
        modelContext.insert(advanceCase)
        var budgetHistoryTransactions: [FinancialTransaction] = []
        
        if !isBorrowedByMe, myShareAmount > 0, let payerAccount {
            let expenseNote = finalNote.isEmpty
                ? "\(finalTitle) (自己份額)"
                : "\(finalNote) (自己份額)"
            
            let expenseTx = FinancialTransaction(
                amount: -abs(myShareAmount),
                currencyCode: currencyCode,
                date: date,
                note: expenseNote,
                type: .expense,
                advanceCaseID: advanceCase.id,
                advanceEntryRole: .selfExpense,
                account: payerAccount,
                category: category,
                tags: tags
            )
            modelContext.insert(expenseTx)
            budgetHistoryTransactions.append(expenseTx)
            advanceCase.selfExpenseTransactionID = expenseTx.id
        }
        
        let transferMemo = finalNote.isEmpty ? finalTitle : finalNote
        
        for input in participants {
            let transferGroupID = UUID()
            let outID = UUID()
            let inID = UUID()
            
            let participant = AdvanceParticipant(
                name: input.debtAccount.name,
                owedAmount: abs(input.owedAmount),
                repaidAmount: 0,
                initialTransferGroupID: transferGroupID,
                createdAt: now,
                updatedAt: now,
                advanceCase: advanceCase,
                debtAccount: input.debtAccount
            )
            modelContext.insert(participant)

            let outTx: FinancialTransaction
            let inTx: FinancialTransaction

            if isBorrowedByMe {
                let expenseTx = FinancialTransaction(
                    id: outID,
                    amount: -abs(input.owedAmount),
                    currencyCode: currencyCode,
                    date: date,
                    note: "\(transferMemo) (他人代墊我：\(input.debtAccount.name))",
                    type: .expense,
                    linkedTransactionID: nil,
                    transferGroupID: transferGroupID,
                    transferSide: .outgoing,
                    advanceCaseID: advanceCase.id,
                    advanceParticipantID: participant.id,
                    advanceEntryRole: .initialDebt,
                    account: input.debtAccount,
                    category: category,
                    tags: tags
                )
                modelContext.insert(expenseTx)
                budgetHistoryTransactions.append(expenseTx)
                continue
            } else {
                guard let payerAccount else {
                    throw AdvanceServiceError.invalidPayerAccount
                }
                outTx = FinancialTransaction(
                    id: outID,
                    amount: -abs(input.owedAmount),
                    currencyCode: currencyCode,
                    date: date,
                    note: "\(transferMemo) (代墊給 \(input.debtAccount.name))",
                    type: .transfer,
                    linkedTransactionID: inID,
                    transferGroupID: transferGroupID,
                    transferSide: .outgoing,
                    advanceCaseID: advanceCase.id,
                    advanceParticipantID: participant.id,
                    advanceEntryRole: .initialAsset,
                    account: payerAccount
                )

                inTx = FinancialTransaction(
                    id: inID,
                    amount: abs(input.owedAmount),
                    currencyCode: currencyCode,
                    date: date,
                    note: "\(transferMemo) (來自 \(payerAccount.name))",
                    type: .transfer,
                    linkedTransactionID: outID,
                    transferGroupID: transferGroupID,
                    transferSide: .incoming,
                    advanceCaseID: advanceCase.id,
                    advanceParticipantID: participant.id,
                    advanceEntryRole: .initialDebt,
                    account: input.debtAccount
                )
            }
            
            modelContext.insert(outTx)
            modelContext.insert(inTx)
        }
        
        try modelContext.save()
        try BudgetHistoryService.shared.syncAffected(
            by: budgetHistoryTransactions,
            modelContext: modelContext,
            currencyService: CurrencyService.shared
        )
        return advanceCase
    }

    @MainActor
    static func repairLegacyBorrowedAdvanceAccountInflation(modelContext: ModelContext) throws -> LegacyBorrowedAdvanceRepairResult {
        let participants = try modelContext.fetch(FetchDescriptor<AdvanceParticipant>())
        var repairedParticipantCount = 0
        var removedInflatedAccountTransactionCount = 0
        var repairedExpenseTransactions: [FinancialTransaction] = []

        for participant in participants {
            guard let groupID = participant.initialTransferGroupID,
                  let debtAccount = participant.debtAccount,
                  let advanceCase = participant.advanceCase
            else { continue }

            let descriptor = FetchDescriptor<FinancialTransaction>(
                predicate: #Predicate { $0.transferGroupID == groupID }
            )
            let group = try modelContext.fetch(descriptor)
            guard let outgoing = group.first(where: { tx in
                tx.account?.id == debtAccount.id && (tx.transferSide == .outgoing || tx.amount < 0)
            }) else { continue }

            let inflatedIncoming = group.filter { tx in
                tx.id != outgoing.id &&
                    tx.amount > 0 &&
                    tx.account?.type != .debt
            }
            guard !inflatedIncoming.isEmpty else { continue }

            outgoing.type = .expense
            outgoing.amount = -abs(outgoing.amount)
            outgoing.linkedTransactionID = nil
            outgoing.transferSide = .outgoing
            outgoing.category = advanceCase.expenseCategory
            outgoing.note = "\(advanceCase.note.isEmpty ? advanceCase.title : advanceCase.note) (他人代墊我：\(debtAccount.name))"
            outgoing.updatedAt = Date()
            repairedExpenseTransactions.append(outgoing)

            for tx in inflatedIncoming {
                modelContext.delete(tx)
                removedInflatedAccountTransactionCount += 1
            }

            advanceCase.payerAccount = nil
            advanceCase.updatedAt = Date()
            participant.updatedAt = Date()
            repairedParticipantCount += 1
        }

        try modelContext.save()
        try BudgetHistoryService.shared.syncAffected(
            by: repairedExpenseTransactions,
            modelContext: modelContext,
            currencyService: CurrencyService.shared
        )

        return LegacyBorrowedAdvanceRepairResult(
            repairedParticipantCount: repairedParticipantCount,
            removedInflatedAccountTransactionCount: removedInflatedAccountTransactionCount
        )
    }
    
    @MainActor
    static func recordRepayment(
        advanceCase: AdvanceCase,
        participant: AdvanceParticipant,
        amount: Decimal,
        currencyCode: String,
        date: Date,
        note: String,
        receiveAccount: Account,
        category: Category?,
        tags: [Tag],
        currencyService: CurrencyService,
        normalizedAmountOverride: Decimal? = nil,
        direction: SettlementDirection? = nil,
        autosave: Bool = true,
        modelContext: ModelContext
    ) throws -> AdvanceRepayment {
        guard participant.advanceCase?.id == advanceCase.id else {
            throw AdvanceServiceError.participantNotInCase
        }
        guard let debtAccount = participant.debtAccount else {
            throw AdvanceServiceError.missingDebtAccount
        }
        guard amount > 0 else {
            throw AdvanceServiceError.invalidRepaymentAmount
        }
        let currencyCode = currencyCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !currencyCode.isEmpty else {
            throw AdvanceServiceError.invalidRepaymentAmount
        }
        guard receiveAccount.type != .debt, !receiveAccount.isArchived else {
            throw AdvanceServiceError.invalidSettlementAccount
        }
        
        let normalizedAmount = normalizedAmountOverride ?? currencyService.convert(
            amount: abs(amount),
            from: currencyCode,
            to: advanceCase.currencyCode
        )
        guard normalizedAmount > 0 else {
            throw AdvanceServiceError.invalidRepaymentAmount
        }
        
        let remaining = participant.remainingAmount
        if normalizedAmount - remaining > roundingTolerance {
            throw AdvanceServiceError.repaymentExceedsRemaining
        }
        
        let finalNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let memo = finalNote.isEmpty ? advanceCase.title : finalNote
        let outID = UUID()
        let inID = UUID()
        let transferGroupID = UUID()

        let settlementDirection = direction ?? inferSettlementDirection(for: participant, modelContext: modelContext)
        try validateSettlementCategory(category, direction: settlementDirection)
        let outTx: FinancialTransaction
        let inTx: FinancialTransaction

        switch settlementDirection {
        case .iAdvancedOthers:
            outTx = FinancialTransaction(
                id: outID,
                amount: -abs(amount),
                currencyCode: currencyCode,
                date: date,
                note: "\(memo) (還款至 \(receiveAccount.name))",
                type: .transfer,
                linkedTransactionID: inID,
                transferGroupID: transferGroupID,
                transferSide: .outgoing,
                account: debtAccount
            )

            inTx = FinancialTransaction(
                id: inID,
                amount: abs(amount),
                currencyCode: currencyCode,
                date: date,
                note: "\(memo) (來自 \(debtAccount.name))",
                type: .transfer,
                linkedTransactionID: outID,
                transferGroupID: transferGroupID,
                transferSide: .incoming,
                account: receiveAccount,
                category: category,
                tags: tags
            )
        case .othersAdvancedMe:
            outTx = FinancialTransaction(
                id: outID,
                amount: -abs(amount),
                currencyCode: currencyCode,
                date: date,
                note: "\(memo) (還款給 \(debtAccount.name))",
                type: .transfer,
                linkedTransactionID: inID,
                transferGroupID: transferGroupID,
                transferSide: .outgoing,
                account: receiveAccount,
                category: category,
                tags: tags
            )

            inTx = FinancialTransaction(
                id: inID,
                amount: abs(amount),
                currencyCode: currencyCode,
                date: date,
                note: "\(memo) (來自 \(receiveAccount.name))",
                type: .transfer,
                linkedTransactionID: outID,
                transferGroupID: transferGroupID,
                transferSide: .incoming,
                account: debtAccount
            )
        }

        modelContext.insert(outTx)
        modelContext.insert(inTx)
        
        let repayment = AdvanceRepayment(
            amount: abs(amount),
            currencyCode: currencyCode,
            normalizedAmount: normalizedAmount,
            date: date,
            note: finalNote,
            linkedTransferGroupID: transferGroupID,
            createdAt: Date(),
            advanceCase: advanceCase,
            participant: participant,
            receivedAccount: receiveAccount
        )
        modelContext.insert(repayment)

        outTx.advanceCaseID = advanceCase.id
        outTx.advanceParticipantID = participant.id
        outTx.advanceRepaymentID = repayment.id
        inTx.advanceCaseID = advanceCase.id
        inTx.advanceParticipantID = participant.id
        inTx.advanceRepaymentID = repayment.id
        switch settlementDirection {
        case .iAdvancedOthers:
            outTx.advanceEntryRole = .repaymentDebt
            inTx.advanceEntryRole = .repaymentAsset
        case .othersAdvancedMe:
            outTx.advanceEntryRole = .repaymentAsset
            inTx.advanceEntryRole = .repaymentDebt
        }
        
        let updatedRepaid = participant.repaidAmount + normalizedAmount
        if participant.owedAmount - updatedRepaid < roundingTolerance {
            participant.repaidAmount = participant.owedAmount
        } else {
            participant.repaidAmount = updatedRepaid
        }
        
        participant.updatedAt = Date()
        advanceCase.updatedAt = Date()
        
        if autosave {
            try modelContext.save()
        }
        return repayment
    }

    @MainActor
    static func updateSelfExpense(
        advanceCase: AdvanceCase,
        transaction: FinancialTransaction,
        draft: SelfExpenseEditDraft,
        modelContext: ModelContext
    ) throws {
        guard advanceCase.selfExpenseTransactionID == transaction.id,
              transaction.type == .expense,
              transaction.transferGroupID == nil,
              transaction.linkedTransactionID == nil
        else {
            throw AdvanceServiceError.missingSelfExpense
        }
        guard draft.amount > 0, draft.normalizedAmount > 0 else {
            throw AdvanceServiceError.invalidRepaymentAmount
        }
        guard draft.account.type != .debt, !draft.account.isArchived else {
            throw AdvanceServiceError.invalidSettlementAccount
        }
        if let category = draft.category, !category.kind.supports(.expense) {
            throw AdvanceServiceError.invalidRepaymentStructure
        }

        let originalBudgetKey = BudgetHistoryService.affectedKey(for: transaction)
        let currencyCode = draft.currencyCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !currencyCode.isEmpty else {
            throw AdvanceServiceError.invalidRepaymentAmount
        }

        let now = Date()
        transaction.amount = -abs(draft.amount)
        transaction.currencyCode = currencyCode
        transaction.date = draft.date
        transaction.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.account = draft.account
        transaction.category = draft.category
        transaction.tags = draft.tags
        transaction.updatedAt = now

        advanceCase.myShareAmount = abs(draft.normalizedAmount)
        advanceCase.expenseCategory = draft.category
        advanceCase.updatedAt = now

        let affectedKeys = [originalBudgetKey, BudgetHistoryService.affectedKey(for: transaction)]
            .compactMap { $0 }
        if affectedKeys.isEmpty {
            try modelContext.save()
        } else {
            try BudgetHistoryService.shared.syncAffected(
                keys: affectedKeys,
                modelContext: modelContext,
                currencyService: CurrencyService.shared
            )
        }
    }

    @MainActor
    static func updateRepayment(
        advanceCase: AdvanceCase,
        repayment: AdvanceRepayment,
        draft: RepaymentEditDraft,
        modelContext: ModelContext
    ) throws {
        guard repayment.advanceCase?.id == advanceCase.id else {
            throw AdvanceServiceError.participantNotInCase
        }
        guard let participant = repayment.participant else {
            throw AdvanceServiceError.missingRepaymentParticipant
        }
        guard let debtAccount = participant.debtAccount else {
            throw AdvanceServiceError.missingDebtAccount
        }
        guard draft.amount > 0, draft.normalizedAmount > 0 else {
            throw AdvanceServiceError.invalidRepaymentAmount
        }
        guard draft.receiveAccount.type != .debt, !draft.receiveAccount.isArchived else {
            throw AdvanceServiceError.invalidSettlementAccount
        }
        guard !isMutualDebtOffset(note: repayment.note),
              !isManualDebtSettlement(note: repayment.note) else {
            throw AdvanceServiceError.specialRepaymentRequiresGroupRollback
        }
        guard let groupID = repayment.linkedTransferGroupID else {
            throw AdvanceServiceError.missingRepaymentLink
        }

        let descriptor = FetchDescriptor<FinancialTransaction>(
            predicate: #Predicate { $0.transferGroupID == groupID }
        )
        let transfers = try modelContext.fetch(descriptor).filter { $0.type == .transfer }
        guard transfers.count == 2,
              let outgoing = transfers.first(where: { $0.transferSide == .outgoing || $0.amount < 0 }),
              let incoming = transfers.first(where: { $0.transferSide == .incoming || $0.amount > 0 }),
              outgoing.id != incoming.id
        else {
            throw AdvanceServiceError.invalidRepaymentStructure
        }

        let allRepayments = try modelContext.fetch(FetchDescriptor<AdvanceRepayment>())
        let otherNormalized = allRepayments
            .filter { $0.id != repayment.id && $0.participant?.id == participant.id }
            .reduce(Decimal.zero) { $0 + $1.normalizedAmount }
        let updatedRepaid = otherNormalized + abs(draft.normalizedAmount)
        if updatedRepaid - participant.owedAmount > roundingTolerance {
            throw AdvanceServiceError.repaymentExceedsRemaining
        }

        let direction = inferSettlementDirection(for: participant, modelContext: modelContext)
        try validateSettlementCategory(draft.category, direction: direction)
        let amount = abs(draft.amount)
        let currencyCode = draft.currencyCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !currencyCode.isEmpty else {
            throw AdvanceServiceError.invalidRepaymentAmount
        }
        let finalNote = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let memo = finalNote.isEmpty ? advanceCase.title : finalNote
        let now = Date()

        outgoing.type = .transfer
        outgoing.amount = -amount
        outgoing.currencyCode = currencyCode
        outgoing.date = draft.date
        outgoing.transferGroupID = groupID
        outgoing.transferSide = .outgoing
        outgoing.linkedTransactionID = incoming.id
        outgoing.updatedAt = now

        incoming.type = .transfer
        incoming.amount = amount
        incoming.currencyCode = currencyCode
        incoming.date = draft.date
        incoming.transferGroupID = groupID
        incoming.transferSide = .incoming
        incoming.linkedTransactionID = outgoing.id
        incoming.updatedAt = now

        switch direction {
        case .iAdvancedOthers:
            outgoing.account = debtAccount
            outgoing.note = "\(memo) (還款至 \(draft.receiveAccount.name))"
            outgoing.category = nil
            outgoing.tags = []

            incoming.account = draft.receiveAccount
            incoming.note = "\(memo) (來自 \(participant.name))"
            incoming.category = draft.category
            incoming.tags = draft.tags
        case .othersAdvancedMe:
            outgoing.account = draft.receiveAccount
            outgoing.note = "\(memo) (還款給 \(participant.name))"
            outgoing.category = draft.category
            outgoing.tags = draft.tags

            incoming.account = debtAccount
            incoming.note = "\(memo) (來自 \(draft.receiveAccount.name))"
            incoming.category = nil
            incoming.tags = []
        }

        repayment.amount = amount
        repayment.currencyCode = currencyCode
        repayment.normalizedAmount = abs(draft.normalizedAmount)
        repayment.date = draft.date
        repayment.note = finalNote
        repayment.receivedAccount = draft.receiveAccount

        participant.repaidAmount = min(updatedRepaid, participant.owedAmount)
        participant.updatedAt = now
        advanceCase.updatedAt = now
        try modelContext.save()
    }

    @MainActor
    static func updateInitialEntry(
        advanceCase: AdvanceCase,
        participant: AdvanceParticipant,
        draft: InitialEntryEditDraft,
        modelContext: ModelContext
    ) throws {
        guard participant.advanceCase?.id == advanceCase.id else {
            throw AdvanceServiceError.participantNotInCase
        }
        guard draft.owedAmount > 0 else {
            throw AdvanceServiceError.invalidAdjustedOwedAmount
        }
        guard draft.owedAmount + roundingTolerance >= participant.repaidAmount else {
            throw AdvanceServiceError.adjustedOwedLowerThanRepaid
        }
        let trimmedParticipantName = draft.participantName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let targetName = (trimmedParticipantName?.isEmpty == false)
            ? trimmedParticipantName!
            : participant.name
        let targetDebtAccount = draft.debtAccount ?? participant.debtAccount
        guard let targetDebtAccount, targetDebtAccount.type == .debt, !targetDebtAccount.isArchived else {
            throw AdvanceServiceError.invalidPayerAccount
        }

        let direction = inferSettlementDirection(for: participant, modelContext: modelContext)
        if direction == .iAdvancedOthers {
            guard let payerAccount = draft.payerAccount,
                  payerAccount.type != .debt,
                  !payerAccount.isArchived
            else {
                throw AdvanceServiceError.invalidPayerAccount
            }
        } else if let category = draft.category, !category.kind.supports(.expense) {
            throw AdvanceServiceError.invalidSettlementCategory
        }

        let entries = try advanceCase.participants.map { caseParticipant -> (AdvanceParticipant, [FinancialTransaction]) in
            guard let groupID = caseParticipant.initialTransferGroupID else {
                throw AdvanceServiceError.missingRepaymentLink
            }
            let descriptor = FetchDescriptor<FinancialTransaction>(
                predicate: #Predicate { $0.transferGroupID == groupID }
            )
            let transactions = try modelContext.fetch(descriptor)
            guard !transactions.isEmpty,
                  inferSettlementDirection(for: caseParticipant, modelContext: modelContext) == direction
            else {
                throw AdvanceServiceError.invalidRepaymentStructure
            }
            switch direction {
            case .iAdvancedOthers:
                guard transactions.count == 2,
                      let outgoing = transactions.first(where: {
                          $0.transferSide == .outgoing || $0.amount < 0
                      }),
                      let incoming = transactions.first(where: {
                          $0.transferSide == .incoming || $0.amount > 0
                      }),
                      outgoing.id != incoming.id
                else {
                    throw AdvanceServiceError.invalidRepaymentStructure
                }
            case .othersAdvancedMe:
                guard transactions.count == 1, caseParticipant.debtAccount != nil else {
                    throw AdvanceServiceError.invalidRepaymentStructure
                }
            }
            return (caseParticipant, transactions)
        }

        let originalBudgetKeys = entries
            .flatMap(\.1)
            .compactMap(BudgetHistoryService.affectedKey(for:))
        let targetTitle = draft.caseTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = (targetTitle?.isEmpty == false) ? targetTitle! : advanceCase.title
        let memo = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseMemo = memo.isEmpty ? finalTitle : memo
        let now = Date()

        for (caseParticipant, transactions) in entries {
            let amount = caseParticipant.id == participant.id
                ? abs(draft.owedAmount)
                : abs(caseParticipant.owedAmount)
            let participantName = caseParticipant.id == participant.id
                ? targetName
                : caseParticipant.name
            let debtAccount = caseParticipant.id == participant.id
                ? targetDebtAccount
                : caseParticipant.debtAccount
            switch direction {
            case .iAdvancedOthers:
                guard let debtAccount,
                      let outgoing = transactions.first(where: {
                          $0.transferSide == .outgoing || $0.amount < 0
                      }),
                      let incoming = transactions.first(where: {
                          $0.transferSide == .incoming || $0.amount > 0
                      }),
                      let payerAccount = caseParticipant.id == participant.id
                        ? draft.payerAccount
                        : outgoing.account
                else {
                    throw AdvanceServiceError.invalidRepaymentStructure
                }
                guard payerAccount.type != .debt, !payerAccount.isArchived else {
                    throw AdvanceServiceError.invalidPayerAccount
                }
                let paymentAmount = caseParticipant.id == participant.id
                    ? abs(draft.paymentAmount ?? draft.owedAmount)
                    : abs(outgoing.amount)
                let paymentCurrency = caseParticipant.id == participant.id
                    ? (draft.paymentCurrencyCode ?? advanceCase.currencyCode)
                    : outgoing.currencyCode
                outgoing.type = .transfer
                outgoing.amount = -paymentAmount
                outgoing.currencyCode = paymentCurrency
                outgoing.date = draft.date
                outgoing.note = "\(baseMemo) (代墊給 \(participantName))"
                outgoing.account = payerAccount
                outgoing.category = nil
                outgoing.tags = []
                outgoing.transferSide = .outgoing
                outgoing.linkedTransactionID = incoming.id
                outgoing.advanceCaseID = advanceCase.id
                outgoing.advanceParticipantID = caseParticipant.id
                outgoing.advanceEntryRole = .initialAsset
                outgoing.updatedAt = now

                incoming.type = .transfer
                incoming.amount = amount
                incoming.currencyCode = advanceCase.currencyCode
                incoming.date = draft.date
                incoming.note = "\(baseMemo) (來自 \(payerAccount.name))"
                incoming.account = debtAccount
                incoming.category = nil
                incoming.tags = []
                incoming.transferSide = .incoming
                incoming.linkedTransactionID = outgoing.id
                incoming.advanceCaseID = advanceCase.id
                incoming.advanceParticipantID = caseParticipant.id
                incoming.advanceEntryRole = .initialDebt
                incoming.updatedAt = now
            case .othersAdvancedMe:
                guard let expense = transactions.first,
                      let debtAccount
                else {
                    throw AdvanceServiceError.invalidRepaymentStructure
                }
                expense.type = .expense
                expense.amount = -amount
                expense.currencyCode = advanceCase.currencyCode
                expense.date = draft.date
                expense.note = "\(baseMemo) (他人代墊我：\(participantName))"
                expense.account = debtAccount
                expense.category = draft.category
                expense.tags = draft.tags
                expense.linkedTransactionID = nil
                expense.transferSide = .outgoing
                expense.advanceCaseID = advanceCase.id
                expense.advanceParticipantID = caseParticipant.id
                expense.advanceEntryRole = .initialDebt
                expense.updatedAt = now
            }
        }

        participant.owedAmount = abs(draft.owedAmount)
        participant.repaidAmount = min(participant.repaidAmount, participant.owedAmount)
        participant.name = targetName
        participant.debtAccount = targetDebtAccount
        participant.updatedAt = now
        advanceCase.title = finalTitle
        if direction == .iAdvancedOthers {
            let paymentAccounts = entries.compactMap { _, transactions in
                transactions.first(where: {
                    $0.transferSide == .outgoing || $0.amount < 0
                })?.account
            }
            let uniqueAccountIDs = Set(paymentAccounts.map(\.id))
            advanceCase.payerAccount = uniqueAccountIDs.count == 1 ? paymentAccounts.first : nil
        } else {
            advanceCase.payerAccount = nil
        }
        advanceCase.direction = direction == .iAdvancedOthers ? .iAdvancedOthers : .othersAdvancedMe
        advanceCase.tagIDs = draft.tags.map(\.id)
        if direction == .othersAdvancedMe {
            advanceCase.expenseCategory = draft.category
        }
        advanceCase.date = draft.date
        advanceCase.note = memo
        advanceCase.updatedAt = now

        let affectedKeys = originalBudgetKeys + entries
            .flatMap(\.1)
            .compactMap(BudgetHistoryService.affectedKey(for:))
        if affectedKeys.isEmpty {
            try modelContext.save()
        } else {
            try BudgetHistoryService.shared.syncAffected(
                keys: affectedKeys,
                modelContext: modelContext,
                currencyService: CurrencyService.shared
            )
        }
    }

    @MainActor
    static func inferSettlementDirection(
        for participant: AdvanceParticipant,
        modelContext: ModelContext
    ) -> SettlementDirection {
        guard let groupID = participant.initialTransferGroupID else {
            return .iAdvancedOthers
        }

        let descriptor = FetchDescriptor<FinancialTransaction>(
            predicate: #Predicate { $0.transferGroupID == groupID }
        )
        let groupedTransfers = (try? modelContext.fetch(descriptor)) ?? []

        guard let outgoing = groupedTransfers.first(where: { $0.transferSide == .outgoing || $0.amount < 0 }) else {
            return .iAdvancedOthers
        }

        if let debtAccount = participant.debtAccount, outgoing.account?.id == debtAccount.id {
            return .othersAdvancedMe
        }

        let compactedNote = outgoing.note.replacingOccurrences(of: " ", with: "")
        if compactedNote.contains("(代墊給我") || compactedNote.contains("(他人代墊我") {
            return .othersAdvancedMe
        }

        return .iAdvancedOthers
    }
    
    @MainActor
    static func updateParticipantOwedAmount(
        advanceCase: AdvanceCase,
        participant: AdvanceParticipant,
        newOwedAmount: Decimal,
        modelContext: ModelContext
    ) throws {
        guard participant.advanceCase?.id == advanceCase.id else {
            throw AdvanceServiceError.participantNotInCase
        }
        guard newOwedAmount > 0 else {
            throw AdvanceServiceError.invalidAdjustedOwedAmount
        }
        guard newOwedAmount + roundingTolerance >= participant.repaidAmount else {
            throw AdvanceServiceError.adjustedOwedLowerThanRepaid
        }
        
        guard let groupID = participant.initialTransferGroupID else {
            throw AdvanceServiceError.missingRepaymentLink
        }
        let descriptor = FetchDescriptor<FinancialTransaction>(
            predicate: #Predicate { $0.transferGroupID == groupID }
        )
        let linkedTransactions = try modelContext.fetch(descriptor)
        guard !linkedTransactions.isEmpty else {
            throw AdvanceServiceError.missingRepaymentLink
        }
        let originalBudgetKeys = linkedTransactions.compactMap(
            BudgetHistoryService.affectedKey(for:)
        )

        let direction = inferSettlementDirection(for: participant, modelContext: modelContext)
        let amount = abs(newOwedAmount)
        let now = Date()
        switch direction {
        case .iAdvancedOthers:
            guard linkedTransactions.count == 2 else {
                throw AdvanceServiceError.invalidRepaymentStructure
            }
            for transaction in linkedTransactions {
                let side = transaction.transferSide
                    ?? (transaction.amount < 0 ? .outgoing : .incoming)
                transaction.amount = side == .outgoing ? -amount : amount
                transaction.currencyCode = advanceCase.currencyCode
                transaction.date = advanceCase.date
                transaction.transferSide = side
                transaction.updatedAt = now
            }
        case .othersAdvancedMe:
            guard linkedTransactions.count == 1,
                  let expense = linkedTransactions.first,
                  let debtAccount = participant.debtAccount
            else {
                throw AdvanceServiceError.invalidRepaymentStructure
            }
            expense.type = .expense
            expense.amount = -amount
            expense.currencyCode = advanceCase.currencyCode
            expense.date = advanceCase.date
            expense.linkedTransactionID = nil
            expense.transferGroupID = groupID
            expense.transferSide = .outgoing
            expense.account = debtAccount
            expense.category = advanceCase.expenseCategory
            expense.updatedAt = now
        }

        participant.owedAmount = amount
        participant.repaidAmount = min(participant.repaidAmount, amount)
        participant.updatedAt = now
        advanceCase.updatedAt = now
        let affectedKeys = originalBudgetKeys + linkedTransactions.compactMap(
            BudgetHistoryService.affectedKey(for:)
        )
        if affectedKeys.isEmpty {
            try modelContext.save()
        } else {
            try BudgetHistoryService.shared.syncAffected(
                keys: affectedKeys,
                modelContext: modelContext,
                currencyService: CurrencyService.shared
            )
        }
    }

    private static func validateSettlementCategory(
        _ category: Category?,
        direction: SettlementDirection
    ) throws {
        guard let category else { return }
        let expectedType: TransactionType = direction == .iAdvancedOthers ? .income : .expense
        guard category.kind.supports(expectedType) else {
            throw AdvanceServiceError.invalidSettlementCategory
        }
    }

    private struct OffsetParticipantEntry {
        let participant: AdvanceParticipant
        let advanceCase: AdvanceCase
    }

    @MainActor
    private static func offsetableParticipants(
        debtAccount: Account,
        currencyCode: String,
        advanceCases: [AdvanceCase],
        modelContext: ModelContext
    ) -> (receivable: [OffsetParticipantEntry], payable: [OffsetParticipantEntry]) {
        var receivable: [OffsetParticipantEntry] = []
        var payable: [OffsetParticipantEntry] = []

        for advanceCase in advanceCases where advanceCase.currencyCode == currencyCode {
            for participant in advanceCase.participants {
                guard participant.debtAccount?.id == debtAccount.id,
                      participant.remainingAmount > roundingTolerance else {
                    continue
                }
                let entry = OffsetParticipantEntry(participant: participant, advanceCase: advanceCase)
                switch inferSettlementDirection(for: participant, modelContext: modelContext) {
                case .iAdvancedOthers:
                    receivable.append(entry)
                case .othersAdvancedMe:
                    payable.append(entry)
                }
            }
        }

        let byDate: (OffsetParticipantEntry, OffsetParticipantEntry) -> Bool = {
            if $0.advanceCase.date == $1.advanceCase.date {
                return $0.participant.createdAt < $1.participant.createdAt
            }
            return $0.advanceCase.date < $1.advanceCase.date
        }
        return (receivable.sorted(by: byDate), payable.sorted(by: byDate))
    }

    @MainActor
    private static func applyMutualDebtOffset(
        amount: Decimal,
        entries: [OffsetParticipantEntry],
        date: Date,
        note: String,
        modelContext: ModelContext
    ) -> Int {
        var remaining = amount
        var repaymentCount = 0

        for entry in entries where remaining > roundingTolerance {
            let allocation = min(entry.participant.remainingAmount, remaining)
            guard allocation > roundingTolerance else { continue }

            let repayment = AdvanceRepayment(
                amount: allocation,
                currencyCode: entry.advanceCase.currencyCode,
                normalizedAmount: allocation,
                date: date,
                note: note,
                linkedTransferGroupID: nil,
                createdAt: Date(),
                advanceCase: entry.advanceCase,
                participant: entry.participant,
                receivedAccount: nil
            )
            modelContext.insert(repayment)

            let updatedRepaid = entry.participant.repaidAmount + allocation
            entry.participant.repaidAmount = entry.participant.owedAmount - updatedRepaid < roundingTolerance
                ? entry.participant.owedAmount
                : updatedRepaid
            entry.participant.updatedAt = Date()
            entry.advanceCase.updatedAt = Date()
            remaining -= allocation
            repaymentCount += 1
        }

        return repaymentCount
    }

    @MainActor
    private static func applyManualDebtSettlement(
        amount: Decimal,
        entries: [OffsetParticipantEntry],
        date: Date,
        note: String,
        modelContext: ModelContext
    ) -> Int {
        applyMutualDebtOffset(
            amount: amount,
            entries: entries,
            date: date,
            note: note,
            modelContext: modelContext
        )
    }
    
    @MainActor
    static func rollbackRepayment(
        advanceCase: AdvanceCase,
        repayment: AdvanceRepayment,
        autosave: Bool = true,
        modelContext: ModelContext
    ) throws {
        guard repayment.advanceCase?.id == advanceCase.id else {
            throw AdvanceServiceError.participantNotInCase
        }
        guard let participant = repayment.participant else {
            throw AdvanceServiceError.missingRepaymentParticipant
        }
        guard !isMutualDebtOffset(note: repayment.note),
              !isManualDebtSettlement(note: repayment.note) else {
            throw AdvanceServiceError.specialRepaymentRequiresGroupRollback
        }
        
        if let groupID = repayment.linkedTransferGroupID {
            let descriptor = FetchDescriptor<FinancialTransaction>(
                predicate: #Predicate { $0.transferGroupID == groupID }
            )
            let linkedTransfers = (try? modelContext.fetch(descriptor)) ?? []
            for tx in linkedTransfers {
                modelContext.delete(tx)
            }
        }
        
        let updatedRepaid = participant.repaidAmount - repayment.normalizedAmount
        participant.repaidAmount = updatedRepaid > 0 ? updatedRepaid : 0
        participant.updatedAt = Date()
        advanceCase.updatedAt = Date()
        
        modelContext.delete(repayment)
        if autosave {
            try modelContext.save()
        }
    }

    @MainActor
    private static func rollbackSpecialRepaymentGroup(
        matching predicate: (AdvanceRepayment) -> Bool,
        modelContext: ModelContext
    ) throws -> Int {
        let repayments = try modelContext.fetch(FetchDescriptor<AdvanceRepayment>())
            .filter(predicate)
        guard !repayments.isEmpty else { return 0 }

        let now = Date()
        for repayment in repayments {
            if let participant = repayment.participant {
                let updated = participant.repaidAmount - repayment.normalizedAmount
                participant.repaidAmount = updated > 0 ? updated : 0
                participant.updatedAt = now
            }
            repayment.advanceCase?.updatedAt = now
            modelContext.delete(repayment)
        }
        try modelContext.save()
        return repayments.count
    }
    
    @MainActor
    static func deleteAdvanceCase(
        _ advanceCase: AdvanceCase,
        deleteLinkedTransactions: Bool,
        autosave: Bool = true,
        modelContext: ModelContext
    ) throws -> DeleteAdvanceResult {
        var deletedTransactionCount = 0
        var missingLinkedRecordCount = 0
        var affectedBudgetKeys: [BudgetHistoryAffectedKey] = []
        
        if deleteLinkedTransactions {
            var groupIDs = Set<UUID>()
            
            for participant in advanceCase.participants {
                if let groupID = participant.initialTransferGroupID {
                    groupIDs.insert(groupID)
                } else {
                    missingLinkedRecordCount += 1
                }
            }
            
            for repayment in advanceCase.repayments {
                if let groupID = repayment.linkedTransferGroupID {
                    groupIDs.insert(groupID)
                } else {
                    missingLinkedRecordCount += 1
                }
            }
            
            for groupID in groupIDs {
                let descriptor = FetchDescriptor<FinancialTransaction>(
                    predicate: #Predicate { $0.transferGroupID == groupID }
                )
                let linkedTransfers = (try? modelContext.fetch(descriptor)) ?? []
                deletedTransactionCount += linkedTransfers.count
                for tx in linkedTransfers {
                    modelContext.delete(tx)
                }
            }
            
            if let expenseID = advanceCase.selfExpenseTransactionID {
                let descriptor = FetchDescriptor<FinancialTransaction>(
                    predicate: #Predicate { $0.id == expenseID }
                )
                if let expenseTx = try? modelContext.fetch(descriptor).first {
                    if let key = BudgetHistoryService.affectedKey(for: expenseTx) {
                        affectedBudgetKeys.append(key)
                    }
                    modelContext.delete(expenseTx)
                    deletedTransactionCount += 1
                } else {
                    missingLinkedRecordCount += 1
                }
            }
        }
        
        modelContext.delete(advanceCase)
        if autosave {
            try modelContext.save()
            try BudgetHistoryService.shared.syncAffected(
                keys: affectedBudgetKeys,
                modelContext: modelContext,
                currencyService: CurrencyService.shared
            )
        }
        
        return DeleteAdvanceResult(
            deletedTransactionCount: deletedTransactionCount,
            missingLinkedRecordCount: missingLinkedRecordCount
        )
    }

    @MainActor
    static func repairLegacyLinks(modelContext: ModelContext) throws -> LegacyLinkRepairResult {
        let advanceCases = try modelContext.fetch(FetchDescriptor<AdvanceCase>())
        let participants = try modelContext.fetch(FetchDescriptor<AdvanceParticipant>())
        let repayments = try modelContext.fetch(FetchDescriptor<AdvanceRepayment>())
        let transactions = try modelContext.fetch(FetchDescriptor<FinancialTransaction>())
        
        var updatedCaseLinkCount = 0
        var unresolvedCaseLinkCount = 0
        var updatedParticipantLinkCount = 0
        var unresolvedParticipantLinkCount = 0
        
        let groupedTransfers = Dictionary(
            grouping: transactions.filter { $0.type == .transfer && $0.transferGroupID != nil }
        ) { $0.transferGroupID! }
        
        var usedExpenseIDs = Set<UUID>(advanceCases.compactMap(\.selfExpenseTransactionID))
        var usedGroupIDs = Set<UUID>(participants.compactMap(\.initialTransferGroupID))
        usedGroupIDs.formUnion(repayments.compactMap(\.linkedTransferGroupID))
        
        let now = Date()
        let calendar = Calendar.current
        
        for advanceCase in advanceCases where advanceCase.myShareAmount > 0 && advanceCase.selfExpenseTransactionID == nil {
            guard let payerAccount = advanceCase.payerAccount else {
                unresolvedCaseLinkCount += 1
                continue
            }
            
            let targetAmount = -abs(advanceCase.myShareAmount)
            let candidates = transactions.filter { tx in
                tx.type == .expense
                    && tx.account?.id == payerAccount.id
                    && tx.currencyCode == advanceCase.currencyCode
                    && decimalEquals(tx.amount, targetAmount)
                    && calendar.isDate(tx.date, inSameDayAs: advanceCase.date)
                    && !usedExpenseIDs.contains(tx.id)
            }
            
            if let best = bestSelfExpenseCandidate(candidates, advanceCase: advanceCase) {
                advanceCase.selfExpenseTransactionID = best.id
                advanceCase.updatedAt = now
                usedExpenseIDs.insert(best.id)
                updatedCaseLinkCount += 1
            } else {
                unresolvedCaseLinkCount += 1
            }
        }
        
        for participant in participants where participant.initialTransferGroupID == nil {
            guard
                let advanceCase = participant.advanceCase,
                let payerAccount = advanceCase.payerAccount,
                let debtAccount = participant.debtAccount
            else {
                unresolvedParticipantLinkCount += 1
                continue
            }
            
            let targetOutgoing = -abs(participant.owedAmount)
            let targetIncoming = abs(participant.owedAmount)
            let participantName = participant.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let payerName = payerAccount.name.trimmingCharacters(in: .whitespacesAndNewlines)
            
            var bestGroupID: UUID?
            var bestScore = Int.min
            var bestDateDiff = TimeInterval.greatestFiniteMagnitude
            
            for (groupID, group) in groupedTransfers {
                if usedGroupIDs.contains(groupID) {
                    continue
                }
                
                let outgoingCandidates = group.filter { tx in
                    tx.account?.id == payerAccount.id
                        && tx.currencyCode == advanceCase.currencyCode
                        && decimalEquals(tx.amount, targetOutgoing)
                }
                if outgoingCandidates.isEmpty {
                    continue
                }
                
                let incomingCandidates = group.filter { tx in
                    tx.account?.id == debtAccount.id
                        && tx.currencyCode == advanceCase.currencyCode
                        && decimalEquals(tx.amount, targetIncoming)
                }
                if incomingCandidates.isEmpty {
                    continue
                }
                
                let outgoingByDate = outgoingCandidates.sorted {
                    abs($0.date.timeIntervalSince(advanceCase.date)) < abs($1.date.timeIntervalSince(advanceCase.date))
                }
                let incomingByDate = incomingCandidates.sorted {
                    abs($0.date.timeIntervalSince(advanceCase.date)) < abs($1.date.timeIntervalSince(advanceCase.date))
                }
                
                guard let outgoing = outgoingByDate.first, let incoming = incomingByDate.first else {
                    continue
                }
                
                var score = 0
                if outgoing.note.contains("代墊") {
                    score += 2
                }
                if !participantName.isEmpty && outgoing.note.localizedCaseInsensitiveContains(participantName) {
                    score += 3
                }
                if !payerName.isEmpty && incoming.note.localizedCaseInsensitiveContains(payerName) {
                    score += 1
                }
                
                let outgoingDateDiff = abs(outgoing.date.timeIntervalSince(advanceCase.date))
                let incomingDateDiff = abs(incoming.date.timeIntervalSince(advanceCase.date))
                let dateDiff = min(outgoingDateDiff, incomingDateDiff)
                
                if outgoingDateDiff <= 5 * 60 {
                    score += 2
                } else if calendar.isDate(outgoing.date, inSameDayAs: advanceCase.date) {
                    score += 1
                }
                
                if incomingDateDiff <= 5 * 60 {
                    score += 1
                }
                
                if score > bestScore || (score == bestScore && dateDiff < bestDateDiff) {
                    bestScore = score
                    bestDateDiff = dateDiff
                    bestGroupID = groupID
                }
            }
            
            if let groupID = bestGroupID {
                participant.initialTransferGroupID = groupID
                participant.updatedAt = now
                advanceCase.updatedAt = now
                usedGroupIDs.insert(groupID)
                updatedParticipantLinkCount += 1
            } else {
                unresolvedParticipantLinkCount += 1
            }
        }
        
        if updatedCaseLinkCount > 0 || updatedParticipantLinkCount > 0 {
            try modelContext.save()
        }
        
        return LegacyLinkRepairResult(
            updatedCaseLinkCount: updatedCaseLinkCount,
            unresolvedCaseLinkCount: unresolvedCaseLinkCount,
            updatedParticipantLinkCount: updatedParticipantLinkCount,
            unresolvedParticipantLinkCount: unresolvedParticipantLinkCount
        )
    }

    @MainActor
    static func backfillExplicitLinks(modelContext: ModelContext) throws -> ExplicitLinkBackfillResult {
        let advanceCases = try modelContext.fetch(FetchDescriptor<AdvanceCase>())
        let transactions = try modelContext.fetch(FetchDescriptor<FinancialTransaction>())
        let transactionByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        let transactionsByGroup = Dictionary(
            grouping: transactions.compactMap { transaction -> (UUID, FinancialTransaction)? in
                transaction.transferGroupID.map { ($0, transaction) }
            },
            by: \.0
        ).mapValues { $0.map(\.1) }

        var linkedTransactionCount = 0
        var updatedCaseCount = 0
        var unresolvedRecordCount = 0

        for advanceCase in advanceCases {
            if advanceCase.direction == nil {
                if let participant = advanceCase.participants.first {
                    advanceCase.direction = inferSettlementDirection(
                        for: participant,
                        modelContext: modelContext
                    ) == .iAdvancedOthers ? .iAdvancedOthers : .othersAdvancedMe
                    updatedCaseCount += 1
                } else {
                    unresolvedRecordCount += 1
                }
            }

            if (advanceCase.tagIDs ?? []).isEmpty,
               let expenseID = advanceCase.selfExpenseTransactionID,
               let expense = transactionByID[expenseID] {
                advanceCase.tagIDs = expense.tags.map(\.id)
                updatedCaseCount += 1
            }

            if let expenseID = advanceCase.selfExpenseTransactionID,
               let expense = transactionByID[expenseID] {
                if expense.advanceCaseID == nil {
                    expense.advanceCaseID = advanceCase.id
                    expense.advanceEntryRole = .selfExpense
                    linkedTransactionCount += 1
                }
            } else if advanceCase.myShareAmount > 0, advanceCase.direction == .iAdvancedOthers {
                unresolvedRecordCount += 1
            }

            for participant in advanceCase.participants {
                guard let groupID = participant.initialTransferGroupID,
                      let entries = transactionsByGroup[groupID],
                      !entries.isEmpty
                else {
                    unresolvedRecordCount += 1
                    continue
                }
                for entry in entries {
                    guard entry.advanceCaseID == nil else { continue }
                    entry.advanceCaseID = advanceCase.id
                    entry.advanceParticipantID = participant.id
                    entry.advanceEntryRole = entry.account?.type == .debt ? .initialDebt : .initialAsset
                    linkedTransactionCount += 1
                }
            }

            for repayment in advanceCase.repayments {
                guard let groupID = repayment.linkedTransferGroupID,
                      let entries = transactionsByGroup[groupID],
                      !entries.isEmpty
                else {
                    if repaymentRecordKind(note: repayment.note) == .ordinary {
                        unresolvedRecordCount += 1
                    }
                    continue
                }
                for entry in entries {
                    guard entry.advanceCaseID == nil else { continue }
                    entry.advanceCaseID = advanceCase.id
                    entry.advanceParticipantID = repayment.participant?.id
                    entry.advanceRepaymentID = repayment.id
                    entry.advanceEntryRole = entry.account?.type == .debt ? .repaymentDebt : .repaymentAsset
                    linkedTransactionCount += 1
                }
            }
        }

        if linkedTransactionCount > 0 || updatedCaseCount > 0 {
            try modelContext.save()
        }
        return ExplicitLinkBackfillResult(
            linkedTransactionCount: linkedTransactionCount,
            updatedCaseCount: updatedCaseCount,
            unresolvedRecordCount: unresolvedRecordCount
        )
    }
    
    private static func bestSelfExpenseCandidate(
        _ candidates: [FinancialTransaction],
        advanceCase: AdvanceCase
    ) -> FinancialTransaction? {
        guard !candidates.isEmpty else { return nil }
        
        let trimmedTitle = advanceCase.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = advanceCase.note.trimmingCharacters(in: .whitespacesAndNewlines)
        
        var bestCandidate: FinancialTransaction?
        var bestScore = Int.min
        var bestDateDiff = TimeInterval.greatestFiniteMagnitude
        
        for candidate in candidates {
            var score = 0
            
            if candidate.note.contains("自己份額") {
                score += 4
            }
            if !trimmedTitle.isEmpty && candidate.note.localizedCaseInsensitiveContains(trimmedTitle) {
                score += 2
            }
            if !trimmedNote.isEmpty && candidate.note.localizedCaseInsensitiveContains(trimmedNote) {
                score += 3
            }
            if let expenseCategoryID = advanceCase.expenseCategory?.id,
               candidate.category?.id == expenseCategoryID {
                score += 2
            }
            
            let dateDiff = abs(candidate.date.timeIntervalSince(advanceCase.date))
            if dateDiff <= 5 * 60 {
                score += 2
            } else if dateDiff <= 60 * 60 {
                score += 1
            }
            
            if score > bestScore || (score == bestScore && dateDiff < bestDateDiff) {
                bestScore = score
                bestDateDiff = dateDiff
                bestCandidate = candidate
            }
        }
        
        return bestCandidate
    }
    
    private static func decimalEquals(_ lhs: Decimal, _ rhs: Decimal) -> Bool {
        abs(lhs - rhs) <= roundingTolerance
    }

    private static func extractTransferMemo(_ note: String) -> String {
        let separators = [
            " (代墊給", " (還款至", " (轉至", " (來自", " (借入至", " (還款給"
        ]

        for separator in separators {
            if let range = note.range(of: separator) {
                return String(note[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
