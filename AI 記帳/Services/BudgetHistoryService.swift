import Foundation
import SwiftData

@MainActor
final class BudgetHistoryService {
    static let shared = BudgetHistoryService()

    private init() {}

    func syncAll(
        modelContext: ModelContext,
        currencyService: CurrencyService,
        budgets: [CategoryMonthlyBudget]? = nil,
        transactions: [FinancialTransaction]? = nil
    ) throws {
        let budgetRecords: [CategoryMonthlyBudget]
        if let budgets {
            budgetRecords = budgets
        } else {
            budgetRecords = try modelContext.fetch(FetchDescriptor<CategoryMonthlyBudget>())
        }

        let transactionRecords: [FinancialTransaction]
        if let transactions {
            transactionRecords = transactions
        } else {
            transactionRecords = try modelContext.fetch(FetchDescriptor<FinancialTransaction>())
        }
        let existingHistories = try modelContext.fetch(FetchDescriptor<BudgetMonthlyHistory>())

        let desiredHistories = buildDesiredHistories(
            budgets: budgetRecords,
            transactions: transactionRecords,
            currencyService: currencyService
        )

        let desiredByKey = Dictionary(uniqueKeysWithValues: desiredHistories.map { ($0.historyKey, $0) })
        let existingByKey = Dictionary(uniqueKeysWithValues: existingHistories.map { ($0.historyKey, $0) })

        for history in existingHistories where desiredByKey[history.historyKey] == nil {
            modelContext.delete(history)
        }

        for snapshot in desiredHistories {
            if let existing = existingByKey[snapshot.historyKey] {
                apply(snapshot, to: existing)
            } else {
                modelContext.insert(snapshot.asModel())
            }
        }

        try modelContext.save()
    }

    func syncAffected(
        by transactions: [FinancialTransaction],
        modelContext: ModelContext,
        currencyService: CurrencyService
    ) throws {
        let keys = transactions.compactMap(Self.affectedKey(for:))
        try syncAffected(keys: keys, modelContext: modelContext, currencyService: currencyService)
    }

    func syncAffected(
        keys: [BudgetHistoryAffectedKey],
        modelContext: ModelContext,
        currencyService: CurrencyService
    ) throws {
        let uniqueKeys = Array(Set(keys))
        guard !uniqueKeys.isEmpty else { return }

        let budgets = try modelContext.fetch(FetchDescriptor<CategoryMonthlyBudget>())
        let existingHistories = try modelContext.fetch(FetchDescriptor<BudgetMonthlyHistory>())
        let existingByKey = Dictionary(uniqueKeysWithValues: existingHistories.map { ($0.historyKey, $0) })

        for key in uniqueKeys {
            let historyKey = Self.historyKey(monthKey: key.monthKey, categoryID: key.categoryID)
            guard let budget = budgets.first(where: { budget in
                budget.monthKey == key.monthKey &&
                budget.category?.id == key.categoryID &&
                budget.isEnabled &&
                budget.category?.kind.supports(.expense) == true
            }) else {
                if let existing = existingByKey[historyKey] {
                    modelContext.delete(existing)
                }
                continue
            }

            let monthRange = Self.dateRange(forMonthKey: key.monthKey)
            let expenseType = TransactionType.expense
            let startDate = monthRange.start
            let endDate = monthRange.end
            let descriptor = FetchDescriptor<FinancialTransaction>(
                predicate: #Predicate { transaction in
                    transaction.type == expenseType &&
                    transaction.date >= startDate &&
                    transaction.date < endDate
                }
            )
            let monthTransactions = try modelContext.fetch(descriptor)
            let categoryTransactions = monthTransactions.filter { $0.category?.id == key.categoryID }

            let snapshot = makeSnapshot(
                for: budget,
                transactions: categoryTransactions,
                currencyService: currencyService
            )

            if let existing = existingByKey[historyKey] {
                apply(snapshot, to: existing)
            } else {
                modelContext.insert(snapshot.asModel())
            }
        }

        try modelContext.save()
    }

    static func affectedKey(for transaction: FinancialTransaction) -> BudgetHistoryAffectedKey? {
        guard transaction.type == .expense,
              let categoryID = transaction.category?.id
        else { return nil }
        return BudgetHistoryAffectedKey(
            monthKey: BudgetService.monthKey(from: transaction.date),
            categoryID: categoryID
        )
    }

    private func buildDesiredHistories(
        budgets: [CategoryMonthlyBudget],
        transactions: [FinancialTransaction],
        currencyService: CurrencyService
    ) -> [BudgetHistorySnapshot] {
        budgets
            .filter { $0.isEnabled }
            .compactMap { budget in
                guard let category = budget.category, category.kind.supports(.expense) else { return nil }

                return makeSnapshot(
                    for: budget,
                    transactions: transactions.filter { transaction in
                        transaction.type == .expense &&
                        BudgetService.monthKey(from: transaction.date) == budget.monthKey &&
                        transaction.category?.id == category.id
                    },
                    currencyService: currencyService
                )
            }
            .sorted {
                if $0.monthKey == $1.monthKey {
                    return $0.categoryNameSnapshot < $1.categoryNameSnapshot
                }
                return $0.monthKey > $1.monthKey
            }
    }

    private func makeSnapshot(
        for budget: CategoryMonthlyBudget,
        transactions: [FinancialTransaction],
        currencyService: CurrencyService
    ) -> BudgetHistorySnapshot {
        let category = budget.category
        let categoryID = category?.id ?? UUID()
        let spent = transactions.reduce(Decimal.zero) { partial, transaction in
            partial + currencyService.convert(
                amount: abs(transaction.amount),
                from: transaction.currencyCode,
                to: budget.currencyCode
            )
        }

        let remaining = budget.amount - spent
        let ratio: Decimal = budget.amount > 0 ? (spent / budget.amount) : 0
        return BudgetHistorySnapshot(
            id: UUID(),
            historyKey: Self.historyKey(monthKey: budget.monthKey, categoryID: categoryID),
            monthKey: budget.monthKey,
            categoryID: categoryID,
            categoryNameSnapshot: category?.name ?? "未分類",
            budgetAmount: budget.amount,
            spentAmount: spent,
            remainingAmount: remaining,
            usageRatio: ratio,
            isOverBudget: remaining < 0,
            currencyCode: budget.currencyCode,
            updatedAt: Date()
        )
    }

    private func apply(_ snapshot: BudgetHistorySnapshot, to history: BudgetMonthlyHistory) {
        history.monthKey = snapshot.monthKey
        history.categoryID = snapshot.categoryID
        history.categoryNameSnapshot = snapshot.categoryNameSnapshot
        history.budgetAmount = snapshot.budgetAmount
        history.spentAmount = snapshot.spentAmount
        history.remainingAmount = snapshot.remainingAmount
        history.usageRatio = snapshot.usageRatio
        history.isOverBudget = snapshot.isOverBudget
        history.currencyCode = snapshot.currencyCode
        history.updatedAt = snapshot.updatedAt
    }

    static func historyKey(monthKey: String, categoryID: UUID) -> String {
        "\(monthKey)|\(categoryID.uuidString)"
    }

    private static func dateRange(forMonthKey monthKey: String) -> (start: Date, end: Date) {
        let parts = monthKey.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        components.year = parts.first
        components.month = parts.dropFirst().first
        components.day = 1

        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: components) ?? Date()
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return (start, end)
    }
}

struct BudgetHistoryAffectedKey: Hashable {
    let monthKey: String
    let categoryID: UUID
}

private struct BudgetHistorySnapshot {
    let id: UUID
    let historyKey: String
    let monthKey: String
    let categoryID: UUID
    let categoryNameSnapshot: String
    let budgetAmount: Decimal
    let spentAmount: Decimal
    let remainingAmount: Decimal
    let usageRatio: Decimal
    let isOverBudget: Bool
    let currencyCode: String
    let updatedAt: Date

    func asModel() -> BudgetMonthlyHistory {
        BudgetMonthlyHistory(
            id: id,
            historyKey: historyKey,
            monthKey: monthKey,
            categoryID: categoryID,
            categoryNameSnapshot: categoryNameSnapshot,
            budgetAmount: budgetAmount,
            spentAmount: spentAmount,
            remainingAmount: remainingAmount,
            usageRatio: usageRatio,
            isOverBudget: isOverBudget,
            currencyCode: currencyCode,
            updatedAt: updatedAt
        )
    }
}
