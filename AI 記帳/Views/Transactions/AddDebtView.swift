import SwiftUI
import SwiftData

struct AddDebtView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]

    private var debtAccounts: [Account] {
        allAccounts.filter { $0.type == .debt && !$0.isArchived }.sorted { $0.name < $1.name }
    }

    private var myAccounts: [Account] {
        allAccounts.filter { $0.type != .debt && !$0.isArchived }
    }

    enum DebtMode: String, CaseIterable {
        case borrow = "借入 (我欠人)"
        case repay = "還款 (還給人)"
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

    @FocusState private var isAmountFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("操作", selection: $mode) {
                        ForEach(DebtMode.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("模式", selection: $entryMode) {
                        ForEach(EntryMode.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    if debtAccounts.isEmpty {
                        Text("請先至「帳戶」頁面新增類型為「借貸」的對象")
                            .foregroundStyle(.red)
                            .font(.caption)
                    } else {
                        Picker(mode == .borrow ? "跟誰借" : "還給誰", selection: $selectedDebtAccount) {
                            Text("請選擇對象").tag(nil as Account?)
                            ForEach(debtAccounts) { acc in
                                Text(acc.name).tag(acc as Account?)
                            }
                        }
                    }

                    if entryMode != .split {
                        Picker(mode == .borrow ? "存入帳戶" : "付款帳戶", selection: $selectedMyAccount) {
                            Text("請選擇帳戶").tag(nil as Account?)
                            ForEach(myAccounts) { acc in
                                Text(acc.name).tag(acc as Account?)
                            }
                        }
                        .onChange(of: selectedMyAccount) { _, _ in
                            if let acc = selectedMyAccount {
                                selectedCurrency = acc.currency
                            }
                        }
                    }
                }

                Section("金額與幣種") {
                    switch entryMode {
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
                    Button("確認") { saveTransaction() }
                        .disabled(!canSubmit)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { isAmountFocused = false }
                }
            }
            .onAppear {
                if selectedMyAccount == nil {
                    selectedMyAccount = myAccounts.first
                }
                if selectedDebtAccount == nil {
                    selectedDebtAccount = debtAccounts.first
                }
                if let acc = selectedMyAccount {
                    selectedCurrency = acc.currency
                }
                if splitLegs.first?.account == nil, let first = myAccounts.first {
                    splitLegs[0].account = first
                    splitLegs[0].currency = first.currency
                }
            }
        }
    }

    @ViewBuilder
    private var normalAmountRow: some View {
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
                    Text("動作：借入（我方資產增加）")
                } else {
                    Text("對象：\(debtAcc.name)")
                    Text("動作：還款（我方資產減少）")
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
        switch entryMode {
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

        switch entryMode {
        case .normal:
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

        switch entryMode {
        case .normal:
            guard let myAcc = selectedMyAccount,
                  let amount = positiveDecimal(from: amountString)
            else {
                showValidation("請輸入完整金額並選擇帳戶。")
                return
            }
            createTransferPair(debtAccount: debtAcc, myAccount: myAcc, amount: amount, currencyCode: selectedCurrency, memo: note)

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
        let finalMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? mode.rawValue : memo

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
}
