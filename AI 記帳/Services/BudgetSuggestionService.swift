import Foundation
import GoogleGenerativeAI

struct BudgetSuggestionItem: Identifiable, Codable, Hashable {
    let categoryId: UUID
    let suggestedAmount: Decimal
    let currencyCode: String
    let reason: String

    var id: UUID { categoryId }
}

struct BudgetSuggestionResult: Codable {
    let suggestions: [BudgetSuggestionItem]
}

struct BudgetSuggestionRequest {
    let startDate: Date
    let endDate: Date
    let targetMonthDate: Date
    let includeIncomeContext: Bool
    let mainCurrency: String
    let appTransactions: [FinancialTransaction]
    let currentBudgets: [CategoryMonthlyBudget]
    let targetCategories: [Category]
    let currencyService: CurrencyService
    let backupData: FullBackupData?
}

private struct BudgetSuggestionCategoryTarget: Codable {
    let categoryId: UUID
    let name: String
}

private struct BudgetSuggestionExistingBudget: Codable {
    let categoryId: UUID
    let categoryName: String
    let amount: Decimal
    let currencyCode: String
}

private struct BudgetSuggestionCategoryTotal: Codable {
    let categoryId: UUID?
    let categoryName: String
    let monthKey: String
    let total: Decimal
}

private struct BudgetSuggestionCurrentPeriodTotal: Codable {
    let categoryId: UUID?
    let categoryName: String
    let total: Decimal
}

private struct BudgetSuggestionPayload: Codable {
    let analysisStartDate: String
    let analysisEndDate: String
    let targetMonthKey: String
    let mainCurrency: String
    let targetCategories: [BudgetSuggestionCategoryTarget]
    let existingBudgets: [BudgetSuggestionExistingBudget]
    let appExpenseHistory: [BudgetSuggestionCategoryTotal]
    let appExpenseCurrentPeriod: [BudgetSuggestionCurrentPeriodTotal]
    let appIncomeHistory: [BudgetSuggestionCategoryTotal]?
    let appIncomeCurrentPeriod: [BudgetSuggestionCurrentPeriodTotal]?
    let backupExpenseHistory: [BudgetSuggestionCategoryTotal]?
    let backupIncomeHistory: [BudgetSuggestionCategoryTotal]?
}

enum BudgetSuggestionError: LocalizedError {
    case noTargetCategories
    case insufficientData
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noTargetCategories:
            return "目前沒有可建議的支出分類。"
        case .insufficientData:
            return "資料不足，暫時無法產生預算建議。"
        case .invalidResponse:
            return "AI 回傳格式錯誤。"
        }
    }
}

final class BudgetSuggestionService {
    static let shared = BudgetSuggestionService()

    private let keychainServiceName = "org.duckdns.lhfser.AIMoney"
    private let keychainAccountName = "gemini_api_key"
    private let legacyUserDefaultsKey = "UserGeminiAPIKey"
    private let modelName = "gemini-flash-latest"

    private init() {}

    private var apiKey: String {
        if let keychainValue = KeychainService.shared.read(service: keychainServiceName, account: keychainAccountName)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !keychainValue.isEmpty {
            return keychainValue
        }

        let legacyValue = (UserDefaults.standard.string(forKey: legacyUserDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !legacyValue.isEmpty {
            _ = KeychainService.shared.save(service: keychainServiceName, account: keychainAccountName, value: legacyValue)
            UserDefaults.standard.removeObject(forKey: legacyUserDefaultsKey)
            return legacyValue
        }

        return ""
    }

    func suggestBudgets(for request: BudgetSuggestionRequest) async throws -> [BudgetSuggestionItem] {
        guard !request.targetCategories.isEmpty else {
            throw BudgetSuggestionError.noTargetCategories
        }

        guard !apiKey.isEmpty else {
            throw NSError(domain: "Gemini", code: 401, userInfo: [NSLocalizedDescriptionKey: "未設定 API Key。"])
        }

        let payload = buildPayload(for: request)
        guard hasMeaningfulSignal(payload) else {
            throw BudgetSuggestionError.insufficientData
        }

        let payloadJSON = try encodePayload(payload)
        let prompt = buildPrompt(payloadJSON: payloadJSON)

        let service = GeminiService.shared
        let model = try service.makeModel(name: modelName)
        let response = try await model.generateContent(prompt)
        guard let text = response.text else {
            throw BudgetSuggestionError.invalidResponse
        }

        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw BudgetSuggestionError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(BudgetSuggestionResult.self, from: data)
        let validCategoryIDs = Set(request.targetCategories.map(\.id))
        return decoded.suggestions.filter { validCategoryIDs.contains($0.categoryId) && $0.suggestedAmount >= 0 }
    }

    private func buildPayload(for request: BudgetSuggestionRequest) -> BudgetSuggestionPayload {
        let targetMonthKey = BudgetService.monthKey(from: request.targetMonthDate)
        let analysisStart = request.startDate
        let analysisEnd = request.endDate

        let appExpenseHistory = summarizeAppTransactions(
            transactions: request.appTransactions,
            startDate: analysisStart,
            endDate: analysisEnd,
            transactionType: .expense,
            currencyService: request.currencyService,
            targetCurrency: request.mainCurrency
        )
        let appExpenseCurrentPeriod = summarizeCurrentPeriodTransactions(
            transactions: request.appTransactions,
            startDate: analysisStart,
            endDate: analysisEnd,
            transactionType: .expense,
            currencyService: request.currencyService,
            targetCurrency: request.mainCurrency
        )

        let appIncomeHistory = request.includeIncomeContext
            ? summarizeAppTransactions(
                transactions: request.appTransactions,
                startDate: analysisStart,
                endDate: analysisEnd,
                transactionType: .income,
                currencyService: request.currencyService,
                targetCurrency: request.mainCurrency
            )
            : nil

        let appIncomeCurrentPeriod = request.includeIncomeContext
            ? summarizeCurrentPeriodTransactions(
                transactions: request.appTransactions,
                startDate: analysisStart,
                endDate: analysisEnd,
                transactionType: .income,
                currencyService: request.currencyService,
                targetCurrency: request.mainCurrency
            )
            : nil

        let backupExpenseHistory = request.backupData.map {
            summarizeBackupTransactions(
                backupData: $0,
                startDate: analysisStart,
                endDate: analysisEnd,
                transactionTypeRawValue: TransactionType.expense.rawValue,
                targetCurrency: request.mainCurrency
            )
        }

        let backupIncomeHistory = request.includeIncomeContext ? request.backupData.map {
            summarizeBackupTransactions(
                backupData: $0,
                startDate: analysisStart,
                endDate: analysisEnd,
                transactionTypeRawValue: TransactionType.income.rawValue,
                targetCurrency: request.mainCurrency
            )
        } : nil

        let existingBudgets = request.currentBudgets
            .filter { $0.monthKey == targetMonthKey }
            .compactMap { budget -> BudgetSuggestionExistingBudget? in
                guard let category = budget.category, category.kind.supports(.expense) else { return nil }
                let normalizedAmount = request.currencyService.convert(
                    amount: budget.amount,
                    from: budget.currencyCode,
                    to: request.mainCurrency
                )
                return BudgetSuggestionExistingBudget(
                    categoryId: category.id,
                    categoryName: category.name,
                    amount: normalizedAmount,
                    currencyCode: request.mainCurrency
                )
            }

        return BudgetSuggestionPayload(
            analysisStartDate: isoDateString(analysisStart),
            analysisEndDate: isoDateString(analysisEnd),
            targetMonthKey: targetMonthKey,
            mainCurrency: request.mainCurrency,
            targetCategories: request.targetCategories.map {
                BudgetSuggestionCategoryTarget(categoryId: $0.id, name: $0.name)
            },
            existingBudgets: existingBudgets,
            appExpenseHistory: appExpenseHistory,
            appExpenseCurrentPeriod: appExpenseCurrentPeriod,
            appIncomeHistory: appIncomeHistory,
            appIncomeCurrentPeriod: appIncomeCurrentPeriod,
            backupExpenseHistory: backupExpenseHistory,
            backupIncomeHistory: backupIncomeHistory
        )
    }

    private func summarizeAppTransactions(
        transactions: [FinancialTransaction],
        startDate: Date,
        endDate: Date,
        transactionType: TransactionType,
        currencyService: CurrencyService,
        targetCurrency: String
    ) -> [BudgetSuggestionCategoryTotal] {
        let filtered = transactions.filter {
            $0.type == transactionType &&
            $0.date >= startDate &&
            $0.date <= endDate
        }

        var totals: [String: Decimal] = [:]
        var categoryIDs: [String: UUID?] = [:]
        var categoryNames: [String: String] = [:]

        for transaction in filtered {
            let monthKey = BudgetService.monthKey(from: transaction.date)
            let categoryName = transaction.category?.name ?? "未分類"
            let categoryID = transaction.category?.id
            let key = "\(monthKey)|\(categoryID?.uuidString ?? categoryName)"
            let normalizedAmount = currencyService.convert(
                amount: abs(transaction.amount),
                from: transaction.currencyCode,
                to: targetCurrency
            )
            totals[key, default: 0] += normalizedAmount
            categoryIDs[key] = categoryID
            categoryNames[key] = categoryName
        }

        return totals.map { key, total in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            return BudgetSuggestionCategoryTotal(
                categoryId: categoryIDs[key] ?? nil,
                categoryName: categoryNames[key] ?? "未分類",
                monthKey: parts.first ?? "",
                total: total
            )
        }
        .sorted {
            if $0.monthKey == $1.monthKey {
                return $0.categoryName < $1.categoryName
            }
            return $0.monthKey < $1.monthKey
        }
    }

    private func summarizeCurrentPeriodTransactions(
        transactions: [FinancialTransaction],
        startDate: Date,
        endDate: Date,
        transactionType: TransactionType,
        currencyService: CurrencyService,
        targetCurrency: String
    ) -> [BudgetSuggestionCurrentPeriodTotal] {
        let filtered = transactions.filter {
            $0.type == transactionType &&
            $0.date >= startDate &&
            $0.date <= endDate
        }

        var totals: [String: Decimal] = [:]
        var categoryIDs: [String: UUID?] = [:]
        var categoryNames: [String: String] = [:]

        for transaction in filtered {
            let categoryName = transaction.category?.name ?? "未分類"
            let key = transaction.category?.id.uuidString ?? categoryName
            let normalizedAmount = currencyService.convert(
                amount: abs(transaction.amount),
                from: transaction.currencyCode,
                to: targetCurrency
            )
            totals[key, default: 0] += normalizedAmount
            categoryIDs[key] = transaction.category?.id
            categoryNames[key] = categoryName
        }

        return totals.map { key, total in
            BudgetSuggestionCurrentPeriodTotal(
                categoryId: categoryIDs[key] ?? nil,
                categoryName: categoryNames[key] ?? "未分類",
                total: total
            )
        }
        .sorted { $0.categoryName < $1.categoryName }
    }

    private func summarizeBackupTransactions(
        backupData: FullBackupData,
        startDate: Date,
        endDate: Date,
        transactionTypeRawValue: String,
        targetCurrency: String
    ) -> [BudgetSuggestionCategoryTotal] {
        let categoryNames = Dictionary(uniqueKeysWithValues: backupData.categories.map { ($0.id, $0.name) })
        let filtered = backupData.transactions.filter {
            $0.type == transactionTypeRawValue &&
            $0.date >= startDate &&
            $0.date <= endDate
        }

        var totals: [String: Decimal] = [:]
        var names: [String: String] = [:]

        for transaction in filtered {
            let categoryName = transaction.categoryID.flatMap { categoryNames[$0] } ?? "未分類"
            let monthKey = BudgetService.monthKey(from: transaction.date)
            let key = "\(monthKey)|\(categoryName)"
            let normalizedAmount = convertBackupAmountToTargetCurrency(
                amount: abs(transaction.amount),
                from: transaction.currencyCode,
                targetCurrency: targetCurrency
            )
            totals[key, default: 0] += normalizedAmount
            names[key] = categoryName
        }

        return totals.map { key, total in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            return BudgetSuggestionCategoryTotal(
                categoryId: nil,
                categoryName: names[key] ?? "未分類",
                monthKey: parts.first ?? "",
                total: total
            )
        }
        .sorted {
            if $0.monthKey == $1.monthKey {
                return $0.categoryName < $1.categoryName
            }
            return $0.monthKey < $1.monthKey
        }
    }

    private func convertBackupAmountToTargetCurrency(amount: Decimal, from: String, targetCurrency: String) -> Decimal {
        if from.uppercased() == targetCurrency.uppercased() {
            return amount
        }
        return amount
    }

    private func hasMeaningfulSignal(_ payload: BudgetSuggestionPayload) -> Bool {
        !payload.appExpenseHistory.isEmpty ||
        !payload.appExpenseCurrentPeriod.isEmpty ||
        !(payload.backupExpenseHistory?.isEmpty ?? true)
    }

    private func encodePayload(_ payload: BudgetSuggestionPayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        guard let string = String(data: data, encoding: .utf8) else {
            throw BudgetSuggestionError.invalidResponse
        }
        return string
    }

    private func buildPrompt(payloadJSON: String) -> String {
        """
        You are an AI assistant for a personal finance app.
        Based on the summarized finance data below, suggest practical monthly budgets for the target month.

        Requirements:
        1. ONLY suggest budgets for the provided targetCategories.
        2. Income data, if present, is supporting context only. Do NOT return income categories.
        3. Use the provided mainCurrency for every suggestedAmount.
        4. Be conservative and realistic. Avoid abrupt increases unless the history clearly supports it.
        5. Keep each reason concise and in Traditional Chinese.
        6. Return strict JSON only, no Markdown.

        Output format:
        {
          "suggestions": [
            {
              "categoryId": "UUID",
              "suggestedAmount": 1234.56,
              "currencyCode": "HKD",
              "reason": "根據近月支出與本月進度的簡短原因"
            }
          ]
        }

        Finance summary:
        \(payloadJSON)
        """
    }

    private func isoDateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}
