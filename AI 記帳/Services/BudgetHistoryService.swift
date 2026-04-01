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

    private func buildDesiredHistories(
        budgets: [CategoryMonthlyBudget],
        transactions: [FinancialTransaction],
        currencyService: CurrencyService
    ) -> [BudgetHistorySnapshot] {
        budgets
            .filter { $0.isEnabled }
            .compactMap { budget in
                guard let category = budget.category, category.kind.supports(.expense) else { return nil }

                let spent = transactions
                    .filter { transaction in
                        transaction.type == .expense &&
                        BudgetService.monthKey(from: transaction.date) == budget.monthKey &&
                        transaction.category?.id == category.id
                    }
                    .reduce(Decimal.zero) { partial, transaction in
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
                    historyKey: Self.historyKey(monthKey: budget.monthKey, categoryID: category.id),
                    monthKey: budget.monthKey,
                    categoryID: category.id,
                    categoryNameSnapshot: category.name,
                    budgetAmount: budget.amount,
                    spentAmount: spent,
                    remainingAmount: remaining,
                    usageRatio: ratio,
                    isOverBudget: remaining < 0,
                    currencyCode: budget.currencyCode,
                    updatedAt: Date()
                )
            }
            .sorted {
                if $0.monthKey == $1.monthKey {
                    return $0.categoryNameSnapshot < $1.categoryNameSnapshot
                }
                return $0.monthKey > $1.monthKey
            }
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
