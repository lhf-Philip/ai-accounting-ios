import Foundation

struct TransferCounterpartInfo {
    let amount: Decimal
    let currencyCode: String
}

enum TransferPresentationService {
    static func counterpartMap(transactions: [FinancialTransaction]) -> [UUID: TransferCounterpartInfo] {
        let transferTransactions = transactions.filter { $0.type == .transfer }
        let idIndex = Dictionary(uniqueKeysWithValues: transferTransactions.map { ($0.id, $0) })
        let groupIndex = Dictionary(grouping: transferTransactions.compactMap { tx -> (UUID, FinancialTransaction)? in
            guard let groupID = tx.transferGroupID else { return nil }
            return (groupID, tx)
        }, by: { $0.0 }).mapValues { $0.map(\.1) }
        
        var result: [UUID: TransferCounterpartInfo] = [:]
        
        for tx in transferTransactions {
            if let linkedID = tx.linkedTransactionID, let linked = idIndex[linkedID] {
                result[tx.id] = TransferCounterpartInfo(amount: linked.amount, currencyCode: linked.currencyCode)
                continue
            }
            
            guard let groupID = tx.transferGroupID, let groupItems = groupIndex[groupID] else {
                continue
            }
            
            var candidates = groupItems.filter { $0.id != tx.id }
            if let currentSide = tx.transferSide {
                let opposite = candidates.filter { $0.transferSide != nil && $0.transferSide != currentSide }
                if !opposite.isEmpty {
                    candidates = opposite
                }
            }
            
            if candidates.count == 1, let counterpart = candidates.first {
                result[tx.id] = TransferCounterpartInfo(amount: counterpart.amount, currencyCode: counterpart.currencyCode)
            }
        }
        
        return result
    }
}
