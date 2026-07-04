import XCTest
@testable import AI_記帳

@MainActor
final class TransactionEditServiceTests: XCTestCase {
    func testApplyingDraftUpdatesTransactionCurrencyWithoutChangingAccountCurrency() throws {
        let account = Account(
            name: "Multi-currency bank",
            currency: "JPY",
            type: .bank,
            baseBalance: 0
        )
        let transaction = FinancialTransaction(
            amount: -725,
            currencyCode: "JPY",
            note: "LUUP",
            type: .expense,
            account: account
        )
        let draft = OrdinaryTransactionEditDraft(
            amount: exactDecimal("35.59"),
            currencyCode: "HKD",
            date: transaction.date,
            note: transaction.note,
            type: .expense,
            account: account,
            category: nil,
            tags: []
        )

        try TransactionEditService.apply(draft, to: transaction, updatedAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual("HKD", transaction.currencyCode)
        XCTAssertEqual("JPY", account.currency)
        XCTAssertEqual(exactDecimal("-35.59"), transaction.amount)
    }

    func testOrdinaryTransactionRequiresAnAccount() {
        let draft = OrdinaryTransactionEditDraft(
            amount: 10,
            currencyCode: "HKD",
            date: Date(),
            note: "",
            type: .expense,
            account: nil,
            category: nil,
            tags: []
        )

        XCTAssertThrowsError(try TransactionEditService.validate(draft)) { error in
            XCTAssertEqual(error as? TransactionEditError, .missingAccount)
        }
    }

    func testIncomeAndExpenseRejectDebtAccounts() {
        let debtAccount = Account(
            name: "Friend",
            currency: "HKD",
            type: .debt,
            baseBalance: 0
        )
        let draft = OrdinaryTransactionEditDraft(
            amount: 10,
            currencyCode: "HKD",
            date: Date(),
            note: "",
            type: .income,
            account: debtAccount,
            category: nil,
            tags: []
        )

        XCTAssertThrowsError(try TransactionEditService.validate(draft)) { error in
            XCTAssertEqual(error as? TransactionEditError, .invalidAccountType)
        }
    }

    func testTransferLegIdentityAllowsSameAccountWithDifferentCurrencies() {
        let accountID = UUID()
        let identities = [
            TransferLegIdentity(accountID: accountID, currencyCode: "JPY"),
            TransferLegIdentity(accountID: accountID, currencyCode: "HKD"),
        ]

        XCTAssertFalse(TransactionEditService.hasDuplicateTransferLegs(identities))
    }

    func testTransferLegIdentityRejectsSameAccountAndCurrencyTwice() {
        let accountID = UUID()
        let identities = [
            TransferLegIdentity(accountID: accountID, currencyCode: "hkd"),
            TransferLegIdentity(accountID: accountID, currencyCode: " HKD "),
        ]

        XCTAssertTrue(TransactionEditService.hasDuplicateTransferLegs(identities))
    }
}
