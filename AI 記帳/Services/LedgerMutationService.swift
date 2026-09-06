import Foundation
import SwiftData

@MainActor
enum LedgerMutationService {
    typealias BudgetSynchronization = (ModelContext, [BudgetHistoryAffectedKey]) throws -> Void

    static func synchronizeBudget(_ context: ModelContext, _ keys: [BudgetHistoryAffectedKey]) throws {
        try BudgetHistoryService.shared.syncAffected(keys: keys, modelContext: context, currencyService: .shared, save: false)
    }

    @discardableResult
    static func add(
        _ drafts: [OrdinaryTransactionEditDraft],
        modelContext: ModelContext,
        synchronize: BudgetSynchronization = synchronizeBudget
    ) throws -> [FinancialTransaction] {
        for draft in drafts { try TransactionEditService.validate(draft) }
        var inserted: [FinancialTransaction] = []
        return try perform(modelContext: modelContext, synchronize: synchronize, recover: {
            // Remove inverse links while the failed inserts still have valid backing data.
            for transaction in inserted {
                transaction.account = nil
                transaction.category = nil
                transaction.tags = []
            }
        }) {
            let transactions = try drafts.map { draft in
                let transaction = FinancialTransaction(amount: draft.amount)
                modelContext.insert(transaction)
                inserted.append(transaction)
                try TransactionEditService.apply(draft, to: transaction)
                return transaction
            }
            return (transactions, transactions.compactMap(BudgetHistoryService.affectedKey(for:)))
        }
    }

    static func edit(
        _ transaction: FinancialTransaction,
        draft: OrdinaryTransactionEditDraft,
        modelContext: ModelContext,
        synchronize: BudgetSynchronization = synchronizeBudget
    ) throws {
        try TransactionEditService.validate(draft)
        let original = OrdinaryTransactionEditDraft(
            amount: transaction.amount, currencyCode: transaction.currencyCode,
            date: transaction.date, note: transaction.note, type: transaction.type,
            account: transaction.account, category: transaction.category, tags: transaction.tags
        )
        let updatedAt = transaction.updatedAt
        try perform(modelContext: modelContext, synchronize: synchronize, recover: {
            // SwiftData restores stored state; restore the object retained by the open editor too.
            transaction.amount = original.amount
            transaction.currencyCode = original.currencyCode
            transaction.date = original.date
            transaction.note = original.note
            transaction.type = original.type
            transaction.account = original.account
            transaction.category = original.category
            transaction.tags = original.tags
            transaction.updatedAt = updatedAt
        }) {
            let oldKey = BudgetHistoryService.affectedKey(for: transaction)
            try TransactionEditService.apply(draft, to: transaction)
            return ((), [oldKey, BudgetHistoryService.affectedKey(for: transaction)].compactMap { $0 })
        }
    }

    @discardableResult
    static func executeShortcut(
        _ shortcut: Shortcut,
        date: Date = Date(),
        modelContext: ModelContext,
        synchronize: BudgetSynchronization = synchronizeBudget
    ) throws -> [FinancialTransaction] {
        try add([OrdinaryTransactionEditDraft(
            amount: abs(shortcut.amount), currencyCode: shortcut.currencyCode,
            date: date, note: shortcut.note.isEmpty ? shortcut.name : shortcut.note,
            type: shortcut.type, account: shortcut.account,
            category: shortcut.category, tags: shortcut.tags
        )], modelContext: modelContext, synchronize: synchronize)
    }

    static func perform<Value>(
        modelContext: ModelContext,
        synchronize: BudgetSynchronization = synchronizeBudget,
        recover: () -> Void = {},
        mutation: () throws -> (Value, [BudgetHistoryAffectedKey])
    ) throws -> Value {
        try atomic(modelContext: modelContext, recover: recover) {
            let (value, keys) = try mutation()
            try synchronize(modelContext, keys)
            return value
        }
    }

    // The caller owns this synchronous context operation. Nested work must stage only:
    // One save commits on success; rollback discards this context's pending work on failure.
    static func atomic<Value>(
        modelContext: ModelContext,
        commit: Bool = true,
        recover: () -> Void = {},
        mutation: () throws -> Value
    ) throws -> Value {
        guard commit else { return try mutation() }
        let autosave = modelContext.autosaveEnabled
        modelContext.autosaveEnabled = false
        defer { modelContext.autosaveEnabled = autosave }
        do {
            let value = try mutation()
            if modelContext.hasChanges { try modelContext.save() }
            return value
        } catch {
            recover()
            // Failed domain inserts can otherwise survive through inverse relationships on retry.
            for model in modelContext.insertedModelsArray {
                if let transaction = model as? FinancialTransaction {
                    transaction.account = nil
                    transaction.category = nil
                    transaction.tags = []
                } else if let budget = model as? CategoryMonthlyBudget {
                    budget.category = nil
                } else if let advance = model as? AdvanceCase {
                    advance.payerAccount = nil
                    advance.expenseCategory = nil
                    advance.participants = []
                    advance.repayments = []
                } else if let participant = model as? AdvanceParticipant {
                    participant.advanceCase = nil
                    participant.debtAccount = nil
                } else if let repayment = model as? AdvanceRepayment {
                    repayment.advanceCase = nil
                    repayment.participant = nil
                    repayment.receivedAccount = nil
                }
            }
            modelContext.rollback()
            throw error
        }
    }
}
