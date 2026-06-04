import SwiftUI
import SwiftData

struct AddAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]
    
    var myAccounts: [Account] {
        allAccounts.filter { $0.type != .debt }
    }
    
    @State private var name: String = ""
    @State private var currency: String = "HKD"
    @State private var type: AccountType = .cash
    @State private var balanceString: String = ""
    @State private var linkedAccount: Account?
    
    // 額外幣種餘額
    struct AdditionalBalance: Identifiable {
        let id = UUID()
        var currency: String = "USD"
        var amountString: String = ""
    }
    @State private var additionalBalances: [AdditionalBalance] = []
    
    @FocusState private var isBalanceFocused: Bool
    
    let currencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("帳戶資訊") {
                    // 🔥 修正：Placeholder
                    TextField("帳戶名稱 (例如: HSBC)", text: $name)
                    
                    Picker("主幣種", selection: $currency) {
                        ForEach(currencies, id: \.self) { code in Text(code).tag(code) }
                    }
                    
                    Picker("類型", selection: $type) {
                        ForEach(AccountType.allCases) { type in Text(type.displayName).tag(type) }
                    }
                }
                
                Section("起始餘額 (\(currency))") {
                    HStack {
                        Text(currency)
                        TextField("0", text: $balanceString)
                            .keyboardType(.decimalPad)
                            .focused($isBalanceFocused)
                    }
                    if type == .creditCard || type == .debt {
                        if !balanceString.isEmpty {
                            if type == .debt {
                                Text(balanceString.hasPrefix("-") ? "負數代表：您欠對方錢 (負債)" : "正數代表：對方欠您錢 (資產)")
                                    .font(.caption).foregroundStyle(balanceString.hasPrefix("-") ? .red : .green)
                            } else {
                                if !balanceString.hasPrefix("-") {
                                    Text("提示：信用卡已用額度通常記為負數").font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
                
                Section {
                    ForEach($additionalBalances) { $item in
                        HStack {
                            Picker("", selection: $item.currency) {
                                ForEach(currencies, id: \.self) { code in Text(code).tag(code) }
                            }.labelsHidden().frame(width: 80)
                            TextField("金額", text: $item.amountString).keyboardType(.decimalPad)
                            Button(action: {
                                if let index = additionalBalances.firstIndex(where: { $0.id == item.id }) {
                                    additionalBalances.remove(at: index)
                                }
                            }) {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }.buttonStyle(.plain)
                        }
                    }
                    Button(action: {
                        let nextCurrency = currencies.first(where: { $0 != currency }) ?? "USD"
                        additionalBalances.append(AdditionalBalance(currency: nextCurrency, amountString: ""))
                    }) {
                        Label("新增其他幣種餘額", systemImage: "plus.circle")
                    }
                } header: { Text("其他幣種餘額 (選填)") } footer: { Text("這些餘額會記為「資產調整」交易，不計入收入/支出報表。") }
                
                if type == .debt && !balanceString.isEmpty && balanceString != "0" && balanceString != "-" {
                    Section("主幣種資金流向 (選填)") {
                        if myAccounts.isEmpty {
                            Text("無其他帳戶可關聯 (建議先建立現金或銀行帳戶)").font(.caption).foregroundStyle(.secondary)
                        } else {
                            let isBorrowing = balanceString.hasPrefix("-")
                            Picker(isBorrowing ? "存入至哪個帳戶" : "從哪個帳戶借出", selection: $linkedAccount) {
                                Text("不關聯 (僅記錄餘額)").tag(nil as Account?)
                                ForEach(myAccounts) { acc in Text(acc.name).tag(acc as Account?) }
                            }
                            if let linked = linkedAccount {
                                let amount = Decimal(string: balanceString) ?? 0
                                let absAmount = abs(amount)
                                if isBorrowing {
                                    Text("系統將自動建立一筆從「\(name)」轉入「\(linked.name)」的 \(currency) \(absAmount.formatted()) 交易。").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text("系統將自動建立一筆從「\(linked.name)」轉出給「\(name)」的 \(currency) \(absAmount.formatted()) 交易。").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .interactiveKeyboardDismiss()
            .navigationTitle("新增帳戶")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("儲存") { saveAccount() }.disabled(name.isEmpty) }
                ToolbarItemGroup(placement: .keyboard) {
                    if isBalanceFocused { Button("+/-") { toggleSign() } }
                    Spacer()
                    Button("完成") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
            .onChange(of: balanceString) { _, _ in
                if linkedAccount == nil && !myAccounts.isEmpty { linkedAccount = myAccounts.first }
            }
        }
    }
    
    private func toggleSign() {
        if balanceString.hasPrefix("-") { balanceString.removeFirst() }
        else { balanceString = "-" + balanceString }
    }
    
    private func saveAccount() {
        let mainBalance = Decimal(string: balanceString) ?? 0
        let initialBaseBalance = (type == .debt && linkedAccount != nil) ? 0 : mainBalance
        let nextSortOrder = (allAccounts.map(\.sortOrder).max() ?? -1) + 1
        let newAccount = Account(name: name, currency: currency, type: type, baseBalance: initialBaseBalance, sortOrder: nextSortOrder)
        modelContext.insert(newAccount)
        
        let now = Date()
        let note = "初始餘額"
        
        if type == .debt, let linked = linkedAccount, mainBalance != 0 {
            let absAmount = abs(mainBalance)
            let isBorrowing = mainBalance < 0
            let txID1 = UUID(); let txID2 = UUID()
            let transferGroupID = UUID()
            if isBorrowing {
                let debtTx = FinancialTransaction(id: txID1, amount: -absAmount, currencyCode: currency, date: now, note: "\(note) (轉至 \(linked.name))", type: .transfer, linkedTransactionID: txID2, transferGroupID: transferGroupID, transferSide: .outgoing, account: newAccount)
                let myTx = FinancialTransaction(id: txID2, amount: absAmount, currencyCode: currency, date: now, note: "\(note) (來自 \(newAccount.name))", type: .transfer, linkedTransactionID: txID1, transferGroupID: transferGroupID, transferSide: .incoming, account: linked)
                modelContext.insert(debtTx); modelContext.insert(myTx)
            } else {
                let myTx = FinancialTransaction(id: txID1, amount: -absAmount, currencyCode: currency, date: now, note: "\(note) (借給 \(newAccount.name))", type: .transfer, linkedTransactionID: txID2, transferGroupID: transferGroupID, transferSide: .outgoing, account: linked)
                let debtTx = FinancialTransaction(id: txID2, amount: absAmount, currencyCode: currency, date: now, note: "\(note) (來自 \(linked.name))", type: .transfer, linkedTransactionID: txID1, transferGroupID: transferGroupID, transferSide: .incoming, account: newAccount)
                modelContext.insert(myTx); modelContext.insert(debtTx)
            }
        }
        
        for item in additionalBalances {
            if let amount = Decimal(string: item.amountString), amount != 0 {
                let tx = FinancialTransaction(
                    amount: amount,
                    currencyCode: item.currency,
                    date: now,
                    note: "[資產調整] \(note) (\(item.currency))",
                    type: .transfer,
                    transferSide: amount >= 0 ? .incoming : .outgoing,
                    account: newAccount
                )
                modelContext.insert(tx)
            }
        }
        dismiss()
    }
}
