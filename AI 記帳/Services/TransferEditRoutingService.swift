import Foundation

enum TransferEditSemantic: Equatable {
    case ordinary
    case debt
    case debtForgiveness
    case advanceSelfExpense
    case advanceInitial
    case advanceRepayment
}

enum TransferEditRoutingService {
    static func classify(
        transaction: FinancialTransaction,
        groupTransactions: [FinancialTransaction],
        advanceSelfExpenseTransactionIDs: Set<UUID> = [],
        advanceInitialGroupIDs: Set<UUID>,
        advanceRepaymentGroupIDs: Set<UUID>
    ) -> TransferEditSemantic {
        if advanceSelfExpenseTransactionIDs.contains(transaction.id) {
            return .advanceSelfExpense
        }
        if let groupID = transaction.transferGroupID {
            if advanceInitialGroupIDs.contains(groupID) {
                return .advanceInitial
            }
            if advanceRepaymentGroupIDs.contains(groupID) {
                return .advanceRepayment
            }
        }
        if TransactionSemantics.isDebtForgiveness(note: transaction.note) {
            return .debtForgiveness
        }
        let compactedNote = transaction.note.replacingOccurrences(of: " ", with: "")
        if compactedNote.contains("(還款至") || compactedNote.contains("(還款給") {
            return .advanceRepayment
        }
        if compactedNote.contains("(代墊給") ||
            compactedNote.contains("(代墊給我") ||
            compactedNote.contains("(他人代墊我") {
            return .advanceInitial
        }
        if groupTransactions.contains(where: { $0.account?.type == .debt }) {
            return .debt
        }
        return .ordinary
    }

    static func groupTransactions(
        for transaction: FinancialTransaction,
        in allTransactions: [FinancialTransaction]
    ) -> [FinancialTransaction] {
        if let groupID = transaction.transferGroupID {
            let group = allTransactions.filter { $0.transferGroupID == groupID }
            if !group.isEmpty {
                return group
            }
        }
        if let linkedID = transaction.linkedTransactionID,
           let linked = allTransactions.first(where: { $0.id == linkedID }) {
            return [transaction, linked]
        }
        return [transaction]
    }
}
