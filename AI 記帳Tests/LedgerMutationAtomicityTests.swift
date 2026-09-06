import XCTest
import SwiftData
@testable import AI_記帳

@MainActor
final class LedgerMutationAtomicityTests: XCTestCase {
    private enum InjectedFailure: Error { case budget, save }

    func testAddRollsBackAllSplitLegsAndPartialBudgetChangesThenRetryCommitsOnce() throws {
        let fixture = try Fixture()
        let drafts = [fixture.draft(amount: 20), fixture.draft(amount: 30)]
        XCTAssertThrowsError(try LedgerMutationService.add(
            drafts, modelContext: fixture.context,
            synchronize: fixture.failAfterUpdatingHistory
        ))
        try fixture.assertUnchanged()
        // A subsequent save must not leak failed inserts through autosave or a later action.
        try fixture.context.save()
        try fixture.assertUnchanged()

        _ = try LedgerMutationService.add(drafts, modelContext: fixture.context)
        let reader = ModelContext(fixture.context.container)
        XCTAssertEqual(2, try reader.fetch(FetchDescriptor<FinancialTransaction>()).count)
        XCTAssertEqual(50, try XCTUnwrap(reader.fetch(FetchDescriptor<BudgetMonthlyHistory>()).first).spentAmount)
    }

    func testEditFailureRestoresLedgerAndBothOldAndNewBudgetKeys() throws {
        let fixture = try Fixture()
        let transaction = try XCTUnwrap(LedgerMutationService.add(
            [fixture.draft(amount: 20)], modelContext: fixture.context
        ).first)
        let oldKey = try XCTUnwrap(BudgetHistoryService.affectedKey(for: transaction))
        let secondCategory = Category(name: "Travel", icon: "tram", colorHex: "#123456", kind: .expense)
        fixture.context.insert(secondCategory)
        fixture.context.insert(CategoryMonthlyBudget(monthKey: "2026-06", amount: 200, currencyCode: "HKD", category: secondCategory))
        try BudgetHistoryService.shared.syncAll(modelContext: fixture.context, currencyService: .shared)
        let draft = OrdinaryTransactionEditDraft(amount: 80, currencyCode: "HKD", date: fixture.date, note: "Changed", type: .expense, account: fixture.account, category: secondCategory, tags: [])
        var capturedKeys: [BudgetHistoryAffectedKey] = []
        XCTAssertThrowsError(try LedgerMutationService.edit(
            transaction, draft: draft, modelContext: fixture.context,
            synchronize: { context, keys in
                capturedKeys = keys
                try BudgetHistoryService.shared.syncAffected(keys: keys, modelContext: context, currencyService: .shared, save: false)
                throw InjectedFailure.budget
            }
        ))
        XCTAssertEqual(Set([oldKey, BudgetHistoryAffectedKey(monthKey: "2026-06", categoryID: secondCategory.id)]), Set(capturedKeys))
        XCTAssertEqual(-20, transaction.amount)
        XCTAssertEqual(fixture.category.id, transaction.category?.id)
        let reader = ModelContext(fixture.context.container)
        XCTAssertEqual(-20, try XCTUnwrap(reader.fetch(FetchDescriptor<FinancialTransaction>()).first).amount)
        XCTAssertEqual([Decimal.zero, Decimal(20)], try reader.fetch(FetchDescriptor<BudgetMonthlyHistory>()).map(\.spentAmount).sorted())
    }

    func testDeleteFailureRestoresTransactionAndBudgetThenRetryRemovesIt() throws {
        let fixture = try Fixture()
        let transaction = try XCTUnwrap(LedgerMutationService.add([fixture.draft(amount: 20)], modelContext: fixture.context).first)
        XCTAssertThrowsError(try LedgerDeletionService.delete(
            transaction: transaction, modelContext: fixture.context,
            synchronize: fixture.failAfterUpdatingHistory
        ))
        XCTAssertEqual(1, try fixture.context.fetch(FetchDescriptor<FinancialTransaction>()).count)
        XCTAssertEqual(20, try XCTUnwrap(fixture.context.fetch(FetchDescriptor<BudgetMonthlyHistory>()).first).spentAmount)
        try LedgerDeletionService.delete(transaction: transaction, modelContext: fixture.context)
        let reader = ModelContext(fixture.context.container)
        XCTAssertTrue(try reader.fetch(FetchDescriptor<FinancialTransaction>()).isEmpty)
        XCTAssertEqual(0, try XCTUnwrap(reader.fetch(FetchDescriptor<BudgetMonthlyHistory>()).first).spentAmount)
    }

    func testScannedDraftUsesSameFailureBoundaryAndDoesNotSignalSuccess() throws {
        let fixture = try Fixture()
        var completed = false
        do {
            _ = try LedgerMutationService.add([fixture.draft(amount: 45)], modelContext: fixture.context, synchronize: fixture.failAfterUpdatingHistory)
            completed = true // The scan view closes only after the service returns.
        } catch {}
        XCTAssertFalse(completed)
        try fixture.assertUnchanged()
    }

    func testShortcutFailureThenRetryCreatesOneEntryAndUpdatesBudget() throws {
        let fixture = try Fixture()
        let shortcut = Shortcut(name: "Coffee", icon: "cup.and.saucer", amount: 25, currencyCode: "HKD", type: .expense, note: "", account: fixture.account, category: fixture.category)
        fixture.context.insert(shortcut)
        try fixture.context.save()
        XCTAssertThrowsError(try LedgerMutationService.executeShortcut(shortcut, date: fixture.date, modelContext: fixture.context, synchronize: fixture.failAfterUpdatingHistory))
        try fixture.assertUnchanged()
        _ = try LedgerMutationService.executeShortcut(shortcut, date: fixture.date, modelContext: fixture.context)
        let reader = ModelContext(fixture.context.container)
        XCTAssertEqual(1, try reader.fetch(FetchDescriptor<FinancialTransaction>()).count)
        XCTAssertEqual(25, try XCTUnwrap(reader.fetch(FetchDescriptor<BudgetMonthlyHistory>()).first).spentAmount)
    }

    func testAffectedSyncSeesPendingDateMoveAndDeletion() throws {
        let fixture = try Fixture()
        let transaction = try XCTUnwrap(LedgerMutationService.add([fixture.draft(amount: 20)], modelContext: fixture.context).first)
        fixture.context.insert(CategoryMonthlyBudget(monthKey: "2026-07", amount: 100, currencyCode: "HKD", category: fixture.category))
        try fixture.context.save()
        let july = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-10T12:00:00Z"))
        let draft = OrdinaryTransactionEditDraft(amount: 40, currencyCode: "HKD", date: july, note: "Moved", type: .expense, account: fixture.account, category: fixture.category, tags: [])
        try LedgerMutationService.edit(transaction, draft: draft, modelContext: fixture.context)
        let histories = try fixture.context.fetch(FetchDescriptor<BudgetMonthlyHistory>())
        XCTAssertEqual(0, histories.first { $0.monthKey == "2026-06" }?.spentAmount)
        XCTAssertEqual(40, histories.first { $0.monthKey == "2026-07" }?.spentAmount)
        try LedgerDeletionService.delete(transaction: transaction, modelContext: fixture.context)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<BudgetMonthlyHistory>()).allSatisfy { $0.spentAmount == 0 })
    }

    func testGroupedTransferDeletionFailureRestoresBothLegsAndRetryDeletesBoth() throws {
        let fixture = try Fixture()
        let groupID = UUID()
        let debit = FinancialTransaction(amount: -50, type: .transfer, transferGroupID: groupID)
        let credit = FinancialTransaction(amount: 50, type: .transfer, transferGroupID: groupID)
        fixture.context.insert(debit)
        fixture.context.insert(credit)
        debit.account = fixture.account
        credit.account = fixture.account
        try fixture.context.save()
        XCTAssertThrowsError(try LedgerDeletionService.delete(
            transaction: debit, modelContext: fixture.context,
            synchronize: { _, _ in throw InjectedFailure.budget }
        ))
        let reader = ModelContext(fixture.context.container)
        XCTAssertEqual(2, try reader.fetch(FetchDescriptor<FinancialTransaction>()).count)
        XCTAssertEqual(2, try fixture.context.fetch(FetchDescriptor<FinancialTransaction>()).count)
        try LedgerDeletionService.delete(transaction: debit, modelContext: fixture.context)
        XCTAssertTrue(try ModelContext(fixture.context.container).fetch(FetchDescriptor<FinancialTransaction>()).isEmpty)
    }

    func testFailureRestoresAutosaveSetting() throws {
        let fixture = try Fixture()
        for autosave in [false, true] {
            fixture.context.autosaveEnabled = autosave
            XCTAssertThrowsError(try LedgerMutationService.add([fixture.draft(amount: 20)], modelContext: fixture.context, synchronize: fixture.failAfterUpdatingHistory))
            XCTAssertEqual(autosave, fixture.context.autosaveEnabled)
            try fixture.assertUnchanged()
        }
    }

    private struct Fixture {
        let context: ModelContext
        let account: Account
        let category: AI_記帳.Category
        let date: Date

        init() throws {
            let schema = Schema([Account.self, FinancialTransaction.self, Category.self, Tag.self, Shortcut.self, RecurringRule.self, RecurringOccurrence.self, CategoryMonthlyBudget.self, BudgetMonthlyHistory.self, BudgetSettings.self, AdvanceCase.self, AdvanceParticipant.self, AdvanceRepayment.self])
            context = ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
            account = Account(name: "Wallet", currency: "HKD", type: .cash, baseBalance: 0)
            category = Category(name: "Dining", icon: "fork.knife", colorHex: "#123456", kind: .expense)
            date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-10T12:00:00Z"))
            context.insert(account)
            context.insert(category)
            context.insert(CategoryMonthlyBudget(monthKey: "2026-06", amount: 100, currencyCode: "HKD", category: category))
            try BudgetHistoryService.shared.syncAll(modelContext: context, currencyService: .shared)
        }

        func draft(amount: Decimal) -> OrdinaryTransactionEditDraft {
            OrdinaryTransactionEditDraft(amount: amount, currencyCode: "HKD", date: date, note: "Test", type: .expense, account: account, category: category, tags: [])
        }

        func failAfterUpdatingHistory(_ context: ModelContext, _ keys: [BudgetHistoryAffectedKey]) throws {
            try BudgetHistoryService.shared.syncAffected(keys: keys, modelContext: context, currencyService: .shared, save: false)
            throw InjectedFailure.budget
        }

        func assertUnchanged(file: StaticString = #filePath, line: UInt = #line) throws {
            XCTAssertTrue(try context.fetch(FetchDescriptor<FinancialTransaction>()).isEmpty, file: file, line: line)
            XCTAssertEqual(0, try XCTUnwrap(context.fetch(FetchDescriptor<BudgetMonthlyHistory>()).first).spentAmount, file: file, line: line)
            let reader = ModelContext(context.container)
            XCTAssertTrue(try reader.fetch(FetchDescriptor<FinancialTransaction>()).isEmpty, file: file, line: line)
            XCTAssertEqual(0, try XCTUnwrap(reader.fetch(FetchDescriptor<BudgetMonthlyHistory>()).first).spentAmount, file: file, line: line)
        }
    }
}
