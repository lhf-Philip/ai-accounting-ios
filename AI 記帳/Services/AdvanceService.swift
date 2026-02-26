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
        }
    }
}

enum AdvanceService {
    struct ParticipantInput {
        let debtAccount: Account
        let owedAmount: Decimal
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
        participants: [ParticipantInput],
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
                category: category
            )
            modelContext.insert(expenseTx)
        }
        
        let transferMemo = finalNote.isEmpty ? finalTitle : finalNote
        
        for input in participants {
            let participant = AdvanceParticipant(
                name: input.debtAccount.name,
                owedAmount: abs(input.owedAmount),
                repaidAmount: 0,
                createdAt: now,
                updatedAt: now,
                advanceCase: advanceCase,
                debtAccount: input.debtAccount
            )
            modelContext.insert(participant)
            
            let outID = UUID()
            let inID = UUID()
            let transferGroupID = UUID()
            
            let outTx = FinancialTransaction(
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
            
            let inTx = FinancialTransaction(
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
        currencyService: CurrencyService,
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
        
        let debtOutTx = FinancialTransaction(
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
        
        let myInTx = FinancialTransaction(
            id: inID,
            amount: abs(amount),
            currencyCode: currencyCode,
            date: date,
            note: "\(memo) (來自 \(debtAccount.name))",
            type: .transfer,
            linkedTransactionID: outID,
            transferGroupID: transferGroupID,
            transferSide: .incoming,
            account: receiveAccount
        )
        
        modelContext.insert(debtOutTx)
        modelContext.insert(myInTx)
        
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
        
        try modelContext.save()
        return repayment
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
}
