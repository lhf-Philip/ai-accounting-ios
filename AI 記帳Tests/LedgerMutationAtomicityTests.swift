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

    func testPendingUnrelatedWorkRejectsSuccessfulAndFailingMutationsWithoutSavingOrRollback() throws {
        for pendingKind in ["edit", "insert", "delete"] {
            for failSynchronization in [false, true] {
                let fixture = try Fixture()
                fixture.context.autosaveEnabled = false
                let unrelated = Account(name: "Unrelated", currency: "HKD", type: .cash, baseBalance: 7)
                if pendingKind != "insert" {
                    fixture.context.insert(unrelated)
                    try fixture.context.save()
                }
                switch pendingKind {
                case "edit": unrelated.name = "Pending name"
                case "insert": fixture.context.insert(unrelated)
                default: fixture.context.delete(unrelated)
                }
                XCTAssertTrue(fixture.context.hasChanges)
                var synchronized = false
                XCTAssertThrowsError(try LedgerMutationService.add(
                    [fixture.draft(amount: 20)], modelContext: fixture.context,
                    synchronize: { context, keys in
                        synchronized = true
                        if failSynchronization { throw InjectedFailure.budget }
                        try LedgerMutationService.synchronizeBudget(context, keys)
                    }
                ), "Must reject a dirty context before touching it")
                XCTAssertFalse(synchronized)
                XCTAssertTrue(fixture.context.hasChanges)
                XCTAssertFalse(fixture.context.autosaveEnabled)
                if pendingKind == "edit" { XCTAssertEqual("Pending name", unrelated.name) }
                if pendingKind == "insert" { XCTAssertTrue(fixture.context.insertedModelsArray.contains { $0 === unrelated }) }
                if pendingKind == "delete" { XCTAssertTrue(fixture.context.deletedModelsArray.contains { $0 === unrelated }) }
                let reader = ModelContext(fixture.context.container)
                let stored = try reader.fetch(FetchDescriptor<Account>()).first { $0.id == unrelated.id }
                XCTAssertEqual(pendingKind == "insert" ? nil : "Unrelated", stored?.name)
                try fixture.assertUnchanged()
                // Only the owner resolves its pending work. The ledger retry then commits once.
                try fixture.context.save()
                _ = try LedgerMutationService.add([fixture.draft(amount: 20)], modelContext: fixture.context)
                XCTAssertEqual(1, try ModelContext(fixture.context.container).fetch(FetchDescriptor<FinancialTransaction>()).count)
            }
        }
    }

    func testDirtyContextAlsoRejectsEditDeleteAndShortcutBeforeChangingLedger() throws {
        for operation in ["edit", "delete", "shortcut"] {
            let fixture = try Fixture()
            fixture.context.autosaveEnabled = false
            let transaction = try XCTUnwrap(LedgerMutationService.add([fixture.draft(amount: 20)], modelContext: fixture.context).first)
            let shortcut = Shortcut(name: "Coffee", icon: "cup.and.saucer", amount: 25, currencyCode: "HKD", type: .expense, note: "", account: fixture.account, category: fixture.category)
            fixture.context.insert(shortcut)
            try fixture.context.save()
            fixture.account.name = "Pending wallet name"
            XCTAssertThrowsError(try {
                switch operation {
                case "edit": try LedgerMutationService.edit(transaction, draft: fixture.draft(amount: 99), modelContext: fixture.context)
                case "delete": try LedgerDeletionService.delete(transaction: transaction, modelContext: fixture.context)
                default: _ = try LedgerMutationService.executeShortcut(shortcut, date: fixture.date, modelContext: fixture.context)
                }
            }())
            XCTAssertEqual("Pending wallet name", fixture.account.name)
            XCTAssertTrue(fixture.context.hasChanges)
            let reader = ModelContext(fixture.context.container)
            let transactions = try reader.fetch(FetchDescriptor<FinancialTransaction>())
            XCTAssertEqual(1, transactions.count)
            XCTAssertEqual(-20, transactions.first?.amount)
            XCTAssertEqual("Wallet", try reader.fetch(FetchDescriptor<Account>()).first?.name)
        }
    }

    func testNewTagCommitLeavesCleanContextForLedgerDraft() throws {
        let fixture = try Fixture()
        let tag = try LedgerMutationService.atomic(modelContext: fixture.context) {
            let tag = Tag(name: "New tag")
            fixture.context.insert(tag)
            return tag
        }
        XCTAssertFalse(fixture.context.hasChanges)
        let draft = OrdinaryTransactionEditDraft(amount: 20, currencyCode: "HKD", date: fixture.date, note: "Tagged", type: .expense, account: fixture.account, category: fixture.category, tags: [tag])
        _ = try LedgerMutationService.add([draft], modelContext: fixture.context)
        let reader = ModelContext(fixture.context.container)
        XCTAssertEqual([tag.id], try reader.fetch(FetchDescriptor<FinancialTransaction>()).first?.tags.map(\.id))
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
