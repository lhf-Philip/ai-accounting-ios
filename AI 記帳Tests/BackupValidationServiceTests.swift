import XCTest
@testable import AI_記帳

final class BackupValidationServiceTests: XCTestCase {
    func testValidate_computesPerAccountCurrencyBalancesAndNoKnownAnomaly() {
        let accountID = UUID()
        let backup = makeBackup(
            accounts: [
                .init(id: accountID, name: "匯豐綜合戶口", currency: "HKD", type: AccountType.bank.rawValue, baseBalance: 100, sortOrder: 0, isArchived: false)
            ],
            transactions: [
                makeTransaction(amount: 50, currencyCode: "HKD", accountID: accountID),
                makeTransaction(amount: 629, currencyCode: "JPY", accountID: accountID)
            ]
        )

        let report = BackupValidationService.validate(backup)
        let account = report.accountBalances.first { $0.accountID == accountID }

        XCTAssertEqual(150, account?.balances.first { $0.currencyCode == "HKD" }?.amount)
        XCTAssertEqual(629, account?.balances.first { $0.currencyCode == "JPY" }?.amount)
        XCTAssertFalse(report.issues.contains { $0.title == "找到近期異常值 -221 JPY" })
        XCTAssertFalse(report.hasBlockingIssues)
    }

    func testValidate_flagsKnownNegativeJPYAnomaly() {
        let accountID = UUID()
        let backup = makeBackup(
            accounts: [
                .init(id: accountID, name: "日元戶口", currency: "JPY", type: AccountType.bank.rawValue, baseBalance: 0, sortOrder: 0, isArchived: false)
            ],
            transactions: [
                makeTransaction(amount: -221, currencyCode: "JPY", accountID: accountID)
            ]
        )

        let report = BackupValidationService.validate(backup)

        XCTAssertTrue(report.issues.contains { $0.title == "找到近期異常值 -221 JPY" })
        XCTAssertTrue(report.issues.contains { $0.title == "非債務帳戶出現負數餘額" })
    }

    func testValidate_duplicateIDsAreBlocking() {
        let accountID = UUID()
        let backup = makeBackup(
            accounts: [
                .init(id: accountID, name: "A", currency: "HKD", type: AccountType.cash.rawValue, baseBalance: 0, sortOrder: 0, isArchived: false),
                .init(id: accountID, name: "B", currency: "HKD", type: AccountType.cash.rawValue, baseBalance: 0, sortOrder: 1, isArchived: false)
            ]
        )

        let report = BackupValidationService.validate(backup)

        XCTAssertTrue(report.hasBlockingIssues)
        XCTAssertTrue(report.issues.contains { $0.severity == .error && $0.title == "重複帳戶 ID" })
    }

    func testValidate_danglingReferencesAreWarnings() {
        let missingAccountID = UUID()
        let missingCategoryID = UUID()
        let backup = makeBackup(
            transactions: [
                makeTransaction(amount: 10, currencyCode: "HKD", accountID: missingAccountID, categoryID: missingCategoryID)
            ]
        )

        let report = BackupValidationService.validate(backup)

        XCTAssertFalse(report.hasBlockingIssues)
        XCTAssertTrue(report.issues.contains { $0.severity == .warning && $0.title == "交易帳戶不存在" })
        XCTAssertTrue(report.issues.contains { $0.severity == .warning && $0.title == "交易分類不存在" })
    }

    private func makeBackup(
        accounts: [FullBackupData.AccountCodable] = [],
        categories: [FullBackupData.CategoryCodable] = [],
        tags: [FullBackupData.TagCodable] = [],
        transactions: [FullBackupData.TransactionCodable] = []
    ) -> FullBackupData {
        FullBackupData(
            version: "1.9",
            timestamp: Date(timeIntervalSince1970: 0),
            accounts: accounts,
            categories: categories,
            tags: tags,
            transactions: transactions,
            shortcuts: [],
            recurringRules: [],
            recurringOccurrences: [],
            budgets: [],
            budgetHistory: [],
            budgetSettings: [],
            advanceCases: [],
            advanceParticipants: [],
            advanceRepayments: []
        )
    }

    private func makeTransaction(
        amount: Decimal,
        currencyCode: String,
        accountID: UUID?,
        categoryID: UUID? = nil
    ) -> FullBackupData.TransactionCodable {
        FullBackupData.TransactionCodable(
            id: UUID(),
            amount: amount,
            currencyCode: currencyCode,
            date: Date(timeIntervalSince1970: 0),
            note: "Test transaction",
            type: TransactionType.expense.rawValue,
            linkedTransactionID: nil,
            transferGroupID: nil,
            transferSide: nil,
            photoPath: nil,
            createdAt: nil,
            updatedAt: nil,
            accountID: accountID,
            categoryID: categoryID,
            tagIDs: [],
            advanceCaseID: nil,
            advanceParticipantID: nil,
            advanceRepaymentID: nil,
            advanceEntryRole: nil
        )
    }
}
