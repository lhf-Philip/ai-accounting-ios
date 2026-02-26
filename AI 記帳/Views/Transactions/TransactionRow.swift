import SwiftUI
import SwiftData

struct TransactionRow: View {
    let transaction: FinancialTransaction
    @Environment(\.modelContext) private var modelContext
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter.string(from: transaction.date)
    }
    
    // 嘗試取得「對向」轉帳資訊；多邊轉帳僅在唯一對向時顯示。
    private func getLinkedTransferInfo() -> (amount: Decimal, currency: String)? {
        guard transaction.type == .transfer else { return nil }
        
        if let linkedID = transaction.linkedTransactionID {
            let descriptor = FetchDescriptor<FinancialTransaction>(
                predicate: #Predicate { $0.id == linkedID }
            )
            if let linkedTx = try? modelContext.fetch(descriptor).first {
                return (linkedTx.amount, linkedTx.currencyCode)
            }
        }
        
        guard let groupID = transaction.transferGroupID else { return nil }
        let descriptor = FetchDescriptor<FinancialTransaction>(
            predicate: #Predicate { $0.transferGroupID == groupID }
        )
        guard let groupedTransfers = try? modelContext.fetch(descriptor) else { return nil }
        
        let counterparts = groupedTransfers.filter { candidate in
            guard candidate.id != transaction.id else { return false }
            if let currentSide = transaction.transferSide, let candidateSide = candidate.transferSide {
                return currentSide != candidateSide
            }
            return true
        }
        
        if counterparts.count == 1, let counterparty = counterparts.first {
            return (counterparty.amount, counterparty.currencyCode)
        }
        
        return nil
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // MARK: - Icon
            if transaction.type == .transfer {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "arrow.left.arrow.right")
                            .foregroundStyle(.blue)
                    }
            } else {
                let colorHex = transaction.category?.colorHex ?? "8E8E93"
                let iconName = transaction.category?.icon ?? "questionmark"
                
                Circle()
                    .fill(Color(hex: colorHex).opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: iconName)
                            .foregroundStyle(Color(hex: colorHex))
                    }
            }
            
            // MARK: - Text Info
            VStack(alignment: .leading, spacing: 4) {
                let mainText = transaction.note.isEmpty ?
                    (transaction.category?.name ?? (transaction.type == .transfer ? "轉帳" : "未分類"))
                    : transaction.note
                
                Text(mainText)
                    .font(.body).bold()
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    if transaction.type == .transfer {
                        Text("轉帳")
                    } else {
                        Text(transaction.category?.name ?? "未分類")
                    }
                    Text("•")
                    Text(transaction.account?.name ?? "未知帳戶")
                        .foregroundStyle(.blue.opacity(0.8))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            
            Spacer()
            
            // MARK: - Amount & Date
            VStack(alignment: .trailing, spacing: 4) {
                // 🔥 使用交易本身的 currencyCode
                let currency = transaction.currencyCode
                let linkedInfo = getLinkedTransferInfo()
                
                // 判斷是否為雙幣種轉帳 (顯示轉換箭頭)
                if transaction.type == .transfer,
                   let linked = linkedInfo,
                   linked.currency != currency { // 比較兩邊交易的實際幣種
                    
                    // 本方金額
                    Text(transaction.amount.formatted(.currency(code: currency)))
                        .bold()
                        .foregroundStyle(.blue)
                    
                    // 對方金額
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                        Text(linked.amount.formatted(.currency(code: linked.currency)))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                } else {
                    // 單幣種或普通交易
                    if transaction.type == .transfer {
                        Text(transaction.amount.formatted(.currency(code: currency)))
                            .bold()
                            .foregroundStyle(.blue)
                    } else {
                        Text(transaction.amount.formatted(.currency(code: currency)))
                            .bold()
                            .foregroundStyle(transaction.amount >= 0 ? .green : .red)
                    }
                }
                
                Text(dateString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
