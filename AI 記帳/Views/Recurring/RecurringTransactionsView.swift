import SwiftUI
import SwiftData

struct RecurringTransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecurringOccurrence.dueDate) private var occurrences: [RecurringOccurrence]
    @Query(sort: \RecurringRule.nextDueDate) private var rules: [RecurringRule]
    @State private var showingAddRule = false
    @State private var editingRule: RecurringRule?
    @State private var alertMessage: String?

    private var pendingOccurrences: [RecurringOccurrence] {
        occurrences.filter { $0.status == .pending }
    }

    var body: some View {
        List {
            if pendingOccurrences.isEmpty {
                Section {
                    ContentUnavailableView(
                        "沒有待確認項目",
                        systemImage: "checkmark.circle",
                        description: Text("定期記帳到期後會先出現在這裡，確認後才會建立正式帳目。")
                    )
                }
            } else {
                Section("待確認") {
                    ForEach(pendingOccurrences) { occurrence in
                        pendingOccurrenceRow(occurrence)
                    }
                }
            }

            Section("規則") {
                if rules.isEmpty {
                    Text("尚未建立定期記帳規則。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rules) { rule in
                        Button {
                            editingRule = rule
                        } label: {
                            recurringRuleRow(rule)
                        }
                    }
                }
            }
        }
        .prominentInlineTitle("定期記帳")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddRule = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddRule, onDismiss: syncDueOccurrences) {
            AddRecurringRuleView()
        }
        .sheet(item: $editingRule, onDismiss: syncDueOccurrences) { rule in
            AddRecurringRuleView(rule: rule)
        }
        .alert("提示", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(alertMessage ?? "")
        }
        .task {
            syncDueOccurrences()
        }
    }

    private func pendingOccurrenceRow(_ occurrence: RecurringOccurrence) -> some View {
        let rule = occurrence.rule
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule?.title ?? "未知規則")
                        .font(.headline)
                    Text(occurrence.dueDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(occurrence.dueDate < Date() ? .red : .secondary)
                }
                Spacer()
                if let rule {
                    Text(signedAmountText(for: rule))
                        .font(.headline)
                        .foregroundStyle(rule.type == .income ? .green : .red)
                }
            }

            HStack {
                Button("跳過") {
                    updateOccurrence(occurrence) {
                        try RecurringTransactionService.skip(occurrence: occurrence, modelContext: modelContext)
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("確認建立") {
                    updateOccurrence(occurrence) {
                        _ = try RecurringTransactionService.confirm(occurrence: occurrence, modelContext: modelContext)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(rule?.account == nil)
            }
        }
        .padding(.vertical, 4)
    }

    private func recurringRuleRow(_ rule: RecurringRule) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(rule.frequency.displayName) · 每 \(rule.intervalCount) 次 · 下次 \(rule.nextDueDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if rule.isPaused {
                    Text("已暫停")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(signedAmountText(for: rule))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(rule.type == .income ? .green : .red)
        }
        .contentShape(Rectangle())
    }

    private func signedAmountText(for rule: RecurringRule) -> String {
        let amount = rule.type == .expense ? -abs(rule.amount) : abs(rule.amount)
        return amount.formatted(.currency(code: rule.currencyCode))
    }

    private func syncDueOccurrences() {
        do {
            try RecurringTransactionService.syncDueOccurrences(
                rules: rules,
                occurrences: occurrences,
                modelContext: modelContext
            )
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func updateOccurrence(_ occurrence: RecurringOccurrence, action: () throws -> Void) {
        do {
            try action()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

struct AddRecurringRuleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Category.name) private var categories: [Category]

    let rule: RecurringRule?

    @State private var title = ""
    @State private var type: TransactionType = .expense
    @State private var amountString = ""
    @State private var currencyCode = "HKD"
    @State private var frequency: RecurringFrequency = .monthly
    @State private var intervalCount = 1
    @State private var nextDueDate = Date()
    @State private var note = ""
    @State private var isPaused = false
    @State private var selectedAccount: Account?
    @State private var selectedCategory: Category?
    @State private var validationMessage: String?

    private let currencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]

    private var availableCurrencies: [String] {
        currencies.contains(currencyCode) ? currencies : [currencyCode] + currencies
    }

    init(rule: RecurringRule? = nil) {
        self.rule = rule
    }

    private var ownAccounts: [Account] {
        accounts.filter { $0.type != .debt && !$0.isArchived }
    }

    private var availableCategories: [Category] {
        categories.filter { category in
            switch type {
            case .income:
                return category.kind == .income || category.kind == .both
            case .expense:
                return category.kind == .expense || category.kind == .both
            case .transfer:
                return false
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資料") {
                    TextField("名稱", text: $title)
                    Picker("類型", selection: $type) {
                        Text("支出").tag(TransactionType.expense)
                        Text("收入").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                    TextField("金額", text: $amountString)
                        .keyboardType(.decimalPad)
                    Picker("幣種", selection: $currencyCode) {
                        ForEach(availableCurrencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    DatePicker("下次日期", selection: $nextDueDate, displayedComponents: [.date, .hourAndMinute])
                }

                Section("重複規則") {
                    Picker("頻率", selection: $frequency) {
                        ForEach(RecurringFrequency.allCases) { frequency in
                            Text(frequency.displayName).tag(frequency)
                        }
                    }
                    Stepper("間隔：每 \(intervalCount) 次", value: $intervalCount, in: 1...24)
                    Toggle("暫停此規則", isOn: $isPaused)
                }

                Section("分類與帳戶") {
                    Picker("帳戶", selection: $selectedAccount) {
                        Text("請選擇").tag(nil as Account?)
                        ForEach(ownAccounts) { account in
                            Text(account.name).tag(account as Account?)
                        }
                    }

                    Picker("分類", selection: $selectedCategory) {
                        Text("未分類").tag(nil as Category?)
                        ForEach(availableCategories) { category in
                            Text("\(category.icon) \(category.name)").tag(category as Category?)
                        }
                    }
                }

                Section("備註") {
                    TextField("備註（可選）", text: $note, axis: .vertical)
                }
            }
            .interactiveKeyboardDismiss()
            .navigationTitle(rule == nil ? "新增定期記帳" : "編輯定期記帳")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                }
            }
            .keyboardDoneToolbar()
            .alert("無法儲存", isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(validationMessage ?? "")
            }
            .onAppear(perform: loadExistingRule)
            .onChange(of: selectedAccount) { _, newValue in
                if let newValue {
                    currencyCode = newValue.currency
                }
            }
            .onChange(of: type) { _, _ in
                if let selectedCategory, !availableCategories.contains(where: { $0.id == selectedCategory.id }) {
                    self.selectedCategory = nil
                }
            }
        }
    }

    private func loadExistingRule() {
        guard let rule, title.isEmpty else {
            selectedAccount = selectedAccount ?? ownAccounts.first
            if let selectedAccount {
                currencyCode = selectedAccount.currency
            }
            return
        }

        title = rule.title
        type = rule.type == .income ? .income : .expense
        amountString = NSDecimalNumber(decimal: abs(rule.amount)).stringValue
        currencyCode = rule.currencyCode
        frequency = rule.frequency
        intervalCount = max(1, rule.intervalCount)
        nextDueDate = rule.nextDueDate
        note = rule.note
        isPaused = rule.isPaused
        selectedAccount = rule.account
        selectedCategory = rule.category
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            validationMessage = "請輸入名稱。"
            return
        }
        guard let amount = Decimal(string: amountString), amount > 0 else {
            validationMessage = "請輸入大於 0 的金額。"
            return
        }
        guard let selectedAccount else {
            validationMessage = "請選擇帳戶。"
            return
        }

        if let rule {
            rule.title = trimmedTitle
            rule.amount = amount
            rule.currencyCode = currencyCode
            rule.type = type
            rule.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            rule.frequency = frequency
            rule.intervalCount = max(1, intervalCount)
            rule.nextDueDate = nextDueDate
            rule.isPaused = isPaused
            rule.account = selectedAccount
            rule.category = selectedCategory
            rule.updatedAt = Date()
        } else {
            modelContext.insert(
                RecurringRule(
                    title: trimmedTitle,
                    amount: amount,
                    currencyCode: currencyCode,
                    type: type,
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                    frequency: frequency,
                    intervalCount: max(1, intervalCount),
                    nextDueDate: nextDueDate,
                    isPaused: isPaused,
                    account: selectedAccount,
                    category: selectedCategory
                )
            )
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}
