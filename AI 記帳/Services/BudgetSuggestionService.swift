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

private struct BudgetSuggestionCategorySignal: Codable {
    let categoryId: UUID
    let categoryName: String
    let averageMonthlyAmount: Decimal
    let lastFullMonthAmount: Decimal
    let currentMonthAmount: Decimal
    let peakMonthlyAmount: Decimal
    let activeMonthCount: Int
    let existingBudgetAmount: Decimal?
}

private struct BudgetSuggestionNamedSignal: Codable {
    let categoryName: String
    let averageMonthlyAmount: Decimal
    let lastFullMonthAmount: Decimal
    let currentMonthAmount: Decimal
    let peakMonthlyAmount: Decimal
    let activeMonthCount: Int
}

private struct BudgetSuggestionIncomeSignal: Codable {
    let averageMonthlyAmount: Decimal
    let lastFullMonthAmount: Decimal
    let currentMonthAmount: Decimal
    let peakMonthlyAmount: Decimal
    let activeMonthCount: Int
}

private struct BudgetSuggestionPayload: Codable {
    let analysisStartDate: String
    let analysisEndDate: String
    let targetMonthKey: String
    let mainCurrency: String
    let targetExpenseCategories: [BudgetSuggestionCategorySignal]
    let backupExpenseSignals: [BudgetSuggestionNamedSignal]?
    let appIncomeSignal: BudgetSuggestionIncomeSignal?
    let backupIncomeSignal: BudgetSuggestionIncomeSignal?
    let hasUploadedBackup: Bool
}

enum BudgetSuggestionError: LocalizedError {
    case noTargetCategories
    case insufficientData
    case invalidResponse
    case serviceRejectedRequest
    case quotaExceeded
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .noTargetCategories:
            return "目前沒有可建議的支出分類。"
        case .insufficientData:
            return "資料不足，暫時無法產生預算建議。"
        case .invalidResponse:
            return "AI 回傳格式錯誤，請稍後再試。"
        case .serviceRejectedRequest:
            return "AI 服務暫時無法處理這次預算分析，請縮短分析時間範圍後再試。"
        case .quotaExceeded:
            return "AI 服務目前已達使用上限，請稍後再試。"
        case .serviceUnavailable:
            return "AI 服務暫時不可用，請稍後再試。"
        }
    }
}

final class BudgetSuggestionService {
    static let shared = BudgetSuggestionService()

    private let keychainServiceName = "org.duckdns.lhfser.AIMoney"
    private let keychainAccountName = "gemini_api_key"
    private let legacyUserDefaultsKey = "UserGeminiAPIKey"
    private let modelName = "gemini-2.0-flash"
    private let responseConfig = GenerationConfig(
        temperature: 0.2,
        topP: 0.9,
        candidateCount: 1,
        maxOutputTokens: 768,
        responseMIMEType: "application/json"
    )

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
        let model = GenerativeModel(
            name: modelName,
            apiKey: apiKey,
            generationConfig: responseConfig,
            systemInstruction: "Return strict JSON only. Do not wrap the response in Markdown."
        )

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
            return decoded.suggestions.filter {
                validCategoryIDs.contains($0.categoryId) && $0.suggestedAmount >= 0
            }
        } catch {
            throw mapAIError(error)
        }
    }

    private func buildPayload(for request: BudgetSuggestionRequest) -> BudgetSuggestionPayload {
        let targetMonthKey = BudgetService.monthKey(from: request.targetMonthDate)
        let analysisStart = request.startDate
        let analysisEnd = request.endDate
        let monthKeys = monthKeysBetween(startDate: analysisStart, endDate: analysisEnd)
        let previousMonthKey = previousMonthKey(before: targetMonthKey)

        let currentBudgetByCategoryID = Dictionary(
            uniqueKeysWithValues: request.currentBudgets
                .filter { $0.monthKey == targetMonthKey }
                .compactMap { budget -> (UUID, Decimal)? in
                    guard let category = budget.category, category.kind.supports(.expense) else { return nil }
                    let normalizedAmount = request.currencyService.convert(
                        amount: budget.amount,
                        from: budget.currencyCode,
                        to: request.mainCurrency
                    )
                    return (category.id, normalizedAmount)
                }
        )

        let appExpenseSignals = buildAppExpenseSignals(
            categories: request.targetCategories,
            transactions: request.appTransactions,
            monthKeys: monthKeys,
            previousMonthKey: previousMonthKey,
            targetMonthKey: targetMonthKey,
            currencyService: request.currencyService,
            targetCurrency: request.mainCurrency,
            currentBudgetByCategoryID: currentBudgetByCategoryID
        )

        let backupExpenseSignals = request.backupData.map {
            buildBackupExpenseSignals(
                backupData: $0,
                targetCategories: request.targetCategories,
                startDate: analysisStart,
                endDate: analysisEnd,
                monthKeys: monthKeys,
                previousMonthKey: previousMonthKey,
                targetMonthKey: targetMonthKey,
                targetCurrency: request.mainCurrency
            )
        }

        let appIncomeSignal = request.includeIncomeContext
            ? buildAppIncomeSignal(
                transactions: request.appTransactions,
                startDate: analysisStart,
                endDate: analysisEnd,
                monthKeys: monthKeys,
                previousMonthKey: previousMonthKey,
                targetMonthKey: targetMonthKey,
                currencyService: request.currencyService,
                targetCurrency: request.mainCurrency
            )
            : nil

        let backupIncomeSignal = request.includeIncomeContext ? request.backupData.map {
            buildBackupIncomeSignal(
                backupData: $0,
                startDate: analysisStart,
                endDate: analysisEnd,
                monthKeys: monthKeys,
                previousMonthKey: previousMonthKey,
                targetMonthKey: targetMonthKey,
                targetCurrency: request.mainCurrency
            )
        } : nil

        return BudgetSuggestionPayload(
            analysisStartDate: isoDateString(analysisStart),
            analysisEndDate: isoDateString(analysisEnd),
            targetMonthKey: targetMonthKey,
            mainCurrency: request.mainCurrency,
            targetExpenseCategories: appExpenseSignals,
            backupExpenseSignals: backupExpenseSignals,
            appIncomeSignal: appIncomeSignal,
            backupIncomeSignal: backupIncomeSignal,
            hasUploadedBackup: request.backupData != nil
        )
    }

    private func buildAppExpenseSignals(
        categories: [Category],
        transactions: [FinancialTransaction],
        monthKeys: [String],
        previousMonthKey: String?,
        targetMonthKey: String,
        currencyService: CurrencyService,
        targetCurrency: String,
        currentBudgetByCategoryID: [UUID: Decimal]
    ) -> [BudgetSuggestionCategorySignal] {
        let categoryIDs = Set(categories.map(\.id))
        let filtered = transactions.filter {
            $0.type == .expense &&
            categoryIDs.contains($0.category?.id ?? UUID())
        }

        var monthlyTotals: [UUID: [String: Decimal]] = [:]
        for transaction in filtered {
            guard let categoryID = transaction.category?.id else { continue }
            let monthKey = BudgetService.monthKey(from: transaction.date)
            guard monthKeys.contains(monthKey) else { continue }
            let normalizedAmount = currencyService.convert(
                amount: abs(transaction.amount),
                from: transaction.currencyCode,
                to: targetCurrency
            )
            monthlyTotals[categoryID, default: [:]][monthKey, default: 0] += normalizedAmount
        }

        return categories.map { category in
            let totals = monthlyTotals[category.id] ?? [:]
            let values = monthKeys.map { totals[$0] ?? 0 }
            return BudgetSuggestionCategorySignal(
                categoryId: category.id,
                categoryName: category.name,
                averageMonthlyAmount: average(values),
                lastFullMonthAmount: previousMonthKey.flatMap { totals[$0] } ?? 0,
                currentMonthAmount: totals[targetMonthKey] ?? 0,
                peakMonthlyAmount: values.max() ?? 0,
                activeMonthCount: values.filter { $0 > 0 }.count,
                existingBudgetAmount: currentBudgetByCategoryID[category.id]
            )
        }
    }

    private func buildBackupExpenseSignals(
        backupData: FullBackupData,
        targetCategories: [Category],
        startDate: Date,
        endDate: Date,
        monthKeys: [String],
        previousMonthKey: String?,
        targetMonthKey: String,
        targetCurrency: String
    ) -> [BudgetSuggestionNamedSignal] {
        let targetNames = Set(targetCategories.map(\.name))
        let categoryNames = Dictionary(uniqueKeysWithValues: backupData.categories.map { ($0.id, $0.name) })
        let filtered = backupData.transactions.filter {
            $0.type == TransactionType.expense.rawValue &&
            $0.date >= startDate &&
            $0.date <= endDate
        }

        var monthlyTotals: [String: [String: Decimal]] = [:]
        for transaction in filtered {
            let categoryName = transaction.categoryID.flatMap { categoryNames[$0] } ?? "未分類"
            guard targetNames.contains(categoryName) else { continue }
            let monthKey = BudgetService.monthKey(from: transaction.date)
            guard monthKeys.contains(monthKey) else { continue }
            let normalizedAmount = convertBackupAmountToTargetCurrency(
                amount: abs(transaction.amount),
                from: transaction.currencyCode,
                targetCurrency: targetCurrency
            )
            monthlyTotals[categoryName, default: [:]][monthKey, default: 0] += normalizedAmount
        }

        return targetCategories.map { category in
            let totals = monthlyTotals[category.name] ?? [:]
            let values = monthKeys.map { totals[$0] ?? 0 }
            return BudgetSuggestionNamedSignal(
                categoryName: category.name,
                averageMonthlyAmount: average(values),
                lastFullMonthAmount: previousMonthKey.flatMap { totals[$0] } ?? 0,
                currentMonthAmount: totals[targetMonthKey] ?? 0,
                peakMonthlyAmount: values.max() ?? 0,
                activeMonthCount: values.filter { $0 > 0 }.count
            )
        }
        .filter {
            $0.averageMonthlyAmount > 0 ||
            $0.lastFullMonthAmount > 0 ||
            $0.currentMonthAmount > 0 ||
            $0.peakMonthlyAmount > 0
        }
    }

    private func buildAppIncomeSignal(
        transactions: [FinancialTransaction],
        startDate: Date,
        endDate: Date,
        monthKeys: [String],
        previousMonthKey: String?,
        targetMonthKey: String,
        currencyService: CurrencyService,
        targetCurrency: String
    ) -> BudgetSuggestionIncomeSignal {
        let filtered = transactions.filter {
            $0.type == .income &&
            $0.date >= startDate &&
            $0.date <= endDate
        }
        return buildIncomeSignal(
            transactions: filtered.map {
                (
                    monthKey: BudgetService.monthKey(from: $0.date),
                    amount: currencyService.convert(
                        amount: abs($0.amount),
                        from: $0.currencyCode,
                        to: targetCurrency
                    )
                )
            },
            monthKeys: monthKeys,
            previousMonthKey: previousMonthKey,
            targetMonthKey: targetMonthKey
        )
    }

    private func buildBackupIncomeSignal(
        backupData: FullBackupData,
        startDate: Date,
        endDate: Date,
        monthKeys: [String],
        previousMonthKey: String?,
        targetMonthKey: String,
        targetCurrency: String
    ) -> BudgetSuggestionIncomeSignal {
        let filtered = backupData.transactions.filter {
            $0.type == TransactionType.income.rawValue &&
            $0.date >= startDate &&
            $0.date <= endDate
        }
        return buildIncomeSignal(
            transactions: filtered.map {
                (
                    monthKey: BudgetService.monthKey(from: $0.date),
                    amount: convertBackupAmountToTargetCurrency(
                        amount: abs($0.amount),
                        from: $0.currencyCode,
                        targetCurrency: targetCurrency
                    )
                )
            },
            monthKeys: monthKeys,
            previousMonthKey: previousMonthKey,
            targetMonthKey: targetMonthKey
        )
    }

    private func buildIncomeSignal(
        transactions: [(monthKey: String, amount: Decimal)],
        monthKeys: [String],
        previousMonthKey: String?,
        targetMonthKey: String
    ) -> BudgetSuggestionIncomeSignal {
        var monthlyTotals: [String: Decimal] = [:]
        for transaction in transactions where monthKeys.contains(transaction.monthKey) {
            monthlyTotals[transaction.monthKey, default: 0] += transaction.amount
        }
        let values = monthKeys.map { monthlyTotals[$0] ?? 0 }
        return BudgetSuggestionIncomeSignal(
            averageMonthlyAmount: average(values),
            lastFullMonthAmount: previousMonthKey.flatMap { monthlyTotals[$0] } ?? 0,
            currentMonthAmount: monthlyTotals[targetMonthKey] ?? 0,
            peakMonthlyAmount: values.max() ?? 0,
            activeMonthCount: values.filter { $0 > 0 }.count
        )
    }

    private func convertBackupAmountToTargetCurrency(amount: Decimal, from: String, targetCurrency: String) -> Decimal {
        if from.uppercased() == targetCurrency.uppercased() {
            return amount
        }
        return amount
    }

    private func monthKeysBetween(startDate: Date, endDate: Date) -> [String] {
        let calendar = Calendar.current
        guard var current = calendar.date(from: calendar.dateComponents([.year, .month], from: startDate)) else {
            return [BudgetService.monthKey(from: endDate)]
        }
        let endMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: endDate)) ?? endDate

        var keys: [String] = []
        while current <= endMonth {
            keys.append(BudgetService.monthKey(from: current))
            guard let next = calendar.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
        }
        return keys
    }

    private func previousMonthKey(before monthKey: String) -> String? {
        guard let monthStart = BudgetService.monthStart(from: monthKey),
              let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: monthStart)
        else {
            return nil
        }
        return BudgetService.monthKey(from: previousMonth)
    }

    private func average(_ values: [Decimal]) -> Decimal {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Decimal(values.count)
    }

    private func hasMeaningfulSignal(_ payload: BudgetSuggestionPayload) -> Bool {
        payload.targetExpenseCategories.contains {
            $0.averageMonthlyAmount > 0 ||
            $0.lastFullMonthAmount > 0 ||
            $0.currentMonthAmount > 0 ||
            $0.peakMonthlyAmount > 0 ||
            ($0.existingBudgetAmount ?? 0) > 0
        } || !(payload.backupExpenseSignals?.isEmpty ?? true)
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
        Suggest realistic monthly budgets for the target month using the compact summary below.

        Rules:
        1. Only return budgets for the provided targetExpenseCategories.
        2. Every suggestedAmount must use mainCurrency.
        3. Income signals, if present, are context only. Do not return income categories.
        4. Prefer stable, conservative budgets instead of sharp jumps.
        5. Reasons must be concise Traditional Chinese.
        6. Return strict JSON only.

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

        Budget summary:
        \(payloadJSON)
        """
    }

    private func mapAIError(_ error: Error) -> Error {
        guard let generateError = error as? GenerateContentError else {
            return error
        }

        switch generateError {
        case .invalidAPIKey(let message):
            return NSError(domain: "Gemini", code: 401, userInfo: [NSLocalizedDescriptionKey: message])
        case .unsupportedUserLocation:
            return NSError(domain: "Gemini", code: 451, userInfo: [NSLocalizedDescriptionKey: "目前所在區域不支援 Gemini API。"])
        case .promptBlocked:
            return BudgetSuggestionError.serviceRejectedRequest
        case .responseStoppedEarly:
            return BudgetSuggestionError.invalidResponse
        case .promptImageContentError:
            return BudgetSuggestionError.serviceRejectedRequest
        case .internalError(let underlying):
            let description = String(describing: underlying)
            if description.localizedCaseInsensitiveContains("RESOURCE_EXHAUSTED") || description.contains("429") {
                return BudgetSuggestionError.quotaExceeded
            }
            if description.localizedCaseInsensitiveContains("UNAVAILABLE") || description.contains("503") {
                return BudgetSuggestionError.serviceUnavailable
            }
            if description.localizedCaseInsensitiveContains("INVALID_ARGUMENT") || description.contains("400") {
                return BudgetSuggestionError.serviceRejectedRequest
            }
            return NSError(
                domain: "Gemini",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "AI 服務暫時無法完成這次預算分析。請縮短分析範圍或稍後再試。"]
            )
        }
    }

    private func isoDateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}
