import SwiftUI
import SwiftData

struct AddDebtView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var currencyService = CurrencyService.shared

    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]
    private let existingForgivenessTransactionID: UUID?
    private let existingDebtTransactionID: UUID?
    private let presetDebtAccountID: UUID?
    private let presetMode: DebtMode?
    private let presetForgivenessDirection: DebtForgivenessDirection?
    private let presetNote: String?

    private var debtAccounts: [Account] {
        allAccounts.filter { $0.type == .debt && !$0.isArchived }.sorted { $0.name < $1.name }
    }

    private var myAccounts: [Account] {
        allAccounts.filter { $0.type != .debt && !$0.isArchived }
    }

    enum DebtMode: String, CaseIterable {
        case borrow = "借入 / 收款"
        case repay = "借出 / 還款"
        case forgive = "免除債務"
    }

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

    @State private var mode: DebtMode = .borrow
    @State private var forgivenessDirection: DebtForgivenessDirection = .forgivenByOthers
    @State private var entryMode: EntryMode = .normal

    @State private var selectedDebtAccount: Account?
    @State private var selectedMyAccount: Account?
    @State private var amountString: String = ""
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""

    @State private var selectedCurrency: String = "HKD"
    private let currencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]

    @State private var splitLegs: [SplitLeg] = [SplitLeg()]
    @State private var mergeLegs: [MergeLeg] = [MergeLeg()]
    @State private var existingDebtGroupID: UUID?

    @FocusState private var isAmountFocused: Bool

    init(
        existingForgivenessTransaction: FinancialTransaction? = nil,
        existingDebtTransaction: FinancialTransaction? = nil,
        presetDebtAccount: Account? = nil,
        presetMode: DebtMode? = nil,
        presetForgivenessDirection: DebtForgivenessDirection? = nil,
        presetNote: String? = nil
    ) {
        self.existingForgivenessTransactionID = existingForgivenessTransaction?.id
        self.existingDebtTransactionID = existingDebtTransaction?.id
        self.presetDebtAccountID = presetDebtAccount?.id
        self.presetMode = presetMode
        self.presetForgivenessDirection = presetForgivenessDirection
        self.presetNote = presetNote
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("操作", selection: $mode) {
                        ForEach(DebtMode.allCases, id: \.self) { option in
                            Text(debtModeTitle(option)).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(existingDebtGroupID != nil)

                    if mode == .forgive {
                        Picker("免除方向", selection: $forgivenessDirection) {
                            ForEach(DebtForgivenessDirection.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(existingDebtGroupID != nil)
                    } else {
                        Picker("模式", selection: $entryMode) {
                            ForEach(EntryMode.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(existingDebtGroupID != nil)
                        if existingDebtGroupID != nil {
                            Text("編輯既有債務時會保留借入／還款方向與原本的轉帳關聯。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    if debtAccounts.isEmpty {
                        Text("請先至「帳戶」頁面新增類型為「借貸」的對象")
                            .foregroundStyle(.red)
                            .font(.caption)
                    } else {
                        Picker(debtAccountLabel, selection: $selectedDebtAccount) {
                            Text("請選擇對象").tag(nil as Account?)
                            ForEach(debtAccounts) { acc in
                                Text(acc.name).tag(acc as Account?)
                            }
                        }
                        .onChange(of: selectedDebtAccount) { _, newValue in
                            if mode == .forgive, let newValue {
                                selectedCurrency = newValue.currency
                            }
                        }
                    }

                    if mode != .forgive && entryMode != .split {
                        Picker(mode == .borrow ? "入帳帳戶" : "付款帳戶", selection: $selectedMyAccount) {
                            Text("請選擇帳戶").tag(nil as Account?)
                            ForEach(myAccounts) { acc in
                                Text(acc.name).tag(acc as Account?)
                            }
                        }
                        .onChange(of: selectedMyAccount) { _, _ in
                            if existingDebtGroupID == nil, let acc = selectedMyAccount {
                                selectedCurrency = acc.currency
                            }
                        }
                    }
                }

                Section("金額與幣種") {
                    switch effectiveEntryMode {
                    case .normal:
                        normalAmountRow
                    case .split:
                        splitAmountRows
                    case .merge:
                        mergeAmountRows
                    }

                    DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    TextField("備註", text: $note)
                }

                Section {
                    previewBlock
                }
            }
            .interactiveKeyboardDismiss()
            .navigationTitle("借貸管理")
            .alert("輸入錯誤", isPresented: $showingValidationAlert) {
                Button("確定", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        existingForgivenessTransactionID == nil && existingDebtTransactionID == nil
                            ? "確認"
                            : "儲存"
                    ) {
                        saveTransaction()
                    }
                        .disabled(!canSubmit)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { isAmountFocused = false }
                }
            }
            .onAppear {
                if let existingForgivenessTransactionID,
                   let transaction = allAccounts
                    .flatMap(\.transactions)
                    .first(where: { $0.id == existingForgivenessTransactionID && TransactionSemantics.isDebtForgiveness(note: $0.note) }) {
                    mode = .forgive
                    forgivenessDirection = TransactionSemantics.debtForgivenessDirection(note: transaction.note)
                        ?? (transaction.amount >= 0 ? .forgivenByOthers : .forgiveOthers)
                    selectedDebtAccount = transaction.account
                    selectedCurrency = transaction.currencyCode
                    amountString = NSDecimalNumber(decimal: abs(transaction.amount)).stringValue
                    date = transaction.date
                    note = extractForgivenessNote(transaction.note)
                }
                loadExistingDebtTransaction()
                if selectedMyAccount == nil {
                    selectedMyAccount = myAccounts.first
                }
                if selectedDebtAccount == nil {
                    selectedDebtAccount = debtAccounts.first
                }
                applyPresetIfNeeded()
                if existingDebtGroupID == nil, let acc = selectedMyAccount {
                    selectedCurrency = acc.currency
                }
                if splitLegs.first?.account == nil, let first = myAccounts.first {
                    splitLegs[0].account = first
                    splitLegs[0].currency = first.currency
                }
                Task { await currencyService.fetchRates() }
            }
            .onChange(of: mode) { _, newMode in
                if newMode == .forgive {
                    entryMode = .normal
                    if let selectedDebtAccount {
                        selectedCurrency = selectedDebtAccount.currency
                    }
                }
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
                Picker(mode == .borrow ? "存入帳戶" : "付款帳戶", selection: $leg.account) {
                    Text("選擇帳戶").tag(nil as Account?)
                    ForEach(myAccounts) { acc in
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
            Label("新增分拆帳戶", systemImage: "plus.circle")
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

    @ViewBuilder
    private var previewBlock: some View {
        if let debtAcc = selectedDebtAccount {
            let total = totalInputAmount
            VStack(alignment: .leading, spacing: 6) {
                Text("交易預覽：")
                    .font(.caption)
                    .bold()

                if mode == .borrow {
                    Text("對象：\(debtAcc.name)")
                    Text("動作：\(debtModeTitle(.borrow))")
                } else if mode == .repay {
                    Text("對象：\(debtAcc.name)")
                    Text("動作：\(debtModeTitle(.repay))")
                } else {
                    Text("對象：\(debtAcc.name)")
                    Text("動作：\(forgivenessDirection.displayTitle)")
                }

                if let total {
                    Text("總金額：\(total.formatted())")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var totalInputAmount: Decimal? {
        switch effectiveEntryMode {
        case .normal:
            return positiveDecimal(from: amountString)
        case .split:
            let values = splitLegs.compactMap { positiveDecimal(from: $0.amountString) }
            guard values.count == splitLegs.count else { return nil }
            return values.reduce(0, +)
        case .merge:
            let values = mergeLegs.compactMap { positiveDecimal(from: $0.amountString) }
            guard values.count == mergeLegs.count else { return nil }
            return values.reduce(0, +)
        }
    }

    private var canSubmit: Bool {
        guard selectedDebtAccount != nil else { return false }

        switch effectiveEntryMode {
        case .normal:
            if mode == .forgive {
                return positiveDecimal(from: amountString) != nil
            }
            return selectedMyAccount != nil && positiveDecimal(from: amountString) != nil
        case .split:
            return splitLegs.contains { $0.account != nil && positiveDecimal(from: $0.amountString) != nil }
                && splitLegs.allSatisfy { $0.account != nil && positiveDecimal(from: $0.amountString) != nil }
        case .merge:
            return selectedMyAccount != nil
                && mergeLegs.contains { positiveDecimal(from: $0.amountString) != nil }
                && mergeLegs.allSatisfy { positiveDecimal(from: $0.amountString) != nil }
        }
    }

    private func saveTransaction() {
        guard let debtAcc = selectedDebtAccount else {
            showValidation("請先選擇借貸對象。")
            return
        }

        if existingDebtGroupID != nil {
            do {
                try updateExistingDebtPair(debtAccount: debtAcc)
                dismiss()
            } catch {
                modelContext.rollback()
                showValidation(error.localizedDescription)
            }
            return
        }

        switch effectiveEntryMode {
        case .normal:
            guard let amount = positiveDecimal(from: amountString) else {
                showValidation("請輸入有效金額。")
                return
            }
            if mode == .forgive {
                createDebtForgivenessTransaction(
                    debtAccount: debtAcc,
                    amount: amount,
                    currencyCode: selectedCurrency,
                    memo: note,
                    direction: forgivenessDirection
                )
            } else {
                guard let myAcc = selectedMyAccount else {
                    showValidation("請輸入完整金額並選擇帳戶。")
                    return
                }
                createTransferPair(debtAccount: debtAcc, myAccount: myAcc, amount: amount, currencyCode: selectedCurrency, memo: note)
            }

        case .split:
            var legs: [(account: Account, amount: Decimal, currency: String)] = []
            for leg in splitLegs {
                guard let account = leg.account,
                      let amount = positiveDecimal(from: leg.amountString)
                else {
                    showValidation("分拆模式下，每一項都需要帳戶與金額。")
                    return
                }
                legs.append((account, amount, leg.currency))
            }

            for (index, leg) in legs.enumerated() {
                createTransferPair(
                    debtAccount: debtAcc,
                    myAccount: leg.account,
                    amount: leg.amount,
                    currencyCode: leg.currency,
                    memo: indexedMemo(base: note, mode: .split, index: index, count: legs.count)
                )
            }

        case .merge:
            guard let myAcc = selectedMyAccount else {
                showValidation("合併模式下請先選擇目標帳戶。")
                return
            }

            var items: [(amount: Decimal, currency: String)] = []
            for leg in mergeLegs {
                guard let amount = positiveDecimal(from: leg.amountString) else {
                    showValidation("合併模式下每一項都需要有效金額。")
                    return
                }
                items.append((amount, leg.currency))
            }

            for (index, item) in items.enumerated() {
                createTransferPair(
                    debtAccount: debtAcc,
                    myAccount: myAcc,
                    amount: item.amount,
                    currencyCode: item.currency,
                    memo: indexedMemo(base: note, mode: .merge, index: index, count: items.count)
                )
            }
        }

        dismiss()
    }

    private func createTransferPair(debtAccount: Account, myAccount: Account, amount: Decimal, currencyCode: String, memo: String) {
        let normalizedAmount = abs(amount)
        let txID1 = UUID()
        let txID2 = UUID()
        let transferGroupID = UUID()
        let finalMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? debtModeTitle(mode) : memo

        if mode == .borrow {
            let debtTx = FinancialTransaction(
                id: txID1,
                amount: -normalizedAmount,
                currencyCode: currencyCode,
                date: date,
                note: "\(finalMemo) (借入至 \(myAccount.name))",
                type: .transfer,
                linkedTransactionID: txID2,
                transferGroupID: transferGroupID,
                transferSide: .outgoing,
                account: debtAccount
            )
            let myTx = FinancialTransaction(
                id: txID2,
                amount: normalizedAmount,
                currencyCode: currencyCode,
                date: date,
                note: "\(finalMemo) (來自 \(debtAccount.name))",
                type: .transfer,
                linkedTransactionID: txID1,
                transferGroupID: transferGroupID,
                transferSide: .incoming,
                account: myAccount
            )
            modelContext.insert(debtTx)
            modelContext.insert(myTx)
        } else {
            let myTx = FinancialTransaction(
                id: txID1,
                amount: -normalizedAmount,
                currencyCode: currencyCode,
                date: date,
                note: "\(finalMemo) (還款給 \(debtAccount.name))",
                type: .transfer,
                linkedTransactionID: txID2,
                transferGroupID: transferGroupID,
                transferSide: .outgoing,
                account: myAccount
            )
            let debtTx = FinancialTransaction(
                id: txID2,
                amount: normalizedAmount,
                currencyCode: currencyCode,
                date: date,
                note: "\(finalMemo) (來自 \(myAccount.name))",
                type: .transfer,
                linkedTransactionID: txID1,
                transferGroupID: transferGroupID,
                transferSide: .incoming,
                account: debtAccount
            )
            modelContext.insert(myTx)
            modelContext.insert(debtTx)
        }
    }

    private func createDebtForgivenessTransaction(
        debtAccount: Account,
        amount: Decimal,
        currencyCode: String,
        memo: String,
        direction: DebtForgivenessDirection
    ) {
        let normalizedAmount = abs(amount) * direction.amountSign
        if let existingForgivenessTransactionID,
           let transaction = allAccounts
            .flatMap(\.transactions)
            .first(where: { $0.id == existingForgivenessTransactionID }) {
            transaction.amount = normalizedAmount
            transaction.currencyCode = currencyCode
            transaction.date = date
            transaction.note = TransactionSemantics.debtForgivenessNote(
                baseNote: memo,
                debtAccountName: debtAccount.name,
                direction: direction
            )
            transaction.type = .transfer
            transaction.linkedTransactionID = nil
            transaction.transferGroupID = nil
            transaction.transferSide = nil
            transaction.account = debtAccount
            transaction.updatedAt = Date()
        } else {
            let transaction = FinancialTransaction(
                amount: normalizedAmount,
                currencyCode: currencyCode,
                date: date,
                note: TransactionSemantics.debtForgivenessNote(
                    baseNote: memo,
                    debtAccountName: debtAccount.name,
                    direction: direction
                ),
                type: .transfer,
                linkedTransactionID: nil,
                transferGroupID: nil,
                transferSide: nil,
                account: debtAccount
            )
            modelContext.insert(transaction)
        }
    }

    private func loadExistingDebtTransaction() {
        guard existingDebtGroupID == nil,
              let existingDebtTransactionID,
              let original = allAccounts
                .flatMap(\.transactions)
                .first(where: { $0.id == existingDebtTransactionID }),
              let groupID = original.transferGroupID
        else {
            return
        }

        let group = allAccounts
            .flatMap(\.transactions)
            .filter { $0.transferGroupID == groupID }
        guard group.count == 2,
              let debtTransaction = group.first(where: { $0.account?.type == .debt }),
              let ownTransaction = group.first(where: { $0.account?.type != .debt }),
              let debtAccount = debtTransaction.account,
              let ownAccount = ownTransaction.account
        else {
            showValidation("這筆債務轉帳的分錄結構不完整。")
            return
        }

        existingDebtGroupID = groupID
        let debtSide = debtTransaction.transferSide
            ?? (debtTransaction.amount < 0 ? .outgoing : .incoming)
        mode = debtSide == .outgoing ? .borrow : .repay
        entryMode = .normal
        selectedDebtAccount = debtAccount
        selectedMyAccount = ownAccount
        selectedCurrency = ownTransaction.currencyCode
        amountString = NSDecimalNumber(decimal: abs(ownTransaction.amount)).stringValue
        date = ownTransaction.date
        note = extractDebtNote(group.first(where: { !$0.note.isEmpty })?.note ?? "")
    }

    private func updateExistingDebtPair(debtAccount: Account) throws {
        guard let groupID = existingDebtGroupID,
              let myAccount = selectedMyAccount,
              let amount = positiveDecimal(from: amountString)
        else {
            throw NSError(
                domain: "AddDebtView",
                code: 20,
                userInfo: [NSLocalizedDescriptionKey: "請輸入完整金額並選擇自己的帳戶。"]
            )
        }

        let group = allAccounts
            .flatMap(\.transactions)
            .filter { $0.transferGroupID == groupID }
        guard group.count == 2,
              let debtTransaction = group.first(where: { $0.account?.type == .debt }),
              let ownTransaction = group.first(where: { $0.account?.type != .debt })
        else {
            throw NSError(
                domain: "AddDebtView",
                code: 21,
                userInfo: [NSLocalizedDescriptionKey: "找不到完整的債務轉帳分錄。"]
            )
        }

        try DebtTransferEditService.apply(
            DebtTransferEditDraft(
                debtAccount: debtAccount,
                ownAccount: myAccount,
                amount: amount,
                currencyCode: selectedCurrency,
                date: date,
                note: note,
                direction: mode == .borrow ? .borrow : .repay
            ),
            debtTransaction: debtTransaction,
            ownTransaction: ownTransaction,
            updatedAt: Date()
        )

        try modelContext.save()
    }

    private func indexedMemo(base: String, mode: EntryMode, index: Int, count: Int) -> String {
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

    private func extractDebtNote(_ value: String) -> String {
        let separators = [" (借入至", " (來自", " (還款給", " (轉至"]
        let indexes = separators.compactMap { value.range(of: $0)?.lowerBound }
        guard let first = indexes.min() else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(value[..<first]).trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var debtAccountLabel: String {
        switch mode {
        case .borrow:
            return selectedDebtBalance > 0 ? "誰還你" : "跟誰借"
        case .repay:
            return selectedDebtBalance > 0 ? "借給誰" : "還給誰"
        case .forgive:
            switch forgivenessDirection {
            case .forgivenByOthers:
                return "誰免除了你的欠款"
            case .forgiveOthers:
                return "你要免除誰的欠款"
            }
        }
    }

    private var effectiveEntryMode: EntryMode {
        mode == .forgive ? .normal : entryMode
    }

    private func extractForgivenessNote(_ note: String) -> String {
        let cleaned = note
            .replacingOccurrences(of: TransactionSemantics.debtForgivenessMarker, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = cleaned.range(of: "(對方免除：") ?? cleaned.range(of: "(我方免除：") {
            return cleaned[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }

    private var selectedDebtBalance: Decimal {
        guard let selectedDebtAccount else { return 0 }
        return selectedDebtAccount.baseBalance + selectedDebtAccount.transactions.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private func debtModeTitle(_ debtMode: DebtMode) -> String {
        switch debtMode {
        case .borrow:
            return selectedDebtBalance > 0 ? "收款（對方還你）" : "借入（你向對方借）"
        case .repay:
            return selectedDebtBalance > 0 ? "借出（對方欠你更多）" : "還款（你還給對方）"
        case .forgive:
            return "免除債務"
        }
    }

    private func applyPresetIfNeeded() {
        if let presetMode {
            mode = presetMode
        }
        if let presetForgivenessDirection {
            forgivenessDirection = presetForgivenessDirection
        }
        if let presetDebtAccountID,
           selectedDebtAccount?.id != presetDebtAccountID,
           let presetAccount = debtAccounts.first(where: { $0.id == presetDebtAccountID }) {
            selectedDebtAccount = presetAccount
            if mode == .forgive {
                selectedCurrency = presetAccount.currency
            }
        }
        if note.isEmpty, let presetNote {
            note = presetNote
        }
    }
}
