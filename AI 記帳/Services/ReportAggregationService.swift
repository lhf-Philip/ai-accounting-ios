import Foundation

enum ReportFlow {
    case expense
    case income

    var transactionType: TransactionType {
        switch self {
        case .expense: return .expense
        case .income: return .income
        }
    }
}

enum ReportGroupingMode {
    case category
    case tag
}

enum ReportEstimateStatus: Equatable {
    case exact
    case live
    case cached
    case partial
    case unavailable

    var label: String? {
        switch self {
        case .exact:
            return nil
        case .live:
            return "即時匯率"
        case .cached:
            return "上次匯率"
        case .partial, .unavailable:
            return "估算不完整"
        }
    }
}

struct ReportConversion {
    let amount: Decimal
    let status: ReportEstimateStatus
}

protocol ReportCurrencyConverting {
    var mainCurrency: String { get }
    func estimateInMainCurrency(amount: Decimal, from currencyCode: String) -> ReportConversion?
}

struct ReportTransactionSnapshot {
    let id: UUID
    let amount: Decimal
    let currencyCode: String
    let date: Date
    let type: TransactionType
    let categoryID: UUID?
    let categoryName: String?
    let categoryColorHex: String?
    let tagNames: [String]
}

struct ReportCurrencyTotal: Equatable {
    let currencyCode: String
    let amount: Decimal
}

struct ReportSlice: Identifiable, Equatable {
    let key: String
    let name: String
    let categoryColorHex: String?
    let estimatedAmount: Decimal
    let originalCurrencyTotals: [ReportCurrencyTotal]
    let estimateStatus: ReportEstimateStatus
    let transactionIDs: [UUID]

    var id: String { key }

    var detailSummary: ReportDetailSummary {
        ReportDetailSummary(
            estimatedAmount: estimatedAmount,
            originalCurrencyTotals: originalCurrencyTotals,
            estimateStatus: estimateStatus,
            transactionIDs: transactionIDs
        )
    }
}

struct ReportDetailSummary: Equatable {
    let estimatedAmount: Decimal
    let originalCurrencyTotals: [ReportCurrencyTotal]
    let estimateStatus: ReportEstimateStatus
    let transactionIDs: [UUID]

    var transactionCount: Int { transactionIDs.count }
}

struct ReportAggregationRequest {
    let transactions: [ReportTransactionSnapshot]
    let flow: ReportFlow
    let grouping: ReportGroupingMode
    let startDate: Date?
    let endDate: Date?
    let tagFilter: String?

    init(
        transactions: [ReportTransactionSnapshot],
        flow: ReportFlow,
        grouping: ReportGroupingMode,
        startDate: Date?,
        endDate: Date?,
        tagFilter: String? = nil
    ) {
        self.transactions = transactions
        self.flow = flow
        self.grouping = grouping
        self.startDate = startDate
        self.endDate = endDate
        self.tagFilter = tagFilter
    }
}

struct ReportAggregationResult {
    let slices: [ReportSlice]

    var totalEstimatedAmount: Decimal {
        slices.reduce(Decimal.zero) { $0 + $1.estimatedAmount }
    }
}

enum ReportAggregationService {
    static func aggregate(
        request: ReportAggregationRequest,
        currencyConverter: ReportCurrencyConverting
    ) -> ReportAggregationResult {
        let filtered = request.transactions.filter { transaction in
            guard transaction.type == request.flow.transactionType else { return false }
            if let startDate = request.startDate, transaction.date < startDate { return false }
            if let endDate = request.endDate, transaction.date >= endDate { return false }
            if let tagFilter = request.tagFilter {
                if tagFilter == "無標籤" {
                    return transaction.tagNames.isEmpty
                }
                return transaction.tagNames.contains(tagFilter)
            }
            return true
        }

        let grouped: [String: [ReportTransactionSnapshot]]
        switch request.grouping {
        case .category:
            grouped = Dictionary(grouping: filtered) { transaction in
                transaction.categoryID?.uuidString ?? "uncategorized"
            }
        case .tag:
            var tagGroups: [String: [ReportTransactionSnapshot]] = [:]
            for transaction in filtered {
                if transaction.tagNames.isEmpty {
                    tagGroups["無標籤", default: []].append(transaction)
                } else {
                    for tagName in transaction.tagNames {
                        tagGroups[tagName, default: []].append(transaction)
                    }
                }
            }
            grouped = tagGroups
        }

        let slices = grouped.map { key, transactions in
            makeSlice(
                key: key,
                transactions: transactions,
                grouping: request.grouping,
                currencyConverter: currencyConverter
            )
        }
        .sorted {
            if $0.estimatedAmount == $1.estimatedAmount {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.estimatedAmount > $1.estimatedAmount
        }

        return ReportAggregationResult(slices: slices)
    }

    private static func makeSlice(
        key: String,
        transactions: [ReportTransactionSnapshot],
        grouping: ReportGroupingMode,
        currencyConverter: ReportCurrencyConverting
    ) -> ReportSlice {
        var estimatedAmount = Decimal.zero
        var originalTotals: [String: Decimal] = [:]
        var conversionStatuses: [ReportEstimateStatus] = []
        var unavailableCount = 0

        for transaction in transactions {
            let amount = abs(transaction.amount)
            let currencyCode = transaction.currencyCode.uppercased()
            originalTotals[currencyCode, default: 0] += amount

            if let conversion = currencyConverter.estimateInMainCurrency(
                amount: amount,
                from: currencyCode
            ) {
                estimatedAmount += conversion.amount
                conversionStatuses.append(conversion.status)
            } else {
                unavailableCount += 1
            }
        }

        let status: ReportEstimateStatus
        if unavailableCount == transactions.count {
            status = .unavailable
        } else if unavailableCount > 0 {
            status = .partial
        } else if conversionStatuses.contains(.cached) {
            status = .cached
        } else if conversionStatuses.contains(.live) {
            status = .live
        } else {
            status = .exact
        }

        let first = transactions.first
        let name: String
        let colorHex: String?
        switch grouping {
        case .category:
            name = first?.categoryName ?? "未分類"
            colorHex = first?.categoryColorHex
        case .tag:
            name = key
            colorHex = nil
        }

        return ReportSlice(
            key: key,
            name: name,
            categoryColorHex: colorHex,
            estimatedAmount: estimatedAmount,
            originalCurrencyTotals: originalTotals
                .sorted { $0.key < $1.key }
                .map { ReportCurrencyTotal(currencyCode: $0.key, amount: $0.value) },
            estimateStatus: status,
            transactionIDs: transactions
                .sorted { $0.date > $1.date }
                .map(\.id)
        )
    }
}

extension CurrencyService: ReportCurrencyConverting {
    func estimateInMainCurrency(amount: Decimal, from currencyCode: String) -> ReportConversion? {
        let normalizedCurrency = currencyCode.uppercased()
        if normalizedCurrency == mainCurrency.uppercased() {
            return ReportConversion(amount: amount, status: .exact)
        }
        guard let estimate = estimate(amount: amount, from: normalizedCurrency, to: mainCurrency) else {
            return nil
        }
        let status: ReportEstimateStatus = estimate.source == .cached ? .cached : .live
        return ReportConversion(amount: estimate.amount, status: status)
    }
}
