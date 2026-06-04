import SwiftUI
import SwiftData

struct EditAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var account: Account
    
    @Query private var allTransactions: [FinancialTransaction]
    
    @State private var adjustmentAmountString: String = ""
    @State private var adjustmentCurrency: String = "HKD"
    @State private var adjustmentNote: String = "資產餘額修正"
    
    @FocusState private var isAmountFocused: Bool
    
    let currencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]
    
    var currentHoldings: [(String, Decimal)] {
        let accountTxs = allTransactions.filter { $0.account?.id == account.id }
        var balances: [String: Decimal] = [:]
        
        if account.baseBalance != 0 {
            balances[account.currency, default: 0] += account.baseBalance
        }
        for tx in accountTxs {
            balances[tx.currencyCode, default: 0] += tx.amount
        }
        
        return balances.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("帳戶資訊"),
                    footer: Text("主幣種建立後不可修改。如需調整其他幣種餘額，請使用下方的「新增餘額調整」。")
                ) {
                    TextField("帳戶名稱", text: $account.name)
                    
                    Picker("主幣種", selection: $account.currency) {
                        ForEach(currencies, id: \.self) { code in Text(code).tag(code) }
                    }
                    .disabled(true)
                    
                    Picker("類型", selection: $account.type) {
                        ForEach(AccountType.allCases) { type in Text(type.displayName).tag(type) }
                    }
                }
                
                Section(header: Text("當前各幣種餘額 (統計值)")) {
                    if currentHoldings.isEmpty {
                        Text("無餘額").foregroundStyle(.secondary)
                    } else {
                        ForEach(currentHoldings, id: \.0) { currency, amount in
                            HStack {
                                Text(currency).bold()
                                Spacer()
                                Text(amount.formatted(.currency(code: currency)))
                                    // 🔥 修正：明確指定 Color.primary
                                    .foregroundStyle(amount >= 0 ? Color.primary : Color.red)
                            }
                        }
                    }
                }
                
                Section(
                    header: Text("主幣種初始餘額 (修正用)"),
                    footer: Text("此數值僅代表帳戶建立時的「主幣種」初始金額。")
                ) {
                    HStack {
                        Text(account.currency)
                        TextField("金額", value: $account.baseBalance, format: .number)
                            .keyboardType(.decimalPad)
                            .focused($isAmountFocused)
                    }
                }
                
                Section(
                    header: Text("新增餘額調整 (其他幣種)"),
                    footer: Text("這會新增一筆「資產調整」交易來調整該幣種總額，不計入收入/支出報表。")
                ) {
                    HStack {
                        Picker("", selection: $adjustmentCurrency) {
                            ForEach(currencies, id: \.self) { code in Text(code).tag(code) }
                        }
                        .labelsHidden().frame(width: 80)
                        
                        TextField("調整金額 (+/-)", text: $adjustmentAmountString)
                            .keyboardType(.decimalPad)
                    }
                    TextField("備註", text: $adjustmentNote)
                    
                    Button("執行調整") { addAdjustment() }
                        .disabled(adjustmentAmountString.isEmpty)
                }
            }
            .interactiveKeyboardDismiss()
            .navigationTitle("編輯帳戶")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Button("+/-") {
                        if isAmountFocused { account.baseBalance *= -1 }
                        else {
                            if adjustmentAmountString.hasPrefix("-") { adjustmentAmountString.removeFirst() }
                            else { adjustmentAmountString = "-" + adjustmentAmountString }
                        }
                    }
                    Spacer()
                    Button("完成") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .onAppear {
                if let other = currencies.first(where: { $0 != account.currency }) { adjustmentCurrency = other }
            }
        }
    }
    
    private func addAdjustment() {
        guard let amount = Decimal(string: adjustmentAmountString), amount != 0 else { return }
        let trimmedNote = adjustmentNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNote = trimmedNote.isEmpty ? "[資產調整] 餘額修正" : "[資產調整] \(trimmedNote)"
        
        let tx = FinancialTransaction(
            amount: amount,
            currencyCode: adjustmentCurrency,
            date: Date(),
            note: finalNote,
            type: .transfer,
            transferSide: amount >= 0 ? .incoming : .outgoing,
            account: account
        )
        modelContext.insert(tx)
        
        adjustmentAmountString = ""
        adjustmentNote = "資產餘額修正"
    }
}
