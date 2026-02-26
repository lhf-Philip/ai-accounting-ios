import SwiftUI
import SwiftData

struct EditTransferView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // 傳入的原始交易 (通常是列表點擊的那筆)
    let originalTransaction: FinancialTransaction
    
    // 查詢關聯的另一筆交易
    @State private var linkedTransaction: FinancialTransaction?
    
    @Query(sort: \Account.name) private var accounts: [Account]
    
    // 編輯狀態
    @State private var fromAccount: Account?
    @State private var toAccount: Account?
    @State private var currencyOut: String = "HKD"
    @State private var currencyIn: String = "HKD"
    @State private var amountOutString: String = ""
    @State private var amountInString: String = ""
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var showingValidationAlert = false
    @State private var validationMessage: String = ""
    
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    @FocusState private var focusedField: Field?
    enum Field { case amountOut, amountIn, note }
    
    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    ProgressView("載入關聯交易中...")
                } else if let error = errorMessage {
                    Text("無法編輯：\(error)").foregroundStyle(.red)
                } else {
                    Section("轉出方") {
                        if let from = fromAccount {
                            HStack {
                                Text("從：\(from.name)")
                                Spacer()
                                Text(currencyOut).bold()
                            }
                            TextField("轉出金額", text: $amountOutString)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .amountOut)
                                .onChange(of: amountOutString) { _, newValue in
                                    let sanitized = sanitizePositiveDecimalInput(newValue)
                                    if sanitized != newValue {
                                        amountOutString = sanitized
                                        return
                                    }
                                    if currencyOut == currencyIn {
                                        amountInString = sanitized
                                    }
                                }
                        }
                    }
                    
                    Section("轉入方") {
                        if let to = toAccount {
                            HStack {
                                Text("到：\(to.name)")
                                Spacer()
                                Text(currencyIn).bold()
                            }
                            
                            if currencyOut != currencyIn {
                                TextField("轉入金額 (實際收到)", text: $amountInString)
                                    .keyboardType(.decimalPad)
                                    .focused($focusedField, equals: .amountIn)
                                    .onChange(of: amountInString) { _, newValue in
                                        let sanitized = sanitizePositiveDecimalInput(newValue)
                                        if sanitized != newValue {
                                            amountInString = sanitized
                                        }
                                    }
                                
                                // 🔥 匯率顯示
                                if let outVal = Double(amountOutString), let inVal = Double(amountInString), outVal > 0 {
                                    let calculatedRate = inVal / outVal
                                    let marketRate = CurrencyService.shared.getMarketRate(from: currencyOut, to: currencyIn)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("本次匯率: 1 \(currencyOut) ≈ \(calculatedRate, specifier: "%.4f") \(currencyIn)")
                                            .foregroundStyle(.blue)
                                        if let market = marketRate {
                                            Text("市場匯率: 1 \(currencyOut) ≈ \(market, specifier: "%.4f") \(currencyIn)")
                                                .foregroundStyle(.secondary).font(.caption)
                                        }
                                    }
                                }
                            } else {
                                Text("幣種相同，金額自動對應").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    Section("其他") {
                        DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        TextField("備註", text: $note)
                            .focused($focusedField, equals: .note)
                    }
                    
                    Section {
                        Text("注意：目前編輯模式暫不支援更改轉帳帳戶。如需更改帳戶，請刪除後重新建立。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("編輯轉帳")
            .alert("輸入錯誤", isPresented: $showingValidationAlert) {
                Button("確定", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { saveChanges() }
                        .disabled(isLoading || amountOutString.isEmpty)
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
        // 1. 找出這筆交易是轉出還是轉入
        // 轉出金額為負，轉入金額為正
        
        guard let linkedID = originalTransaction.linkedTransactionID else {
            errorMessage = "找不到關聯交易，資料可能已損壞。"
            isLoading = false
            return
        }
        
        // 2. 查找另一半
        let descriptor = FetchDescriptor<FinancialTransaction>(predicate: #Predicate { $0.id == linkedID })
        do {
            if let linked = try modelContext.fetch(descriptor).first {
                self.linkedTransaction = linked
                
                // 3. 判定誰是轉出，誰是轉入
                let tx1 = originalTransaction
                let tx2 = linked
                
                var outTx: FinancialTransaction
                var inTx: FinancialTransaction
                
                // 邏輯：金額小於0是轉出，大於0是轉入
                if tx1.amount < 0 {
                    outTx = tx1; inTx = tx2
                } else {
                    outTx = tx2; inTx = tx1
                }
                
                self.fromAccount = outTx.account
                self.toAccount = inTx.account
                self.currencyOut = outTx.currencyCode.isEmpty ? (outTx.account?.currency ?? "HKD") : outTx.currencyCode
                self.currencyIn = inTx.currencyCode.isEmpty ? (inTx.account?.currency ?? "HKD") : inTx.currencyCode
                
                // 設定初始值 (轉出顯示正數)
                self.amountOutString = "\(abs(outTx.amount))"
                self.amountInString = "\(abs(inTx.amount))"
                self.date = tx1.date
                
                // 備註處理 (去除系統自動加的後綴)
                let rawNote = tx1.note
                    .components(separatedBy: " (轉至").first?
                    .components(separatedBy: " (來自").first?
                    .components(separatedBy: " (借入").first?
                    .components(separatedBy: " (還款").first ?? ""
                self.note = rawNote
                
                isLoading = false
            } else {
                errorMessage = "找不到關聯交易記錄。"
                isLoading = false
            }
        } catch {
            errorMessage = "讀取錯誤: \(error)"
            isLoading = false
        }
    }
    
    private func saveChanges() {
        guard let outTx = (originalTransaction.amount < 0 ? originalTransaction : linkedTransaction),
              let inTx = (originalTransaction.amount > 0 ? originalTransaction : linkedTransaction),
              let to = toAccount, let from = fromAccount
        else { return }
        
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
        
        let normalizedAmountOut = abs(amountOut)
        let normalizedAmountIn = abs(amountIn)
        
        // 更新轉出
        outTx.amount = -normalizedAmountOut
        outTx.currencyCode = currencyOut
        outTx.date = date
        outTx.note = note.isEmpty ? "轉帳 (轉至 \(to.name))" : "\(note) (轉至 \(to.name))"
        outTx.transferSide = .outgoing
        outTx.updatedAt = Date()
        
        // 更新轉入
        inTx.amount = normalizedAmountIn
        inTx.currencyCode = currencyIn
        inTx.date = date
        inTx.note = note.isEmpty ? "轉帳 (來自 \(from.name))" : "\(note) (來自 \(from.name))"
        inTx.transferSide = .incoming
        inTx.updatedAt = Date()
        
        if outTx.transferGroupID == nil && inTx.transferGroupID == nil {
            let groupID = UUID()
            outTx.transferGroupID = groupID
            inTx.transferGroupID = groupID
        } else if outTx.transferGroupID == nil {
            outTx.transferGroupID = inTx.transferGroupID
        } else if inTx.transferGroupID == nil {
            inTx.transferGroupID = outTx.transferGroupID
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
