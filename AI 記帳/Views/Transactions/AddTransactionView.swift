import SwiftUI
import SwiftData

struct AddTransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // 依照 sortOrder 排序
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \Tag.name) private var tags: [Tag]
    
    @State private var amountString = ""
    @State private var selectedType: TransactionType = .expense
    @State private var date = Date()
    @State private var note = ""
    @State private var selectedAccount: Account?
    @State private var selectedCategory: Category?
    @State private var selectedTags: Set<Tag> = []
    
    // 🔥 新增：交易幣種 (預設 HKD，會隨帳戶改變)
    @State private var selectedCurrency: String = "HKD"
    let currencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]
    
    @State private var showingAddCategory = false
    @State private var showingAddTag = false
    @State private var newTagName = ""
    
    // 焦點控制
    @FocusState private var isAmountFocused: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                // 1. 金額與類型
                Section("金額與類型") {
                    Picker("類型", selection: $selectedType) {
                        Text("支出").tag(TransactionType.expense)
                        Text("收入").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedType) {
                        if let current = selectedCategory, !current.kind.supports(selectedType) {
                            selectedCategory = nil
                        }
                    }
                    
                    HStack {
                        // 🔥 修改：幣種選擇器
                        Picker("", selection: $selectedCurrency) {
                            ForEach(currencies, id: \.self) { code in
                                Text(code).tag(code)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)
                        
                        TextField("0", text: $amountString)
                            .font(.largeTitle)
                            .keyboardType(.decimalPad)
                            .focused($isAmountFocused)
                    }
                }
                
                // 2. 帳戶與分類
                Section {
                    Picker("帳戶", selection: $selectedAccount) {
                        Text("選擇帳戶").tag(nil as Account?)
                        ForEach(accounts.filter { !$0.isArchived }) { acc in
                            Text(acc.name).tag(acc as Account?)
                        }
                    }
                    // 當切換帳戶時，自動切換幣種為該帳戶的預設幣種
                    // 但用戶之後可以手動改回去，實現「單帳戶多幣種」
                    .onChange(of: selectedAccount) {
                        if let acc = selectedAccount {
                            selectedCurrency = acc.currency
                        }
                    }
                    
                    HStack {
                        Picker("分類", selection: $selectedCategory) {
                            Text("無分類").tag(nil as Category?)
                            ForEach(filteredCategories) { cat in
                                HStack {
                                    Image(systemName: cat.icon)
                                    Text(cat.name)
                                }.tag(cat as Category?)
                            }
                        }
                        
                        Button(action: { showingAddCategory = true }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // 3. 標籤與其他
                Section {
                    HStack {
                        Text("標籤")
                        Spacer()
                        Button(action: { showingAddTag = true }) {
                            Label("新增", systemImage: "plus")
                                .font(.caption)
                        }
                    }
                    
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
                                    }
                            }
                        }
                    }
                    
                    DatePicker("日期", selection: $date)
                    TextField("備註", text: $note)
                }
            }
            .navigationTitle("記一筆")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { saveTransaction() }
                        .disabled(amountString.isEmpty || selectedAccount == nil)
                }
                
                // 鍵盤工具列
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        isAmountFocused = false
                    }
                }
            }
            .sheet(isPresented: $showingAddCategory) { AddCategoryView() }
            .alert("新增標籤", isPresented: $showingAddTag) {
                TextField("標籤名稱", text: $newTagName)
                Button("取消", role: .cancel) { newTagName = "" }
                Button("新增") {
                    if !newTagName.isEmpty {
                        let tag = Tag(name: newTagName)
                        modelContext.insert(tag)
                        newTagName = ""
                    }
                }
            }
            .onAppear {
                if selectedAccount == nil, let firstAccount = accounts.first {
                    selectedAccount = firstAccount
                    selectedCurrency = firstAccount.currency
                }
            }
        }
    }
    
    private func saveTransaction() {
        guard let amount = Decimal(string: amountString),
              let account = selectedAccount else { return }
        
        let finalAmount = (selectedType == .expense) ? -abs(amount) : abs(amount)
        
        let tx = FinancialTransaction(
            amount: finalAmount,
            currencyCode: selectedCurrency, // 🔥 使用用戶選擇的幣種
            date: date,
            note: note,
            type: selectedType,
            account: account,
            category: selectedCategory,
            tags: Array(selectedTags)
        )
        
        modelContext.insert(tx)
        dismiss()
    }
    
    private var filteredCategories: [Category] {
        categories.filter { $0.kind.supports(selectedType) }
    }
}
