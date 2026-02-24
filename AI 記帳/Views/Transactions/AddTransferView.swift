import SwiftUI
import SwiftData

struct AddTransferView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Account.name) private var accounts: [Account]
    
    @State private var fromAccount: Account?
    @State private var toAccount: Account?
    
    // 🔥 新增：獨立的幣種選擇，不綁死帳戶
    @State private var currencyOut: String = "HKD"
    @State private var currencyIn: String = "HKD"
    
    @State private var amountOutString: String = "" // 轉出金額
    @State private var amountInString: String = ""  // 轉入金額
    @State private var date: Date = Date()
    @State private var note: String = ""
    
    let currencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]
    
    // 焦點控制
    @FocusState private var focusedField: Field?
    enum Field {
        case amountOut, amountIn, note
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - 轉出方
                Section("轉出方 (支出)") {
                    Picker("從帳戶", selection: $fromAccount) {
                        Text("選擇帳戶").tag(nil as Account?)
                        ForEach(accounts.filter { !$0.isArchived }) { acc in Text(acc.name).tag(acc as Account?) }
                    }
                    .onChange(of: fromAccount) {
                        if let acc = fromAccount { currencyOut = acc.currency }
                    }
                    
                    if let _ = fromAccount {
                        HStack {
                            // 轉出幣種選擇
                            Picker("", selection: $currencyOut) {
                                ForEach(currencies, id: \.self) { code in Text(code).tag(code) }
                            }
                            .labelsHidden().frame(width: 80)
                            
                            TextField("轉出金額", text: $amountOutString)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .amountOut)
                                .onChange(of: amountOutString) { _, _ in
                                    // 若幣種相同，自動同步輸入
                                    if currencyOut == currencyIn {
                                        amountInString = amountOutString
                                    }
                                }
                        }
                    }
                }
                
                // MARK: - 轉入方
                Section("轉入方 (收入)") {
                    Picker("到帳戶", selection: $toAccount) {
                        Text("選擇帳戶").tag(nil as Account?)
                        ForEach(accounts.filter { $0 != fromAccount }) { acc in
                            Text(acc.name).tag(acc as Account?)
                        }
                    }
                    .onChange(of: toAccount) {
                        if let acc = toAccount { currencyIn = acc.currency }
                    }
                    
                    if let _ = toAccount {
                        HStack {
                            // 轉入幣種選擇
                            Picker("", selection: $currencyIn) {
                                ForEach(currencies, id: \.self) { code in Text(code).tag(code) }
                            }
                            .labelsHidden().frame(width: 80)
                            
                            TextField("轉入金額 (實收)", text: $amountInString)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .amountIn)
                        }
                        
                        // 雙幣種匯率顯示
                        if currencyOut != currencyIn {
                            if let outVal = Double(amountOutString), let inVal = Double(amountInString), outVal > 0 {
                                let calculatedRate = inVal / outVal
                                let marketRate = CurrencyService.shared.getMarketRate(from: currencyOut, to: currencyIn)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("交易匯率: 1 \(currencyOut) ≈ \(calculatedRate, specifier: "%.4f") \(currencyIn)")
                                        .foregroundStyle(.blue)
                                    
                                    if let market = marketRate {
                                        Text("市場匯率: 1 \(currencyOut) ≈ \(market, specifier: "%.4f") \(currencyIn)")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                    }
                                }
                            }
                        } else {
                            Text("幣種相同，金額自動對應")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("其他") {
                    DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    TextField("備註", text: $note)
                        .focused($focusedField, equals: .note)
                }
            }
            .navigationTitle("轉帳")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("確認") { saveTransfer() }
                        .disabled(fromAccount == nil || toAccount == nil || amountOutString.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedField = nil }
                }
            }
        }
    }
    
    private func saveTransfer() {
        guard let from = fromAccount, let to = toAccount,
              let amountOut = Decimal(string: amountOutString) else { return }
        
        var amountIn = amountOut
        if currencyOut != currencyIn, let customIn = Decimal(string: amountInString) {
            amountIn = customIn
        }
        
        let txID1 = UUID()
        let txID2 = UUID()
        let memo = note.isEmpty ? "轉帳" : note
        
        // 1. 轉出 (支出) - 使用 currencyOut
        let outTx = FinancialTransaction(
            id: txID1,
            amount: -amountOut,
            currencyCode: currencyOut, // 🔥 明確指定轉出幣種
            date: date,
            note: "\(memo) (轉至 \(to.name))",
            type: .transfer,
            linkedTransactionID: txID2,
            account: from
        )
        
        // 2. 轉入 (收入) - 使用 currencyIn
        let inTx = FinancialTransaction(
            id: txID2,
            amount: amountIn,
            currencyCode: currencyIn, // 🔥 明確指定轉入幣種
            date: date,
            note: "\(memo) (來自 \(from.name))",
            type: .transfer,
            linkedTransactionID: txID1,
            account: to
        )
        
        modelContext.insert(outTx)
        modelContext.insert(inTx)
        try? modelContext.save()
        
        dismiss()
    }
}
