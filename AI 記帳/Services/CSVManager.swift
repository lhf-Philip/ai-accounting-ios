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

        var csvString = "Date,Type,Amount,Currency,Category,Account,Note,Tags\n"

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        for tx in transactions {
            let date = formatter.string(from: tx.date)
            let type = tx.type.rawValue
            let amount = "\(tx.amount)"
            let currency = tx.currencyCode
            let category = tx.category?.name ?? "Uncategorized"
            let account = tx.account?.name ?? "Unknown"
            let note = tx.note
                .replacingOccurrences(of: ",", with: "，")
                .replacingOccurrences(of: "\n", with: " ")
            let tags = tx.tags.map { $0.name }.joined(separator: "|")

            csvString.append("\(date),\(type),\(amount),\(currency),\(category),\(account),\(note),\(tags)\n")
        }

        return csvString
    }
}
