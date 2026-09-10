import XCTest
import SwiftData
@testable import AI_記帳

@MainActor
final class CurrencyAvailabilityTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "CurrencyAvailabilityTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.set("HKD", forKey: "mainCurrency")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testMissingSourceRateDoesNotBecomeOneToOne() async throws {
        let service = CurrencyService(defaults: defaults)
        XCTAssertThrowsError(try service.convert(amount: 100, from: "USD"))
        XCTAssertNil(service.estimate(amount: 100, from: "USD", to: "HKD"))
    }

    func testMissingSourceCannotBeMultipliedByAvailableTargetRate() async throws {
        let service = CurrencyService(defaults: defaults)
        service.rates = ["EUR": 2]
        XCTAssertThrowsError(try service.convert(amount: 100, from: "USD", to: "EUR"))
    }

    func testMissingTargetAndInvalidRatesAreUnavailable() async throws {
        let service = CurrencyService(defaults: defaults)
        XCTAssertThrowsError(try service.convert(amount: 100, from: "HKD", to: "USD"))
        for invalid in [Double.zero, -1, .nan, .infinity, .greatestFiniteMagnitude, .leastNonzeroMagnitude] {
            service.rates = ["USD": invalid]
            XCTAssertThrowsError(try service.convert(amount: 100, from: "USD"))
            XCTAssertNil(service.estimate(amount: 100, from: "USD", to: "HKD"))
        }
    }

    func testSameCurrencyIsExactWithoutRatesAndNormalizesCodes() async throws {
        let service = CurrencyService(defaults: defaults)
        XCTAssertEqual(try service.convert(amount: 100, from: "usd", to: "USD"), 100)
        XCTAssertEqual(service.estimate(amount: 100, from: "usd", to: "USD")?.amount, 100)
    }

    func testValidConversionUsesBothRates() async throws {
        let service = CurrencyService(defaults: defaults)
        service.rates = ["USD": 2, "EUR": 4]
        XCTAssertEqual(try service.convert(amount: 100, from: "USD"), 50)
        XCTAssertEqual(try service.convert(amount: 100, from: "USD", to: "EUR"), 200)
    }

    func testTotalsDoNotPresentPartialOrMissingAmountsAsComplete() async throws {
        let service = CurrencyService(defaults: defaults)
        let partial = service.totalEstimate([(25, "HKD"), (100, "USD")])
        XCTAssertNil(partial.amount)
        XCTAssertEqual(partial.status, .partial)
        XCTAssertEqual(service.totalEstimate([(100, "USD")]).status, .unavailable)
        XCTAssertEqual(service.totalEstimate([(25, "HKD")]).status, .exact)
        XCTAssertEqual(service.totalEstimate([]).amount, 0)
        service.rates = ["USD": 2]
        XCTAssertEqual(service.totalEstimate([(25, "HKD"), (100, "USD")]).amount, 75)
        XCTAssertEqual(service.totalEstimate([(25, "HKD"), (100, "USD")]).status, .live)
    }

    func testMissingFXCannotRewritePreviouslyValidBudgetHistory() async throws {
        let service = CurrencyService(defaults: defaults)
        service.rates = ["USD": 2]
        let schema = Schema([Account.self, FinancialTransaction.self, Category.self, Tag.self, Shortcut.self, RecurringRule.self, RecurringOccurrence.self, CategoryMonthlyBudget.self, BudgetMonthlyHistory.self, BudgetSettings.self, AdvanceCase.self, AdvanceParticipant.self, AdvanceRepayment.self])
        let context = ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        context.autosaveEnabled = false
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-10T12:00:00Z"))
        var categories: [AI_記帳.Category] = []
        for currency in ["HKD", "USD"] {
            let category = Category(name: currency, icon: "cart", colorHex: "#123456", kind: .expense)
            context.insert(category)
            categories.append(category)
            context.insert(CategoryMonthlyBudget(monthKey: "2026-06", amount: 200, currencyCode: "HKD", category: category))
            let transaction = FinancialTransaction(amount: -100, currencyCode: currency, date: date)
            context.insert(transaction)
            transaction.category = category
        }
        try BudgetHistoryService.shared.syncAll(modelContext: context, currencyService: service)
        let histories = try context.fetch(FetchDescriptor<BudgetMonthlyHistory>())
        let original = Dictionary(uniqueKeysWithValues: histories.map { ($0.historyKey, $0.spentAmount) })
        XCTAssertEqual(Set(original.values), Set([Decimal(50), Decimal(100)]))
        service.rates = [:]
        let keys = categories.map { BudgetHistoryAffectedKey(monthKey: "2026-06", categoryID: $0.id) }
        for action in [
            { try BudgetHistoryService.shared.syncAll(modelContext: context, currencyService: service) },
            { try BudgetHistoryService.shared.syncAffected(keys: keys, modelContext: context, currencyService: service) }
        ] {
            XCTAssertThrowsError(try action())
            XCTAssertFalse(context.hasChanges, "Failed estimates must not even dirty an earlier valid snapshot")
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: histories.map { ($0.historyKey, $0.spentAmount) }), original)
            try context.save() // A later autosave must not leak partial history updates.
            let reader = ModelContext(context.container)
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: try reader.fetch(FetchDescriptor<BudgetMonthlyHistory>()).map { ($0.historyKey, $0.spentAmount) }), original)
        }
        XCTAssertThrowsError(try BudgetService.statuses(for: "2026-06", budgets: context.fetch(FetchDescriptor<CategoryMonthlyBudget>()), transactions: context.fetch(FetchDescriptor<FinancialTransaction>()), currencyService: service))
    }

    func testFreshAndStaleCacheRemainExplicitlyCached() async throws {
        struct Cache: Encodable { let base: String; let rates: [String: Double]; let fetchedAt: Date }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for age in [TimeInterval(60), TimeInterval(8 * 24 * 60 * 60)] {
            defaults.set(try JSONEncoder().encode(Cache(base: "HKD", rates: ["USD": 2], fetchedAt: now.addingTimeInterval(-age))), forKey: "cachedExchangeRatesV2")
            let service = CurrencyService(defaults: defaults, now: { now })
            let result = try XCTUnwrap(service.estimate(amount: 100, from: "USD", to: "HKD"))
            XCTAssertEqual(result.amount, 50)
            XCTAssertEqual(result.source, .cached)
            XCTAssertEqual(service.totalEstimate([(100, "USD")]).status, .cached)
        }
    }
}
