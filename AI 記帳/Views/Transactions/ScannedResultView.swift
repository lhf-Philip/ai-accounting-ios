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
    @State private var saveErrorMessage: String?
    @State private var amountString: String = ""
    @State private var selectedAccount: Account?
    @State private var selectedCategory: Category?
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var selectedTags: Set<Tag> = []

    private var selectableAccounts: [Account] {
        TransactionSemantics.ownAccounts(from: accounts)
    }

    var body: some View {
        Form {
            Section("AI 識別結果 (請確認)") {
                HStack {
                    Text(info.currency)
                    TextField("金額", text: $amountString)
                        .keyboardType(.decimalPad)
                }
                DatePicker("日期時間", selection: $date, displayedComponents: [.date, .hourAndMinute])
                TextField("商戶/備註", text: $note)
            }

            Section("帳戶與分類") {
                Picker("帳戶", selection: $selectedAccount) {
                    Text("選擇帳戶").tag(nil as Account?)
                    ForEach(selectableAccounts) { acc in Text(acc.name).tag(acc as Account?) }
                }

                Picker("分類", selection: $selectedCategory) {
                    Text("選擇分類").tag(nil as Category?)
                    ForEach(expenseCategories) { cat in
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
        .standardKeyboardBehavior()
        .navigationTitle("確認資料")
        .toolbar {
            Button("儲存") {
                saveTransaction()
            }
            .disabled(selectedAccount == nil || amountString.isEmpty)
        }
        .alert("儲存失敗", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("確定", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .onAppear {
            // 填充 AI 資料
            amountString = "\(info.amount)"
            note = "\(info.merchant) - \(info.note)"

            date = parseDateTime(info: info) ?? Date()

            // 嘗試自動匹配分類
            if let match = matchCategory(named: info.categoryName) {
                selectedCategory = match
            }

            // 預設帳戶
            if let first = selectableAccounts.first {
                selectedAccount = first
            }
        }
    }

    private func saveTransaction() {
        guard let amount = Decimal(string: amountString),
              let account = selectedAccount else { return }

        let txCurrency = normalizedCurrencyCode(info.currency, fallback: account.currency)

        let draft = OrdinaryTransactionEditDraft(
            amount: abs(amount), currencyCode: txCurrency, date: date, note: note,
            type: .expense, account: account, category: selectedCategory, tags: Array(selectedTags)
        )
        do {
            try LedgerMutationService.add([draft], modelContext: modelContext)
        } catch {
            saveErrorMessage = error.localizedDescription
            return
        }

        // 這裡需要連續 dismiss 兩次 (回到主頁)，或者使用 Binding 控制
        // 簡單做法：發送 Notification 讓 ContentView 關閉 Sheet
        NotificationCenter.default.post(name: NSNotification.Name("CloseAddFlow"), object: nil)
    }

    private func normalizedCurrencyCode(_ raw: String, fallback: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        switch value {
        case "HKD", "HK$", "H$":
            return "HKD"
        case "USD", "US$", "$":
            return "USD"
        case "TWD", "NT$", "NTD":
            return "TWD"
        case "JPY", "¥":
            return "JPY"
        case "CNY", "RMB", "CN¥":
            return "CNY"
        case "EUR", "€":
            return "EUR"
        case "GBP", "£":
            return "GBP"
        default:
            if value.count == 3, value.allSatisfy(\.isLetter) {
                return value
            }
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
    }

    private var expenseCategories: [Category] {
        categories.filter { $0.kind.supports(.expense) }
    }

    private func parseDateTime(info: ReceiptInfo) -> Date? {
        let rawDate = info.date.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTime = info.time?.trimmingCharacters(in: .whitespacesAndNewlines)

        let dateTimeFormats = [
            "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm"
        ]
        for format in dateTimeFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let parsed = formatter.date(from: rawDate) {
                return parsed
            }
        }

        let dateFormats = ["yyyy-MM-dd", "yyyy/MM/dd"]
        for format in dateFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let parsedDate = formatter.date(from: rawDate) {
                guard let rawTime, !rawTime.isEmpty else { return parsedDate }

                let timeFormatter = DateFormatter()
                timeFormatter.locale = Locale(identifier: "en_US_POSIX")
                timeFormatter.dateFormat = "HH:mm"
                if let parsedTime = timeFormatter.date(from: rawTime) {
                    let calendar = Calendar.current
                    let dateComponents = calendar.dateComponents([.year, .month, .day], from: parsedDate)
                    let timeComponents = calendar.dateComponents([.hour, .minute], from: parsedTime)
                    return calendar.date(from: DateComponents(
                        year: dateComponents.year,
                        month: dateComponents.month,
                        day: dateComponents.day,
                        hour: timeComponents.hour,
                        minute: timeComponents.minute
                    ))
                }
                return parsedDate
            }
        }

        return nil
    }

    private func matchCategory(named name: String) -> Category? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let exact = expenseCategories.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact
        }

        return expenseCategories.first(where: { category in
            category.name.localizedCaseInsensitiveContains(trimmed)
                || trimmed.localizedCaseInsensitiveContains(category.name)
        })
    }
}
