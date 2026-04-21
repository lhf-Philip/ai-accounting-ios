import SwiftUI
import SwiftData
import UIKit

struct AddTransferView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var currencyService = CurrencyService.shared

    @Query(sort: \Account.name) private var accounts: [Account]

    private enum TransferMode: String, CaseIterable, Identifiable {
        case oneToOne
        case oneToMany
        case manyToOne

        var id: String { rawValue }

        var title: String {
            switch self {
            case .oneToOne: return "一般 (1 -> 1)"
            case .oneToMany: return "分拆 (1 -> 多)"
            case .manyToOne: return "合併 (多 -> 1)"
            }
        }
    }

    private struct TransferLegInput: Identifiable {
        let id = UUID()
        var account: Account?
        var currency: String = "HKD"
        var amountString: String = ""
    }

    @State private var mode: TransferMode = .oneToOne

    // 1 -> 1
    @State private var fromAccount: Account?
    @State private var toAccount: Account?
    @State private var currencyOut: String = "HKD"
    @State private var currencyIn: String = "HKD"
    @State private var amountOutString: String = ""
    @State private var amountInString: String = ""

    // 1 -> many
    @State private var sourceAccount: Account?
    @State private var sourceCurrency: String = "HKD"
    @State private var sourceAmountString: String = ""
    @State private var destinationLegs: [TransferLegInput] = [TransferLegInput()]

    // many -> 1
    @State private var destinationAccount: Account?
    @State private var destinationCurrency: String = "HKD"
    @State private var destinationAmountString: String = ""
    @State private var sourceLegs: [TransferLegInput] = [TransferLegInput()]

    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""

    private let currencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]

    private var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    private var canSubmit: Bool {
        switch mode {
        case .oneToOne:
            guard fromAccount != nil, toAccount != nil, positiveDecimal(from: amountOutString) != nil else {
                return false
            }
            if currencyOut != currencyIn {
                return positiveDecimal(from: amountInString) != nil
            }
            return true
        case .oneToMany:
            guard sourceAccount != nil, positiveDecimal(from: sourceAmountString) != nil else {
                return false
            }
            return !destinationLegs.isEmpty && destinationLegs.allSatisfy {
                $0.account != nil && positiveDecimal(from: $0.amountString) != nil
            }
        case .manyToOne:
            guard destinationAccount != nil, positiveDecimal(from: destinationAmountString) != nil else {
                return false
            }
            return !sourceLegs.isEmpty && sourceLegs.allSatisfy {
                $0.account != nil && positiveDecimal(from: $0.amountString) != nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("模式") {
                    Picker("模式", selection: $mode) {
                        ForEach(TransferMode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _, _ in
                        dismissKeyboard()
                    }
                }

                switch mode {
                case .oneToOne:
                    oneToOneSections
                case .oneToMany:
                    oneToManySections
                case .manyToOne:
                    manyToOneSections
                }

                Section("其他") {
                    DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    TextField("備註", text: $note)
                }
            }
            .navigationTitle("轉帳")
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
                    Button("確認") { saveTransfer() }
                        .disabled(!canSubmit)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { dismissKeyboard() }
                }
            }
            .onAppear {
                Task { await currencyService.fetchRates() }
            }
        }
    }

    @ViewBuilder
    private var oneToOneSections: some View {
        Section("轉出方 (支出)") {
            Picker("從帳戶", selection: $fromAccount) {
                Text("選擇帳戶").tag(nil as Account?)
                ForEach(activeAccounts) { acc in
                    Text(acc.name).tag(acc as Account?)
                }
            }
            .onChange(of: fromAccount) { _, _ in
                if let acc = fromAccount {
                    currencyOut = acc.currency
                }
            }

            if fromAccount != nil {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Picker("", selection: $currencyOut) {
                            ForEach(currencies, id: \.self) { code in
                                Text(code).tag(code)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)

                        TextField("轉出金額", text: Binding(
                            get: { amountOutString },
                            set: { newValue in
                                let sanitized = sanitizePositiveDecimalInput(newValue)
                                amountOutString = sanitized
                                if currencyOut == currencyIn {
                                    amountInString = sanitized
                                }
                            }
                        ))
                        .keyboardType(.decimalPad)
                    }
                    CurrencyRateHintView(
                        currencyService: currencyService,
                        amount: positiveDecimal(from: amountOutString),
                        currencyCode: currencyOut
                    )
                }
            }
        }

        Section("轉入方 (收入)") {
            Picker("到帳戶", selection: $toAccount) {
                Text("選擇帳戶").tag(nil as Account?)
                ForEach(activeAccounts) { acc in
                    Text(acc.name).tag(acc as Account?)
                }
            }
            .onChange(of: toAccount) { _, _ in
                if let acc = toAccount {
                    currencyIn = acc.currency
                    if currencyOut == currencyIn {
                        amountInString = amountOutString
                    }
                }
            }

            if toAccount != nil {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Picker("", selection: $currencyIn) {
                            ForEach(currencies, id: \.self) { code in
                                Text(code).tag(code)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)

                        TextField("轉入金額 (實收)", text: Binding(
                            get: { amountInString },
                            set: { amountInString = sanitizePositiveDecimalInput($0) }
                        ))
                        .keyboardType(.decimalPad)
                    }
                    CurrencyRateHintView(
                        currencyService: currencyService,
                        amount: positiveDecimal(from: amountInString),
                        currencyCode: currencyIn
                    )
                }

                TransferRateHintView(
                    currencyService: currencyService,
                    outgoingAmount: positiveDecimal(from: amountOutString),
                    outgoingCurrency: currencyOut,
                    incomingAmount: positiveDecimal(from: amountInString),
                    incomingCurrency: currencyIn
                )

                if currencyOut == currencyIn {
                    Text("幣種相同，金額自動對應")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var oneToManySections: some View {
        Section("單一轉出") {
            Picker("從帳戶", selection: $sourceAccount) {
                Text("選擇帳戶").tag(nil as Account?)
                ForEach(activeAccounts) { acc in
                    Text(acc.name).tag(acc as Account?)
                }
            }
            .onChange(of: sourceAccount) { _, _ in
                if let acc = sourceAccount {
                    sourceCurrency = acc.currency
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Picker("", selection: $sourceCurrency) {
                        ForEach(currencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)

                    TextField("轉出總額", text: Binding(
                        get: { sourceAmountString },
                        set: { sourceAmountString = sanitizePositiveDecimalInput($0) }
                    ))
                    .keyboardType(.decimalPad)
                }
                CurrencyRateHintView(
                    currencyService: currencyService,
                    amount: positiveDecimal(from: sourceAmountString),
                    currencyCode: sourceCurrency
                )
            }
        }

        Section("分拆轉入") {
            ForEach($destinationLegs) { $leg in
                VStack(spacing: 10) {
                    Picker("到帳戶", selection: $leg.account) {
                        Text("選擇帳戶").tag(nil as Account?)
                        ForEach(activeAccounts) { acc in
                            Text(acc.name).tag(acc as Account?)
                        }
                    }
                    .onChange(of: leg.account) { _, _ in
                        if let acc = leg.account {
                            leg.currency = acc.currency
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Picker("", selection: $leg.currency) {
                                ForEach(currencies, id: \.self) { code in
                                    Text(code).tag(code)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 80)

                            TextField("轉入金額", text: Binding(
                                get: { leg.amountString },
                                set: { leg.amountString = sanitizePositiveDecimalInput($0) }
                            ))
                            .keyboardType(.decimalPad)
                        }
                        CurrencyRateHintView(
                            currencyService: currencyService,
                            amount: positiveDecimal(from: leg.amountString),
                            currencyCode: leg.currency
                        )
                    }

                    if destinationLegs.count > 1 {
                        Button(role: .destructive) {
                            destinationLegs.removeAll { $0.id == leg.id }
                        } label: {
                            Text("移除此轉入帳戶")
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Button {
                destinationLegs.append(TransferLegInput(currency: sourceCurrency))
            } label: {
                Label("新增轉入帳戶", systemImage: "plus.circle")
            }
        }
    }

    @ViewBuilder
    private var manyToOneSections: some View {
        Section("多個轉出") {
            ForEach($sourceLegs) { $leg in
                VStack(spacing: 10) {
                    Picker("從帳戶", selection: $leg.account) {
                        Text("選擇帳戶").tag(nil as Account?)
                        ForEach(activeAccounts) { acc in
                            Text(acc.name).tag(acc as Account?)
                        }
                    }
                    .onChange(of: leg.account) { _, _ in
                        if let acc = leg.account {
                            leg.currency = acc.currency
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Picker("", selection: $leg.currency) {
                                ForEach(currencies, id: \.self) { code in
                                    Text(code).tag(code)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 80)

                            TextField("轉出金額", text: Binding(
                                get: { leg.amountString },
                                set: { leg.amountString = sanitizePositiveDecimalInput($0) }
                            ))
                            .keyboardType(.decimalPad)
                        }
                        CurrencyRateHintView(
                            currencyService: currencyService,
                            amount: positiveDecimal(from: leg.amountString),
                            currencyCode: leg.currency
                        )
                    }

                    if sourceLegs.count > 1 {
                        Button(role: .destructive) {
                            sourceLegs.removeAll { $0.id == leg.id }
                        } label: {
                            Text("移除此轉出帳戶")
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Button {
                sourceLegs.append(TransferLegInput(currency: destinationCurrency))
            } label: {
                Label("新增轉出帳戶", systemImage: "plus.circle")
            }
        }

        Section("單一轉入") {
            Picker("到帳戶", selection: $destinationAccount) {
                Text("選擇帳戶").tag(nil as Account?)
                ForEach(activeAccounts) { acc in
                    Text(acc.name).tag(acc as Account?)
                }
            }
            .onChange(of: destinationAccount) { _, _ in
                if let acc = destinationAccount {
                    destinationCurrency = acc.currency
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Picker("", selection: $destinationCurrency) {
                        ForEach(currencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)

                    TextField("轉入總額", text: Binding(
                        get: { destinationAmountString },
                        set: { destinationAmountString = sanitizePositiveDecimalInput($0) }
                    ))
                    .keyboardType(.decimalPad)
                }
                CurrencyRateHintView(
                    currencyService: currencyService,
                    amount: positiveDecimal(from: destinationAmountString),
                    currencyCode: destinationCurrency
                )
            }
        }
    }

    private func saveTransfer() {
        switch mode {
        case .oneToOne:
            saveOneToOneTransfer()
        case .oneToMany:
            saveOneToManyTransfer()
        case .manyToOne:
            saveManyToOneTransfer()
        }
    }

    private func saveOneToOneTransfer() {
        guard let from = fromAccount, let to = toAccount else { return }
        guard let amountOut = positiveDecimal(from: amountOutString) else {
            showValidation("請輸入大於 0 的轉出金額。")
            return
        }

        var amountIn = amountOut
        if currencyOut != currencyIn {
            guard let customIn = positiveDecimal(from: amountInString) else {
                showValidation("跨幣種轉帳請輸入大於 0 的轉入金額。")
                return
            }
            amountIn = customIn
        }

        let txID1 = UUID()
        let txID2 = UUID()
        let transferGroupID = UUID()
        let memo = note.isEmpty ? "轉帳" : note

        let outTx = FinancialTransaction(
            id: txID1,
            amount: -abs(amountOut),
            currencyCode: currencyOut,
            date: date,
            note: "\(memo) (轉至 \(to.name))",
            type: .transfer,
            linkedTransactionID: txID2,
            transferGroupID: transferGroupID,
            transferSide: .outgoing,
            account: from
        )

        let inTx = FinancialTransaction(
            id: txID2,
            amount: abs(amountIn),
            currencyCode: currencyIn,
            date: date,
            note: "\(memo) (來自 \(from.name))",
            type: .transfer,
            linkedTransactionID: txID1,
            transferGroupID: transferGroupID,
            transferSide: .incoming,
            account: to
        )

        modelContext.insert(outTx)
        modelContext.insert(inTx)
        saveContextAndDismiss()
    }

    private func saveOneToManyTransfer() {
        guard let source = sourceAccount else {
            showValidation("請選擇轉出帳戶。")
            return
        }
        guard let sourceAmount = positiveDecimal(from: sourceAmountString) else {
            showValidation("請輸入大於 0 的轉出總額。")
            return
        }

        let parsedLegs = destinationLegs.enumerated().compactMap { index, leg -> (index: Int, account: Account, currency: String, amount: Decimal)? in
            guard let account = leg.account,
                  let amount = positiveDecimal(from: leg.amountString) else {
                return nil
            }
            return (index + 1, account, leg.currency, amount)
        }

        if parsedLegs.count != destinationLegs.count || parsedLegs.isEmpty {
            showValidation("請完整填寫每一個轉入帳戶與金額。")
            return
        }

        var accountIDs = Set<UUID>()
        for leg in parsedLegs {
            if accountIDs.contains(leg.account.id) {
                showValidation("分拆轉入帳戶不可重複，請合併該帳戶的金額。")
                return
            }
            accountIDs.insert(leg.account.id)
        }

        let sameCurrencyOnly = parsedLegs.allSatisfy { $0.currency == sourceCurrency }
        if sameCurrencyOnly {
            let totalIn = parsedLegs.reduce(Decimal.zero) { $0 + $1.amount }
            if totalIn != sourceAmount {
                showValidation("同幣種分拆時，轉入總額需等於轉出總額。")
                return
            }
        }

        let transferGroupID = UUID()
        let memo = note.isEmpty ? "轉帳" : note

        let outTx = FinancialTransaction(
            amount: -abs(sourceAmount),
            currencyCode: sourceCurrency,
            date: date,
            note: "\(memo) (分拆轉至 \(parsedLegs.count) 個帳戶)",
            type: .transfer,
            transferGroupID: transferGroupID,
            transferSide: .outgoing,
            account: source
        )
        modelContext.insert(outTx)

        for leg in parsedLegs {
            let inTx = FinancialTransaction(
                amount: abs(leg.amount),
                currencyCode: leg.currency,
                date: date,
                note: "\(memo) (來自 \(source.name))",
                type: .transfer,
                transferGroupID: transferGroupID,
                transferSide: .incoming,
                account: leg.account
            )
            modelContext.insert(inTx)
        }

        saveContextAndDismiss()
    }

    private func saveManyToOneTransfer() {
        guard let destination = destinationAccount else {
            showValidation("請選擇轉入帳戶。")
            return
        }
        guard let destinationAmount = positiveDecimal(from: destinationAmountString) else {
            showValidation("請輸入大於 0 的轉入總額。")
            return
        }

        let parsedLegs = sourceLegs.enumerated().compactMap { index, leg -> (index: Int, account: Account, currency: String, amount: Decimal)? in
            guard let account = leg.account,
                  let amount = positiveDecimal(from: leg.amountString) else {
                return nil
            }
            return (index + 1, account, leg.currency, amount)
        }

        if parsedLegs.count != sourceLegs.count || parsedLegs.isEmpty {
            showValidation("請完整填寫每一個轉出帳戶與金額。")
            return
        }

        var accountIDs = Set<UUID>()
        for leg in parsedLegs {
            if accountIDs.contains(leg.account.id) {
                showValidation("轉出帳戶不可重複，請合併該帳戶的金額。")
                return
            }
            accountIDs.insert(leg.account.id)
        }

        let sameCurrencyOnly = parsedLegs.allSatisfy { $0.currency == destinationCurrency }
        if sameCurrencyOnly {
            let totalOut = parsedLegs.reduce(Decimal.zero) { $0 + $1.amount }
            if totalOut != destinationAmount {
                showValidation("同幣種合併時，轉出總額需等於轉入總額。")
                return
            }
        }

        let transferGroupID = UUID()
        let memo = note.isEmpty ? "轉帳" : note

        for leg in parsedLegs {
            let outTx = FinancialTransaction(
                amount: -abs(leg.amount),
                currencyCode: leg.currency,
                date: date,
                note: "\(memo) (轉至 \(destination.name))",
                type: .transfer,
                transferGroupID: transferGroupID,
                transferSide: .outgoing,
                account: leg.account
            )
            modelContext.insert(outTx)
        }

        let inTx = FinancialTransaction(
            amount: abs(destinationAmount),
            currencyCode: destinationCurrency,
            date: date,
            note: "\(memo) (來自 \(parsedLegs.count) 個帳戶)",
            type: .transfer,
            transferGroupID: transferGroupID,
            transferSide: .incoming,
            account: destination
        )
        modelContext.insert(inTx)

        saveContextAndDismiss()
    }

    private func saveContextAndDismiss() {
        do {
            try modelContext.save()
            dismiss()
        } catch {
            showValidation("儲存失敗：\(error.localizedDescription)")
        }
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

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func showValidation(_ message: String) {
        validationMessage = message
        showingValidationAlert = true
    }
}
