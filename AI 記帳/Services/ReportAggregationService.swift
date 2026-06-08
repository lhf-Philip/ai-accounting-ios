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
    let semantic: ReportTransactionSemantic

    init(
        id: UUID,
        amount: Decimal,
        currencyCode: String,
        date: Date,
        type: TransactionType,
        categoryID: UUID?,
        categoryName: String?,
        categoryColorHex: String?,
        tagNames: [String],
        semantic: ReportTransactionSemantic = .regular
    ) {
        self.id = id
        self.amount = amount
        self.currencyCode = currencyCode
        self.date = date
        self.type = type
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.categoryColorHex = categoryColorHex
        self.tagNames = tagNames
        self.semantic = semantic
    }
}

enum ReportTransactionSemantic: Equatable {
    case regular
    case refund(destination: RefundDestinationKind, originalExpenseRemaining: Decimal?)
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
    let grossEstimatedAmount: Decimal
    let grossOriginalCurrencyTotals: [ReportCurrencyTotal]
    let refundReductionEstimatedAmount: Decimal
    let refundReductionOriginalCurrencyTotals: [ReportCurrencyTotal]
    let refundSettlementOnlyEstimatedAmount: Decimal
    let refundSettlementOnlyOriginalCurrencyTotals: [ReportCurrencyTotal]
    let estimateStatus: ReportEstimateStatus
    let transactionIDs: [UUID]

    var id: String { key }

    var detailSummary: ReportDetailSummary {
        ReportDetailSummary(
            estimatedAmount: estimatedAmount,
            originalCurrencyTotals: originalCurrencyTotals,
            grossEstimatedAmount: grossEstimatedAmount,
            grossOriginalCurrencyTotals: grossOriginalCurrencyTotals,
            refundReductionEstimatedAmount: refundReductionEstimatedAmount,
            refundReductionOriginalCurrencyTotals: refundReductionOriginalCurrencyTotals,
            refundSettlementOnlyEstimatedAmount: refundSettlementOnlyEstimatedAmount,
            refundSettlementOnlyOriginalCurrencyTotals: refundSettlementOnlyOriginalCurrencyTotals,
            estimateStatus: estimateStatus,
            transactionIDs: transactionIDs
        )
    }
}

struct ReportDetailSummary: Equatable {
    let estimatedAmount: Decimal
    let originalCurrencyTotals: [ReportCurrencyTotal]
    let grossEstimatedAmount: Decimal
    let grossOriginalCurrencyTotals: [ReportCurrencyTotal]
    let refundReductionEstimatedAmount: Decimal
    let refundReductionOriginalCurrencyTotals: [ReportCurrencyTotal]
    let refundSettlementOnlyEstimatedAmount: Decimal
    let refundSettlementOnlyOriginalCurrencyTotals: [ReportCurrencyTotal]
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
        let filtered = request.transactions.compactMap { transaction -> ReportAggregationItem? in
            guard let contribution = contribution(for: transaction, flow: request.flow) else { return nil }
            if let startDate = request.startDate, transaction.date < startDate { return nil }
            if let endDate = request.endDate, transaction.date >= endDate { return nil }
            if let tagFilter = request.tagFilter {
                if tagFilter == "無標籤" {
                    guard transaction.tagNames.isEmpty else { return nil }
                } else {
                    guard transaction.tagNames.contains(tagFilter) else { return nil }
                }
            }
            return ReportAggregationItem(transaction: transaction, contribution: contribution)
        }

        let grouped: [String: [ReportAggregationItem]]
        switch request.grouping {
        case .category:
            grouped = Dictionary(grouping: filtered) { item in
                item.transaction.categoryID?.uuidString ?? "uncategorized"
            }
        case .tag:
            var tagGroups: [String: [ReportAggregationItem]] = [:]
            for item in filtered {
                if item.transaction.tagNames.isEmpty {
                    tagGroups["無標籤", default: []].append(item)
                } else {
                    for tagName in item.transaction.tagNames {
                        tagGroups[tagName, default: []].append(item)
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

    private static func contribution(
        for transaction: ReportTransactionSnapshot,
        flow: ReportFlow
    ) -> ReportContribution? {
        switch transaction.semantic {
        case .regular:
            guard transaction.type == flow.transactionType else { return nil }
            return .regular(amount: abs(transaction.amount))
        case let .refund(destination, originalExpenseRemaining):
            guard flow == .expense else { return nil }
            let input = RefundSemanticInput(
                amount: abs(transaction.amount),
                destination: destination,
                originalExpenseRemaining: originalExpenseRemaining
            )
            guard let effect = try? RefundSemanticsService.effect(for: input) else { return nil }
            return .refund(
                reductionAmount: effect.expenseReduction,
                settlementOnlyAmount: effect.settlementOnlyAmount
            )
        }
    }

    private static func makeSlice(
        key: String,
        transactions: [ReportAggregationItem],
        grouping: ReportGroupingMode,
        currencyConverter: ReportCurrencyConverting
    ) -> ReportSlice {
        var gross = ReportAmountAccumulator()
        var refundReduction = ReportAmountAccumulator()
        var refundSettlementOnly = ReportAmountAccumulator()
        var netOriginalTotals: [String: Decimal] = [:]
        var conversionStatuses: [ReportEstimateStatus] = []
        var unavailableCount = 0
        var conversionAttemptCount = 0

        for item in transactions {
            let currencyCode = item.transaction.currencyCode.uppercased()
            switch item.contribution {
            case let .regular(amount):
                netOriginalTotals[currencyCode, default: 0] += amount
                add(
                    amount: amount,
                    currencyCode: currencyCode,
                    to: &gross,
                    currencyConverter: currencyConverter,
                    conversionStatuses: &conversionStatuses,
                    unavailableCount: &unavailableCount,
                    conversionAttemptCount: &conversionAttemptCount
                )
            case let .refund(reductionAmount, settlementOnlyAmount):
                netOriginalTotals[currencyCode, default: 0] -= reductionAmount
                add(
                    amount: reductionAmount,
                    currencyCode: currencyCode,
                    to: &refundReduction,
                    currencyConverter: currencyConverter,
                    conversionStatuses: &conversionStatuses,
                    unavailableCount: &unavailableCount,
                    conversionAttemptCount: &conversionAttemptCount
                )
                add(
                    amount: settlementOnlyAmount,
                    currencyCode: currencyCode,
                    to: &refundSettlementOnly,
                    currencyConverter: currencyConverter,
                    conversionStatuses: &conversionStatuses,
                    unavailableCount: &unavailableCount,
                    conversionAttemptCount: &conversionAttemptCount
                )
            }
        }
        let estimatedAmount = gross.estimatedAmount - refundReduction.estimatedAmount

        let status: ReportEstimateStatus
        if conversionAttemptCount == 0 {
            status = .exact
        } else if unavailableCount == conversionAttemptCount {
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

        let first = transactions.first?.transaction
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
            originalCurrencyTotals: totals(from: netOriginalTotals),
            grossEstimatedAmount: gross.estimatedAmount,
            grossOriginalCurrencyTotals: gross.originalCurrencyTotals,
            refundReductionEstimatedAmount: refundReduction.estimatedAmount,
            refundReductionOriginalCurrencyTotals: refundReduction.originalCurrencyTotals,
            refundSettlementOnlyEstimatedAmount: refundSettlementOnly.estimatedAmount,
            refundSettlementOnlyOriginalCurrencyTotals: refundSettlementOnly.originalCurrencyTotals,
            estimateStatus: status,
            transactionIDs: transactions
                .sorted { $0.transaction.date > $1.transaction.date }
                .map(\.transaction.id)
        )
    }

    private static func add(
        amount: Decimal,
        currencyCode: String,
        to accumulator: inout ReportAmountAccumulator,
        currencyConverter: ReportCurrencyConverting,
        conversionStatuses: inout [ReportEstimateStatus],
        unavailableCount: inout Int,
        conversionAttemptCount: inout Int
    ) {
        guard amount != 0 else { return }
        accumulator.originalTotals[currencyCode, default: 0] += amount
        conversionAttemptCount += 1
        if let conversion = currencyConverter.estimateInMainCurrency(amount: amount, from: currencyCode) {
            accumulator.estimatedAmount += conversion.amount
            conversionStatuses.append(conversion.status)
        } else {
            unavailableCount += 1
        }
    }

    private static func totals(from values: [String: Decimal]) -> [ReportCurrencyTotal] {
        values
            .filter { $0.value != 0 }
            .sorted { $0.key < $1.key }
            .map { ReportCurrencyTotal(currencyCode: $0.key, amount: $0.value) }
    }
}

private struct ReportAggregationItem {
    let transaction: ReportTransactionSnapshot
    let contribution: ReportContribution
}

private enum ReportContribution {
    case regular(amount: Decimal)
    case refund(reductionAmount: Decimal, settlementOnlyAmount: Decimal)
}

private struct ReportAmountAccumulator {
    var estimatedAmount: Decimal = 0
    var originalTotals: [String: Decimal] = [:]

    var originalCurrencyTotals: [ReportCurrencyTotal] {
        originalTotals
            .filter { $0.value != 0 }
            .sorted { $0.key < $1.key }
            .map { ReportCurrencyTotal(currencyCode: $0.key, amount: $0.value) }
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
