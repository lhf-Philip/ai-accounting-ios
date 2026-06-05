import Foundation
import SwiftData

struct DebtSettlementCurrencyBalance: Identifiable, Equatable {
    let currencyCode: String
    let amount: Decimal

    var id: String { currencyCode }
}

@MainActor
enum DebtSettlementBalanceService {
    private static let tolerance = Decimal(string: "0.0001") ?? Decimal(0.0001)

    static func balances(
        for account: Account,
        transactions: [FinancialTransaction],
        advanceCases: [AdvanceCase],
        modelContext: ModelContext
    ) -> [DebtSettlementCurrencyBalance] {
        if account.type == .debt {
            return semanticDebtBalances(
                for: account,
                transactions: transactions,
                advanceCases: advanceCases,
                modelContext: modelContext
            )
        }

        return rawBalances(for: account, transactions: transactions)
    }

    static func rawBalances(
        for account: Account,
        transactions: [FinancialTransaction]
    ) -> [DebtSettlementCurrencyBalance] {
        var totals: [String: Decimal] = [:]
        if account.baseBalance != 0 {
            totals[account.currency, default: 0] += account.baseBalance
        }
        for transaction in transactions where transaction.account?.id == account.id {
            totals[transaction.currencyCode, default: 0] += transaction.amount
        }
        return sortedBalances(totals)
    }

    static func semanticDebtBalances(
        for account: Account,
        transactions: [FinancialTransaction],
        advanceCases: [AdvanceCase],
        modelContext: ModelContext
    ) -> [DebtSettlementCurrencyBalance] {
        var totals: [String: Decimal] = [:]
        if account.baseBalance != 0 {
            totals[account.currency, default: 0] += account.baseBalance
        }

        let advanceGroupIDs = Set(
            advanceCases.flatMap { advanceCase in
                advanceCase.participants.compactMap(\.initialTransferGroupID)
                    + advanceCase.repayments.compactMap(\.linkedTransferGroupID)
            }
        )

        for transaction in transactions where transaction.account?.id == account.id {
            if let groupID = transaction.transferGroupID, advanceGroupIDs.contains(groupID) {
                continue
            }
            totals[transaction.currencyCode, default: 0] += transaction.amount
        }

        for advanceCase in advanceCases {
            for participant in advanceCase.participants where participant.debtAccount?.id == account.id {
                let remaining = participant.remainingAmount
                guard remaining > tolerance else { continue }
                let signedRemaining = advanceCase.payerAccount == nil ? -remaining : remaining
                totals[advanceCase.currencyCode, default: 0] += signedRemaining
            }
        }

        return sortedBalances(totals)
    }

    private static func sortedBalances(_ totals: [String: Decimal]) -> [DebtSettlementCurrencyBalance] {
        totals
            .filter { abs($0.value) > tolerance }
            .sorted { $0.key < $1.key }
            .map { DebtSettlementCurrencyBalance(currencyCode: $0.key, amount: $0.value) }
    }
}
