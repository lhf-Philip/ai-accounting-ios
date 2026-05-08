import SwiftUI
import SwiftData

struct EditAdvanceTransferView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let originalTransaction: FinancialTransaction

    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query private var participants: [AdvanceParticipant]
    @Query private var repayments: [AdvanceRepayment]

    @State private var outgoingTransaction: FinancialTransaction?
    @State private var incomingTransaction: FinancialTransaction?
    @State private var transferGroupID: UUID?

    @State private var fromAccount: Account?
    @State private var toAccount: Account?
    @State private var currencyOut: String = "HKD"
    @State private var currencyIn: String = "HKD"
    @State private var amountOutString: String = ""
    @State private var amountInString: String = ""
    @State private var date: Date = Date()
    @State private var note: String = ""

    @State private var selectedCategory: Category?
    @State private var selectedTags: Set<Tag> = []

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""
    @State private var showingAddTag = false
    @State private var newTagName = ""

    @FocusState private var focusedField: Field?

    private enum Field {
        case amountOut
        case amountIn
        case note
    }

    private enum AdvanceLinkKind {
        case initial(AdvanceParticipant)
        case repayment(AdvanceRepayment)
        case unknown
    }

    @State private var linkKind: AdvanceLinkKind = .unknown

    private let currencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]

    private var activeAccounts: [Account] {
        allAccounts.filter { !$0.isArchived }
    }

    private var incomeCategories: [Category] {
        categories.filter { $0.kind.supports(.income) }
    }

    private var canSubmit: Bool {
        !isLoading
            && fromAccount != nil
            && toAccount != nil
            && positiveDecimal(from: amountOutString) != nil
            && positiveDecimal(from: amountInString) != nil
    }

    private var titleText: String {
        switch linkKind {
        case .repayment:
            return "編輯代墊還款"
        case .initial, .unknown:
            return "編輯代墊"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    ProgressView("載入代墊交易中...")
                } else if let errorMessage {
                    Text("無法編輯：\(errorMessage)")
                        .foregroundStyle(.red)
                } else {
                    Section("轉出方") {
                        Picker("從帳戶", selection: $fromAccount) {
                            Text("選擇帳戶").tag(nil as Account?)
                            ForEach(activeAccounts) { account in
                                Text(account.name).tag(account as Account?)
                            }
                        }
                        .onChange(of: fromAccount) { _, newValue in
                            guard let newValue else { return }
                            currencyOut = newValue.currency
                        }

                        HStack {
                            Picker("幣種", selection: $currencyOut) {
                                ForEach(currencies, id: \.self) { code in
                                    Text(code).tag(code)
                                }
                            }
                            .frame(width: 110)

                            TextField("轉出金額", text: Binding(
                                get: { amountOutString },
                                set: { amountOutString = sanitizePositiveDecimalInput($0) }
                            ))
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .amountOut)
                        }
                    }

                    Section("轉入方") {
                        Picker("到帳戶", selection: $toAccount) {
                            Text("選擇帳戶").tag(nil as Account?)
                            ForEach(activeAccounts) { account in
                                Text(account.name).tag(account as Account?)
                            }
                        }
                        .onChange(of: toAccount) { _, newValue in
                            guard let newValue else { return }
                            currencyIn = newValue.currency
                        }

                        HStack {
                            Picker("幣種", selection: $currencyIn) {
                                ForEach(currencies, id: \.self) { code in
                                    Text(code).tag(code)
                                }
                            }
                            .frame(width: 110)

                            TextField("轉入金額", text: Binding(
                                get: { amountInString },
                                set: { amountInString = sanitizePositiveDecimalInput($0) }
                            ))
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .amountIn)
                        }
                    }

                    Section("自己的入帳標記") {
                        Picker("分類", selection: $selectedCategory) {
                            Text("不設定").tag(nil as Category?)
                            ForEach(incomeCategories) { category in
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

                    Section("其他") {
                        DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .accessibilityIdentifier("advanceTransferEditor.datePicker")
                        TextField("備註", text: $note)
                            .focused($focusedField, equals: .note)
                            .accessibilityIdentifier("advanceTransferEditor.noteField")
                    }
                }
            }
            .navigationTitle(titleText)
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
            .onAppear { loadData() }
        }
    }

    private func loadData() {
        do {
            guard let (outTx, inTx, groupID) = try resolveTransferPair(for: originalTransaction) else {
                errorMessage = "找不到可編輯的代墊交易配對。"
                isLoading = false
                return
            }

            outgoingTransaction = outTx
            incomingTransaction = inTx
            transferGroupID = groupID

            fromAccount = outTx.account
            toAccount = inTx.account
            currencyOut = outTx.currencyCode.isEmpty ? (outTx.account?.currency ?? "HKD") : outTx.currencyCode
            currencyIn = inTx.currencyCode.isEmpty ? (inTx.account?.currency ?? "HKD") : inTx.currencyCode
            amountOutString = decimalString(from: abs(outTx.amount))
            amountInString = decimalString(from: abs(inTx.amount))
            date = outTx.date
            note = extractMemo(from: outTx.note)

            selectedCategory = inTx.category
            selectedTags = Set(inTx.tags)

            if let groupID {
                if let participant = participants.first(where: { $0.initialTransferGroupID == groupID }) {
                    linkKind = .initial(participant)
                } else if let repayment = repayments.first(where: { $0.linkedTransferGroupID == groupID }) {
                    linkKind = .repayment(repayment)
                } else {
                    linkKind = .unknown
                }
            }

            isLoading = false
        } catch {
            errorMessage = "讀取錯誤：\(error.localizedDescription)"
            isLoading = false
        }
    }

    private func saveChanges() {
        guard let outTx = outgoingTransaction,
              let inTx = incomingTransaction,
              let from = fromAccount,
              let to = toAccount
        else {
            showValidation("找不到可更新的交易資料。")
            return
        }

        guard from.id != to.id else {
            showValidation("轉出與轉入帳戶不可相同。")
            return
        }

        guard let amountOut = positiveDecimal(from: amountOutString),
              let amountIn = positiveDecimal(from: amountInString)
        else {
            showValidation("請輸入大於 0 的金額。")
            return
        }

        let groupID = transferGroupID ?? outTx.transferGroupID ?? inTx.transferGroupID ?? UUID()
        let baseNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()

        outTx.type = .transfer
        outTx.amount = -abs(amountOut)
        outTx.currencyCode = currencyOut
        outTx.date = date
        outTx.account = from
        outTx.transferSide = .outgoing
        outTx.transferGroupID = groupID
        outTx.updatedAt = now

        inTx.type = .transfer
        inTx.amount = abs(amountIn)
        inTx.currencyCode = currencyIn
        inTx.date = date
        inTx.account = to
        inTx.transferSide = .incoming
        inTx.transferGroupID = groupID
        inTx.category = selectedCategory
        inTx.tags = Array(selectedTags)
        inTx.updatedAt = now

        outTx.linkedTransactionID = inTx.id
        inTx.linkedTransactionID = outTx.id

        switch linkKind {
        case .initial:
            outTx.note = baseNote.isEmpty ? "代墊 (代墊給 \(to.name))" : "\(baseNote) (代墊給 \(to.name))"
            inTx.note = baseNote.isEmpty ? "代墊 (來自 \(from.name))" : "\(baseNote) (來自 \(from.name))"
        case .repayment:
            outTx.note = baseNote.isEmpty ? "還款 (還款至 \(to.name))" : "\(baseNote) (還款至 \(to.name))"
            inTx.note = baseNote.isEmpty ? "還款 (來自 \(from.name))" : "\(baseNote) (來自 \(from.name))"
        case .unknown:
            outTx.note = baseNote.isEmpty ? "轉帳 (轉至 \(to.name))" : "\(baseNote) (轉至 \(to.name))"
            inTx.note = baseNote.isEmpty ? "轉帳 (來自 \(from.name))" : "\(baseNote) (來自 \(from.name))"
        }

        do {
            try AdvanceService.syncLinkedTransferGroup(groupID: groupID, modelContext: modelContext)
            try modelContext.save()
            dismiss()
        } catch {
            showValidation("儲存失敗：\(error.localizedDescription)")
        }
    }

    private func resolveTransferPair(for tx: FinancialTransaction) throws -> (FinancialTransaction, FinancialTransaction, UUID?)? {
        if let groupID = tx.transferGroupID {
            let descriptor = FetchDescriptor<FinancialTransaction>(
                predicate: #Predicate { $0.transferGroupID == groupID }
            )
            let groupItems = try modelContext.fetch(descriptor)
            if let outTx = groupItems.first(where: { isOutgoing($0) }),
               let inTx = groupItems.first(where: { !isOutgoing($0) }) {
                return (outTx, inTx, groupID)
            }
        }

        if let linkedID = tx.linkedTransactionID {
            let descriptor = FetchDescriptor<FinancialTransaction>(
                predicate: #Predicate { $0.id == linkedID }
            )
            if let linked = try modelContext.fetch(descriptor).first {
                let outTx = isOutgoing(tx) ? tx : linked
                let inTx = isOutgoing(tx) ? linked : tx
                let groupID = tx.transferGroupID ?? linked.transferGroupID
                return (outTx, inTx, groupID)
            }
        }

        return nil
    }

    private func isOutgoing(_ tx: FinancialTransaction) -> Bool {
        if let side = tx.transferSide {
            return side == .outgoing
        }
        return tx.amount < 0
    }

    private func createTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = tags.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            selectedTags.insert(existing)
            newTagName = ""
            return
        }

        let tag = Tag(name: trimmed)
        modelContext.insert(tag)
        selectedTags.insert(tag)
        newTagName = ""
    }

    private func extractMemo(from note: String) -> String {
        let separators = [
            " (代墊給", " (還款至", " (轉至", " (來自", " (借入至", " (還款給"
        ]

        for separator in separators {
            if let range = note.range(of: separator) {
                return String(note[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decimalString(from value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
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

    private func positiveDecimal(from value: String) -> Decimal? {
        guard let parsed = Decimal(string: value), parsed > 0 else { return nil }
        return parsed
    }

    private func showValidation(_ message: String) {
        validationMessage = message
        showingValidationAlert = true
    }
}
