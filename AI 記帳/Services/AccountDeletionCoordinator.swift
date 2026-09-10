import Foundation
import SwiftData

struct AccountDeletionCounts {
    let transactionCount: Int
    let advanceCaseCount: Int
    let participantCount: Int
    let repaymentCount: Int
    let shortcutDetachCount: Int

    var hasBookkeeping: Bool {
        transactionCount > 0 || advanceCaseCount > 0 || participantCount > 0 || repaymentCount > 0
    }
}

struct AccountDeletionImpact {
    let account: Account
    let counts: AccountDeletionCounts
    let advanceCasesToDelete: [AdvanceCase]
    let repaymentsToRollback: [AdvanceRepayment]
    let directTransactionsToDelete: [FinancialTransaction]
    let shortcutsToDetach: [Shortcut]

    var isEmptyAccount: Bool {
        !counts.hasBookkeeping
    }
}

enum AccountDeletionCoordinator {
    static func preview(account: Account, modelContext: ModelContext) throws -> AccountDeletionImpact {
        let allTransactions = try modelContext.fetch(FetchDescriptor<FinancialTransaction>())
        let allShortcuts = try modelContext.fetch(FetchDescriptor<Shortcut>())
        let allAdvanceCases = try modelContext.fetch(FetchDescriptor<AdvanceCase>())

        let caseIDsToDelete = Set(
            allAdvanceCases
                .filter { advanceCase in
                    advanceCase.payerAccount?.id == account.id
                        || advanceCase.participants.contains { $0.debtAccount?.id == account.id }
                }
                .map(\.id)
        )

        let advanceCasesToDelete = allAdvanceCases.filter { caseIDsToDelete.contains($0.id) }
        let repaymentsToRollback = allAdvanceCases
            .flatMap(\.repayments)
            .filter { repayment in
                repayment.receivedAccount?.id == account.id
                    && !caseIDsToDelete.contains(repayment.advanceCase?.id ?? UUID())
            }

        let protectedGroupIDs = Set(
            advanceCasesToDelete.flatMap { advanceCase in
                advanceCase.participants.compactMap(\.initialTransferGroupID)
                    + advanceCase.repayments.compactMap(\.linkedTransferGroupID)
            } + repaymentsToRollback.compactMap(\.linkedTransferGroupID)
        )

        let protectedTransactionIDs = Set(
            advanceCasesToDelete.compactMap(\.selfExpenseTransactionID)
                + allTransactions
                    .filter { tx in
                        guard let groupID = tx.transferGroupID else { return false }
                        return protectedGroupIDs.contains(groupID)
                    }
                    .map(\.id)
        )

        let accountTransactions = allTransactions.filter { $0.account?.id == account.id }
        let directGroupIDs: Set<UUID> = Set(
            accountTransactions.compactMap { tx in
                guard let groupID = tx.transferGroupID else { return nil }
                return protectedGroupIDs.contains(groupID) ? nil : groupID
            }
        )

        let directTransactionsToDelete = allTransactions.filter { tx in
            if protectedTransactionIDs.contains(tx.id) {
                return false
            }
            if let groupID = tx.transferGroupID {
                return directGroupIDs.contains(groupID)
            }
            if tx.account?.id == account.id {
                return true
            }
            if let linkedID = tx.linkedTransactionID {
                return accountTransactions.contains(where: { $0.id == linkedID && $0.transferGroupID == nil })
            }
            return false
        }

        let shortcutsToDetach = allShortcuts.filter { $0.account?.id == account.id }
        let participantCount = advanceCasesToDelete.reduce(0) { $0 + $1.participants.count }
        let repaymentCount = advanceCasesToDelete.reduce(0) { $0 + $1.repayments.count } + repaymentsToRollback.count

        return AccountDeletionImpact(
            account: account,
            counts: AccountDeletionCounts(
                transactionCount: directTransactionsToDelete.count,
                advanceCaseCount: advanceCasesToDelete.count,
                participantCount: participantCount,
                repaymentCount: repaymentCount,
                shortcutDetachCount: shortcutsToDetach.count
            ),
            advanceCasesToDelete: advanceCasesToDelete,
            repaymentsToRollback: repaymentsToRollback,
            directTransactionsToDelete: directTransactionsToDelete,
            shortcutsToDetach: shortcutsToDetach
        )
    }

    static func archive(account: Account, modelContext: ModelContext) throws {
        account.isArchived = true
        try modelContext.save()
    }

    static func deleteAccount(using impact: AccountDeletionImpact, modelContext: ModelContext) throws {
        return try LedgerMutationService.atomic(modelContext: modelContext, commit: true) {
            for shortcut in impact.shortcutsToDetach {
                shortcut.account = nil
            }

            for repayment in impact.repaymentsToRollback {
                guard let advanceCase = repayment.advanceCase else { continue }
                try AdvanceService.rollbackRepayment(
                    advanceCase: advanceCase,
                    repayment: repayment,
                    autosave: false,
                    modelContext: modelContext
                )
            }

            for advanceCase in impact.advanceCasesToDelete {
                _ = try AdvanceService.deleteAdvanceCase(
                    advanceCase,
                    deleteLinkedTransactions: true,
                    autosave: false,
                    modelContext: modelContext
                )
            }

            for transaction in impact.directTransactionsToDelete {
                modelContext.delete(transaction)
            }

            modelContext.delete(impact.account)
            try BudgetHistoryService.shared.syncAll(
                modelContext: modelContext,
                currencyService: CurrencyService.shared,
                save: false
            )
        }
    }
}
