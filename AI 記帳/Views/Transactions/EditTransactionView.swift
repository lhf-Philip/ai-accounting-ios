import SwiftUI
import SwiftData

struct EditTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let transaction: FinancialTransaction
    @StateObject private var currencyService = CurrencyService.shared
    
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \Tag.name) private var tags: [Tag]
    
    @State private var amountString: String = ""
    @State private var selectedCurrency = "HKD"
    @State private var selectedType: TransactionType = .expense
    @State private var selectedAccount: Account?
    @State private var selectedCategory: Category?
    @State private var selectedDate = Date()
    @State private var note = ""
    @State private var selectedTags: Set<Tag> = []
    @State private var originalBudgetKey: BudgetHistoryAffectedKey?
    @State private var errorMessage: String?
    @State private var didLoadDraft = false
    
    // 🔥 新增：焦點控制
    @FocusState private var isAmountFocused: Bool

    private let currencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]

    private var availableCurrencies: [String] {
        currencies.contains(selectedCurrency) ? currencies : [selectedCurrency] + currencies
    }

    private var selectableAccounts: [Account] {
        let allowed = TransactionSemantics.allowedAccounts(for: selectedType, from: accounts)
        guard let current = selectedAccount else { return allowed }
        if allowed.contains(where: { $0.id == current.id }) {
            return allowed
        }
        return [current] + allowed
    }

    private var amountBinding: Binding<String> {
        Binding(
            get: { amountString },
            set: { amountString = sanitizePositiveDecimalInput($0) }
        )
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("金額與類型") {
                    if selectedType == .transfer {
                        LabeledContent("類型") {
                            Text("轉帳")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Picker("類型", selection: $selectedType) {
                            Text("支出").tag(TransactionType.expense)
                            Text("收入").tag(TransactionType.income)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedType) { _, newType in
                            if let category = selectedCategory, !category.kind.supports(newType) {
                                selectedCategory = nil
                            }
                            if let currentAccount = selectedAccount,
                               !TransactionSemantics.allowedAccounts(for: newType, from: accounts).contains(where: { $0.id == currentAccount.id }) {
                                selectedAccount = TransactionSemantics.allowedAccounts(for: newType, from: accounts).first
                            }
                        }
                    }

                    HStack {
                        Picker("幣種", selection: $selectedCurrency) {
                            ForEach(availableCurrencies, id: \.self) { code in
                                Text(code).tag(code)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 88)

                        TextField("金額", text: amountBinding)
                            .keyboardType(.decimalPad)
                            .focused($isAmountFocused)
                            .accessibilityIdentifier("transactionEditor.amountField")
                    }
                    CurrencyRateHintView(
                        currencyService: currencyService,
                        amount: Decimal(string: amountString),
                        currencyCode: selectedCurrency
                    )
                }

                Section("詳細資訊") {
                    Picker("帳戶", selection: $selectedAccount) {
                        Text("選擇帳戶").tag(nil as Account?)
                        ForEach(selectableAccounts) { acc in
                            Text(acc.name).tag(acc as Account?)
                        }
                    }

                    if selectedType != .transfer {
                        Picker("分類", selection: $selectedCategory) {
                            Text("無").tag(nil as Category?)
                            ForEach(filteredCategories) { cat in
                                HStack {
                                    Image(systemName: cat.icon)
                                    Text(cat.name)
                                }.tag(cat as Category?)
                            }
                        }
                    }

                    DatePicker("日期", selection: $selectedDate)
                        .accessibilityIdentifier("transactionEditor.datePicker")
                    TextField("備註", text: $note)
                        .accessibilityIdentifier("transactionEditor.noteField")
                }

                if selectedType != .transfer {
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
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .interactiveKeyboardDismiss()
            .navigationTitle("編輯交易")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        saveChanges()
                    }
                    .disabled(!canSubmit)
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
                loadDraftIfNeeded()
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
            guard let amount = positiveDecimal(from: amountString) else {
                errorMessage = "請輸入有效金額。"
                return
            }

            let previousKey = originalBudgetKey
            let draft = OrdinaryTransactionEditDraft(
                amount: amount,
                currencyCode: selectedCurrency,
                date: selectedDate,
                note: note,
                type: selectedType,
                account: selectedAccount,
                category: selectedCategory,
                tags: Array(selectedTags)
            )
            try TransactionEditService.apply(draft, to: transaction)
            try modelContext.save()
            let currentKey = BudgetHistoryService.affectedKey(for: transaction)
            try BudgetHistoryService.shared.syncAffected(
                keys: [previousKey, currentKey].compactMap { $0 },
                modelContext: modelContext,
                currencyService: currencyService
            )
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func loadDraftIfNeeded() {
        guard !didLoadDraft else { return }
        didLoadDraft = true
        selectedType = transaction.type
        selectedAccount = transaction.account
        selectedCurrency = transaction.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (transaction.account?.currency ?? "HKD")
            : transaction.currencyCode.uppercased()
        selectedCategory = transaction.category
        selectedDate = transaction.date
        note = transaction.note
        amountString = NSDecimalNumber(decimal: abs(transaction.amount)).stringValue
        selectedTags = Set(transaction.tags)
        originalBudgetKey = BudgetHistoryService.affectedKey(for: transaction)
    }

    private var canSubmit: Bool {
        positiveDecimal(from: amountString) != nil
            && selectedAccount != nil
            && !selectedCurrency.isEmpty
    }

    private var filteredCategories: [Category] {
        categories.filter { $0.kind.supports(selectedType) }
    }

    private func positiveDecimal(from rawValue: String) -> Decimal? {
        guard let value = Decimal(string: rawValue), value > 0 else { return nil }
        return value
    }

    private func sanitizePositiveDecimalInput(_ rawValue: String) -> String {
        var output = ""
        var hasDecimalSeparator = false

        for character in rawValue {
            if character.isNumber {
                output.append(character)
            } else if character == "." && !hasDecimalSeparator {
                hasDecimalSeparator = true
                output.append(character)
            }
        }

        return output
    }
}
