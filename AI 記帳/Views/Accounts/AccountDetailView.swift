import SwiftUI
import SwiftData

struct AccountDetailView: View {
    let account: Account
    @Query(sort: \FinancialTransaction.date, order: .reverse) private var allTransactions: [FinancialTransaction]
    @Environment(\.modelContext) private var modelContext
    
    // 只篩選該帳戶的交易
    var accountTransactions: [FinancialTransaction] {
        allTransactions.filter { $0.account?.id == account.id }
    }
    
    // 🔥 修正 1：定義一個結構體來代替 Tuple，讓 ForEach 能識別
    struct CurrencyBalance: Identifiable {
        var id: String { currency } // 使用幣種作為唯一 ID
        let currency: String
        let amount: Decimal
    }
    
    // 🔥 修正 2：回傳 [CurrencyBalance] 結構體陣列
    var currencyBalances: [CurrencyBalance] {
        var balances: [String: Decimal] = [:]
        
        // 1. 加上初始餘額 (歸入帳戶預設幣種)
        if account.baseBalance != 0 {
            balances[account.currency, default: 0] += account.baseBalance
        }
        
        // 2. 加上所有交易 (歸入交易各自的幣種)
        for tx in accountTransactions {
            balances[tx.currencyCode, default: 0] += tx.amount
        }
        
        // 過濾掉金額為 0 的，並轉為結構體陣列
        return balances
            .filter { $0.value != 0 }
            .map { CurrencyBalance(currency: $0.key, amount: $0.value) }
            .sorted { $0.currency < $1.currency }
    }
    
    var body: some View {
        List {
            // 1. 頂部資訊卡 (總覽)
            Section {
                VStack(spacing: 16) {
                    
                    if currencyBalances.isEmpty {
                        // 如果剛好歸零，顯示 0 (預設幣種)
                        Text(Decimal(0).formatted(.currency(code: account.currency)))
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.secondary)
                    } else {
                        // 🔥 修正 3：現在 ForEach 可以正常運作了
                        ForEach(currencyBalances) { item in
                            HStack {
                                Text(item.currency)
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .leading)
                                
                                Spacer()
                                
                                Text(item.amount.formatted(.currency(code: item.currency)))
                                    .font(.title2)
                                    .bold()
                                    .foregroundStyle(item.amount >= 0 ? Color.primary : Color.red)
                            }
                            
                            // 分隔線邏輯：如果不是最後一個，顯示分隔線
                            if item.id != currencyBalances.last?.id {
                                Divider()
                            }
                        }
                    }
                    
                    HStack {
                        Text(account.name)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        Text(account.type.displayName)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 10)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color(uiColor: .systemGroupedBackground))
            }
            
            // 2. 交易列表
            Section("交易紀錄") {
                ForEach(accountTransactions) { transaction in
                    TransactionRow(transaction: transaction)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteTransaction(transaction)
                            } label: {
                                Label("刪除", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func deleteTransaction(_ transaction: FinancialTransaction) {
        if transaction.type == .transfer, let groupID = transaction.transferGroupID {
            let descriptor = FetchDescriptor<FinancialTransaction>(
                predicate: #Predicate { $0.transferGroupID == groupID }
            )
            if let groupedTransfers = try? modelContext.fetch(descriptor) {
                for transfer in groupedTransfers {
                    modelContext.delete(transfer)
                }
                return
            }
        }
        
        if transaction.type == .transfer, let linkedID = transaction.linkedTransactionID {
            let descriptor = FetchDescriptor<FinancialTransaction>(
                predicate: #Predicate { $0.id == linkedID }
            )
            if let linkedTx = try? modelContext.fetch(descriptor).first {
                modelContext.delete(linkedTx)
            }
        }
        
        modelContext.delete(transaction)
    }
}
