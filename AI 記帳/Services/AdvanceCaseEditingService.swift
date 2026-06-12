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
    let participant: AdvanceParticipant?
    let name: String
    let debtAccount: Account
    let owedAmount: Decimal
    let paymentLegs: [AdvancePaymentLegDraft]

    init(
        participant: AdvanceParticipant? = nil,
        name: String,
        debtAccount: Account,
        owedAmount: Decimal,
        paymentLegs: [AdvancePaymentLegDraft]
    ) {
        self.participant = participant
        self.name = name
        self.debtAccount = debtAccount
        self.owedAmount = owedAmount
        self.paymentLegs = paymentLegs
    }
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
    let removedParticipantCount: Int
    let removedRepaymentCount: Int
    let warnings: [String]
}

enum AdvanceCaseEditingError: LocalizedError {
    case emptyTitle
    case invalidCurrency
    case noParticipants
    case duplicateParticipant
    case invalidDebtAccount
    case invalidPaymentLeg
    case invalidShare
    case currencyChangeRequiresExplicitAmounts
    case participantNotInCase
    case repaymentNotInCase
    case duplicateRepayment
    case missingLinkedEntry
    case transactionNotInCase
    case specialRepaymentRequiresGroupRollback

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "請輸入案件名稱。"
        case .invalidCurrency:
            return "請選擇案件幣種。"
        case .noParticipants:
            return "請至少保留一位代墊對象。"
        case .duplicateParticipant:
            return "同一債務對象不可重複。"
        case .invalidDebtAccount:
            return "請選擇未歸檔的借貸帳戶。"
        case .invalidPaymentLeg:
            return "實際付款帳戶、金額或幣種無效。"
        case .invalidShare:
            return "自己的份額、付款帳戶或幣種無效。"
        case .currencyChangeRequiresExplicitAmounts:
            return "改變案件幣種前，必須重新確認自己份額、每位對象與每筆還款的沖銷金額。"
        case .participantNotInCase:
            return "編輯草稿包含不屬於此案件的參與人。"
        case .repaymentNotInCase:
            return "編輯草稿包含不屬於此案件的還款。"
        case .duplicateRepayment:
            return "同一筆還款不可重複。"
        case .missingLinkedEntry:
            return "案件底層分錄連結不完整，無法安全重建。"
        case .transactionNotInCase:
            return "付款分錄識別碼已屬於其他交易，無法安全重建。"
        case .specialRepaymentRequiresGroupRollback:
            return "債務抵銷或跨幣種平賬必須先整組撤銷，不能在案件編輯中拆開修改。"
        }
    }
}

enum AdvanceCaseEditingService {
    private struct TransactionSpec {
        let id: UUID
        let amount: Decimal
        let currencyCode: String
        let date: Date
        let note: String
        let type: TransactionType
        let linkedTransactionID: UUID?
        let transferGroupID: UUID?
        let transferSide: TransferSide?
        let advanceCaseID: UUID
        let advanceParticipantID: UUID?
        let advanceRepaymentID: UUID?
        let advanceEntryRole: AdvanceEntryRole
        let account: Account
        let category: Category?
        let tags: [Tag]
    }

    private struct PreparedParticipant {
        let draft: AdvanceParticipantDraft
        let participant: AdvanceParticipant
        let isNew: Bool
        let groupID: UUID
        let repaidAmount: Decimal
    }

    @MainActor
    static func preview(
        _ draft: AdvanceCaseEditDraft,
        modelContext: ModelContext
    ) throws -> AdvanceCaseImpactPreview {
        try validate(draft, modelContext: modelContext)
        let transactions = try linkedTransactions(for: draft.advanceCase, modelContext: modelContext)
        let retainedParticipantIDs = Set(draft.participants.compactMap { $0.participant?.id })
        let retainedRepaymentIDs = Set(draft.repayments.map(\.repayment.id))
        let removedParticipants = draft.advanceCase.participants.filter {
            !retainedParticipantIDs.contains($0.id)
        }
        let removedRepayments = draft.advanceCase.repayments.filter {
            !retainedRepaymentIDs.contains($0.id)
        }

        var warnings: [String] = []
        if draft.direction != draft.advanceCase.direction {
            warnings.append("改變方向會原子重建案件的初始分錄與普通還款分錄。")
        }
        if normalizedCurrency(draft.currencyCode) != normalizedCurrency(draft.advanceCase.currencyCode) {
            warnings.append("案件幣種改變後，所有沖銷金額均以輸入值為準，不會自動換算。")
        }
        if !removedParticipants.isEmpty {
            warnings.append("刪除參與人會一併刪除其普通還款及相關底層分錄。")
        } else if !removedRepayments.isEmpty {
            warnings.append("未保留的普通還款會連同底層分錄刪除。")
        }

        return AdvanceCaseImpactPreview(
            changesDirection: draft.direction != draft.advanceCase.direction,
            changesCurrency: normalizedCurrency(draft.currencyCode) != normalizedCurrency(draft.advanceCase.currencyCode),
            affectedTransactionCount: transactions.count,
            affectedParticipantCount: draft.participants.count,
            affectedRepaymentCount: draft.repayments.count,
            removedParticipantCount: removedParticipants.count,
            removedRepaymentCount: removedRepayments.count,
            warnings: warnings
        )
    }

    @MainActor
    static func apply(
        _ draft: AdvanceCaseEditDraft,
        modelContext: ModelContext
    ) throws {
        try validate(draft, modelContext: modelContext)

        let existingTransactions = try linkedTransactions(
            for: draft.advanceCase,
            modelContext: modelContext
        )
        let existingByID = Dictionary(uniqueKeysWithValues: existingTransactions.map { ($0.id, $0) })
        let preparedParticipants = try prepareParticipants(draft)
        let participantByID = Dictionary(
            uniqueKeysWithValues: preparedParticipants.map { ($0.participant.id, $0) }
        )
        let specs = try buildTransactionSpecs(
            draft,
            preparedParticipants: preparedParticipants,
            existingTransactions: existingTransactions
        )
        guard Set(specs.map(\.id)).count == specs.count else {
            throw AdvanceCaseEditingError.missingLinkedEntry
        }

        do {
            let now = Date()
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let currencyCode = normalizedCurrency(draft.currencyCode)
            let desiredParticipantIDs = Set(preparedParticipants.map(\.participant.id))
            let desiredRepaymentIDs = Set(draft.repayments.map(\.repayment.id))

            for repayment in draft.advanceCase.repayments where !desiredRepaymentIDs.contains(repayment.id) {
                modelContext.delete(repayment)
            }
            for participant in draft.advanceCase.participants where !desiredParticipantIDs.contains(participant.id) {
                modelContext.delete(participant)
            }

            for prepared in preparedParticipants {
                let participantDraft = prepared.draft
                let participant = prepared.participant
                if prepared.isNew {
                    modelContext.insert(participant)
                }
                participant.name = participantDraft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                participant.owedAmount = abs(participantDraft.owedAmount)
                participant.repaidAmount = prepared.repaidAmount
                participant.initialTransferGroupID = prepared.groupID
                participant.advanceCase = draft.advanceCase
                participant.debtAccount = participantDraft.debtAccount
                participant.updatedAt = now
            }

            for repaymentDraft in draft.repayments {
                guard let prepared = participantByID[repaymentDraft.repayment.participant?.id ?? UUID()] else {
                    throw AdvanceCaseEditingError.repaymentNotInCase
                }
                let repayment = repaymentDraft.repayment
                repayment.amount = abs(repaymentDraft.amount)
                repayment.currencyCode = normalizedCurrency(repaymentDraft.currencyCode)
                repayment.normalizedAmount = abs(repaymentDraft.normalizedAmount)
                repayment.date = repaymentDraft.date
                repayment.note = repaymentDraft.note.trimmingCharacters(in: .whitespacesAndNewlines)
                repayment.linkedTransferGroupID = specs.first(where: {
                    $0.advanceRepaymentID == repayment.id
                })?.transferGroupID
                repayment.advanceCase = draft.advanceCase
                repayment.participant = prepared.participant
                repayment.receivedAccount = repaymentDraft.account
            }

            let desiredTransactionIDs = Set(specs.map(\.id))
            for transaction in existingTransactions where !desiredTransactionIDs.contains(transaction.id) {
                modelContext.delete(transaction)
            }
            for spec in specs {
                let transaction: FinancialTransaction
                if let existing = existingByID[spec.id] {
                    transaction = existing
                } else {
                    transaction = FinancialTransaction(
                        id: spec.id,
                        amount: spec.amount,
                        currencyCode: spec.currencyCode,
                        date: spec.date,
                        note: spec.note,
                        type: spec.type
                    )
                    modelContext.insert(transaction)
                }
                apply(spec, to: transaction, updatedAt: now)
            }

            let paymentAccounts = draft.participants.flatMap(\.paymentLegs).map(\.account)
            let uniquePaymentAccountIDs = Set(paymentAccounts.map(\.id))
            draft.advanceCase.title = title
            draft.advanceCase.date = draft.date
            draft.advanceCase.direction = draft.direction
            draft.advanceCase.currencyCode = currencyCode
            draft.advanceCase.myShareAmount = draft.share.map { abs($0.normalizedAmount) } ?? 0
            draft.advanceCase.note = note
            draft.advanceCase.selfExpenseTransactionID = draft.share?.transactionID
                ?? specs.first(where: { $0.advanceEntryRole == .selfExpense })?.id
            draft.advanceCase.payerAccount = draft.direction == .iAdvancedOthers &&
                uniquePaymentAccountIDs.count == 1 ? paymentAccounts.first : nil
            draft.advanceCase.expenseCategory = draft.category
            draft.advanceCase.tagIDs = draft.tags.map(\.id)
            draft.advanceCase.updatedAt = now

            try BudgetHistoryService.shared.syncAll(
                modelContext: modelContext,
                currencyService: CurrencyService.shared
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    @MainActor
    private static func validate(
        _ draft: AdvanceCaseEditDraft,
        modelContext: ModelContext
    ) throws {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AdvanceCaseEditingError.emptyTitle
        }
        let currencyCode = normalizedCurrency(draft.currencyCode)
        guard !currencyCode.isEmpty else {
            throw AdvanceCaseEditingError.invalidCurrency
        }
        guard !draft.participants.isEmpty else {
            throw AdvanceCaseEditingError.noParticipants
        }
        if let category = draft.category,
           draft.direction == .othersAdvancedMe,
           !category.kind.supports(.expense) {
            throw AdvanceServiceError.invalidSettlementCategory
        }

        let existingParticipantIDs = Set(draft.advanceCase.participants.map(\.id))
        let participantIDs = draft.participants.compactMap { $0.participant?.id }
        guard participantIDs.allSatisfy(existingParticipantIDs.contains) else {
            throw AdvanceCaseEditingError.participantNotInCase
        }
        guard Set(participantIDs).count == participantIDs.count else {
            throw AdvanceCaseEditingError.duplicateParticipant
        }
        let debtAccountIDs = draft.participants.map(\.debtAccount.id)
        guard Set(debtAccountIDs).count == debtAccountIDs.count else {
            throw AdvanceCaseEditingError.duplicateParticipant
        }

        let repaymentIDs = draft.repayments.map(\.repayment.id)
        guard Set(repaymentIDs).count == repaymentIDs.count else {
            throw AdvanceCaseEditingError.duplicateRepayment
        }
        let existingRepaymentIDs = Set(draft.advanceCase.repayments.map(\.id))
        guard repaymentIDs.allSatisfy(existingRepaymentIDs.contains) else {
            throw AdvanceCaseEditingError.repaymentNotInCase
        }

        let requestedTransactionIDs = [
            draft.share?.transactionID
        ].compactMap { $0 } + draft.participants.flatMap(\.paymentLegs).compactMap(\.transactionID)
        guard Set(requestedTransactionIDs).count == requestedTransactionIDs.count else {
            throw AdvanceCaseEditingError.missingLinkedEntry
        }
        let caseID = draft.advanceCase.id
        let selfExpenseID = draft.advanceCase.selfExpenseTransactionID
        let conflictingTransaction = try modelContext.fetch(FetchDescriptor<FinancialTransaction>())
            .contains {
                requestedTransactionIDs.contains($0.id) &&
                    $0.advanceCaseID != caseID &&
                    $0.id != selfExpenseID
            }
        guard !conflictingTransaction else {
            throw AdvanceCaseEditingError.transactionNotInCase
        }

        let retainedParticipantIDs = Set(participantIDs)
        for repaymentDraft in draft.repayments {
            guard let participant = repaymentDraft.repayment.participant,
                  retainedParticipantIDs.contains(participant.id),
                  repaymentDraft.repayment.advanceCase?.id == draft.advanceCase.id
            else {
                throw AdvanceCaseEditingError.repaymentNotInCase
            }
            guard AdvanceService.repaymentRecordKind(note: repaymentDraft.repayment.note) == .ordinary else {
                throw AdvanceCaseEditingError.specialRepaymentRequiresGroupRollback
            }
            guard repaymentDraft.amount > 0,
                  repaymentDraft.normalizedAmount > 0,
                  !normalizedCurrency(repaymentDraft.currencyCode).isEmpty,
                  repaymentDraft.account.type != .debt,
                  !repaymentDraft.account.isArchived
            else {
                throw AdvanceServiceError.invalidRepaymentAmount
            }
            if let category = repaymentDraft.category {
                let expectedType: TransactionType = draft.direction == .iAdvancedOthers ? .income : .expense
                guard category.kind.supports(expectedType) else {
                    throw AdvanceServiceError.invalidSettlementCategory
                }
            }
        }

        let omittedSpecialRepayments = draft.advanceCase.repayments.filter {
            !repaymentIDs.contains($0.id) &&
                AdvanceService.repaymentRecordKind(note: $0.note) != .ordinary
        }
        guard omittedSpecialRepayments.isEmpty else {
            throw AdvanceCaseEditingError.specialRepaymentRequiresGroupRollback
        }

        let normalizedByParticipant = Dictionary(
            grouping: draft.repayments,
            by: { $0.repayment.participant?.id }
        ).mapValues { repayments in
            repayments.reduce(Decimal.zero) { $0 + abs($1.normalizedAmount) }
        }

        for participant in draft.participants {
            guard participant.debtAccount.type == .debt,
                  !participant.debtAccount.isArchived
            else {
                throw AdvanceCaseEditingError.invalidDebtAccount
            }
            guard participant.owedAmount > 0 else {
                throw AdvanceServiceError.invalidAdjustedOwedAmount
            }
            let settled = normalizedByParticipant[participant.participant?.id] ?? 0
            guard participant.owedAmount >= settled else {
                throw AdvanceServiceError.adjustedOwedLowerThanRepaid
            }
            if draft.direction == .iAdvancedOthers {
                guard !participant.paymentLegs.isEmpty,
                      participant.paymentLegs.allSatisfy({
                          $0.account.type != .debt &&
                              !$0.account.isArchived &&
                              $0.amount > 0 &&
                              !normalizedCurrency($0.currencyCode).isEmpty
                      })
                else {
                    throw AdvanceCaseEditingError.invalidPaymentLeg
                }
            } else if !participant.paymentLegs.isEmpty {
                throw AdvanceCaseEditingError.invalidPaymentLeg
            }
        }

        if let share = draft.share {
            guard draft.direction == .iAdvancedOthers,
                  share.account.type != .debt,
                  !share.account.isArchived,
                  share.amount > 0,
                  share.normalizedAmount > 0,
                  !normalizedCurrency(share.currencyCode).isEmpty
            else {
                throw AdvanceCaseEditingError.invalidShare
            }
        }

        if normalizedCurrency(draft.advanceCase.currencyCode) != currencyCode {
            guard draft.participants.allSatisfy({ $0.owedAmount > 0 }),
                  draft.repayments.allSatisfy({ $0.normalizedAmount > 0 }),
                  draft.share == nil || draft.share!.normalizedAmount > 0
            else {
                throw AdvanceCaseEditingError.currencyChangeRequiresExplicitAmounts
            }
        }
    }

    @MainActor
    private static func prepareParticipants(
        _ draft: AdvanceCaseEditDraft
    ) throws -> [PreparedParticipant] {
        let normalizedByParticipant = Dictionary(
            grouping: draft.repayments,
            by: { $0.repayment.participant?.id }
        ).mapValues { repayments in
            repayments.reduce(Decimal.zero) { $0 + abs($1.normalizedAmount) }
        }
        return draft.participants.map { participantDraft in
            let participant = participantDraft.participant ?? AdvanceParticipant(
                name: participantDraft.name,
                owedAmount: abs(participantDraft.owedAmount),
                advanceCase: draft.advanceCase,
                debtAccount: participantDraft.debtAccount
            )
            return PreparedParticipant(
                draft: participantDraft,
                participant: participant,
                isNew: participantDraft.participant == nil,
                groupID: participant.initialTransferGroupID ?? UUID(),
                repaidAmount: normalizedByParticipant[participant.id] ?? 0
            )
        }
    }

    @MainActor
    private static func buildTransactionSpecs(
        _ draft: AdvanceCaseEditDraft,
        preparedParticipants: [PreparedParticipant],
        existingTransactions: [FinancialTransaction]
    ) throws -> [TransactionSpec] {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let memo = note.isEmpty ? title : note
        let currencyCode = normalizedCurrency(draft.currencyCode)
        var specs: [TransactionSpec] = []

        if let share = draft.share {
            let transactionID = share.transactionID
                ?? draft.advanceCase.selfExpenseTransactionID
                ?? UUID()
            specs.append(
                TransactionSpec(
                    id: transactionID,
                    amount: -abs(share.amount),
                    currencyCode: normalizedCurrency(share.currencyCode),
                    date: draft.date,
                    note: "\(memo) (自己份額)",
                    type: .expense,
                    linkedTransactionID: nil,
                    transferGroupID: nil,
                    transferSide: nil,
                    advanceCaseID: draft.advanceCase.id,
                    advanceParticipantID: nil,
                    advanceRepaymentID: nil,
                    advanceEntryRole: .selfExpense,
                    account: share.account,
                    category: draft.category,
                    tags: draft.tags
                )
            )
        }

        for prepared in preparedParticipants {
            let participant = prepared.participant
            let participantDraft = prepared.draft
            let existingGroup = existingTransactions.filter {
                $0.transferGroupID == prepared.groupID &&
                    $0.advanceRepaymentID == nil
            }
            let existingDebtID = existingGroup.first(where: {
                $0.advanceEntryRole == .initialDebt ||
                    $0.account?.id == participant.debtAccount?.id
            })?.id

            if draft.direction == .othersAdvancedMe {
                specs.append(
                    TransactionSpec(
                        id: existingDebtID ?? UUID(),
                        amount: -abs(participantDraft.owedAmount),
                        currencyCode: currencyCode,
                        date: draft.date,
                        note: "\(memo) (他人代墊我：\(participantDraft.name))",
                        type: .expense,
                        linkedTransactionID: nil,
                        transferGroupID: prepared.groupID,
                        transferSide: .outgoing,
                        advanceCaseID: draft.advanceCase.id,
                        advanceParticipantID: participant.id,
                        advanceRepaymentID: nil,
                        advanceEntryRole: .initialDebt,
                        account: participantDraft.debtAccount,
                        category: draft.category,
                        tags: draft.tags
                    )
                )
                continue
            }

            let debtID = existingDebtID ?? UUID()
            let assetIDs = participantDraft.paymentLegs.map { leg in
                leg.transactionID ?? UUID()
            }
            for (leg, assetID) in zip(participantDraft.paymentLegs, assetIDs) {
                specs.append(
                    TransactionSpec(
                        id: assetID,
                        amount: -abs(leg.amount),
                        currencyCode: normalizedCurrency(leg.currencyCode),
                        date: draft.date,
                        note: "\(memo) (代墊給 \(participantDraft.name))",
                        type: .transfer,
                        linkedTransactionID: debtID,
                        transferGroupID: prepared.groupID,
                        transferSide: .outgoing,
                        advanceCaseID: draft.advanceCase.id,
                        advanceParticipantID: participant.id,
                        advanceRepaymentID: nil,
                        advanceEntryRole: .initialAsset,
                        account: leg.account,
                        category: nil,
                        tags: []
                    )
                )
            }
            specs.append(
                TransactionSpec(
                    id: debtID,
                    amount: abs(participantDraft.owedAmount),
                    currencyCode: currencyCode,
                    date: draft.date,
                    note: "\(memo) (來自多付款來源)",
                    type: .transfer,
                    linkedTransactionID: assetIDs.count == 1 ? assetIDs.first : nil,
                    transferGroupID: prepared.groupID,
                    transferSide: .incoming,
                    advanceCaseID: draft.advanceCase.id,
                    advanceParticipantID: participant.id,
                    advanceRepaymentID: nil,
                    advanceEntryRole: .initialDebt,
                    account: participantDraft.debtAccount,
                    category: nil,
                    tags: []
                )
            )
        }

        for repaymentDraft in draft.repayments {
            let repayment = repaymentDraft.repayment
            guard let participant = repayment.participant,
                  let debtAccount = preparedParticipants.first(where: {
                      $0.participant.id == participant.id
                  })?.draft.debtAccount
            else {
                throw AdvanceCaseEditingError.repaymentNotInCase
            }
            let groupID = repayment.linkedTransferGroupID ?? UUID()
            let existingGroup = existingTransactions.filter { $0.transferGroupID == groupID }
            let debtID = existingGroup.first(where: {
                $0.advanceEntryRole == .repaymentDebt
            })?.id ?? UUID()
            let assetID = existingGroup.first(where: {
                $0.advanceEntryRole == .repaymentAsset
            })?.id ?? UUID()
            let amount = abs(repaymentDraft.amount)
            let repaymentCurrency = normalizedCurrency(repaymentDraft.currencyCode)
            let repaymentNote = repaymentDraft.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let repaymentMemo = repaymentNote.isEmpty ? title : repaymentNote

            if draft.direction == .iAdvancedOthers {
                specs.append(
                    TransactionSpec(
                        id: debtID,
                        amount: -amount,
                        currencyCode: repaymentCurrency,
                        date: repaymentDraft.date,
                        note: "\(repaymentMemo) (還款至 \(repaymentDraft.account.name))",
                        type: .transfer,
                        linkedTransactionID: assetID,
                        transferGroupID: groupID,
                        transferSide: .outgoing,
                        advanceCaseID: draft.advanceCase.id,
                        advanceParticipantID: participant.id,
                        advanceRepaymentID: repayment.id,
                        advanceEntryRole: .repaymentDebt,
                        account: debtAccount,
                        category: nil,
                        tags: []
                    )
                )
                specs.append(
                    TransactionSpec(
                        id: assetID,
                        amount: amount,
                        currencyCode: repaymentCurrency,
                        date: repaymentDraft.date,
                        note: "\(repaymentMemo) (來自 \(participant.name))",
                        type: .transfer,
                        linkedTransactionID: debtID,
                        transferGroupID: groupID,
                        transferSide: .incoming,
                        advanceCaseID: draft.advanceCase.id,
                        advanceParticipantID: participant.id,
                        advanceRepaymentID: repayment.id,
                        advanceEntryRole: .repaymentAsset,
                        account: repaymentDraft.account,
                        category: repaymentDraft.category,
                        tags: repaymentDraft.tags
                    )
                )
            } else {
                specs.append(
                    TransactionSpec(
                        id: assetID,
                        amount: -amount,
                        currencyCode: repaymentCurrency,
                        date: repaymentDraft.date,
                        note: "\(repaymentMemo) (還款給 \(participant.name))",
                        type: .transfer,
                        linkedTransactionID: debtID,
                        transferGroupID: groupID,
                        transferSide: .outgoing,
                        advanceCaseID: draft.advanceCase.id,
                        advanceParticipantID: participant.id,
                        advanceRepaymentID: repayment.id,
                        advanceEntryRole: .repaymentAsset,
                        account: repaymentDraft.account,
                        category: repaymentDraft.category,
                        tags: repaymentDraft.tags
                    )
                )
                specs.append(
                    TransactionSpec(
                        id: debtID,
                        amount: amount,
                        currencyCode: repaymentCurrency,
                        date: repaymentDraft.date,
                        note: "\(repaymentMemo) (來自 \(repaymentDraft.account.name))",
                        type: .transfer,
                        linkedTransactionID: assetID,
                        transferGroupID: groupID,
                        transferSide: .incoming,
                        advanceCaseID: draft.advanceCase.id,
                        advanceParticipantID: participant.id,
                        advanceRepaymentID: repayment.id,
                        advanceEntryRole: .repaymentDebt,
                        account: debtAccount,
                        category: nil,
                        tags: []
                    )
                )
            }
        }
        return specs
    }

    @MainActor
    private static func linkedTransactions(
        for advanceCase: AdvanceCase,
        modelContext: ModelContext
    ) throws -> [FinancialTransaction] {
        let caseID = advanceCase.id
        let allTransactions = try modelContext.fetch(FetchDescriptor<FinancialTransaction>())
        let groupIDs = Set(
            advanceCase.participants.compactMap(\.initialTransferGroupID) +
                advanceCase.repayments.compactMap(\.linkedTransferGroupID)
        )
        return allTransactions.filter {
            $0.advanceCaseID == caseID ||
                $0.transferGroupID.map(groupIDs.contains) == true ||
                $0.id == advanceCase.selfExpenseTransactionID
        }
    }

    private static func apply(
        _ spec: TransactionSpec,
        to transaction: FinancialTransaction,
        updatedAt: Date
    ) {
        transaction.amount = spec.amount
        transaction.currencyCode = spec.currencyCode
        transaction.date = spec.date
        transaction.note = spec.note
        transaction.photoPath = nil
        transaction.type = spec.type
        transaction.linkedTransactionID = spec.linkedTransactionID
        transaction.transferGroupID = spec.transferGroupID
        transaction.transferSide = spec.transferSide
        transaction.advanceCaseID = spec.advanceCaseID
        transaction.advanceParticipantID = spec.advanceParticipantID
        transaction.advanceRepaymentID = spec.advanceRepaymentID
        transaction.advanceEntryRole = spec.advanceEntryRole
        transaction.account = spec.account
        transaction.category = spec.category
        transaction.tags = spec.tags
        transaction.updatedAt = updatedAt
    }

    private static func normalizedCurrency(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
