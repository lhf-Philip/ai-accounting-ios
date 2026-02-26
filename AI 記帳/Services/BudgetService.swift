import Foundation

struct BudgetStatus: Identifiable {
    let budget: CategoryMonthlyBudget
    let spent: Decimal
    let remaining: Decimal
    let ratio: Decimal
    let isOverBudget: Bool
    
    var id: UUID { budget.id }
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
}
