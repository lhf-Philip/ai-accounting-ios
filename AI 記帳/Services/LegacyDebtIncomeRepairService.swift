import Foundation
import SwiftData

@MainActor
enum LegacyDebtIncomeRepairService {
    static func legacyDebtIncomeTransactions(from transactions: [FinancialTransaction]) -> [FinancialTransaction] {
        transactions.filter(TransactionSemantics.isLegacyDebtIncome)
    }

    static func legacyDebtIncomeShortcuts(from shortcuts: [Shortcut]) -> [Shortcut] {
        shortcuts.filter(TransactionSemantics.isLegacyDebtIncome)
    }

    @discardableResult
    static func convertLegacyDebtIncomeTransactions(
        _ transactions: [FinancialTransaction],
        modelContext: ModelContext
    ) throws -> Int {
        var updatedCount = 0
        for transaction in transactions {
            guard convertLegacyDebtIncomeTransaction(transaction, modelContext: modelContext) else {
                continue
            }
            updatedCount += 1
        }
        if updatedCount > 0 {
            try modelContext.save()
        }
        return updatedCount
    }

    @discardableResult
    static func convertLegacyDebtIncomeTransaction(
        _ transaction: FinancialTransaction,
        modelContext: ModelContext
    ) -> Bool {
        guard let account = transaction.account, account.type == .debt else {
            return false
        }

        let direction: DebtForgivenessDirection = transaction.amount >= 0 ? .forgivenByOthers : .forgiveOthers
        let normalizedAmount = abs(transaction.amount) * direction.amountSign
        let baseNote = TransactionSemantics.debtForgivenessDisplayTitle(note: transaction.note)

        transaction.amount = normalizedAmount
        transaction.type = .transfer
        transaction.note = TransactionSemantics.debtForgivenessNote(
            baseNote: baseNote,
            debtAccountName: account.name,
            direction: direction
        )
        transaction.linkedTransactionID = nil
        transaction.transferGroupID = nil
        transaction.transferSide = nil
        transaction.updatedAt = Date()
        return true
    }

    @discardableResult
    static func detachLegacyDebtIncomeShortcuts(
        _ shortcuts: [Shortcut],
        modelContext: ModelContext
    ) throws -> Int {
        var updatedCount = 0
        for shortcut in shortcuts {
            guard detachLegacyDebtIncomeShortcut(shortcut, modelContext: modelContext) else {
                continue
            }
            updatedCount += 1
        }
        if updatedCount > 0 {
            try modelContext.save()
        }
        return updatedCount
    }

    @discardableResult
    static func detachLegacyDebtIncomeShortcut(
        _ shortcut: Shortcut,
        modelContext: ModelContext
    ) -> Bool {
        guard shortcut.type == .income, shortcut.account?.type == .debt else {
            return false
        }
        shortcut.account = nil
        return true
    }
}
