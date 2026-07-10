import SwiftUI
import SwiftData

struct EditAdvanceTransferView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let originalTransaction: FinancialTransaction?
    private let directRepayment: AdvanceRepayment?

    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query private var advanceCases: [AdvanceCase]
    @Query private var participants: [AdvanceParticipant]
    @Query private var repayments: [AdvanceRepayment]

    @State private var linkKind: LinkKind = .unknown
    @State private var settlementDirection: AdvanceSemantics.SettlementDirection = .iAdvancedOthers
    @State private var selectedAccount: Account?
    @State private var amountString = ""
    @State private var currencyCode = "HKD"
    @State private var normalizedAmountString = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var selectedCategory: Category?
    @State private var selectedTags: Set<Tag> = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""
    @State private var showingAddTag = false
    @State private var newTagName = ""
    @State private var didLoadDraft = false

    @FocusState private var focusedField: Field?
    private let currencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]

    private var availableCurrencies: [String] {
        currencies.contains(currencyCode) ? currencies : [currencyCode] + currencies
    }

    init(originalTransaction: FinancialTransaction) {
        self.originalTransaction = originalTransaction
        self.directRepayment = nil
    }

    init(repayment: AdvanceRepayment) {
        self.originalTransaction = nil
        self.directRepayment = repayment
    }

    private enum Field {
        case amount
        case normalizedAmount
        case note
    }

    private enum LinkKind {
        case selfExpense(AdvanceCase, FinancialTransaction)
        case initial(AdvanceParticipant)
        case repayment(AdvanceRepayment)
        case unknown
    }

    private var activeOwnAccounts: [Account] {
        allAccounts.filter { !$0.isArchived && $0.type != .debt }
    }

    private var directionalCategories: [Category] {
        switch linkKind {
        case .selfExpense:
            return categories.filter { $0.kind.supports(.expense) }
        case .initial:
            return settlementDirection == .othersAdvancedMe
                ? categories.filter { $0.kind.supports(.expense) }
                : []
        case .repayment:
            return settlementDirection == .iAdvancedOthers
                ? categories.filter { $0.kind.supports(.income) }
                : categories.filter { $0.kind.supports(.expense) }
        case .unknown:
            return []
        }
    }

    private var requiresOwnAccount: Bool {
        switch linkKind {
        case .selfExpense, .repayment:
            return true
        case .initial:
            return settlementDirection == .iAdvancedOthers
        case .unknown:
            return false
        }
    }

    private var canSubmit: Bool {
        guard !isLoading, errorMessage == nil, positiveDecimal(from: amountString) != nil else {
            return false
        }
        if requiresOwnAccount && selectedAccount == nil {
            return false
        }
        switch linkKind {
        case .selfExpense, .repayment:
            return positiveDecimal(from: normalizedAmountString) != nil
        case .initial, .unknown:
            return true
        }
    }

    private var titleText: String {
        switch linkKind {
        case .selfExpense:
            return "編輯自己的份額"
        case .initial:
            return "編輯代墊"
        case .repayment:
            return "編輯代墊還款"
        case .unknown:
            return "編輯代墊紀錄"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    ProgressView("載入代墊紀錄中...")
                } else if let errorMessage {
                    Text("無法編輯：\(errorMessage)")
                        .foregroundStyle(.red)
                } else {
                    summarySection
                    amountSection
                    metadataSection
                    Section("其他") {
                        DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .accessibilityIdentifier("advanceTransferEditor.datePicker")
                        TextField("備註", text: $note)
                            .focused($focusedField, equals: .note)
                            .accessibilityIdentifier("advanceTransferEditor.noteField")
                    }
                }
            }
            .interactiveKeyboardDismiss()
            .navigationTitle(titleText)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { saveChanges() }
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("advanceTransferEditor.saveButton")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedField = nil }
                }
            }
            .alert("輸入錯誤", isPresented: $showingValidationAlert) {
                Button("確定", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
            .alert("新增標籤", isPresented: $showingAddTag) {
                TextField("標籤名稱", text: $newTagName)
                Button("取消", role: .cancel) { newTagName = "" }
                Button("新增") { createTag() }
            }
            .onAppear { loadData() }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        Section("案件") {
            switch linkKind {
            case .selfExpense(let advanceCase, _):
                summaryRow("案件", advanceCase.title)
                summaryRow("類型", "自己的份額")
                summaryRow("案件幣種", advanceCase.currencyCode)
            case .initial(let participant):
                summaryRow("對象", participant.name)
                summaryRow(
                    "方向",
                    settlementDirection == .iAdvancedOthers ? "我代墊他人" : "他人代墊我"
                )
                summaryRow("案件幣種", participant.advanceCase?.currencyCode ?? currencyCode)
            case .repayment(let repayment):
                summaryRow("對象", repayment.participant?.name ?? "未指定")
                summaryRow(
                    "方向",
                    settlementDirection == .iAdvancedOthers ? "對方還款給我" : "我還款給對方"
                )
                summaryRow("案件幣種", repayment.advanceCase?.currencyCode ?? currencyCode)
            case .unknown:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var amountSection: some View {
        Section(linkKindAmountTitle) {
            if requiresOwnAccount {
                Picker(accountLabel, selection: $selectedAccount) {
                    Text("選擇帳戶").tag(nil as Account?)
                    ForEach(activeOwnAccounts) { account in
                        Text(account.name).tag(account as Account?)
                    }
                }
            } else {
                Text("自己的帳戶沒有變動。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                switch linkKind {
                case .selfExpense, .repayment:
                    Picker("幣種", selection: $currencyCode) {
                        ForEach(availableCurrencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .frame(width: 105)
                case .initial, .unknown:
                    Text(currencyCode)
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .leading)
                }

                TextField("金額", text: Binding(
                    get: { amountString },
                    set: { amountString = sanitizePositiveDecimalInput($0) }
                ))
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .amount)
            }

            switch linkKind {
            case .selfExpense(let advanceCase, _):
                normalizedAmountField(
                    title: "案件中的自己份額",
                    currencyCode: advanceCase.currencyCode,
                    helpText: "實際扣款可用其他幣種；這個金額用於代墊案件摘要。"
                )
            case .repayment(let repayment):
                normalizedAmountField(
                    title: "沖銷案件金額",
                    currencyCode: repayment.advanceCase?.currencyCode ?? "",
                    helpText: "此值會直接保存，不會在儲存時用目前匯率重新計算。"
                )
            case .initial, .unknown:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func normalizedAmountField(
        title: String,
        currencyCode: String,
        helpText: String
    ) -> some View {
        HStack {
            TextField(title, text: Binding(
                get: { normalizedAmountString },
                set: { normalizedAmountString = sanitizePositiveDecimalInput($0) }
            ))
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: .normalizedAmount)

            Text(currencyCode)
                .foregroundStyle(.secondary)
        }
        Text(helpText)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var metadataSection: some View {
        if !directionalCategories.isEmpty {
            Section(categorySectionTitle) {
                Picker("分類", selection: $selectedCategory) {
                    Text("不設定").tag(nil as Category?)
                    ForEach(directionalCategories) { category in
                        Text(category.name).tag(category as Category?)
                    }
                }

                HStack {
                    Text("標籤")
                    Spacer()
                    Button {
                        showingAddTag = true
                    } label: {
                        Label("新增", systemImage: "plus")
                            .font(.caption)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(tags) { tag in
                            let isSelected = selectedTags.contains(tag)
                            Button {
                                if isSelected {
                                    selectedTags.remove(tag)
                                } else {
                                    selectedTags.insert(tag)
                                }
                            } label: {
                                Text(tag.name)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                                    .foregroundStyle(isSelected ? .white : .primary)
                                    .cornerRadius(16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var linkKindAmountTitle: String {
        switch linkKind {
        case .selfExpense:
            return "實際扣款"
        case .initial:
            return "代墊金額"
        case .repayment:
            return settlementDirection == .iAdvancedOthers ? "實際收到" : "實際支付"
        case .unknown:
            return "金額"
        }
    }

    private var accountLabel: String {
        switch linkKind {
        case .selfExpense:
            return "支出帳戶"
        case .initial:
            return "付款帳戶"
        case .repayment:
            return settlementDirection == .iAdvancedOthers ? "入帳帳戶" : "付款帳戶"
        case .unknown:
            return "帳戶"
        }
    }

    private var categorySectionTitle: String {
        switch linkKind {
        case .selfExpense:
            return "支出分類與標籤"
        case .initial:
            return "支出分類與標籤"
        case .repayment:
            return settlementDirection == .iAdvancedOthers
                ? "自己的入帳標記"
                : "還款標記（不重複計入支出）"
        case .unknown:
            return "分類與標籤"
        }
    }

    private func loadData() {
        guard !didLoadDraft else { return }
        didLoadDraft = true

        if let directRepayment, let groupID = directRepayment.linkedTransferGroupID {
            do {
                try loadRepayment(directRepayment, groupID: groupID)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
            return
        }

        if let transaction = originalTransaction,
           let advanceCase = advanceCases.first(where: { $0.selfExpenseTransactionID == transaction.id }) {
            loadSelfExpense(advanceCase, transaction: transaction)
            isLoading = false
            return
        }

        guard let groupID = originalTransaction?.transferGroupID else {
            errorMessage = "找不到代墊關聯識別資料。"
            isLoading = false
            return
        }

        do {
            if let repayment = repayments.first(where: { $0.linkedTransferGroupID == groupID }) {
                try loadRepayment(repayment, groupID: groupID)
            } else if let participant = participants.first(where: { $0.initialTransferGroupID == groupID }) {
                try loadInitialParticipant(participant, groupID: groupID)
            } else {
                errorMessage = "找不到對應的代墊案件或還款紀錄。"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadRepayment(_ repayment: AdvanceRepayment, groupID: UUID) throws {
        guard let participant = repayment.participant else {
            throw AdvanceServiceError.missingRepaymentParticipant
        }
        let group = try fetchGroup(groupID)
        guard group.count == 2 else {
            throw AdvanceServiceError.invalidRepaymentStructure
        }
        settlementDirection = AdvanceService.inferSettlementDirection(
            for: participant,
            modelContext: modelContext
        )
        let ownLeg = group.first {
            settlementDirection == .iAdvancedOthers
                ? ($0.transferSide == .incoming || $0.amount > 0)
                : ($0.transferSide == .outgoing || $0.amount < 0)
        }
        linkKind = .repayment(repayment)
        selectedAccount = repayment.receivedAccount ?? ownLeg?.account
        amountString = decimalString(repayment.amount)
        currencyCode = repayment.currencyCode
        normalizedAmountString = decimalString(repayment.normalizedAmount)
        date = repayment.date
        note = repayment.note
        selectedCategory = ownLeg?.category
        selectedTags = Set(ownLeg?.tags ?? [])
    }

    private func loadSelfExpense(
        _ advanceCase: AdvanceCase,
        transaction: FinancialTransaction
    ) {
        linkKind = .selfExpense(advanceCase, transaction)
        selectedAccount = transaction.account
        amountString = decimalString(abs(transaction.amount))
        currencyCode = transaction.currencyCode
        normalizedAmountString = decimalString(advanceCase.myShareAmount)
        date = transaction.date
        note = transaction.note
        selectedCategory = transaction.category
        selectedTags = Set(transaction.tags)
    }

    private func loadInitialParticipant(_ participant: AdvanceParticipant, groupID: UUID) throws {
        guard let advanceCase = participant.advanceCase else {
            throw AdvanceServiceError.participantNotInCase
        }
        let group = try fetchGroup(groupID)
        settlementDirection = AdvanceService.inferSettlementDirection(
            for: participant,
            modelContext: modelContext
        )
        linkKind = .initial(participant)
        amountString = decimalString(participant.owedAmount)
        currencyCode = advanceCase.currencyCode
        date = group.first?.date ?? advanceCase.date
        note = extractMemo(group.first?.note ?? advanceCase.note)

        switch settlementDirection {
        case .iAdvancedOthers:
            guard group.count == 2,
                  let outgoing = group.first(where: { $0.transferSide == .outgoing || $0.amount < 0 })
            else {
                throw AdvanceServiceError.invalidRepaymentStructure
            }
            selectedAccount = outgoing.account
        case .othersAdvancedMe:
            guard group.count == 1, let expense = group.first else {
                throw AdvanceServiceError.invalidRepaymentStructure
            }
            selectedAccount = nil
            selectedCategory = expense.category
            selectedTags = Set(expense.tags)
        }
    }

    private func saveChanges() {
        guard let amount = positiveDecimal(from: amountString) else {
            showValidation("請輸入大於 0 的金額。")
            return
        }

        do {
            switch linkKind {
            case .selfExpense(let advanceCase, let transaction):
                guard let account = selectedAccount,
                      let normalizedAmount = positiveDecimal(from: normalizedAmountString)
                else {
                    showValidation("請填寫完整的自己份額資料。")
                    return
                }
                try AdvanceService.updateSelfExpense(
                    advanceCase: advanceCase,
                    transaction: transaction,
                    draft: .init(
                        account: account,
                        amount: amount,
                        currencyCode: currencyCode,
                        normalizedAmount: normalizedAmount,
                        date: date,
                        note: note,
                        category: selectedCategory,
                        tags: Array(selectedTags)
                    ),
                    modelContext: modelContext
                )
            case .repayment(let repayment):
                guard let advanceCase = repayment.advanceCase,
                      let receiveAccount = selectedAccount,
                      let normalizedAmount = positiveDecimal(from: normalizedAmountString)
                else {
                    showValidation("請填寫完整的還款資料。")
                    return
                }
                try AdvanceService.updateRepayment(
                    advanceCase: advanceCase,
                    repayment: repayment,
                    draft: .init(
                        receiveAccount: receiveAccount,
                        amount: amount,
                        currencyCode: currencyCode,
                        normalizedAmount: normalizedAmount,
                        date: date,
                        note: note,
                        category: selectedCategory,
                        tags: Array(selectedTags)
                    ),
                    modelContext: modelContext
                )
            case .initial(let participant):
                guard let advanceCase = participant.advanceCase else {
                    throw AdvanceServiceError.participantNotInCase
                }
                try AdvanceService.updateInitialEntry(
                    advanceCase: advanceCase,
                    participant: participant,
                    draft: .init(
                        payerAccount: selectedAccount,
                        owedAmount: amount,
                        paymentAmount: amount,
                        paymentCurrencyCode: currencyCode,
                        date: date,
                        note: note,
                        category: selectedCategory,
                        tags: Array(selectedTags)
                    ),
                    modelContext: modelContext
                )
            case .unknown:
                throw AdvanceServiceError.invalidRepaymentStructure
            }
            dismiss()
        } catch {
            modelContext.rollback()
            showValidation("儲存失敗：\(error.localizedDescription)")
        }
    }

    private func fetchGroup(_ groupID: UUID) throws -> [FinancialTransaction] {
        let descriptor = FetchDescriptor<FinancialTransaction>(
            predicate: #Predicate { $0.transferGroupID == groupID }
        )
        return try modelContext.fetch(descriptor)
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func createTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let existing = tags.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            selectedTags.insert(existing)
        } else {
            let tag = Tag(name: trimmed)
            modelContext.insert(tag)
            selectedTags.insert(tag)
        }
        newTagName = ""
    }

    private func extractMemo(_ value: String) -> String {
        let separators = [" (代墊給", " (他人代墊我", " (還款至", " (還款給", " (來自"]
        let indexes = separators.compactMap { value.range(of: $0)?.lowerBound }
        guard let first = indexes.min() else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(value[..<first]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: abs(value)).stringValue
    }

    private func sanitizePositiveDecimalInput(_ value: String) -> String {
        let allowed = value.filter { "0123456789.".contains($0) }
        var result = ""
        var hasDot = false
        for character in allowed {
            if character == "." {
                if hasDot { continue }
                hasDot = true
            }
            result.append(character)
        }
        return result == "." ? "" : result
    }

    private func positiveDecimal(from value: String) -> Decimal? {
        guard let parsed = Decimal(string: value), parsed > 0 else { return nil }
        return parsed
    }

    private func showValidation(_ message: String) {
        validationMessage = message
        showingValidationAlert = true
    }
}
