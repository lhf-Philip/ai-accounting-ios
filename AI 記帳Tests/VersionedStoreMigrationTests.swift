import XCTest
import SwiftData
@testable import AI_記帳

@Model
private final class UnsupportedMigrationRecord {
    var payload: String
    init(payload: String) { self.payload = payload }
}

private enum FailingCategoryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { AccountingMigrationPlan.schemas }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: AccountingSchemaV1.self, toVersion: AccountingSchemaV2.self),
         .custom(fromVersion: AccountingSchemaV2.self, toVersion: AccountingSchemaV3.self,
                 willMigrate: nil, didMigrate: { context in
             let categories = try context.fetch(FetchDescriptor<AI_記帳.Category>())
             for category in categories { category.storedKind = .both }
             throw NSError(domain: "InjectedMigrationStage", code: 169)
         })]
    }
}

@MainActor
final class VersionedStoreMigrationTests: XCTestCase {
    private typealias V2 = AccountingSchemaV2
    private let storeName = "AI_Accounting_v3.store"
    private let date = Date(timeIntervalSince1970: 1700000000)

    func testPreviouslyAutomaticallyOpenedLegacyStoreBackfillsMissingKind() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/SwiftData")
        for suffix in ["", "-wal", "-shm"] {
            try FileManager.default.copyItem(at: fixtures.appendingPathComponent("v1.0.1-populated.store" + suffix),
                                            to: directory.appendingPathComponent(storeName + suffix))
        }
        try autoreleasepool {
            // Recreate main's successful automatic open without accessing its unsafe getter.
            let schema = Schema(V2.models)
            let container = try ModelContainer(for: schema, configurations: [configuration(schema, directory)])
            XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<V2.Category>()), 1)
        }
        for _ in 0..<2 {
            try autoreleasepool {
                let container = try open(directory)
                let context = ModelContext(container)
                let category = try one(Category.self, context, id: id(2))
                XCTAssertEqual(category.storedKind, .both)
                XCTAssertEqual(category.kind, .both)
                let accounts = try context.fetch(FetchDescriptor<Account>())
                XCTAssertEqual(accounts.count, 2)
                XCTAssertEqual(accounts.first { $0.id == id(1) }?.currentBalance, decimal("1114.41"))
                XCTAssertEqual(accounts.first { $0.id == id(6) }?.currentBalance, decimal("62.80"))
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<FinancialTransaction>()), 4)
            }
        }
    }

    func testUnversionedCurrentGraphPreservesKindsAndAllThirteenModels() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedCurrentGraph(directory)
        for _ in 0..<2 {
            try autoreleasepool {
                let container = try open(directory)
                let context = ModelContext(container)
                let categories = try context.fetch(FetchDescriptor<AI_記帳.Category>())
                XCTAssertEqual(categories.count, 3)
                for (index, expected) in [(2, CategoryKind.expense), (14, .income), (15, .both)] {
                    let category = try XCTUnwrap(categories.first { $0.id == id(index) })
                    XCTAssertEqual(category.storedKind, expected)
                    XCTAssertEqual(category.kind, expected)
                }
                let account = try one(Account.self, context, id: id(1))
                XCTAssertEqual(account.currentBalance, decimal("64.41"))
                let transaction = try one(FinancialTransaction.self, context, id: id(4))
                XCTAssertEqual(transaction.amount, decimal("-35.59"))
                XCTAssertEqual(transaction.type, .expense)
                XCTAssertEqual(transaction.account?.id, id(1))
                XCTAssertEqual(transaction.category?.id, id(2))
                XCTAssertEqual(transaction.tags.map(\.id), [id(3)])
                XCTAssertEqual(transaction.date, date)
                _ = try one(Tag.self, context, id: id(3))
                let shortcut = try one(Shortcut.self, context, id: id(5))
                XCTAssertEqual(shortcut.category?.id, id(2))
                XCTAssertEqual(shortcut.account?.id, id(1))
                XCTAssertEqual(shortcut.tags.map(\.id), [id(3)])
                let advance = try one(AdvanceCase.self, context, id: id(6))
                XCTAssertEqual(advance.direction, .iAdvancedOthers)
                XCTAssertEqual(advance.tagIDs, [id(3)])
                XCTAssertEqual(advance.payerAccount?.id, id(1))
                XCTAssertEqual(advance.expenseCategory?.id, id(2))
                let participant = try one(AdvanceParticipant.self, context, id: id(7))
                XCTAssertEqual(participant.advanceCase?.id, id(6))
                XCTAssertEqual(participant.owedAmount, decimal("20.25"))
                let repayment = try one(AdvanceRepayment.self, context, id: id(8))
                XCTAssertEqual(repayment.advanceCase?.id, id(6))
                XCTAssertEqual(repayment.participant?.id, id(7))
                XCTAssertEqual(repayment.receivedAccount?.id, id(1))
                XCTAssertEqual(repayment.normalizedAmount, decimal("10.10"))
                let rule = try one(RecurringRule.self, context, id: id(9))
                XCTAssertEqual(rule.category?.id, id(2))
                XCTAssertEqual(rule.account?.id, id(1))
                XCTAssertEqual(rule.tags.map(\.id), [id(3)])
                XCTAssertEqual(rule.amount, decimal("8.25"))
                XCTAssertEqual(rule.frequency, .monthly)
                let occurrence = try one(RecurringOccurrence.self, context, id: id(10))
                XCTAssertEqual(occurrence.rule?.id, id(9))
                XCTAssertEqual(occurrence.status, .pending)
                let budget = try one(CategoryMonthlyBudget.self, context, id: id(11))
                XCTAssertEqual(budget.category?.id, id(2))
                XCTAssertEqual(budget.amount, decimal("500.50"))
                let history = try one(BudgetMonthlyHistory.self, context, id: id(12))
                XCTAssertEqual(history.categoryID, id(2))
                XCTAssertEqual(history.spentAmount, decimal("35.59"))
                let settings = try context.fetch(FetchDescriptor<BudgetSettings>())
                XCTAssertEqual(settings.count, 1)
                XCTAssertEqual(settings.first?.id, "global")
                XCTAssertEqual(settings.first?.carryOverMode, .netBalance)
                XCTAssertEqual(settings.first?.alertThresholdPercent, decimal("85.50"))
                // Exercise every JSON snapshot fetch on the migrated full graph too.
                let backup = try BackupManager.shared.createBackupData(modelContext: context)
                XCTAssertEqual(backup.categories.count, 3)
            }
        }
    }

    func testNewStoreCategoryKindEditsSurviveReopen() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try autoreleasepool {
            let container = try open(directory)
            container.mainContext.insert(Category(id: id(2), name: "Synthetic", icon: "folder", colorHex: "#123456", kind: .expense))
            try container.mainContext.save()
        }
        var previous = CategoryKind.expense
        for next in [CategoryKind.income, .both, .expense] {
            try autoreleasepool {
                let container = try open(directory)
                let category = try one(Category.self, container.mainContext, id: id(2))
                XCTAssertEqual(category.kind, previous)
                XCTAssertEqual(category.storedKind, previous)
                category.kind = next
                try container.mainContext.save()
            }
            previous = next
        }
        try autoreleasepool {
            let container = try open(directory)
            XCTAssertEqual(try one(Category.self, container.mainContext, id: id(2)).storedKind, .expense)
        }
    }

    func testUnsupportedSchemaEntersRecoveryAndPreservesOriginalSnapshot() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try autoreleasepool {
            let schema = Schema([UnsupportedMigrationRecord.self])
            let container = try ModelContainer(for: schema, configurations: [configuration(schema, directory)])
            container.mainContext.insert(UnsupportedMigrationRecord(payload: "Synthetic unknown schema"))
            try container.mainContext.save()
        }
        var original: [String: Data] = [:]
        for suffix in ["", "-wal", "-shm"] {
            let url = directory.appendingPathComponent(storeName + suffix)
            if FileManager.default.fileExists(atPath: url.path) { original[suffix] = try Data(contentsOf: url) }
        }
        guard case .failure(let failure) = StoreStartupService(documents: { directory }, prepare: { _ in }).load() else {
            return XCTFail("Unknown schema must not open a replacement empty ledger")
        }
        XCTAssertEqual(failure.stage, .container)
        let snapshot = try XCTUnwrap(failure.backupURL)
        for (suffix, data) in original {
            XCTAssertEqual(try Data(contentsOf: snapshot.appendingPathComponent(storeName + suffix)), data)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(storeName).path))
    }

    func testMigrationStageFailureKeepsSnapshotUsableByRealPlan() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/SwiftData")
        var original: [String: Data] = [:]
        for suffix in ["", "-wal", "-shm"] {
            let source = fixtures.appendingPathComponent("v1.0.1-populated.store" + suffix)
            original[suffix] = try Data(contentsOf: source)
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(storeName + suffix))
        }
        let service = StoreStartupService(documents: { directory }, prepare: { _ in }, open: { url in
            let schema = StoreStartupService.schema()
            return try ModelContainer(for: schema, migrationPlan: FailingCategoryMigrationPlan.self,
                                      configurations: [ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)])
        })
        guard case .failure(let failure) = service.load() else { return XCTFail("Expected migration-stage failure") }
        XCTAssertEqual(failure.stage, .container)
        let snapshot = try XCTUnwrap(failure.backupURL)
        for (suffix, bytes) in original {
            XCTAssertEqual(try Data(contentsOf: snapshot.appendingPathComponent(storeName + suffix)), bytes)
        }
        let recovered = directory.appendingPathComponent("recovered", isDirectory: true)
        try FileManager.default.copyItem(at: snapshot, to: recovered)
        for _ in 0..<2 {
            try autoreleasepool {
                let container = try open(recovered)
                let context = ModelContext(container)
                XCTAssertEqual(try one(Category.self, context, id: id(2)).storedKind, .both)
                let accounts = try context.fetch(FetchDescriptor<Account>())
                XCTAssertEqual(accounts.count, 2)
                XCTAssertEqual(accounts.first { $0.id == id(1) }?.currentBalance, decimal("1114.41"))
                XCTAssertEqual(accounts.first { $0.id == id(6) }?.currentBalance, decimal("62.80"))
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<FinancialTransaction>()), 4)
            }
        }
        for (suffix, bytes) in original {
            XCTAssertEqual(try Data(contentsOf: snapshot.appendingPathComponent(storeName + suffix)), bytes)
        }
    }

    private func seedCurrentGraph(_ directory: URL) throws {
        try autoreleasepool {
            let schema = Schema(V2.models) // Intentionally unversioned, as main was before this change.
            let container = try ModelContainer(for: schema, configurations: [configuration(schema, directory)])
            let context = container.mainContext
            let account = V2.Account(id: id(1), name: "Synthetic cash", currency: "HKD", type: .cash, baseBalance: 100)
            let category = V2.Category(id: id(2), name: "Synthetic food", icon: "folder", colorHex: "#123456", kind: .expense)
            let tag = V2.Tag(id: id(3), name: "Synthetic tag")
            let transaction = V2.FinancialTransaction(id: id(4), amount: decimal("-35.59"), date: date, note: "Synthetic expense", account: account, category: category, tags: [tag], createdAt: date, updatedAt: date)
            let shortcut = V2.Shortcut(id: id(5), name: "Synthetic shortcut", icon: "folder", amount: decimal("35.59"), type: .expense, note: "Synthetic shortcut", account: account, category: category, tags: [tag])
            let advance = V2.AdvanceCase(id: id(6), title: "Synthetic advance", date: date, direction: .iAdvancedOthers, tagIDs: [tag.id], createdAt: date, updatedAt: date, payerAccount: account, expenseCategory: category)
            let participant = V2.AdvanceParticipant(id: id(7), name: "Synthetic participant", owedAmount: decimal("20.25"), repaidAmount: decimal("10.10"), createdAt: date, updatedAt: date, advanceCase: advance)
            let repayment = V2.AdvanceRepayment(id: id(8), amount: decimal("10.10"), normalizedAmount: decimal("10.10"), date: date, createdAt: date, advanceCase: advance, participant: participant, receivedAccount: account)
            let rule = V2.RecurringRule(id: id(9), title: "Synthetic recurring", amount: decimal("8.25"), type: .expense, nextDueDate: date, createdAt: date, updatedAt: date, account: account, category: category, tags: [tag])
            let occurrence = V2.RecurringOccurrence(id: id(10), dueDate: date, createdAt: date, updatedAt: date, rule: rule)
            let budget = V2.CategoryMonthlyBudget(id: id(11), monthKey: "2023-11", amount: decimal("500.50"), createdAt: date, updatedAt: date, category: category)
            let history = V2.BudgetMonthlyHistory(id: id(12), historyKey: "2023-11-synthetic", monthKey: "2023-11", categoryID: category.id, categoryNameSnapshot: category.name, budgetAmount: decimal("500.50"), spentAmount: decimal("35.59"), remainingAmount: decimal("464.91"), usageRatio: decimal("0.0711088911"), isOverBudget: false, currencyCode: "HKD", updatedAt: date)
            let settings = V2.BudgetSettings(carryOverMode: .netBalance, alertThresholdPercent: decimal("85.50"), updatedAt: date)
            for model in [account as any PersistentModel, category, tag, transaction, shortcut, advance, participant, repayment, rule, occurrence, budget, history, settings,
                          V2.Category(id: id(14), name: "Synthetic income", icon: "folder", colorHex: "#123456", kind: .income),
                          V2.Category(id: id(15), name: "Synthetic both", icon: "folder", colorHex: "#123456", kind: .both)] {
                context.insert(model)
            }
            try context.save()
        }
    }

    private func one<T: PersistentModel>(_ type: T.Type, _ context: ModelContext, id expectedID: UUID) throws -> T where T.ID == UUID {
        let rows = try context.fetch(FetchDescriptor<T>())
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.id, expectedID)
        return row
    }
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func configuration(_ schema: Schema, _ directory: URL) -> ModelConfiguration {
        ModelConfiguration(schema: schema, url: directory.appendingPathComponent(storeName), allowsSave: true, cloudKitDatabase: .none)
    }
    private func open(_ directory: URL) throws -> ModelContainer {
        switch StoreStartupService(documents: { directory }, prepare: { _ in }).load() {
        case .success(let container): return container
        case .failure(let error): throw error
        }
    }
    private func id(_ index: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))! }
    private func decimal(_ value: String) -> Decimal { Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))! }
}
