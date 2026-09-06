import XCTest
import SwiftData
@testable import AI_記帳

@MainActor
final class MissingFXMutationTests: XCTestCase {
    func testAdvanceCreationMissingFXRollsBackGraphAndRetryCreatesOneCase() async throws {
        let fixture = try Fixture()
        let rates = CurrencyService.shared.rates
        defer { CurrencyService.shared.rates = rates }
        CurrencyService.shared.rates["ZZZ"] = nil
        func create() throws -> AdvanceCase {
            try AdvanceService.createAdvanceCase(title: "FX", date: fixture.date, currencyCode: "ZZZ", myShareAmount: 20, note: "", payerAccount: fixture.cash, category: fixture.category, tags: [], participants: [.init(debtAccount: fixture.debt, owedAmount: 80)], modelContext: fixture.context)
        }
        XCTAssertThrowsError(try create())
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<AdvanceCase>()).isEmpty)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<AdvanceParticipant>()).isEmpty)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<FinancialTransaction>()).isEmpty)
        XCTAssertFalse(fixture.context.hasChanges)
        try fixture.context.save()
        XCTAssertTrue(try ModelContext(fixture.context.container).fetch(FetchDescriptor<FinancialTransaction>()).isEmpty)
        CurrencyService.shared.rates["ZZZ"] = 2
        _ = try create()
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<AdvanceCase>()).count, 1)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<FinancialTransaction>()).count, 3)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<BudgetMonthlyHistory>()).first?.spentAmount, 10)
    }

    func testRecurringMissingFXKeepsOccurrencePendingAndRetryDoesNotDuplicate() async throws {
        let fixture = try Fixture()
        let rates = CurrencyService.shared.rates
        defer { CurrencyService.shared.rates = rates }
        CurrencyService.shared.rates["ZZZ"] = nil
        let rule = RecurringRule(title: "FX", amount: 20, currencyCode: "ZZZ", type: .expense, account: fixture.cash, category: fixture.category)
        fixture.context.insert(rule)
        let occurrence = RecurringOccurrence(dueDate: fixture.date, rule: rule)
        fixture.context.insert(occurrence)
        try fixture.context.save()
        XCTAssertThrowsError(try RecurringTransactionService.confirm(occurrence: occurrence, modelContext: fixture.context))
        XCTAssertEqual(occurrence.status, .pending)
        XCTAssertNil(occurrence.createdTransactionID)
        XCTAssertTrue(try ModelContext(fixture.context.container).fetch(FetchDescriptor<FinancialTransaction>()).isEmpty)
        CurrencyService.shared.rates["ZZZ"] = 2
        let first = try RecurringTransactionService.confirm(occurrence: occurrence, modelContext: fixture.context)
        let second = try RecurringTransactionService.confirm(occurrence: occurrence, modelContext: fixture.context)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<FinancialTransaction>()).count, 1)
        XCTAssertEqual(occurrence.status, .confirmed)
    }

    func testAccountDeletionMissingFXPreservesAccountAndPreviousHistory() async throws {
        let fixture = try Fixture()
        let rates = CurrencyService.shared.rates
        defer { CurrencyService.shared.rates = rates }
        CurrencyService.shared.rates["ZZZ"] = 2
        let other = Account(name: "Other", currency: "ZZZ", type: .cash, baseBalance: 0)
        fixture.context.insert(other)
        let tx = FinancialTransaction(amount: -20, currencyCode: "ZZZ", date: fixture.date)
        fixture.context.insert(tx)
        tx.account = other
        tx.category = fixture.category
        try BudgetHistoryService.shared.syncAll(modelContext: fixture.context, currencyService: .shared)
        let impact = try AccountDeletionCoordinator.preview(account: fixture.cash, modelContext: fixture.context)
        CurrencyService.shared.rates["ZZZ"] = nil
        XCTAssertThrowsError(try AccountDeletionCoordinator.deleteAccount(using: impact, modelContext: fixture.context))
        let reader = ModelContext(fixture.context.container)
        XCTAssertTrue(try reader.fetch(FetchDescriptor<Account>()).contains { $0.id == fixture.cash.id })
        XCTAssertEqual(try reader.fetch(FetchDescriptor<BudgetMonthlyHistory>()).first?.spentAmount, 10)
        CurrencyService.shared.rates["ZZZ"] = 2
        try AccountDeletionCoordinator.deleteAccount(using: impact, modelContext: fixture.context)
        XCTAssertFalse(try ModelContext(fixture.context.container).fetch(FetchDescriptor<Account>()).contains { $0.id == fixture.cash.id })
    }

    func testBudgetBatchFailureRestoresRetainedBudgetAndDropsNewBudgetBeforeRetry() async throws {
        let fixture = try Fixture()
        let rates = CurrencyService.shared.rates
        defer { CurrencyService.shared.rates = rates }
        CurrencyService.shared.rates["ZZZ"] = nil
        let budget = try XCTUnwrap(fixture.context.fetch(FetchDescriptor<CategoryMonthlyBudget>()).first)
        XCTAssertThrowsError(try BudgetHistoryService.shared.mutateBudgets(modelContext: fixture.context, currencyService: .shared) {
            budget.amount = 300
            fixture.context.insert(CategoryMonthlyBudget(monthKey: "2026-07", amount: 200, currencyCode: CurrencyService.shared.mainCurrency, category: fixture.category))
            _ = try CurrencyService.shared.convert(amount: 100, from: "ZZZ")
        })
        XCTAssertEqual(budget.amount, 100)
        XCTAssertFalse(fixture.context.hasChanges)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<CategoryMonthlyBudget>()).count, 1)
        try BudgetHistoryService.shared.mutateBudgets(modelContext: fixture.context, currencyService: .shared) {
            budget.amount = 150
            fixture.context.insert(CategoryMonthlyBudget(monthKey: "2026-07", amount: 200, currencyCode: CurrencyService.shared.mainCurrency, category: fixture.category))
        }
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<CategoryMonthlyBudget>()).count, 2)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<BudgetMonthlyHistory>()).count, 2)
    }

    func testAdvanceDeletionMissingFXPreservesBothCasesThenRetryDeletesOnlyTarget() async throws {
        let fixture = try Fixture()
        let rates = CurrencyService.shared.rates
        defer { CurrencyService.shared.rates = rates }
        CurrencyService.shared.rates["ZZZ"] = 2
        var cases: [AdvanceCase] = []
        for _ in 0..<2 {
            cases.append(try AdvanceService.createAdvanceCase(title: "FX", date: fixture.date, currencyCode: "ZZZ", myShareAmount: 20, note: "", payerAccount: fixture.cash, category: fixture.category, tags: [], participants: [.init(debtAccount: fixture.debt, owedAmount: 80)], modelContext: fixture.context))
        }
        CurrencyService.shared.rates["ZZZ"] = nil
        XCTAssertThrowsError(try AdvanceService.deleteAdvanceCase(cases[0], deleteLinkedTransactions: true, modelContext: fixture.context))
        XCTAssertEqual(try ModelContext(fixture.context.container).fetch(FetchDescriptor<AdvanceCase>()).count, 2)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<FinancialTransaction>()).count, 6)
        CurrencyService.shared.rates["ZZZ"] = 2
        _ = try AdvanceService.deleteAdvanceCase(cases[0], deleteLinkedTransactions: true, modelContext: fixture.context)
        XCTAssertEqual(try ModelContext(fixture.context.container).fetch(FetchDescriptor<AdvanceCase>()).count, 1)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<FinancialTransaction>()).count, 3)
    }

    private struct Fixture {
        let context: ModelContext
        let cash: Account
        let debt: Account
        let category: AI_記帳.Category
        let date: Date
        init() throws {
            let schema = Schema([Account.self, FinancialTransaction.self, Category.self, Tag.self, Shortcut.self, RecurringRule.self, RecurringOccurrence.self, CategoryMonthlyBudget.self, BudgetMonthlyHistory.self, BudgetSettings.self, AdvanceCase.self, AdvanceParticipant.self, AdvanceRepayment.self])
            context = ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
            context.autosaveEnabled = false
            cash = Account(name: "Cash", currency: "ZZZ", type: .cash, baseBalance: 0)
            debt = Account(name: "Person", currency: "ZZZ", type: .debt, baseBalance: 0)
            category = Category(name: "Food", icon: "cart", colorHex: "#123456", kind: .expense)
            date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-10T12:00:00Z"))
            context.insert(cash)
            context.insert(debt)
            context.insert(category)
            context.insert(CategoryMonthlyBudget(monthKey: "2026-06", amount: 100, currencyCode: CurrencyService.shared.mainCurrency, category: category))
            try BudgetHistoryService.shared.syncAll(modelContext: context, currencyService: .shared)
        }
    }
}
