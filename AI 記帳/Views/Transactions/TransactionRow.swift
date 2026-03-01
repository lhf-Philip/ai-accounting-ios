import SwiftUI
import SwiftData

struct TransactionRow: View {
    let transaction: FinancialTransaction
    let transferCounterpart: TransferCounterpartInfo?
    
    private static let rowDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter
    }()
    
    private var dateString: String {
        Self.rowDateFormatter.string(from: transaction.date)
    }
    
    private var isAdvanceTransfer: Bool {
        guard transaction.type == .transfer else { return false }
        let compacted = transaction.note.replacingOccurrences(of: " ", with: "")
        return compacted.contains("(代墊給") || compacted.contains("(還款至")
    }
    
    private var transferIconName: String {
        isAdvanceTransfer ? "person.2.fill" : "arrow.left.arrow.right"
    }
    
    private var transferBadgeText: String {
        isAdvanceTransfer ? "代墊追蹤" : "轉帳"
    }
    
    private var transferTint: Color {
        isAdvanceTransfer ? .orange : .blue
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // MARK: - Icon
            if transaction.type == .transfer {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: transferIconName)
                            .foregroundStyle(transferTint)
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
                    (transaction.category?.name ?? (transaction.type == .transfer ? transferBadgeText : "未分類"))
                    : transaction.note
                
                Text(mainText)
                    .font(.body).bold()
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    if transaction.type == .transfer {
                        Text(transferBadgeText)
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
                let linkedInfo = transferCounterpart
                
                // 判斷是否為雙幣種轉帳 (顯示轉換箭頭)
                if transaction.type == .transfer,
                   let linked = linkedInfo,
                   linked.currencyCode != currency { // 比較兩邊交易的實際幣種
                    
                    // 本方金額
                    Text(transaction.amount.formatted(.currency(code: currency)))
                        .bold()
                        .foregroundStyle(transferTint)
                    
                    // 對方金額
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                        Text(linked.amount.formatted(.currency(code: linked.currencyCode)))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                } else {
                    // 單幣種或普通交易
                    if transaction.type == .transfer {
                        Text(transaction.amount.formatted(.currency(code: currency)))
                            .bold()
                            .foregroundStyle(transferTint)
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

extension TransactionRow {
    init(transaction: FinancialTransaction) {
        self.transaction = transaction
        self.transferCounterpart = nil
    }
}
