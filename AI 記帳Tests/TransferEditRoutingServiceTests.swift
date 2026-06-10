import XCTest
@testable import AI_記帳

@MainActor
final class TransferEditRoutingServiceTests: XCTestCase {
    func testDebtGroupRoutesToDebtEditor() {
        let debt = Account(name: "Friend", currency: "HKD", type: .debt, baseBalance: 0)
        let wallet = Account(name: "Wallet", currency: "HKD", type: .cash, baseBalance: 0)
        let groupID = UUID()
        let outgoing = FinancialTransaction(
            amount: -100,
            currencyCode: "HKD",
            type: .transfer,
            transferGroupID: groupID,
            transferSide: .outgoing,
            account: debt
        )
        let incoming = FinancialTransaction(
            amount: 100,
            currencyCode: "HKD",
            type: .transfer,
            transferGroupID: groupID,
            transferSide: .incoming,
            account: wallet
        )

        XCTAssertEqual(
            .debt,
            TransferEditRoutingService.classify(
                transaction: incoming,
                groupTransactions: [outgoing, incoming],
                advanceInitialGroupIDs: [],
                advanceRepaymentGroupIDs: []
            )
        )
    }

    func testAdvanceGroupWinsOverDebtAccountShape() {
        let debt = Account(name: "Friend", currency: "HKD", type: .debt, baseBalance: 0)
        let groupID = UUID()
        let transaction = FinancialTransaction(
            amount: 100,
            currencyCode: "HKD",
            type: .transfer,
            transferGroupID: groupID,
            transferSide: .incoming,
            account: debt
        )

        XCTAssertEqual(
            .advanceInitial,
            TransferEditRoutingService.classify(
                transaction: transaction,
                groupTransactions: [transaction],
                advanceInitialGroupIDs: [groupID],
                advanceRepaymentGroupIDs: []
            )
        )
    }

    func testOrdinaryTransferRemainsOrdinary() {
        let wallet = Account(name: "Wallet", currency: "HKD", type: .cash, baseBalance: 0)
        let transaction = FinancialTransaction(
            amount: -10,
            currencyCode: "HKD",
            type: .transfer,
            account: wallet
        )

        XCTAssertEqual(
            .ordinary,
            TransferEditRoutingService.classify(
                transaction: transaction,
                groupTransactions: [transaction],
                advanceInitialGroupIDs: [],
                advanceRepaymentGroupIDs: []
            )
        )
    }
}
