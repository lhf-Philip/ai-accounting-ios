import Foundation
import SwiftData

enum LedgerDeletionError: LocalizedError {
    case advanceInitialTransferRequiresCase

    var errorDescription: String? {
        switch self {
        case .advanceInitialTransferRequiresCase:
            return "這是代墊建立分錄，請進入代墊詳情刪除整個代墊案件。"
        }
    }
}

@MainActor
enum LedgerDeletionService {
    static func delete(transaction: FinancialTransaction, modelContext: ModelContext, synchronize: LedgerMutationService.BudgetSynchronization = LedgerMutationService.synchronizeBudget) throws {
        try LedgerMutationService.atomic(modelContext: modelContext) {
            try deleteStaged(transaction: transaction, modelContext: modelContext, synchronize: synchronize)
        }
    }

    private static func deleteStaged(transaction: FinancialTransaction, modelContext: ModelContext, synchronize: LedgerMutationService.BudgetSynchronization) throws {
        if let groupID = transaction.transferGroupID {
            try deleteTransferGroup(groupID, fallbackTransaction: transaction, modelContext: modelContext, synchronize: synchronize)
            return
        }

        let affectedKeys = [BudgetHistoryService.affectedKey(for: transaction)].compactMap { $0 }

        if try isAdvanceSelfExpense(transaction, modelContext: modelContext) {
            throw LedgerDeletionError.advanceInitialTransferRequiresCase
        }

        if transaction.type == .transfer, let linkedID = transaction.linkedTransactionID {
            let descriptor = FetchDescriptor<FinancialTransaction>(
                predicate: #Predicate { $0.id == linkedID }
            )
            if let linked = try modelContext.fetch(descriptor).first {
                modelContext.delete(linked)
            }
        }

        modelContext.delete(transaction)
        try synchronize(modelContext, affectedKeys)
    }

    private static func deleteTransferGroup(
        _ groupID: UUID,
        fallbackTransaction: FinancialTransaction,
        modelContext: ModelContext,
        synchronize: LedgerMutationService.BudgetSynchronization
    ) throws {
        if let repayment = try repayment(for: groupID, modelContext: modelContext),
           let advanceCase = repayment.advanceCase {
            try AdvanceService.rollbackRepayment(
                advanceCase: advanceCase,
                repayment: repayment,
                autosave: false,
                modelContext: modelContext
            )
            return
        }

        if try isAdvanceInitialTransferGroup(groupID, modelContext: modelContext) {
            throw LedgerDeletionError.advanceInitialTransferRequiresCase
        }

        let descriptor = FetchDescriptor<FinancialTransaction>(
            predicate: #Predicate { $0.transferGroupID == groupID }
        )
        let groupedTransfers = try modelContext.fetch(descriptor)
        let affectedKeys = (groupedTransfers.isEmpty ? [fallbackTransaction] : groupedTransfers)
            .compactMap { BudgetHistoryService.affectedKey(for: $0) }
        if groupedTransfers.isEmpty {
            modelContext.delete(fallbackTransaction)
        } else {
            for transfer in groupedTransfers {
                modelContext.delete(transfer)
            }
        }
        try synchronize(modelContext, affectedKeys)
    }

    private static func repayment(for groupID: UUID, modelContext: ModelContext) throws -> AdvanceRepayment? {
        let descriptor = FetchDescriptor<AdvanceRepayment>(
            predicate: #Predicate { $0.linkedTransferGroupID == groupID }
        )
        return try modelContext.fetch(descriptor).first
    }

    private static func isAdvanceInitialTransferGroup(_ groupID: UUID, modelContext: ModelContext) throws -> Bool {
        let descriptor = FetchDescriptor<AdvanceParticipant>(
            predicate: #Predicate { $0.initialTransferGroupID == groupID }
        )
        return try modelContext.fetch(descriptor).first != nil
    }

    private static func isAdvanceSelfExpense(_ transaction: FinancialTransaction, modelContext: ModelContext) throws -> Bool {
        let transactionID: UUID? = transaction.id
        let descriptor = FetchDescriptor<AdvanceCase>(
            predicate: #Predicate { $0.selfExpenseTransactionID == transactionID }
        )
        return try modelContext.fetch(descriptor).isEmpty == false
    }
}
