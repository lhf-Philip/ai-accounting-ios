import SwiftUI
import SwiftData

struct CSVManager {
    static let shared = CSVManager()
    
    private init() {}
    
    // MARK: - 生成 CSV
    @MainActor
    func generateCSV(modelContext: ModelContext) -> String {
        let descriptor = FetchDescriptor<FinancialTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let transactions = try? modelContext.fetch(descriptor) else { return "" }
        
        // 標題列：確保包含 Currency Code
        var csvString = "Date,Type,Amount,Currency,Category,Account,Note,Tags\n"
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        for tx in transactions {
            let date = formatter.string(from: tx.date)
            let type = tx.type.rawValue
            let amount = "\(tx.amount)"
            // 🔥 匯出時務必記錄交易當下的幣種
            let currency = tx.currencyCode
            let category = tx.category?.name ?? "Uncategorized"
            let account = tx.account?.name ?? "Unknown"
            let note = tx.note.replacingOccurrences(of: ",", with: "，").replacingOccurrences(of: "\n", with: " ")
            let tags = tx.tags.map { $0.name }.joined(separator: "|")
            
            let line = "\(date),\(type),\(amount),\(currency),\(category),\(account),\(note),\(tags)\n"
            csvString.append(line)
        }
        return csvString
    }
    
    // MARK: - 匯入 CSV (修復幣種錯亂問題)
    @MainActor
    func importCSV(url: URL, modelContext: ModelContext) throws {
        let data = try String(contentsOf: url, encoding: .utf8)
        var rows = parseCSVRows(data)
        guard rows.count > 1 else { return }
        rows.removeFirst() // 移除標題
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        // 預取現有資料
        var accounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
        var categories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        var tags = (try? modelContext.fetch(FetchDescriptor<Tag>())) ?? []
        var nextSortOrder = (accounts.map(\.sortOrder).max() ?? -1) + 1
        
        for cols in rows {
            if cols.count < 7 { continue }
            
            guard let date = formatter.date(from: cols[0]),
                  let amount = Decimal(string: cols[2]) else { continue }
            
            let typeString = cols[1]
            let type = TransactionType(rawValue: typeString) ?? .expense
            // CSV 欄位: 0:Date, 1:Type, 2:Amount, 3:Currency, 4:Category, 5:Account, 6:Note, 7:Tags
            let csvCurrency = cols[3]
            let categoryName = cols[4]
            let accountName = cols[5]
            let note = cols[6]
            let tagString = cols.count > 7 ? cols[7] : ""
            
            // 1. 重複檢測
            let duplicateDescriptor = FetchDescriptor<FinancialTransaction>(
                predicate: #Predicate { $0.date == date && $0.amount == amount && $0.note == note }
            )
            if let count = try? modelContext.fetchCount(duplicateDescriptor), count > 0 {
                continue
            }
            
            // 2. 處理帳戶
            var account = accounts.first(where: { $0.name == accountName })
            if account == nil {
                // 如果是新帳戶，這裡預設建立為 HKD，這可能是潛在問題點
                // 但如果 CSV 的 currency 欄位有值，我們應該用 CSV 的
                let initialCurrency = csvCurrency.isEmpty ? "HKD" : csvCurrency
                
                let newAcc = Account(name: accountName, currency: initialCurrency, type: .cash, baseBalance: 0, sortOrder: nextSortOrder)
                modelContext.insert(newAcc)
                account = newAcc
                accounts.append(newAcc)
                nextSortOrder += 1
            }
            
            // 3. 處理分類
            var category = categories.first(where: { $0.name == categoryName && $0.kind.supports(type) })
            if category == nil && categoryName != "Uncategorized" {
                let inferredKind: CategoryKind
                switch type {
                case .income:
                    inferredKind = .income
                case .expense:
                    inferredKind = .expense
                case .transfer:
                    inferredKind = .both
                }
                let newCat = Category(name: categoryName, icon: "tag", colorHex: "808080", kind: inferredKind)
                modelContext.insert(newCat)
                category = newCat
                categories.append(newCat)
            }
            
            // 4. 處理標籤
            var txTags: [Tag] = []
            if !tagString.isEmpty {
                for tName in tagString.components(separatedBy: "|") {
                    if let t = tags.first(where: { $0.name == tName }) {
                        txTags.append(t)
                    } else {
                        let newTag = Tag(name: tName)
                        modelContext.insert(newTag)
                        txTags.append(newTag)
                        tags.append(newTag)
                    }
                }
            }
            
            // 🔥 關鍵修復：決定交易幣種
            // 邏輯：
            // 1. 如果 CSV 裡有寫幣種，且不是 "HKD" (假設這是預設)，就用 CSV 的。
            // 2. 如果 CSV 裡沒寫，或者寫的是預設值，但帳戶本身是外幣帳戶 (例如 USD)，
            //    那麼這筆交易大概率就是該外幣交易，強制繼承帳戶的幣種。
            
            var finalCurrencyCode = csvCurrency
            
            if let acc = account {
                // 如果 CSV 幣種是空的，或者 CSV 說是 HKD 但帳戶其實是 USD/JPY...
                // 我們假設這筆交易屬於該帳戶的本幣交易
                if (csvCurrency.isEmpty || csvCurrency == "HKD") && acc.currency != "HKD" {
                    finalCurrencyCode = acc.currency
                }
            }
            
            // 雙重保險：如果還是空的，設為 HKD
            if finalCurrencyCode.isEmpty { finalCurrencyCode = "HKD" }
            
            let tx = FinancialTransaction(
                amount: amount,
                currencyCode: finalCurrencyCode, // 使用修正後的幣種
                date: date,
                note: note,
                type: type,
                account: account,
                category: category,
                tags: txTags
            )
            modelContext.insert(tx)
        }
    }
    
    private func parseCSVRows(_ input: String) -> [[String]] {
        let text = input.replacingOccurrences(of: "\u{FEFF}", with: "")
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            
            if ch == "\"" {
                let next = text.index(after: index)
                if inQuotes && next < text.endIndex && text[next] == "\"" {
                    field.append("\"")
                    index = next
                } else {
                    inQuotes.toggle()
                }
            } else if ch == "," && !inQuotes {
                row.append(field)
                field = ""
            } else if (ch == "\n" || ch == "\r") && !inQuotes {
                row.append(field)
                field = ""
                
                if !row.allSatisfy(\.isEmpty) {
                    rows.append(row)
                }
                row = []
                
                if ch == "\r" {
                    let next = text.index(after: index)
                    if next < text.endIndex && text[next] == "\n" {
                        index = next
                    }
                }
            } else {
                field.append(ch)
            }
            
            index = text.index(after: index)
        }
        
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            if !row.allSatisfy(\.isEmpty) {
                rows.append(row)
            }
        }
        
        return rows
    }
}
