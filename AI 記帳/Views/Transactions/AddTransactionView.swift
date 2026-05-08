import SwiftUI
import SwiftData

struct AddTransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var currencyService = CurrencyService.shared

    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \Tag.name) private var tags: [Tag]

    private let initialType: TransactionType
    private let locksTransactionType: Bool

    private enum EntryMode: String, CaseIterable, Identifiable {
        case normal
        case split
        case merge

        var id: String { rawValue }

        var title: String {
            switch self {
            case .normal: return "一般"
            case .split: return "分拆 (1 -> 多)"
            case .merge: return "合併 (多 -> 1)"
            }
        }
    }

    private struct SplitLeg: Identifiable {
        let id = UUID()
        var account: Account?
        var currency: String = "HKD"
        var amountString: String = ""
    }

    private struct MergeLeg: Identifiable {
        let id = UUID()
        var currency: String = "HKD"
        var amountString: String = ""
    }

    @State private var entryMode: EntryMode = .normal

    @State private var amountString = ""
    @State private var selectedType: TransactionType
    @State private var date = Date()
    @State private var note = ""
    @State private var selectedAccount: Account?
    @State private var selectedCategory: Category?
    @State private var selectedTags: Set<Tag> = []

    @State private var selectedCurrency: String = "HKD"
    private let currencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]

    @State private var splitLegs: [SplitLeg] = [SplitLeg()]
    @State private var mergeLegs: [MergeLeg] = [MergeLeg()]

    @State private var showingAddCategory = false
    @State private var showingAddTag = false
    @State private var newTagName = ""
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""

    @FocusState private var isAmountFocused: Bool

    private var activeAccounts: [Account] {
        TransactionSemantics.allowedAccounts(for: selectedType, from: accounts)
    }

    init(initialType: TransactionType = .expense, locksTransactionType: Bool = false) {
        self.initialType = initialType
        self.locksTransactionType = locksTransactionType
        _selectedType = State(initialValue: initialType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("模式") {
                    Picker("記帳模式", selection: $entryMode) {
                        ForEach(EntryMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("金額與類型") {
                    if locksTransactionType {
                        LabeledContent("類型") {
                            Text(selectedType == .expense ? "支出" : "收入")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Picker("類型", selection: $selectedType) {
                            Text("支出").tag(TransactionType.expense)
                            Text("收入").tag(TransactionType.income)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedType) { _, _ in
                            if let current = selectedCategory, !current.kind.supports(selectedType) {
                                selectedCategory = nil
                            }
                            selectedAccount = reconcileSelectedAccount(selectedAccount)
                            splitLegs = splitLegs.map { leg in
                                var updated = leg
                                updated.account = reconcileSplitAccount(leg.account)
                                if let account = updated.account {
                                    updated.currency = account.currency
                                }
                                return updated
                            }
                        }
                    }

                    switch entryMode {
                    case .normal:
                        normalAmountRow
                    case .split:
                        splitAmountRows
                    case .merge:
                        mergeAmountRows
                    }
                }

                Section {
                    if entryMode != .split {
                        accountPicker
                    }

                    HStack {
                        Picker("分類", selection: $selectedCategory) {
                            Text("無分類").tag(nil as Category?)
                            ForEach(filteredCategories) { cat in
                                HStack {
                                    Image(systemName: cat.icon)
                                    Text(cat.name)
                                }
                                .tag(cat as Category?)
                            }
                        }

                        Button(action: { showingAddCategory = true }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }

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
                                        if isSelected {
                                            selectedTags.remove(tag)
                                        } else {
                                            selectedTags.insert(tag)
                                        }
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { saveTransactions() }
                        .disabled(!canSubmit)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        isAmountFocused = false
                    }
                }
            }
            .sheet(isPresented: $showingAddCategory) {
                AddCategoryView { newCategory in
                    if newCategory.kind.supports(selectedType) {
                        selectedCategory = newCategory
                    }
                    showingAddCategory = false
                }
            }
            .alert("新增標籤", isPresented: $showingAddTag) {
                TextField("標籤名稱", text: $newTagName)
                Button("取消", role: .cancel) { newTagName = "" }
                Button("新增") { createTag() }
            }
            .alert("輸入錯誤", isPresented: $showingValidationAlert) {
                Button("確定", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
            .onAppear {
                selectedType = initialType
                if selectedAccount == nil || !activeAccounts.contains(where: { $0.id == selectedAccount?.id }) {
                    selectedAccount = activeAccounts.first
                }
                if let selectedAccount {
                    selectedCurrency = selectedAccount.currency
                }
                if splitLegs.first?.account == nil, let firstAccount = activeAccounts.first {
                    splitLegs[0].account = firstAccount
                    splitLegs[0].currency = firstAccount.currency
                }
                Task { await currencyService.fetchRates() }
            }
        }
    }

    @ViewBuilder
    private var accountPicker: some View {
        Picker("帳戶", selection: $selectedAccount) {
            Text("選擇帳戶").tag(nil as Account?)
            ForEach(activeAccounts) { acc in
                Text(acc.name).tag(acc as Account?)
            }
        }
        .onChange(of: selectedAccount) { _, _ in
            if let acc = selectedAccount {
                selectedCurrency = acc.currency
            }
        }
    }

    @ViewBuilder
    private var normalAmountRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("", selection: $selectedCurrency) {
                    ForEach(currencies, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                .labelsHidden()
                .frame(width: 80)

                TextField("0", text: Binding(
                    get: { amountString },
                    set: { amountString = sanitizePositiveDecimalInput($0) }
                ))
                .font(.largeTitle)
                .keyboardType(.decimalPad)
                .focused($isAmountFocused)
            }
            CurrencyRateHintView(
                currencyService: currencyService,
                amount: positiveDecimal(from: amountString),
                currencyCode: selectedCurrency
            )
        }
    }

    @ViewBuilder
    private var splitAmountRows: some View {
        ForEach($splitLegs) { $leg in
            VStack(spacing: 10) {
                Picker("帳戶", selection: $leg.account) {
                    Text("選擇帳戶").tag(nil as Account?)
                    ForEach(activeAccounts) { acc in
                        Text(acc.name).tag(acc as Account?)
                    }
                }
                .onChange(of: leg.account) { _, _ in
                    if let account = leg.account {
                        leg.currency = account.currency
                    }
                }

                HStack {
                    Picker("", selection: $leg.currency) {
                        ForEach(currencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)

                    TextField("金額", text: Binding(
                        get: { leg.amountString },
                        set: { leg.amountString = sanitizePositiveDecimalInput($0) }
                    ))
                    .keyboardType(.decimalPad)
                    .focused($isAmountFocused)
                }
                CurrencyRateHintView(
                    currencyService: currencyService,
                    amount: positiveDecimal(from: leg.amountString),
                    currencyCode: leg.currency
                )

                if splitLegs.count > 1 {
                    Button(role: .destructive) {
                        splitLegs.removeAll { $0.id == leg.id }
                    } label: {
                        Text("移除此帳戶")
                    }
                }
            }
            .padding(.vertical, 4)
        }

        Button {
            splitLegs.append(SplitLeg(currency: selectedCurrency))
        } label: {
            Label("新增帳戶分拆", systemImage: "plus.circle")
        }
    }

    @ViewBuilder
    private var mergeAmountRows: some View {
        ForEach($mergeLegs) { $leg in
            HStack {
                Picker("", selection: $leg.currency) {
                    ForEach(currencies, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                .labelsHidden()
                .frame(width: 80)

                TextField("金額", text: Binding(
                    get: { leg.amountString },
                    set: { leg.amountString = sanitizePositiveDecimalInput($0) }
                ))
                .keyboardType(.decimalPad)
                .focused($isAmountFocused)
            }
            CurrencyRateHintView(
                currencyService: currencyService,
                amount: positiveDecimal(from: leg.amountString),
                currencyCode: leg.currency
            )

            if mergeLegs.count > 1 {
                Button(role: .destructive) {
                    mergeLegs.removeAll { $0.id == leg.id }
                } label: {
                    Text("移除此金額項")
                }
            }
        }

        Button {
            mergeLegs.append(MergeLeg(currency: selectedCurrency))
        } label: {
            Label("新增合併金額項", systemImage: "plus.circle")
        }
    }

    private var canSubmit: Bool {
        switch entryMode {
        case .normal:
            return selectedAccount != nil && positiveDecimal(from: amountString) != nil
        case .split:
            return splitLegs.contains { $0.account != nil && positiveDecimal(from: $0.amountString) != nil }
                && splitLegs.allSatisfy { $0.account != nil && positiveDecimal(from: $0.amountString) != nil }
        case .merge:
            return selectedAccount != nil
                && mergeLegs.contains { positiveDecimal(from: $0.amountString) != nil }
                && mergeLegs.allSatisfy { positiveDecimal(from: $0.amountString) != nil }
        }
    }

    private func saveTransactions() {
        var insertedTransactions: [FinancialTransaction] = []

        switch entryMode {
        case .normal:
            guard let account = selectedAccount,
                  let amount = positiveDecimal(from: amountString)
            else {
                showValidation("請先填寫完整的帳戶與金額。")
                return
            }

            insertedTransactions.append(insertTransaction(
                amount: amount,
                currencyCode: selectedCurrency,
                account: account,
                note: note
            ))

        case .split:
            var legs: [(account: Account, amount: Decimal, currency: String)] = []
            for leg in splitLegs {
                guard let account = leg.account,
                      let amount = positiveDecimal(from: leg.amountString)
                else {
                    showValidation("分拆模式下，請為每一項選擇帳戶並填入金額。")
                    return
                }
                legs.append((account, amount, leg.currency))
            }

            for (index, leg) in legs.enumerated() {
                insertedTransactions.append(insertTransaction(
                    amount: leg.amount,
                    currencyCode: leg.currency,
                    account: leg.account,
                    note: indexedNote(base: note, mode: .split, index: index, count: legs.count)
                ))
            }

        case .merge:
            guard let account = selectedAccount else {
                showValidation("合併模式下，請先選擇目標帳戶。")
                return
            }

            var items: [(amount: Decimal, currency: String)] = []
            for leg in mergeLegs {
                guard let amount = positiveDecimal(from: leg.amountString) else {
                    showValidation("合併模式下，請為每一項填入金額。")
                    return
                }
                items.append((amount, leg.currency))
            }

            for (index, item) in items.enumerated() {
                insertedTransactions.append(insertTransaction(
                    amount: item.amount,
                    currencyCode: item.currency,
                    account: account,
                    note: indexedNote(base: note, mode: .merge, index: index, count: items.count)
                ))
            }
        }

        do {
            try modelContext.save()
            try BudgetHistoryService.shared.syncAffected(
                by: insertedTransactions,
                modelContext: modelContext,
                currencyService: currencyService
            )
        } catch {
            showValidation("儲存失敗：\(error.localizedDescription)")
            return
        }

        dismiss()
    }

    private func insertTransaction(amount: Decimal, currencyCode: String, account: Account, note: String) -> FinancialTransaction {
        let finalAmount = (selectedType == .expense) ? -abs(amount) : abs(amount)

        let tx = FinancialTransaction(
            amount: finalAmount,
            currencyCode: currencyCode,
            date: date,
            note: note,
            type: selectedType,
            account: account,
            category: selectedCategory,
            tags: Array(selectedTags)
        )

        modelContext.insert(tx)
        return tx
    }

    private func indexedNote(base: String, mode: EntryMode, index: Int, count: Int) -> String {
        let suffix: String
        switch mode {
        case .split:
            suffix = "[分拆 \(index + 1)/\(count)]"
        case .merge:
            suffix = "[合併 \(index + 1)/\(count)]"
        case .normal:
            suffix = ""
        }

        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return suffix
        }
        return "\(trimmed) \(suffix)"
    }

    private func createTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let tag = Tag(name: trimmed)
        modelContext.insert(tag)
        selectedTags.insert(tag)
        newTagName = ""
    }

    private func positiveDecimal(from value: String) -> Decimal? {
        guard let parsed = Decimal(string: value), parsed > 0 else { return nil }
        return parsed
    }

    private func sanitizePositiveDecimalInput(_ value: String) -> String {
        let allowed = value.filter { "0123456789.".contains($0) }
        var result = ""
        var hasDot = false

        for char in allowed {
            if char == "." {
                if hasDot { continue }
                hasDot = true
            }
            result.append(char)
        }

        return result == "." ? "" : result
    }

    private func showValidation(_ message: String) {
        validationMessage = message
        showingValidationAlert = true
    }

    private var filteredCategories: [Category] {
        categories.filter { $0.kind.supports(selectedType) }
    }

    private func reconcileSelectedAccount(_ account: Account?) -> Account? {
        guard let account else { return activeAccounts.first }
        return activeAccounts.first(where: { $0.id == account.id }) ?? activeAccounts.first
    }

    private func reconcileSplitAccount(_ account: Account?) -> Account? {
        guard let account else { return activeAccounts.first }
        return activeAccounts.first(where: { $0.id == account.id }) ?? activeAccounts.first
    }
}
