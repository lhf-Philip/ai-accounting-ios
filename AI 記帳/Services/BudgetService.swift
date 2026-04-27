import Foundation

struct BudgetStatus: Identifiable {
    let budget: CategoryMonthlyBudget
    let spent: Decimal
    let remaining: Decimal
    let ratio: Decimal
    let isOverBudget: Bool
    
    var id: UUID { budget.id }
}

struct BudgetForecast {
    let projectedSpent: Decimal
    let projectedRemaining: Decimal
    let projectedRatio: Decimal
    let daysElapsed: Int
    let daysInMonth: Int

    var isProjectedOverBudget: Bool {
        projectedRemaining < 0
    }
}

enum BudgetService {
    static func monthKey(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        return String(format: "%04d-%02d", year, month)
    }
    
    static func monthStart(from monthKey: String) -> Date? {
        let parts = monthKey.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1])
        else { return nil }
        
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return Calendar.current.date(from: components)
    }

    static func previousMonthKey(from monthKey: String) -> String? {
        guard let start = monthStart(from: monthKey),
              let previous = Calendar.current.date(byAdding: .month, value: -1, to: start)
        else { return nil }
        return self.monthKey(from: previous)
    }
    
    static func statuses(
        for targetMonthKey: String,
        budgets: [CategoryMonthlyBudget],
        transactions: [FinancialTransaction],
        currencyService: CurrencyService
    ) -> [BudgetStatus] {
        let activeBudgets = budgets.filter { $0.isEnabled && $0.monthKey == targetMonthKey }
        
        let results: [BudgetStatus] = activeBudgets.map { budget in
            let spent = transactions
                .filter { tx in
                    tx.type == .expense &&
                    monthKey(from: tx.date) == targetMonthKey &&
                    tx.category?.id == budget.category?.id
                }
                .reduce(Decimal.zero) { partial, tx in
                    partial + currencyService.convert(amount: abs(tx.amount), from: tx.currencyCode, to: budget.currencyCode)
                }
            
            let remaining = budget.amount - spent
            let ratio: Decimal = budget.amount > 0 ? (spent / budget.amount) : 0
            return BudgetStatus(
                budget: budget,
                spent: spent,
                remaining: remaining,
                ratio: ratio,
                isOverBudget: remaining < 0
            )
        }
        
        return results.sorted {
            if $0.isOverBudget != $1.isOverBudget {
                return $0.isOverBudget && !$1.isOverBudget
            }
            return $0.ratio > $1.ratio
        }
    }

    static func forecast(for status: BudgetStatus, today: Date = Date()) -> BudgetForecast {
        guard let monthStart = monthStart(from: status.budget.monthKey),
              let monthRange = Calendar.current.range(of: .day, in: .month, for: monthStart)
        else {
            return BudgetForecast(
                projectedSpent: status.spent,
                projectedRemaining: status.remaining,
                projectedRatio: status.ratio,
                daysElapsed: 1,
                daysInMonth: 1
            )
        }

        let daysInMonth = monthRange.count
        let currentMonthKey = monthKey(from: today)
        let projectedSpent: Decimal
        let daysElapsed: Int

        if status.budget.monthKey == currentMonthKey {
            let day = Calendar.current.component(.day, from: today)
            daysElapsed = max(1, min(day, daysInMonth))
            projectedSpent = status.spent / Decimal(daysElapsed) * Decimal(daysInMonth)
        } else {
            daysElapsed = daysInMonth
            projectedSpent = status.spent
        }

        let projectedRemaining = status.budget.amount - projectedSpent
        let projectedRatio: Decimal = status.budget.amount > 0 ? projectedSpent / status.budget.amount : 0
        return BudgetForecast(
            projectedSpent: projectedSpent,
            projectedRemaining: projectedRemaining,
            projectedRatio: projectedRatio,
            daysElapsed: daysElapsed,
            daysInMonth: daysInMonth
        )
    }

    static func carryOverAmount(
        previousBudgetAmount: Decimal,
        previousRemaining: Decimal,
        mode: BudgetCarryOverMode
    ) -> Decimal {
        switch mode {
        case .none:
            return previousBudgetAmount
        case .unusedOnly:
            return previousBudgetAmount + max(previousRemaining, 0)
        case .overspendOnly:
            return max(previousBudgetAmount + min(previousRemaining, 0), 0)
        case .netBalance:
            return max(previousBudgetAmount + previousRemaining, 0)
        }
    }
}
