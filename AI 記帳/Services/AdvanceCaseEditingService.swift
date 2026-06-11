import Foundation
import SwiftData

struct AdvancePaymentLegDraft {
    let transactionID: UUID?
    let account: Account
    let amount: Decimal
    let currencyCode: String
}

struct AdvanceShareDraft {
    let transactionID: UUID?
    let account: Account
    let amount: Decimal
    let normalizedAmount: Decimal
    let currencyCode: String
}

struct AdvanceParticipantDraft {
    let participant: AdvanceParticipant
    let name: String
    let debtAccount: Account
    let owedAmount: Decimal
    let paymentLegs: [AdvancePaymentLegDraft]
}

struct AdvanceRepaymentDraft {
    let repayment: AdvanceRepayment
    let account: Account
    let amount: Decimal
    let currencyCode: String
    let normalizedAmount: Decimal
    let date: Date
    let note: String
    let category: Category?
    let tags: [Tag]
}

struct AdvanceCaseEditDraft {
    let advanceCase: AdvanceCase
    let title: String
    let date: Date
    let direction: AdvanceDirection
    let currencyCode: String
    let note: String
    let category: Category?
    let tags: [Tag]
    let share: AdvanceShareDraft?
    let participants: [AdvanceParticipantDraft]
    let repayments: [AdvanceRepaymentDraft]
}

struct AdvanceCaseImpactPreview {
    let changesDirection: Bool
    let changesCurrency: Bool
    let affectedTransactionCount: Int
    let affectedParticipantCount: Int
    let affectedRepaymentCount: Int
    let warnings: [String]
}

enum AdvanceCaseEditingError: LocalizedError {
    case emptyTitle
    case invalidCurrency
    case noParticipants
    case duplicateParticipant
    case invalidPaymentLeg
    case unsupportedDirectionChange
    case unsupportedSplitPaymentEdit
    case currencyChangeRequiresExplicitAmounts

    var errorDescription: String? {
        switch self {
        case .emptyTitle: return "請輸入案件名稱。"
        case .invalidCurrency: return "請選擇案件幣種。"
        case .noParticipants: return "請至少保留一位代墊對象。"
        case .duplicateParticipant: return "同一債務對象不可重複。"
        case .invalidPaymentLeg: return "實際付款帳戶、金額或幣種無效。"
        case .unsupportedDirectionChange:
            return "改變代墊方向需要重建底層分錄，請使用案件完整編輯流程。"
        case .unsupportedSplitPaymentEdit:
            return "多付款來源需要使用案件完整編輯流程。"
        case .currencyChangeRequiresExplicitAmounts:
            return "改變案件幣種前，必須重新確認每位對象與每筆還款的沖銷金額。"
        }
    }
}

enum AdvanceCaseEditingService {
    @MainActor
    static func preview(_ draft: AdvanceCaseEditDraft, modelContext: ModelContext) throws -> AdvanceCaseImpactPreview {
        try validate(draft)
        let transactions = try modelContext.fetch(FetchDescriptor<FinancialTransaction>())
        let affected = transactions.filter { $0.advanceCaseID == draft.advanceCase.id }
        var warnings: [String] = []
        if draft.direction != draft.advanceCase.direction {
            warnings.append("改變方向會重建案件的初始帳務分錄。")
        }
        if draft.currencyCode != draft.advanceCase.currencyCode {
            warnings.append("案件幣種改變後，舊金額不會自動換算。")
        }
        return AdvanceCaseImpactPreview(
            changesDirection: draft.direction != draft.advanceCase.direction,
            changesCurrency: draft.currencyCode != draft.advanceCase.currencyCode,
            affectedTransactionCount: affected.count,
            affectedParticipantCount: draft.participants.count,
            affectedRepaymentCount: draft.repayments.count,
            warnings: warnings
        )
    }

    @MainActor
    static func apply(_ draft: AdvanceCaseEditDraft, modelContext: ModelContext) throws {
        try validate(draft)
        if draft.direction != draft.advanceCase.direction {
            throw AdvanceCaseEditingError.unsupportedDirectionChange
        }

        let now = Date()
        draft.advanceCase.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.advanceCase.date = draft.date
        draft.advanceCase.direction = draft.direction
        draft.advanceCase.currencyCode = draft.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        draft.advanceCase.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.advanceCase.expenseCategory = draft.category
        draft.advanceCase.tagIDs = draft.tags.map(\.id)
        draft.advanceCase.updatedAt = now

        for participantDraft in draft.participants {
            if participantDraft.paymentLegs.count > 1 {
                throw AdvanceCaseEditingError.unsupportedSplitPaymentEdit
            }
            let payment = participantDraft.paymentLegs.first
            if draft.direction == .iAdvancedOthers, payment == nil {
                throw AdvanceCaseEditingError.invalidPaymentLeg
            }
            participantDraft.participant.name = participantDraft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            participantDraft.participant.debtAccount = participantDraft.debtAccount
            try AdvanceService.updateInitialEntry(
                advanceCase: draft.advanceCase,
                participant: participantDraft.participant,
                draft: .init(
                    payerAccount: draft.direction == .iAdvancedOthers ? payment?.account : nil,
                    owedAmount: participantDraft.owedAmount,
                    paymentAmount: payment?.amount,
                    paymentCurrencyCode: payment?.currencyCode,
                    date: draft.date,
                    note: draft.note,
                    category: draft.category,
                    tags: draft.tags
                ),
                modelContext: modelContext
            )
        }

        for repaymentDraft in draft.repayments {
            try AdvanceService.updateRepayment(
                advanceCase: draft.advanceCase,
                repayment: repaymentDraft.repayment,
                draft: .init(
                    receiveAccount: repaymentDraft.account,
                    amount: repaymentDraft.amount,
                    currencyCode: repaymentDraft.currencyCode,
                    normalizedAmount: repaymentDraft.normalizedAmount,
                    date: repaymentDraft.date,
                    note: repaymentDraft.note,
                    category: repaymentDraft.category,
                    tags: repaymentDraft.tags
                ),
                modelContext: modelContext
            )
        }
        try modelContext.save()
    }

    private static func validate(_ draft: AdvanceCaseEditDraft) throws {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AdvanceCaseEditingError.emptyTitle
        }
        guard !draft.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AdvanceCaseEditingError.invalidCurrency
        }
        guard !draft.participants.isEmpty else {
            throw AdvanceCaseEditingError.noParticipants
        }
        let accountIDs = draft.participants.map(\.debtAccount.id)
        guard Set(accountIDs).count == accountIDs.count else {
            throw AdvanceCaseEditingError.duplicateParticipant
        }
        for participant in draft.participants {
            guard participant.owedAmount > 0,
                  participant.owedAmount >= participant.participant.repaidAmount
            else {
                throw AdvanceServiceError.adjustedOwedLowerThanRepaid
            }
            guard draft.direction == .othersAdvancedMe || (
                !participant.paymentLegs.isEmpty && participant.paymentLegs.allSatisfy({
                $0.account.type != .debt &&
                    !$0.account.isArchived &&
                    $0.amount > 0 &&
                    !$0.currencyCode.isEmpty
                })
            ) else {
                throw AdvanceCaseEditingError.invalidPaymentLeg
            }
        }
        if draft.currencyCode != draft.advanceCase.currencyCode,
           draft.repayments.contains(where: { $0.normalizedAmount <= 0 }) {
            throw AdvanceCaseEditingError.currencyChangeRequiresExplicitAmounts
        }
    }
}
