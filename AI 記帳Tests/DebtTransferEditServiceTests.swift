import XCTest
@testable import AI_記帳

@MainActor
final class DebtTransferEditServiceTests: XCTestCase {
    func testBorrowEditPreservesGroupAndTransactionCurrency() throws {
        let debtAccount = Account(name: "Friend", currency: "JPY", type: .debt, baseBalance: 0)
        let wallet = Account(name: "Wallet", currency: "JPY", type: .cash, baseBalance: 0)
        let groupID = UUID()
        let debtTransaction = FinancialTransaction(
            amount: -725,
            currencyCode: "JPY",
            type: .transfer,
            transferGroupID: groupID,
            transferSide: .outgoing,
            account: debtAccount
        )
        let ownTransaction = FinancialTransaction(
            amount: 725,
            currencyCode: "JPY",
            type: .transfer,
            transferGroupID: groupID,
            transferSide: .incoming,
            account: wallet
        )

        try DebtTransferEditService.apply(
            DebtTransferEditDraft(
                debtAccount: debtAccount,
                ownAccount: wallet,
                amount: 35.59,
                currencyCode: "HKD",
                date: Date(timeIntervalSince1970: 10),
                note: "LUUP",
                direction: .borrow
            ),
            debtTransaction: debtTransaction,
            ownTransaction: ownTransaction,
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(groupID, debtTransaction.transferGroupID)
        XCTAssertEqual(groupID, ownTransaction.transferGroupID)
        XCTAssertEqual("HKD", debtTransaction.currencyCode)
        XCTAssertEqual("HKD", ownTransaction.currencyCode)
        XCTAssertEqual(Decimal(string: "-35.59"), debtTransaction.amount)
        XCTAssertEqual(Decimal(string: "35.59"), ownTransaction.amount)
        XCTAssertEqual("JPY", wallet.currency)
    }

    func testEditRejectsDirectionFlip() {
        let debtAccount = Account(name: "Friend", currency: "HKD", type: .debt, baseBalance: 0)
        let wallet = Account(name: "Wallet", currency: "HKD", type: .cash, baseBalance: 0)
        let groupID = UUID()
        let debtTransaction = FinancialTransaction(
            amount: -100,
            type: .transfer,
            transferGroupID: groupID,
            transferSide: .outgoing,
            account: debtAccount
        )
        let ownTransaction = FinancialTransaction(
            amount: 100,
            type: .transfer,
            transferGroupID: groupID,
            transferSide: .incoming,
            account: wallet
        )

        XCTAssertThrowsError(
            try DebtTransferEditService.apply(
                DebtTransferEditDraft(
                    debtAccount: debtAccount,
                    ownAccount: wallet,
                    amount: 100,
                    currencyCode: "HKD",
                    date: Date(),
                    note: "",
                    direction: .repay
                ),
                debtTransaction: debtTransaction,
                ownTransaction: ownTransaction,
                updatedAt: Date()
            )
        ) { error in
            XCTAssertEqual(error as? DebtTransferEditError, .directionChanged)
        }
    }

    func testLegacyEditInfersMissingSidesFromAmounts() throws {
        let debtAccount = Account(name: "Friend", currency: "HKD", type: .debt, baseBalance: 0)
        let wallet = Account(name: "Wallet", currency: "HKD", type: .cash, baseBalance: 0)
        let groupID = UUID()
        let debtTransaction = FinancialTransaction(
            amount: -100,
            type: .transfer,
            transferGroupID: groupID,
            transferSide: nil,
            account: debtAccount
        )
        let ownTransaction = FinancialTransaction(
            amount: 100,
            type: .transfer,
            transferGroupID: groupID,
            transferSide: nil,
            account: wallet
        )

        try DebtTransferEditService.apply(
            DebtTransferEditDraft(
                debtAccount: debtAccount,
                ownAccount: wallet,
                amount: 80,
                currencyCode: "HKD",
                date: Date(timeIntervalSince1970: 10),
                note: "",
                direction: .borrow
            ),
            debtTransaction: debtTransaction,
            ownTransaction: ownTransaction,
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(.outgoing, debtTransaction.transferSide)
        XCTAssertEqual(.incoming, ownTransaction.transferSide)
        XCTAssertEqual(Decimal(-80), debtTransaction.amount)
        XCTAssertEqual(Decimal(80), ownTransaction.amount)
    }
}
