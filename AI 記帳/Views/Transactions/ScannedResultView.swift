import SwiftUI
import SwiftData

struct ScannedResultView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss // dismiss 當前視圖
    
    // 為了能夠直接關閉整個掃描流程回到主頁，我們可能需要回調
    // 這裡簡單處理：存檔後發送通知或使用 NavigationPath (如果你的 App 架構支援)
    // 這裡示範存檔後 dismiss 到根視圖的簡單做法：
    
    let info: ReceiptInfo
    let receiptImage: UIImage
    
    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @Query private var tags: [Tag]
    
    // 表單狀態
    @State private var amountString: String = ""
    @State private var selectedCurrency: String = "HKD"
    @State private var currencyMessage: String = ""
    @State private var currencyFromAI: Bool = true
    @State private var selectedAccount: Account?
    @State private var selectedCategory: Category?
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var selectedTags: Set<Tag> = []
    
    private let supportedCurrencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]
    
    var body: some View {
        Form {
            Section("AI 識別結果 (請確認)") {
                HStack {
                    Picker("幣種", selection: $selectedCurrency) {
                        ForEach(supportedCurrencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                    
                    TextField("金額", text: $amountString)
                        .keyboardType(.decimalPad)
                }
                
                Text(currencyMessage)
                    .font(.caption)
                    .foregroundStyle(currencyFromAI ? .secondary : .orange)
                
                DatePicker("日期", selection: $date)
                TextField("商戶/備註", text: $note)
            }
            
            Section("帳戶與分類") {
                Picker("帳戶", selection: $selectedAccount) {
                    Text("選擇帳戶").tag(nil as Account?)
                    ForEach(accounts) { acc in Text(acc.name).tag(acc as Account?) }
                }
                .onChange(of: selectedAccount) {
                    applyCurrencyRule()
                }
                
                Picker("分類", selection: $selectedCategory) {
                    Text("選擇分類").tag(nil as Category?)
                    ForEach(categories) { cat in
                        HStack {
                            Image(systemName: cat.icon)
                            Text(cat.name)
                        }.tag(cat as Category?)
                    }
                }
            }
            
            Section("圖片存檔") {
                Image(uiImage: receiptImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .cornerRadius(8)
                Text("圖片將不會被儲存到相簿，僅用於此次識別。(如需儲存圖片功能需另外開發文件系統)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("確認資料")
        .toolbar {
            Button("儲存") {
                saveTransaction()
            }
            .disabled(selectedAccount == nil || amountString.isEmpty)
        }
        .onAppear {
            // 填充 AI 資料
            amountString = "\(info.amount)"
            note = "\(info.merchant) - \(info.note)"
            
            // 嘗試解析日期
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let dateObj = formatter.date(from: info.date) {
                date = dateObj
            }
            
            // 嘗試自動匹配分類
            if let match = categories.first(where: { $0.name == info.categoryName }) {
                selectedCategory = match
            }
            
            // 預設帳戶
            if let first = accounts.first {
                selectedAccount = first
            }
            
            applyCurrencyRule()
        }
    }
    
    private func saveTransaction() {
        guard let amount = Decimal(string: amountString),
              let account = selectedAccount else { return }
        
        let tx = FinancialTransaction(
            amount: -abs(amount), // 預設為支出
            currencyCode: selectedCurrency,
            date: date,
            note: note,
            type: .expense,
            account: account,
            category: selectedCategory,
            tags: Array(selectedTags)
            // photoPath: 如果你有實作圖片儲存，這裡可以存檔名
        )
        
        modelContext.insert(tx)
        
        // 這裡需要連續 dismiss 兩次 (回到主頁)，或者使用 Binding 控制
        // 簡單做法：發送 Notification 讓 ContentView 關閉 Sheet
        NotificationCenter.default.post(name: NSNotification.Name("CloseAddFlow"), object: nil)
    }
    
    private func applyCurrencyRule() {
        let rawAICurrency = info.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        if supportedCurrencies.contains(rawAICurrency) {
            selectedCurrency = rawAICurrency
            currencyFromAI = true
            currencyMessage = "幣種來源：AI 辨識 (\(rawAICurrency))"
            return
        }
        
        currencyFromAI = false
        if let accountCurrency = selectedAccount?.currency, supportedCurrencies.contains(accountCurrency) {
            selectedCurrency = accountCurrency
            currencyMessage = "AI 幣種無效，已改用帳戶幣種：\(accountCurrency)"
        } else {
            selectedCurrency = "HKD"
            currencyMessage = "AI 幣種無效，已改用預設幣種：HKD"
        }
    }
}
