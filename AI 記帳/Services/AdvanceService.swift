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
    
    private static let roundingTolerance = Decimal(string: "0.0001") ?? 0.0001
    
    static func totalAdvanced(for advanceCase: AdvanceCase) -> Decimal {
        advanceCase.myShareAmount + advanceCase.participants.reduce(Decimal.zero) { $0 + $1.owedAmount }
    }
    
    static func outstandingAmount(for advanceCase: AdvanceCase) -> Decimal {
        advanceCase.participants.reduce(Decimal.zero) { partial, participant in
            partial + participant.remainingAmount
        }
    }
    
    @MainActor
    static func createAdvanceCase(
        title: String,
        date: Date,
        currencyCode: String,
        myShareAmount: Decimal,
        note: String,
        payerAccount: Account,
        category: Category?,
        tags: [Tag],
        participants: [ParticipantInput],
        isBorrowedByMe: Bool = false,
        modelContext: ModelContext
    ) throws -> AdvanceCase {
        guard payerAccount.type != .debt else {
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
        
        if myShareAmount > 0 {
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
                outTx = FinancialTransaction(
                    id: outID,
                    amount: -abs(input.owedAmount),
                    currencyCode: currencyCode,
                    date: date,
                    note: "\(transferMemo) (代墊給我 \(payerAccount.name))",
                    type: .transfer,
                    linkedTransactionID: inID,
                    transferGroupID: transferGroupID,
                    transferSide: .outgoing,
                    account: input.debtAccount
                )

                inTx = FinancialTransaction(
                    id: inID,
                    amount: abs(input.owedAmount),
                    currencyCode: currencyCode,
                    date: date,
                    note: "\(transferMemo) (來自 \(input.debtAccount.name))",
                    type: .transfer,
                    linkedTransactionID: outID,
                    transferGroupID: transferGroupID,
                    transferSide: .incoming,
                    account: payerAccount
                )
            } else {
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
        return advanceCase
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
        
        let normalizedAmount = currencyService.convert(
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
    
    @MainActor
    static func rollbackRepayment(
        advanceCase: AdvanceCase,
        repayment: AdvanceRepayment,
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
        try modelContext.save()
    }
    
    @MainActor
    static func deleteAdvanceCase(
        _ advanceCase: AdvanceCase,
        deleteLinkedTransactions: Bool,
        modelContext: ModelContext
    ) throws -> DeleteAdvanceResult {
        var deletedTransactionCount = 0
        var missingLinkedRecordCount = 0
        
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
                    modelContext.delete(expenseTx)
                    deletedTransactionCount += 1
                } else {
                    missingLinkedRecordCount += 1
                }
            }
        }
        
        modelContext.delete(advanceCase)
        try modelContext.save()
        
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
            if let incoming, let debtAccount = incoming.account {
                participant.debtAccount = debtAccount
                participant.name = debtAccount.name
            }

            if let advanceCase = participant.advanceCase {
                if let outgoing {
                    advanceCase.payerAccount = outgoing.account
                }
                if let incoming {
                    let normalized = CurrencyService.shared.convert(
                        amount: abs(incoming.amount),
                        from: incoming.currencyCode,
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
