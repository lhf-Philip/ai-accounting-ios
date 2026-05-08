import SwiftUI
import SwiftData

struct EditTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var transaction: FinancialTransaction
    @StateObject private var currencyService = CurrencyService.shared
    
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \Tag.name) private var tags: [Tag]
    
    @State private var amountString: String = ""
    @State private var selectedTags: Set<Tag> = []
    @State private var originalBudgetKey: BudgetHistoryAffectedKey?
    @State private var errorMessage: String?
    
    // 🔥 新增：焦點控制
    @FocusState private var isAmountFocused: Bool

    private var selectableAccounts: [Account] {
        let allowed = TransactionSemantics.allowedAccounts(for: transaction.type, from: accounts)
        guard let current = transaction.account else { return allowed }
        if allowed.contains(where: { $0.id == current.id }) {
            return allowed
        }
        return [current] + allowed
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("金額與類型") {
                    if transaction.type == .transfer {
                        LabeledContent("類型") {
                            Text("轉帳")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Picker("類型", selection: $transaction.type) {
                            Text("支出").tag(TransactionType.expense)
                            Text("收入").tag(TransactionType.income)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: transaction.type) { _, newType in
                            updateAmountSign()
                            if let category = transaction.category, !category.kind.supports(newType) {
                                transaction.category = nil
                            }
                            if let currentAccount = transaction.account,
                               !TransactionSemantics.allowedAccounts(for: newType, from: accounts).contains(where: { $0.id == currentAccount.id }) {
                                transaction.account = TransactionSemantics.allowedAccounts(for: newType, from: accounts).first
                            }
                        }
                    }

                    HStack {
                        Text(transaction.account?.currency ?? "$")
                        TextField("金額", text: $amountString)
                            .keyboardType(.decimalPad)
                            .focused($isAmountFocused) // 🔥 綁定焦點
                            .onChange(of: amountString) { _, _ in updateTransactionAmount() }
                            .accessibilityIdentifier("transactionEditor.amountField")
                    }
                    CurrencyRateHintView(
                        currencyService: currencyService,
                        amount: Decimal(string: amountString),
                        currencyCode: transaction.currencyCode
                    )
                }

                Section("詳細資訊") {
                    Picker("帳戶", selection: $transaction.account) {
                        Text("無").tag(nil as Account?)
                        ForEach(selectableAccounts) { acc in
                            Text(acc.name).tag(acc as Account?)
                        }
                    }

                    if transaction.type != .transfer {
                        Picker("分類", selection: $transaction.category) {
                            Text("無").tag(nil as Category?)
                            ForEach(filteredCategories) { cat in
                                HStack {
                                    Image(systemName: cat.icon)
                                    Text(cat.name)
                                }.tag(cat as Category?)
                            }
                        }
                    }

                    DatePicker("日期", selection: $transaction.date)
                        .accessibilityIdentifier("transactionEditor.datePicker")
                    TextField("備註", text: $transaction.note)
                        .accessibilityIdentifier("transactionEditor.noteField")
                }

                if transaction.type != .transfer {
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
                    Button("完成") {
                        saveChanges()
                    }
                    .accessibilityIdentifier("transactionEditor.saveButton")
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
                originalBudgetKey = BudgetHistoryService.affectedKey(for: transaction)
                Task { await currencyService.fetchRates() }
            }
            .alert("儲存失敗", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func saveChanges() {
        do {
            let previousKey = originalBudgetKey
            transaction.updatedAt = Date()
            try modelContext.save()
            let currentKey = BudgetHistoryService.affectedKey(for: transaction)
            try BudgetHistoryService.shared.syncAffected(
                keys: [previousKey, currentKey].compactMap { $0 },
                modelContext: modelContext,
                currencyService: currencyService
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func updateAmountSign() {
        guard let val = Decimal(string: amountString) else { return }
        if transaction.type == .transfer {
            transaction.amount = transaction.amount >= 0 ? abs(val) : -abs(val)
            return
        }
        transaction.amount = (transaction.type == .expense) ? -abs(val) : abs(val)
    }
    
    private func updateTransactionAmount() {
        guard let val = Decimal(string: amountString) else { return }
        if transaction.type == .transfer {
            transaction.amount = transaction.amount >= 0 ? abs(val) : -abs(val)
            return
        }
        transaction.amount = (transaction.type == .expense) ? -abs(val) : abs(val)
    }
    
    private var filteredCategories: [Category] {
        categories.filter { $0.kind.supports(transaction.type) }
    }
}
