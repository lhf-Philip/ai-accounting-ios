import XCTest
import SwiftData
@testable import AI_記帳

@MainActor
final class AdvanceLifecycleCharacterisationTests: XCTestCase {
    func testBorrowedAdvanceLifecycleKeepsBudgetHistoryConsistent() throws {
        let context = try makeContext()
        let ownAccount = Account(name: "Wallet", currency: "HKD", type: .cash, baseBalance: 0)
        let debtAccount = Account(name: "Friend", currency: "HKD", type: .debt, baseBalance: 0)
        let category = Category(
            name: "Dining",
            icon: "fork.knife",
            colorHex: "#123456",
            kind: .expense
        )
        let budget = CategoryMonthlyBudget(
            monthKey: "2026-06",
            amount: 500,
            currencyCode: "HKD",
            category: category
        )
        [ownAccount, debtAccount].forEach(context.insert)
        context.insert(category)
        context.insert(budget)
        try context.save()

        let advanceCase = try AdvanceService.createAdvanceCase(
            title: "Dinner",
            date: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-10T10:00:00Z")),
            currencyCode: "HKD",
            myShareAmount: 0,
            note: "",
            payerAccount: nil,
            category: category,
            tags: [],
            participants: [.init(debtAccount: debtAccount, owedAmount: 150)],
            isBorrowedByMe: true,
            modelContext: context
        )

        let createdHistory = try XCTUnwrap(
            context.fetch(FetchDescriptor<BudgetMonthlyHistory>()).first
        )
        XCTAssertEqual(Decimal(150), createdHistory.spentAmount)
        XCTAssertEqual(Decimal(350), createdHistory.remainingAmount)
        XCTAssertEqual(1, try context.fetch(FetchDescriptor<AdvanceCase>()).count)
        XCTAssertEqual(
            [Decimal(-150)],
            try context.fetch(FetchDescriptor<FinancialTransaction>()).map(\.amount)
        )

        _ = try AdvanceService.deleteAdvanceCase(
            advanceCase,
            deleteLinkedTransactions: true,
            modelContext: context
        )

        let deletedHistory = try XCTUnwrap(
            context.fetch(FetchDescriptor<BudgetMonthlyHistory>()).first
        )
        XCTAssertEqual(Decimal.zero, deletedHistory.spentAmount)
        XCTAssertEqual(Decimal(500), deletedHistory.remainingAmount)
        XCTAssertTrue(try context.fetch(FetchDescriptor<AdvanceCase>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<FinancialTransaction>()).isEmpty)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Account.self,
            FinancialTransaction.self,
            Category.self,
            Tag.self,
            Shortcut.self,
            RecurringRule.self,
            RecurringOccurrence.self,
            CategoryMonthlyBudget.self,
            BudgetMonthlyHistory.self,
            BudgetSettings.self,
            AdvanceCase.self,
            AdvanceParticipant.self,
            AdvanceRepayment.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}
