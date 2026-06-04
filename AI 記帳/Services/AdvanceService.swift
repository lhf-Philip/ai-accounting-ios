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
        case .cannotDeleteAdvanceCaseWithoutModelContext:
            return "刪除代墊失敗：缺少可用資料上下文。"
        }
    }
}

enum AdvanceService {
    enum SettlementDirection {
        case iAdvancedOthers
        case othersAdvancedMe
    }

    struct ParticipantInput {
        let debtAccount: Account
        let owedAmount: Decimal
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

    struct LegacyBorrowedAdvanceRepairResult {
        let repairedParticipantCount: Int
        let removedInflatedAccountTransactionCount: Int
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
    
    private static let roundingTolerance = Decimal(string: "0.0001") ?? 0.0001
    static let mutualDebtOffsetMarkerPrefix = "[債務抵銷:"
    
    static func totalAdvanced(for advanceCase: AdvanceCase) -> Decimal {
        advanceCase.myShareAmount + advanceCase.participants.reduce(Decimal.zero) { $0 + $1.owedAmount }
    }
    
    static func outstandingAmount(for advanceCase: AdvanceCase) -> Decimal {
        advanceCase.participants.reduce(Decimal.zero) { partial, participant in
            partial + participant.remainingAmount
        }
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
        let repayments = try modelContext.fetch(FetchDescriptor<AdvanceRepayment>())
            .filter { mutualDebtOffsetID(from: $0.note) == offsetGroupID }
        guard !repayments.isEmpty else { return 0 }

        for repayment in repayments {
            if let participant = repayment.participant {
                let updated = participant.repaidAmount - repayment.normalizedAmount
                participant.repaidAmount = updated > 0 ? updated : 0
                participant.updatedAt = Date()
            }
            repayment.advanceCase?.updatedAt = Date()
            modelContext.delete(repayment)
        }
        try modelContext.save()
        return repayments.count
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

        if outgoing.note.replacingOccurrences(of: " ", with: "").contains("(代墊給我") {
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
        
        participant.owedAmount = newOwedAmount
        if participant.repaidAmount > newOwedAmount {
            participant.repaidAmount = newOwedAmount
        }
        participant.updatedAt = Date()
        advanceCase.updatedAt = Date()
        
        try modelContext.save()
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
    static func syncLinkedTransferGroup(
        groupID: UUID,
        modelContext: ModelContext
    ) throws {
        let txDescriptor = FetchDescriptor<FinancialTransaction>(
            predicate: #Predicate { $0.transferGroupID == groupID }
        )
        let transfers = try modelContext.fetch(txDescriptor).filter { $0.type == .transfer }
        guard !transfers.isEmpty else { return }

        let outgoing = transfers.first(where: { $0.transferSide == .outgoing || $0.amount < 0 })
        let incoming = transfers.first(where: { $0.transferSide == .incoming || $0.amount > 0 })
        let now = Date()

        let participantDescriptor = FetchDescriptor<AdvanceParticipant>(
            predicate: #Predicate { $0.initialTransferGroupID == groupID }
        )
        if let participant = try modelContext.fetch(participantDescriptor).first {
            if incoming == nil, outgoing?.type == .expense, let debtAccount = outgoing?.account {
                participant.debtAccount = debtAccount
                participant.name = debtAccount.name
            } else if let incoming, let debtAccount = incoming.account {
                participant.debtAccount = debtAccount
                participant.name = debtAccount.name
            }

            if let advanceCase = participant.advanceCase {
                if let outgoing, incoming != nil {
                    advanceCase.payerAccount = outgoing.account
                }
                if let amountSource = incoming ?? outgoing {
                    let normalized = CurrencyService.shared.convert(
                        amount: abs(amountSource.amount),
                        from: amountSource.currencyCode,
                        to: advanceCase.currencyCode
                    )
                    participant.owedAmount = normalized >= participant.repaidAmount
                        ? normalized
                        : participant.repaidAmount
                }
                advanceCase.updatedAt = now
            }
            participant.updatedAt = now
        }

        let repaymentDescriptor = FetchDescriptor<AdvanceRepayment>(
            predicate: #Predicate { $0.linkedTransferGroupID == groupID }
        )
        if let repayment = try modelContext.fetch(repaymentDescriptor).first {
            if let incoming {
                repayment.amount = abs(incoming.amount)
                repayment.currencyCode = incoming.currencyCode
                repayment.date = incoming.date
                repayment.note = extractTransferMemo(incoming.note)
                repayment.receivedAccount = incoming.account

                if let advanceCase = repayment.advanceCase {
                    repayment.normalizedAmount = CurrencyService.shared.convert(
                        amount: abs(incoming.amount),
                        from: incoming.currencyCode,
                        to: advanceCase.currencyCode
                    )
                    advanceCase.updatedAt = now
                }
            }

            if let participant = repayment.participant, let advanceCase = repayment.advanceCase {
                let normalizedTotal = advanceCase.repayments
                    .filter { $0.participant?.id == participant.id }
                    .reduce(Decimal.zero) { $0 + $1.normalizedAmount }
                participant.repaidAmount = normalizedTotal > participant.owedAmount
                    ? participant.owedAmount
                    : normalizedTotal
                participant.updatedAt = now
            }
        }
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
