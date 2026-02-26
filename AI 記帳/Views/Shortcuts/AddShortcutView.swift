import SwiftUI
import SwiftData

struct AddShortcutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \Tag.name) private var tags: [Tag]
    
    // 過濾已歸檔帳戶 (不讓用戶建立關聯到已歸檔帳戶的捷徑)
    var accounts: [Account] { allAccounts.filter { !$0.isArchived } }
    
    @State private var name: String = ""
    @State private var icon: String = "⚡️"
    @State private var amountString: String = ""
    // 🔥 新增：捷徑幣種
    @State private var selectedCurrency: String = "HKD"
    @State private var selectedType: TransactionType = .expense
    @State private var note: String = ""
    @State private var selectedAccount: Account?
    @State private var selectedCategory: Category?
    @State private var selectedTags: Set<Tag> = []
    
    @FocusState private var isAmountFocused: Bool
    
    let currencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("捷徑外觀") {
                    HStack {
                        TextField("捷徑名稱 (例如: 買咖啡)", text: $name)
                        Divider()
                        HStack {
                            Text("圖標:")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("Emoji", text: $icon)
                                .font(.title2).frame(width: 50).multilineTextAlignment(.center)
                                .keyboardType(.default)
                                .onChange(of: icon) { if icon.count > 1 { icon = String(icon.prefix(1)) } }
                        }
                    }
                }
                
                Section("預設交易內容") {
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
                        // 🔥 幣種選擇
                        Picker("", selection: $selectedCurrency) {
                            ForEach(currencies, id: \.self) { code in Text(code).tag(code) }
                        }
                        .labelsHidden().frame(width: 80)
                        
                        TextField("金額", text: $amountString)
                            .keyboardType(.decimalPad)
                            .focused($isAmountFocused)
                    }
                    
                    TextField("備註 (選填)", text: $note)
                    
                    Picker("帳戶", selection: $selectedAccount) {
                        Text("選擇帳戶").tag(nil as Account?)
                        ForEach(accounts) { acc in Text(acc.name).tag(acc as Account?) }
                    }
                    .onChange(of: selectedAccount) {
                        if let acc = selectedAccount { selectedCurrency = acc.currency }
                    }
                    
                    Picker("分類", selection: $selectedCategory) {
                        Text("無分類").tag(nil as Category?)
                        ForEach(filteredCategories) { cat in
                            HStack { Image(systemName: cat.icon); Text(cat.name) }.tag(cat as Category?)
                        }
                    }
                }
                
                Section("標籤 (選填)") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(tags) { tag in
                                let isSelected = selectedTags.contains(tag)
                                Text(tag.name)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                                    .foregroundStyle(isSelected ? .white : .primary)
                                    .cornerRadius(16)
                                    .onTapGesture { if isSelected { selectedTags.remove(tag) } else { selectedTags.insert(tag) } }
                            }
                        }
                    }
                }
            }
            .navigationTitle("新增捷徑")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { saveShortcut() }
                        .disabled(name.isEmpty || amountString.isEmpty || selectedAccount == nil)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { isAmountFocused = false } }
            }
            .onAppear {
                if selectedAccount == nil { selectedAccount = accounts.first; if let acc = selectedAccount { selectedCurrency = acc.currency } }
            }
        }
    }
    
    private func saveShortcut() {
        guard let amount = Decimal(string: amountString), let account = selectedAccount else { return }
        let finalIcon = icon.isEmpty ? "⚡️" : icon
        let shortcut = Shortcut(name: name, icon: finalIcon, amount: amount, currencyCode: selectedCurrency, type: selectedType, note: note, account: account, category: selectedCategory, tags: Array(selectedTags))
        modelContext.insert(shortcut)
        dismiss()
    }
    
    private var filteredCategories: [Category] {
        categories.filter { $0.kind.supports(selectedType) }
    }
}
