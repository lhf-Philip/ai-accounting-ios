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
    let budgetHistories: [BudgetMonthlyHistory]
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

private struct BudgetSuggestionMonthlyHistoryPayload: Codable {
    let categoryId: UUID
    let categoryName: String
    let monthKey: String
    let budgetAmount: Decimal
    let spentAmount: Decimal
    let remainingAmount: Decimal
    let usageRatio: Decimal
    let isOverBudget: Bool
    let currencyCode: String
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
    let appExpenseBudgetHistory: [BudgetSuggestionMonthlyHistoryPayload]
    let appExpenseCurrentPeriod: [BudgetSuggestionCurrentPeriodTotal]
    let appIncomeHistory: [BudgetSuggestionCategoryTotal]?
    let appIncomeCurrentPeriod: [BudgetSuggestionCurrentPeriodTotal]?
    let backupExpenseBudgetHistory: [BudgetSuggestionMonthlyHistoryPayload]?
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
        do {
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
        } catch {
            throw mappedAIError(from: error)
        }
    }

    private func buildPayload(for request: BudgetSuggestionRequest) -> BudgetSuggestionPayload {
        let targetMonthKey = BudgetService.monthKey(from: request.targetMonthDate)
        let analysisStart = request.startDate
        let analysisEnd = request.endDate

        let appExpenseHistory = summarizeAppBudgetHistory(for: request)
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
            summarizeBackupBudgetHistory(
                backupData: $0,
                startDate: analysisStart,
                endDate: analysisEnd,
                targetCurrency: request.mainCurrency,
                currencyService: request.currencyService
            )
        }

        let backupIncomeHistory = request.includeIncomeContext ? request.backupData.map {
            summarizeBackupTransactions(
                backupData: $0,
                startDate: analysisStart,
                endDate: analysisEnd,
                transactionTypeRawValue: TransactionType.income.rawValue,
                targetCurrency: request.mainCurrency,
                currencyService: request.currencyService
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
            appExpenseBudgetHistory: appExpenseHistory,
            appExpenseCurrentPeriod: appExpenseCurrentPeriod,
            appIncomeHistory: appIncomeHistory,
            appIncomeCurrentPeriod: appIncomeCurrentPeriod,
            backupExpenseBudgetHistory: backupExpenseHistory,
            backupIncomeHistory: backupIncomeHistory
        )
    }

    private func summarizeAppBudgetHistory(for request: BudgetSuggestionRequest) -> [BudgetSuggestionMonthlyHistoryPayload] {
        let relevantHistory = request.budgetHistories.filter { history in
            guard monthKeyInRange(history.monthKey, startDate: request.startDate, endDate: request.endDate) else {
                return false
            }
            return request.targetCategories.contains { $0.id == history.categoryID }
        }

        if !relevantHistory.isEmpty {
            return relevantHistory
                .map {
                    BudgetSuggestionMonthlyHistoryPayload(
                        categoryId: $0.categoryID,
                        categoryName: $0.categoryNameSnapshot,
                        monthKey: $0.monthKey,
                        budgetAmount: request.currencyService.convert(amount: $0.budgetAmount, from: $0.currencyCode, to: request.mainCurrency),
                        spentAmount: request.currencyService.convert(amount: $0.spentAmount, from: $0.currencyCode, to: request.mainCurrency),
                        remainingAmount: request.currencyService.convert(amount: $0.remainingAmount, from: $0.currencyCode, to: request.mainCurrency),
                        usageRatio: $0.usageRatio,
                        isOverBudget: $0.isOverBudget,
                        currencyCode: request.mainCurrency
                    )
                }
                .sorted {
                    if $0.monthKey == $1.monthKey {
                        return $0.categoryName < $1.categoryName
                    }
                    return $0.monthKey < $1.monthKey
                }
        }

        return synthesizeBudgetHistoryFromAppData(for: request)
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

    private func synthesizeBudgetHistoryFromAppData(for request: BudgetSuggestionRequest) -> [BudgetSuggestionMonthlyHistoryPayload] {
        request.currentBudgets
            .filter { budget in
                budget.isEnabled &&
                monthKeyInRange(budget.monthKey, startDate: request.startDate, endDate: request.endDate) &&
                request.targetCategories.contains { $0.id == budget.category?.id }
            }
            .compactMap { budget -> BudgetSuggestionMonthlyHistoryPayload? in
                guard let category = budget.category else { return nil }

                let spent = request.appTransactions
                    .filter { transaction in
                        transaction.type == .expense &&
                        BudgetService.monthKey(from: transaction.date) == budget.monthKey &&
                        transaction.category?.id == category.id
                    }
                    .reduce(Decimal.zero) { partial, transaction in
                        partial + request.currencyService.convert(
                            amount: abs(transaction.amount),
                            from: transaction.currencyCode,
                            to: budget.currencyCode
                        )
                    }

                let remaining = budget.amount - spent
                let ratio: Decimal = budget.amount > 0 ? (spent / budget.amount) : 0

                return BudgetSuggestionMonthlyHistoryPayload(
                    categoryId: category.id,
                    categoryName: category.name,
                    monthKey: budget.monthKey,
                    budgetAmount: request.currencyService.convert(amount: budget.amount, from: budget.currencyCode, to: request.mainCurrency),
                    spentAmount: request.currencyService.convert(amount: spent, from: budget.currencyCode, to: request.mainCurrency),
                    remainingAmount: request.currencyService.convert(amount: remaining, from: budget.currencyCode, to: request.mainCurrency),
                    usageRatio: ratio,
                    isOverBudget: remaining < 0,
                    currencyCode: request.mainCurrency
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
        targetCurrency: String,
        currencyService: CurrencyService
    ) -> [BudgetSuggestionCategoryTotal] {
        let categoryNames = Dictionary(uniqueKeysWithValues: backupData.categories.map { ($0.id, $0.name) })
        let filtered = backupData.transactions.filter {
            $0.type == transactionTypeRawValue &&
            $0.date >= startDate &&
            $0.date <= endDate
        }

        var totals: [String: Decimal] = [:]
        var categoryIDs: [String: UUID?] = [:]
        var categoryNamesByKey: [String: String] = [:]

        for transaction in filtered {
            let monthKey = BudgetService.monthKey(from: transaction.date)
            let categoryName = transaction.categoryID.flatMap { categoryNames[$0] } ?? "未分類"
            let key = "\(monthKey)|\(transaction.categoryID?.uuidString ?? categoryName)"
            let normalizedAmount = currencyService.convert(
                amount: abs(transaction.amount),
                from: transaction.currencyCode,
                to: targetCurrency
            )
            totals[key, default: 0] += normalizedAmount
            categoryIDs[key] = transaction.categoryID
            categoryNamesByKey[key] = categoryName
        }

        return totals.map { key, total in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            return BudgetSuggestionCategoryTotal(
                categoryId: categoryIDs[key] ?? nil,
                categoryName: categoryNamesByKey[key] ?? "未分類",
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

    private func summarizeBackupBudgetHistory(
        backupData: FullBackupData,
        startDate: Date,
        endDate: Date,
        targetCurrency: String,
        currencyService: CurrencyService
    ) -> [BudgetSuggestionMonthlyHistoryPayload] {
        if let history = backupData.budgetHistory, !history.isEmpty {
            return history
                .filter { monthKeyInRange($0.monthKey, startDate: startDate, endDate: endDate) }
                .map {
                    BudgetSuggestionMonthlyHistoryPayload(
                        categoryId: $0.categoryID,
                        categoryName: $0.categoryNameSnapshot,
                        monthKey: $0.monthKey,
                        budgetAmount: currencyService.convert(amount: $0.budgetAmount, from: $0.currencyCode, to: targetCurrency),
                        spentAmount: currencyService.convert(amount: $0.spentAmount, from: $0.currencyCode, to: targetCurrency),
                        remainingAmount: currencyService.convert(amount: $0.remainingAmount, from: $0.currencyCode, to: targetCurrency),
                        usageRatio: $0.usageRatio,
                        isOverBudget: $0.isOverBudget,
                        currencyCode: targetCurrency
                    )
                }
                .sorted {
                    if $0.monthKey == $1.monthKey {
                        return $0.categoryName < $1.categoryName
                    }
                    return $0.monthKey < $1.monthKey
                }
        }

        let categoryNames = Dictionary(uniqueKeysWithValues: backupData.categories.map { ($0.id, $0.name) })

        return (backupData.budgets ?? [])
            .filter { ($0.isEnabled ?? true) && monthKeyInRange($0.monthKey, startDate: startDate, endDate: endDate) }
            .compactMap { budget -> BudgetSuggestionMonthlyHistoryPayload? in
                guard let categoryID = budget.categoryID else { return nil }
                let categoryName = categoryNames[categoryID] ?? "未分類"
                let spentAmount = backupData.transactions
                    .filter { transaction in
                        transaction.type == TransactionType.expense.rawValue &&
                        BudgetService.monthKey(from: transaction.date) == budget.monthKey &&
                        transaction.categoryID == categoryID
                    }
                    .reduce(Decimal.zero) { partial, transaction in
                        partial + currencyService.convert(amount: abs(transaction.amount), from: transaction.currencyCode, to: budget.currencyCode)
                    }
                let remainingAmount = budget.amount - spentAmount
                let usageRatio: Decimal = budget.amount > 0 ? (spentAmount / budget.amount) : 0

                return BudgetSuggestionMonthlyHistoryPayload(
                    categoryId: categoryID,
                    categoryName: categoryName,
                    monthKey: budget.monthKey,
                    budgetAmount: currencyService.convert(amount: budget.amount, from: budget.currencyCode, to: targetCurrency),
                    spentAmount: currencyService.convert(amount: spentAmount, from: budget.currencyCode, to: targetCurrency),
                    remainingAmount: currencyService.convert(amount: remainingAmount, from: budget.currencyCode, to: targetCurrency),
                    usageRatio: usageRatio,
                    isOverBudget: remainingAmount < 0,
                    currencyCode: targetCurrency
                )
            }
            .sorted {
                if $0.monthKey == $1.monthKey {
                    return $0.categoryName < $1.categoryName
                }
                return $0.monthKey < $1.monthKey
            }
    }

    private func monthKeyInRange(_ monthKey: String, startDate: Date, endDate: Date) -> Bool {
        guard let monthStart = BudgetService.monthStart(from: monthKey) else { return false }
        let rangeStart = Calendar.current.startOfDay(for: startDate)
        let rangeEnd = Calendar.current.startOfDay(for: endDate)
        return monthStart >= rangeStart && monthStart <= rangeEnd
    }

    private func hasMeaningfulSignal(_ payload: BudgetSuggestionPayload) -> Bool {
        !payload.appExpenseBudgetHistory.isEmpty ||
        !payload.appExpenseCurrentPeriod.isEmpty ||
        !(payload.backupExpenseBudgetHistory?.isEmpty ?? true)
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
        Based on the summarized finance data below, especially the historical monthly budget usage, suggest practical monthly budgets for the target month.

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

    private func mappedAIError(from error: Error) -> Error {
        guard let generateError = error as? GenerateContentError else {
            return error
        }

        switch generateError {
        case .invalidAPIKey(let message):
            return NSError(
                domain: "Gemini",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Gemini API Key 無效：\(message)"]
            )
        case .unsupportedUserLocation:
            return NSError(
                domain: "Gemini",
                code: 451,
                userInfo: [NSLocalizedDescriptionKey: "目前所在網路區域不支援 Gemini API。請確認 VPN 已連線並重試。"]
            )
        case .promptBlocked:
            return NSError(
                domain: "Gemini",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Gemini 拒絕了這次預算分析請求。請縮短分析時間範圍，或先不要加入收入資料與 JSON 備份再試。"]
            )
        case .responseStoppedEarly(let reason, _):
            return NSError(
                domain: "Gemini",
                code: 499,
                userInfo: [NSLocalizedDescriptionKey: "Gemini 回應中途停止（\(reason)）。請再試一次。"]
            )
        case .promptImageContentError:
            return NSError(
                domain: "Gemini",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "AI 預算建議請求格式錯誤。請稍後再試。"]
            )
        case .internalError(let underlying):
            let details = extractGeminiUnderlyingDetails(from: underlying)
            let status = details.status.uppercased()
            let message = details.message.isEmpty ? String(describing: underlying) : details.message

            if details.httpCode == 429 || status.contains("RESOURCE_EXHAUSTED") {
                return NSError(
                    domain: "Gemini",
                    code: 429,
                    userInfo: [NSLocalizedDescriptionKey: "Gemini 已達使用上限或暫時繁忙。請稍後再試。"]
                )
            }

            if details.httpCode == 503 || status.contains("UNAVAILABLE") {
                return NSError(
                    domain: "Gemini",
                    code: 503,
                    userInfo: [NSLocalizedDescriptionKey: "Gemini 服務暫時不可用。請稍後再試。"]
                )
            }

            if details.httpCode == 400 || status.contains("INVALID_ARGUMENT") {
                return NSError(
                    domain: "Gemini",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Gemini 不接受這次預算分析請求。常見原因是分析資料太多。請縮短分析時間範圍，或先不要加入收入資料與 JSON 備份再試。\n\n服務訊息：\(message)"]
                )
            }

            return NSError(
                domain: "Gemini",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Gemini 內部錯誤。\n\n服務狀態：\(status.isEmpty ? "未知" : status)\n服務訊息：\(message)"]
            )
        }
    }

    private func extractGeminiUnderlyingDetails(from error: Error) -> (httpCode: Int?, status: String, message: String) {
        var httpCode: Int?
        var status = ""
        var message = error.localizedDescription

        let mirror = Mirror(reflecting: error)
        for child in mirror.children {
            guard let label = child.label else { continue }
            switch label {
            case "httpResponseCode":
                httpCode = child.value as? Int
            case "message":
                if let value = child.value as? String, !value.isEmpty {
                    message = value
                }
            case "status":
                status = String(describing: child.value)
            default:
                continue
            }
        }

        return (httpCode, status, message)
    }

    private func isoDateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}
