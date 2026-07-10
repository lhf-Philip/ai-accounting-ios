import XCTest
@testable import AI_記帳

@MainActor
final class LedgerSemanticVectorsTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_772_366_400)

    func testVector6_crossCurrencyRepayment_usesNormalisedAmountForOutstanding() {
        let participant = AdvanceParticipant(
            name: "Friend A",
            owedAmount: 1_000,
            repaidAmount: 900
        )
        let repayment = AdvanceRepayment(
            amount: 50,
            currencyCode: "HKD",
            normalizedAmount: 900,
            date: date,
            note: "朋友用港幣還款"
        )

        XCTAssertEqual(Decimal(50), repayment.amount)
        XCTAssertEqual("HKD", repayment.currencyCode)
        XCTAssertEqual(Decimal(900), repayment.normalizedAmount)
        XCTAssertEqual(Decimal(100), participant.remainingAmount)
    }

    func testVector7_iAdvancedOthers_reportsOnlyUserShare() {
        let transactions = [
            snapshot(amount: -50, type: .expense),
            snapshot(amount: -100, type: .transfer),
            snapshot(amount: 100, type: .transfer)
        ]
        let participant = AdvanceParticipant(
            name: "Friend A",
            owedAmount: 100
        )

        XCTAssertEqual(Decimal(50), total(for: .expense, transactions: transactions))
        XCTAssertEqual(Decimal.zero, total(for: .income, transactions: transactions))
        XCTAssertEqual(Decimal(100), participant.remainingAmount)
    }

    func testVector8_othersAdvancedMe_repaymentDoesNotDoubleCountExpense() {
        let transactions = [
            snapshot(amount: -150, type: .expense),
            snapshot(amount: -150, type: .transfer),
            snapshot(amount: 150, type: .transfer)
        ]
        let participant = AdvanceParticipant(
            name: "Friend A",
            owedAmount: 150,
            repaidAmount: 150
        )

        XCTAssertEqual(Decimal(150), total(for: .expense, transactions: transactions))
        XCTAssertEqual(Decimal.zero, total(for: .income, transactions: transactions))
        XCTAssertEqual(Decimal.zero, participant.remainingAmount)
    }

    func testVector13_settlementRecordsAreExcludedFromReports() {
        let forgivenessNote = TransactionSemantics.debtForgivenessNote(
            baseNote: "",
            debtAccountName: "Friend A",
            direction: .forgivenByOthers
        )
        let offsetID = UUID(uuidString: "13131313-1313-1313-1313-131313131313")!
        let offsetNote = "[債務抵銷:\(offsetID.uuidString)] 與對方代墊互相抵銷"
        let transactions = [
            snapshot(amount: -20, type: .expense),
            snapshot(amount: -40, type: .transfer),
            snapshot(amount: 40, type: .transfer),
            snapshot(amount: 40, type: .transfer),
            snapshot(amount: -100, currency: "HKD", type: .transfer),
            snapshot(amount: 92, currency: "CNY", type: .transfer),
            snapshot(amount: 1_000, currency: "JPY", type: .transfer)
        ]

        XCTAssertTrue(TransactionSemantics.isDebtForgiveness(note: forgivenessNote))
        XCTAssertTrue(AdvanceSemantics.isMutualDebtOffset(note: offsetNote))
        XCTAssertEqual(Decimal(20), total(for: .expense, transactions: transactions))
        XCTAssertEqual(Decimal.zero, total(for: .income, transactions: transactions))
    }

    private func total(
        for flow: ReportFlow,
        transactions: [ReportTransactionSnapshot]
    ) -> Decimal {
        ReportAggregationService.aggregate(
            request: ReportAggregationRequest(
                transactions: transactions,
                flow: flow,
                grouping: .category,
                startDate: nil,
                endDate: nil
            ),
            currencyConverter: SemanticVectorCurrencyConverter()
        ).totalEstimatedAmount
    }

    private func snapshot(
        amount: Decimal,
        currency: String = "HKD",
        type: TransactionType
    ) -> ReportTransactionSnapshot {
        return ReportTransactionSnapshot(
            id: UUID(),
            amount: amount,
            currencyCode: currency,
            date: date,
            type: type,
            categoryID: nil,
            categoryName: nil,
            categoryColorHex: nil,
            tagNames: []
        )
    }
}

private struct SemanticVectorCurrencyConverter: ReportCurrencyConverting {
    let mainCurrency = "HKD"

    func estimateInMainCurrency(amount: Decimal, from currencyCode: String) -> ReportConversion? {
        let rate: Decimal
        switch currencyCode.uppercased() {
        case "HKD":
            rate = 1
        case "USD":
            rate = Decimal(string: "7.8")!
        case "CNY":
            rate = Decimal(string: "1.08")!
        default:
            return nil
        }
        return ReportConversion(amount: amount * rate, status: .exact)
    }
}
