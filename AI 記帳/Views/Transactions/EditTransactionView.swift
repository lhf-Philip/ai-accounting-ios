import SwiftUI
import SwiftData

struct EditTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var transaction: FinancialTransaction
    
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \Tag.name) private var tags: [Tag]
    
    @State private var amountString: String = ""
    @State private var selectedTags: Set<Tag> = []
    
    // 🔥 新增：焦點控制
    @FocusState private var isAmountFocused: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                if transaction.type == .transfer {
                    Text("轉帳交易請使用「編輯轉帳」功能，或刪除後重新建立。")
                        .foregroundStyle(.secondary)
                } else {
                    Section("金額與類型") {
                        Picker("類型", selection: $transaction.type) {
                            Text("支出").tag(TransactionType.expense)
                            Text("收入").tag(TransactionType.income)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: transaction.type) { _, _ in updateAmountSign() }
                        
                        HStack {
                            Text(transaction.account?.currency ?? "$")
                            TextField("金額", text: $amountString)
                                .keyboardType(.decimalPad)
                                .focused($isAmountFocused) // 🔥 綁定焦點
                                .onChange(of: amountString) { _, _ in updateTransactionAmount() }
                        }
                    }
                    
                    Section("詳細資訊") {
                        Picker("帳戶", selection: $transaction.account) {
                            Text("無").tag(nil as Account?)
                            ForEach(accounts.filter { !$0.isArchived }) { acc in
                                Text(acc.name).tag(acc as Account?)
                            }
                        }
                        
                        Picker("分類", selection: $transaction.category) {
                            Text("無").tag(nil as Category?)
                            ForEach(categories) { cat in
                                HStack {
                                    Image(systemName: cat.icon)
                                    Text(cat.name)
                                }.tag(cat as Category?)
                            }
                        }
                        
                        DatePicker("日期", selection: $transaction.date)
                        TextField("備註", text: $transaction.note)
                    }
                    
                    Section("標籤") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(tags) { tag in
                                    let isSelected = selectedTags.contains(tag)
                                    Text(tag.name)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                                        .foregroundStyle(isSelected ? .white : .primary)
                                        .cornerRadius(16)
                                        .onTapGesture {
                                            if isSelected { selectedTags.remove(tag) }
                                            else { selectedTags.insert(tag) }
                                            transaction.tags = Array(selectedTags)
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("編輯交易")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
                
                // 🔥 新增：鍵盤工具列 (收起按鈕)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        isAmountFocused = false // 收起鍵盤
                    }
                }
            }
            .onAppear {
                amountString = String(format: "%.2f", abs(NSDecimalNumber(decimal: transaction.amount).doubleValue))
                selectedTags = Set(transaction.tags)
            }
        }
    }
    
    private func updateAmountSign() {
        guard let val = Decimal(string: amountString) else { return }
        transaction.amount = (transaction.type == .expense) ? -abs(val) : abs(val)
    }
    
    private func updateTransactionAmount() {
        guard let val = Decimal(string: amountString) else { return }
        transaction.amount = (transaction.type == .expense) ? -abs(val) : abs(val)
    }
}
