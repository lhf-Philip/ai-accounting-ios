import Foundation

enum RefundSemanticsError: Error, Equatable {
    case invalidRefundAmount
    case invalidOriginalExpenseRemaining
}

enum RefundDestinationKind: Equatable {
    case ownAccount
    case debtAccount
}

struct RefundSemanticInput: Equatable {
    let amount: Decimal
    let destination: RefundDestinationKind
    let originalExpenseRemaining: Decimal?

    init(
        amount: Decimal,
        destination: RefundDestinationKind,
        originalExpenseRemaining: Decimal? = nil
    ) {
        self.amount = amount
        self.destination = destination
        self.originalExpenseRemaining = originalExpenseRemaining
    }
}

struct RefundSemanticEffect: Equatable {
    let ownAccountDelta: Decimal
    let debtBalanceDelta: Decimal
    let expenseReduction: Decimal
    let incomeContribution: Decimal
    let settlementOnlyAmount: Decimal

    var reportNetExpenseDelta: Decimal {
        -expenseReduction
    }
}

enum RefundSemanticsService {
    static func effect(for input: RefundSemanticInput) throws -> RefundSemanticEffect {
        guard input.amount > 0 else {
            throw RefundSemanticsError.invalidRefundAmount
        }
        if let originalExpenseRemaining = input.originalExpenseRemaining,
           originalExpenseRemaining < 0 {
            throw RefundSemanticsError.invalidOriginalExpenseRemaining
        }

        let expenseReduction = min(input.amount, input.originalExpenseRemaining ?? input.amount)
        let settlementOnlyAmount = max(0, input.amount - expenseReduction)

        let ownAccountDelta: Decimal
        let debtBalanceDelta: Decimal
        switch input.destination {
        case .ownAccount:
            ownAccountDelta = input.amount
            debtBalanceDelta = 0
        case .debtAccount:
            ownAccountDelta = 0
            debtBalanceDelta = input.amount
        }

        return RefundSemanticEffect(
            ownAccountDelta: ownAccountDelta,
            debtBalanceDelta: debtBalanceDelta,
            expenseReduction: expenseReduction,
            incomeContribution: 0,
            settlementOnlyAmount: settlementOnlyAmount
        )
    }
}
