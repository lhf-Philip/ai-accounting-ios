import SwiftUI
import SwiftData

struct AddDebtView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]
    
    var debtAccounts: [Account] { allAccounts.filter { $0.type == .debt }.sorted { $0.name < $1.name } }
    var myAccounts: [Account] { allAccounts.filter { $0.type != .debt } }
    
    @State private var mode: DebtMode = .borrow
    @State private var selectedDebtAccount: Account?
    @State private var selectedMyAccount: Account?
    @State private var amountString: String = ""
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""
    
    // 🔥 新增：幣種選擇 (預設為我的帳戶幣種，但可更改)
    @State private var selectedCurrency: String = "HKD"
    let currencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]
    
    @FocusState private var isAmountFocused: Bool
    
    enum DebtMode: String, CaseIterable {
        case borrow = "借入 (我欠人)"
        case repay = "還款 (還給人)"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("操作", selection: $mode) {
                        ForEach(DebtMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section {
                    if debtAccounts.isEmpty {
                        Text("請先至「帳戶」頁面新增類型為「借貸」的對象").foregroundStyle(.red).font(.caption)
                    } else {
                        Picker(mode == .borrow ? "跟誰借" : "還給誰", selection: $selectedDebtAccount) {
                            Text("請選擇對象").tag(nil as Account?)
                            ForEach(debtAccounts.filter { !$0.isArchived }) { acc in Text(acc.name).tag(acc as Account?) }
                        }
                    }
                    Picker(mode == .borrow ? "存入帳戶" : "付款帳戶", selection: $selectedMyAccount) {
                        Text("請選擇帳戶").tag(nil as Account?)
                        ForEach(myAccounts.filter { !$0.isArchived }) { acc in Text(acc.name).tag(acc as Account?) }
                    }
                    .onChange(of: selectedMyAccount) {
                        if let acc = selectedMyAccount { selectedCurrency = acc.currency }
                    }
                }
                
                Section("金額與幣種") {
                    HStack {
                        // 🔥 幣種選擇器
                        Picker("", selection: $selectedCurrency) {
                            ForEach(currencies, id: \.self) { code in Text(code).tag(code) }
                        }
                        .labelsHidden()
                        .frame(width: 80)
                        
                        TextField("0", text: $amountString)
                            .keyboardType(.decimalPad)
                            .focused($isAmountFocused)
                            .onChange(of: amountString) { _, newValue in
                                let sanitized = sanitizePositiveDecimalInput(newValue)
                                if sanitized != newValue {
                                    amountString = sanitized
                                }
                            }
                    }
                    
                    DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    TextField("備註", text: $note)
                }
                
                Section {
                    if let debtAcc = selectedDebtAccount, let myAcc = selectedMyAccount, let amount = Decimal(string: amountString) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("交易預覽：").font(.caption).bold()
                            if mode == .borrow {
                                Text("1. \(myAcc.name) 將增加 \(selectedCurrency) \(amount.formatted()) (資產)")
                                Text("2. \(debtAcc.name) 將減少 \(selectedCurrency) \(amount.formatted()) (負債)").foregroundStyle(.red)
                            } else {
                                Text("1. \(myAcc.name) 將減少 \(selectedCurrency) \(amount.formatted()) (資產)")
                                Text("2. \(debtAcc.name) 將增加 \(selectedCurrency) \(amount.formatted()) (負債)").foregroundStyle(.green)
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("借貸管理")
            .alert("輸入錯誤", isPresented: $showingValidationAlert) {
                Button("確定", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("確認") { saveTransaction() }
                        .disabled(selectedDebtAccount == nil || selectedMyAccount == nil || amountString.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { isAmountFocused = false } }
            }
            .onAppear {
                if selectedMyAccount == nil { selectedMyAccount = myAccounts.first }
                if selectedDebtAccount == nil { selectedDebtAccount = debtAccounts.first }
                if let acc = selectedMyAccount { selectedCurrency = acc.currency }
            }
        }
    }
    
    private func saveTransaction() {
        guard let debtAcc = selectedDebtAccount, let myAcc = selectedMyAccount else { return }
        guard let amount = positiveDecimal(from: amountString) else {
            showValidation("請輸入大於 0 的金額。")
            return
        }
        
        let normalizedAmount = abs(amount)
        
        let txID1 = UUID(); let txID2 = UUID()
        let transferGroupID = UUID()
        let memo = note.isEmpty ? mode.rawValue : note
        
        // 注意：這裡我們將 transaction 的 currencyCode 設為用戶選擇的 selectedCurrency
        // 這樣即使「媽媽」的預設幣種是 HKD，這筆交易也會被標記為 CNY
        
        if mode == .borrow {
            let debtTx = FinancialTransaction(
                id: txID1, amount: -normalizedAmount, currencyCode: selectedCurrency, // 🔥 設定幣種
                date: date, note: "\(memo) (借入至 \(myAcc.name))", type: .transfer, linkedTransactionID: txID2, transferGroupID: transferGroupID, transferSide: .outgoing, account: debtAcc
            )
            let myTx = FinancialTransaction(
                id: txID2, amount: normalizedAmount, currencyCode: selectedCurrency, // 🔥 設定幣種
                date: date, note: "\(memo) (來自 \(debtAcc.name))", type: .transfer, linkedTransactionID: txID1, transferGroupID: transferGroupID, transferSide: .incoming, account: myAcc
            )
            modelContext.insert(debtTx); modelContext.insert(myTx)
        } else {
            let myTx = FinancialTransaction(
                id: txID1, amount: -normalizedAmount, currencyCode: selectedCurrency, // 🔥 設定幣種
                date: date, note: "\(memo) (還款給 \(debtAcc.name))", type: .transfer, linkedTransactionID: txID2, transferGroupID: transferGroupID, transferSide: .outgoing, account: myAcc
            )
            let debtTx = FinancialTransaction(
                id: txID2, amount: normalizedAmount, currencyCode: selectedCurrency, // 🔥 設定幣種
                date: date, note: "\(memo) (來自 \(myAcc.name))", type: .transfer, linkedTransactionID: txID1, transferGroupID: transferGroupID, transferSide: .incoming, account: debtAcc
            )
            modelContext.insert(myTx); modelContext.insert(debtTx)
        }
        dismiss()
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
