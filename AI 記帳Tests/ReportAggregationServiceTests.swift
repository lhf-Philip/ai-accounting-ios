import XCTest
@testable import AI_記帳

@MainActor
final class ReportAggregationServiceTests: XCTestCase {
    func testCategoryAggregation_preservesOriginalCurrencyAndEstimatesMainCurrency() {
        let foodID = UUID()
        let transactionID = UUID()
        let request = ReportAggregationRequest(
            transactions: [
                ReportTransactionSnapshot(
                    id: transactionID,
                    amount: -50,
                    currencyCode: "USD",
                    date: Date(timeIntervalSince1970: 1_700_000_000),
                    type: .expense,
                    categoryID: foodID,
                    categoryName: "餐飲",
                    categoryColorHex: "#FF0000",
                    tagNames: ["旅行"]
                )
            ],
            flow: .expense,
            grouping: .category,
            startDate: nil,
            endDate: nil
        )

        let result = ReportAggregationService.aggregate(
            request: request,
            currencyConverter: FixedReportCurrencyConverter(
                mainCurrency: "HKD",
                ratesToMain: ["USD": 7.8],
                source: .live
            )
        )

        XCTAssertEqual(1, result.slices.count)
        XCTAssertEqual("餐飲", result.slices[0].name)
        XCTAssertEqual(Decimal(390), result.slices[0].estimatedAmount)
        XCTAssertEqual(
            [ReportCurrencyTotal(currencyCode: "USD", amount: 50)],
            result.slices[0].originalCurrencyTotals
        )
        XCTAssertEqual(.live, result.slices[0].estimateStatus)
        XCTAssertEqual([transactionID], result.slices[0].transactionIDs)
        XCTAssertEqual(1, result.slices[0].detailSummary.transactionCount)
    }

    func testTagAggregation_filtersFlowAndDateAndSupportsCategoryDrillDown() {
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let endDate = startDate.addingTimeInterval(86_400)
        let foodID = UUID()
        let travelExpenseID = UUID()
        let ignoredIncomeID = UUID()
        let converter = FixedReportCurrencyConverter(
            mainCurrency: "HKD",
            ratesToMain: [:],
            source: .live
        )
        let transactions = [
            ReportTransactionSnapshot(
                id: travelExpenseID,
                amount: -80,
                currencyCode: "HKD",
                date: startDate.addingTimeInterval(60),
                type: .expense,
                categoryID: foodID,
                categoryName: "餐飲",
                categoryColorHex: "#FF0000",
                tagNames: ["旅行", "朋友"]
            ),
            ReportTransactionSnapshot(
                id: ignoredIncomeID,
                amount: 500,
                currencyCode: "HKD",
                date: startDate.addingTimeInterval(120),
                type: .income,
                categoryID: nil,
                categoryName: nil,
                categoryColorHex: nil,
                tagNames: ["旅行"]
            ),
            ReportTransactionSnapshot(
                id: UUID(),
                amount: -30,
                currencyCode: "HKD",
                date: endDate,
                type: .expense,
                categoryID: foodID,
                categoryName: "餐飲",
                categoryColorHex: "#FF0000",
                tagNames: ["旅行"]
            )
        ]

        let tagResult = ReportAggregationService.aggregate(
            request: ReportAggregationRequest(
                transactions: transactions,
                flow: .expense,
                grouping: .tag,
                startDate: startDate,
                endDate: endDate
            ),
            currencyConverter: converter
        )
        let travelSlice = tagResult.slices.first { $0.name == "旅行" }
        let friendSlice = tagResult.slices.first { $0.name == "朋友" }

        XCTAssertEqual([travelExpenseID], travelSlice?.transactionIDs)
        XCTAssertEqual([travelExpenseID], friendSlice?.transactionIDs)

        let drillDown = ReportAggregationService.aggregate(
            request: ReportAggregationRequest(
                transactions: transactions,
                flow: .expense,
                grouping: .category,
                startDate: startDate,
                endDate: endDate,
                tagFilter: "旅行"
            ),
            currencyConverter: converter
        )

        XCTAssertEqual("餐飲", drillDown.slices.first?.name)
        XCTAssertEqual([travelExpenseID], drillDown.slices.first?.transactionIDs)
    }

    func testEstimateStatus_distinguishesCachedPartialAndUnavailable() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let transactions = [
            snapshot(amount: -100, currency: "HKD", date: date),
            snapshot(amount: -10, currency: "USD", date: date),
            snapshot(amount: -1_000, currency: "JPY", date: date)
        ]
        let cachedConverter = FixedReportCurrencyConverter(
            mainCurrency: "HKD",
            ratesToMain: ["USD": 7.8],
            source: .cached
        )

        let partial = ReportAggregationService.aggregate(
            request: ReportAggregationRequest(
                transactions: transactions,
                flow: .expense,
                grouping: .category,
                startDate: nil,
                endDate: nil
            ),
            currencyConverter: cachedConverter
        )
        XCTAssertEqual(Decimal(178), partial.slices.first?.estimatedAmount)
        XCTAssertEqual(.partial, partial.slices.first?.estimateStatus)

        let unavailable = ReportAggregationService.aggregate(
            request: ReportAggregationRequest(
                transactions: [snapshot(amount: -1_000, currency: "JPY", date: date)],
                flow: .expense,
                grouping: .category,
                startDate: nil,
                endDate: nil
            ),
            currencyConverter: cachedConverter
        )
        XCTAssertEqual(.unavailable, unavailable.slices.first?.estimateStatus)

        let cached = ReportAggregationService.aggregate(
            request: ReportAggregationRequest(
                transactions: [snapshot(amount: -10, currency: "USD", date: date)],
                flow: .expense,
                grouping: .category,
                startDate: nil,
                endDate: nil
            ),
            currencyConverter: cachedConverter
        )
        XCTAssertEqual(.cached, cached.slices.first?.estimateStatus)
    }

    func testRefundAggregation_reducesExpenseWithoutCountingIncome() {
        let travelID = UUID()
        let expenseID = UUID()
        let refundID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let transactions = [
            snapshot(
                id: expenseID,
                amount: -20_650,
                currency: "JPY",
                date: date,
                categoryId: travelID,
                tags: ["旅行"]
            ),
            snapshot(
                id: refundID,
                amount: 2_550,
                currency: "JPY",
                date: date.addingTimeInterval(60),
                type: .transfer,
                categoryId: travelID,
                tags: ["旅行"],
                semantic: .refund(destination: .debtAccount, originalExpenseRemaining: 20_650)
            )
        ]
        let converter = FixedReportCurrencyConverter(mainCurrency: "JPY")

        let expense = aggregate(transactions, converter)
        XCTAssertEqual(1, expense.slices.count)
        let slice = expense.slices[0]

        XCTAssertEqual("餐飲", slice.name)
        XCTAssertEqual(Decimal(18_100), slice.estimatedAmount)
        XCTAssertEqual(Decimal(20_650), slice.grossEstimatedAmount)
        XCTAssertEqual(Decimal(2_550), slice.refundReductionEstimatedAmount)
        XCTAssertEqual(Decimal.zero, slice.refundSettlementOnlyEstimatedAmount)
        XCTAssertEqual(
            [ReportCurrencyTotal(currencyCode: "JPY", amount: 18_100)],
            slice.originalCurrencyTotals
        )
        XCTAssertEqual(
            [ReportCurrencyTotal(currencyCode: "JPY", amount: 20_650)],
            slice.grossOriginalCurrencyTotals
        )
        XCTAssertEqual(
            [ReportCurrencyTotal(currencyCode: "JPY", amount: 2_550)],
            slice.refundReductionOriginalCurrencyTotals
        )
        XCTAssertEqual([refundID, expenseID], slice.transactionIDs)

        let income = ReportAggregationService.aggregate(
            request: ReportAggregationRequest(
                transactions: transactions,
                flow: .income,
                grouping: .category,
                startDate: nil,
                endDate: nil
            ),
            currencyConverter: converter
        )
        XCTAssertTrue(income.slices.isEmpty)
    }

    func testRefundAggregation_capsExpenseReductionAndKeepsExcessSettlementOnly() {
        let travelID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let transactions = [
            snapshot(
                amount: -2_000,
                currency: "JPY",
                date: date,
                categoryId: travelID
            ),
            snapshot(
                amount: 2_550,
                currency: "JPY",
                date: date.addingTimeInterval(60),
                type: .transfer,
                categoryId: travelID,
                semantic: .refund(destination: .debtAccount, originalExpenseRemaining: 2_000)
            )
        ]

        let result = aggregate(transactions, FixedReportCurrencyConverter(mainCurrency: "JPY"))
        XCTAssertEqual(1, result.slices.count)
        let slice = result.slices[0]

        XCTAssertEqual(Decimal.zero, slice.estimatedAmount)
        XCTAssertEqual(Decimal(2_000), slice.refundReductionEstimatedAmount)
        XCTAssertEqual(Decimal(550), slice.refundSettlementOnlyEstimatedAmount)
        XCTAssertTrue(slice.originalCurrencyTotals.isEmpty)
        XCTAssertEqual(
            [ReportCurrencyTotal(currencyCode: "JPY", amount: 550)],
            slice.refundSettlementOnlyOriginalCurrencyTotals
        )
    }

    func testSharedDateFilter_excludesExclusiveEndBoundary() {
        let calendar = Calendar(identifier: .gregorian)
        let selectedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let interval = FilterType.day.dateInterval(
            selectedDate: selectedDate,
            customStartDate: selectedDate,
            customEndDate: selectedDate,
            calendar: calendar
        )

        XCTAssertNotNil(interval)
        XCTAssertTrue(
            FilterType.day.matches(
                date: interval!.start,
                selectedDate: selectedDate,
                customStartDate: selectedDate,
                customEndDate: selectedDate,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            FilterType.day.matches(
                date: interval!.end,
                selectedDate: selectedDate,
                customStartDate: selectedDate,
                customEndDate: selectedDate,
                calendar: calendar
            )
        )
    }

    private func aggregate(
        _ transactions: [ReportTransactionSnapshot],
        _ converter: ReportCurrencyConverting
    ) -> ReportAggregationResult {
        ReportAggregationService.aggregate(
            request: ReportAggregationRequest(
                transactions: transactions,
                flow: .expense,
                grouping: .category,
                startDate: nil,
                endDate: nil
            ),
            currencyConverter: converter
        )
    }

    private func snapshot(
        id: UUID = UUID(),
        amount: Decimal,
        currency: String,
        date: Date,
        type: TransactionType = .expense,
        categoryId: UUID? = nil,
        tags: [String] = [],
        semantic: ReportTransactionSemantic = .regular
    ) -> ReportTransactionSnapshot {
        ReportTransactionSnapshot(
            id: id,
            amount: amount,
            currencyCode: currency,
            date: date,
            type: type,
            categoryID: categoryId,
            categoryName: categoryId == nil ? nil : "餐飲",
            categoryColorHex: categoryId == nil ? nil : "#FF0000",
            tagNames: tags,
            semantic: semantic
        )
    }
}

private struct FixedReportCurrencyConverter: ReportCurrencyConverting {
    let mainCurrency: String
    let ratesToMain: [String: Decimal]
    let source: ReportEstimateStatus

    func estimateInMainCurrency(amount: Decimal, from currencyCode: String) -> ReportConversion? {
        if currencyCode.uppercased() == mainCurrency.uppercased() {
            return ReportConversion(amount: amount, status: .exact)
        }
        guard let rate = ratesToMain[currencyCode.uppercased()] else { return nil }
        return ReportConversion(amount: amount * rate, status: source)
    }
}
