import XCTest
@testable import AI_記帳

@MainActor
final class RefundSemanticsServiceTests: XCTestCase {
    func testRefundToOwnAccount_reducesExpenseWithoutIncome() throws {
        let effect = try RefundSemanticsService.effect(
            for: RefundSemanticInput(
                amount: 2_550,
                destination: .ownAccount,
                originalExpenseRemaining: 20_650
            )
        )

        XCTAssertEqual(Decimal(2_550), effect.ownAccountDelta)
        XCTAssertEqual(Decimal.zero, effect.debtBalanceDelta)
        XCTAssertEqual(Decimal(2_550), effect.expenseReduction)
        XCTAssertEqual(Decimal(-2_550), effect.reportNetExpenseDelta)
        XCTAssertEqual(Decimal.zero, effect.incomeContribution)
        XCTAssertEqual(Decimal.zero, effect.settlementOnlyAmount)
    }

    func testRefundToDebtAccount_reducesExpenseAndCreatesReceivableOrReducesPayable() throws {
        let effect = try RefundSemanticsService.effect(
            for: RefundSemanticInput(
                amount: 2_550,
                destination: .debtAccount,
                originalExpenseRemaining: 20_650
            )
        )

        XCTAssertEqual(Decimal.zero, effect.ownAccountDelta)
        XCTAssertEqual(Decimal(2_550), effect.debtBalanceDelta)
        XCTAssertEqual(Decimal(2_550), effect.expenseReduction)
        XCTAssertEqual(Decimal(-2_550), effect.reportNetExpenseDelta)
        XCTAssertEqual(Decimal.zero, effect.incomeContribution)
        XCTAssertEqual(Decimal.zero, effect.settlementOnlyAmount)
    }

    func testRefundReductionIsCappedAtOriginalExpenseRemaining() throws {
        let effect = try RefundSemanticsService.effect(
            for: RefundSemanticInput(
                amount: 2_550,
                destination: .debtAccount,
                originalExpenseRemaining: 2_000
            )
        )

        XCTAssertEqual(Decimal(2_550), effect.debtBalanceDelta)
        XCTAssertEqual(Decimal(2_000), effect.expenseReduction)
        XCTAssertEqual(Decimal(-2_000), effect.reportNetExpenseDelta)
        XCTAssertEqual(Decimal.zero, effect.incomeContribution)
        XCTAssertEqual(Decimal(550), effect.settlementOnlyAmount)
    }

    func testRefundAmountMustBePositive() {
        XCTAssertThrowsError(
            try RefundSemanticsService.effect(
                for: RefundSemanticInput(amount: 0, destination: .ownAccount)
            )
        ) { error in
            XCTAssertEqual(error as? RefundSemanticsError, .invalidRefundAmount)
        }
    }
}
