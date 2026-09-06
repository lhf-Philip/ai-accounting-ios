import XCTest
import SwiftData
import SQLite3
@testable import AI_記帳

@MainActor
final class BackupCompatibilityTests: XCTestCase {
    func testCreateBackupData_anyRequiredFetchFailureThrowsInsteadOfExportingPartialData() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        try seedCompleteBackupGraph(in: context)

        for modelType in requiredBackupModelTypes {
            let reader = FailingBackupReader(modelContext: context, failingType: modelType)
            XCTAssertThrowsError(
                try BackupManager.shared.createBackupData(modelContext: context, reader: reader),
                "Must fail when \(modelType) cannot be read"
            ) { error in
                XCTAssertEqual(error as? BackupInjectedFailure, .read)
            }
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testReplaceBackup_recoveryCaptureFailurePreservesAllOriginalRecords() throws {
        let sourceContainer = try makeInMemoryContainer()
        let replacement = try BackupManager.shared.createBackupData(modelContext: ModelContext(sourceContainer))

        for modelType in requiredBackupModelTypes {
            let container = try makeInMemoryContainer()
            let context = ModelContext(container)
            try seedCompleteBackupGraph(in: context)
            let before = try BackupManager.shared.createBackupData(modelContext: context)
            let reader = FailingBackupReader(modelContext: context, failingType: modelType)

            XCTAssertThrowsError(
                try BackupManager.shared.restoreBackupData(
                    replacement, modelContext: context, replaceExisting: true, reader: reader
                ),
                "Must stop before deletion when recovery cannot read \(modelType)"
            ) { error in
                XCTAssertEqual(error as? BackupInjectedFailure, .read)
            }

            let after = try BackupManager.shared.createBackupData(modelContext: context)
            XCTAssertEqual(try backupPayload(before), try backupPayload(after))
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testMergeBackup_existingRecordReadFailureStopsBeforeAnyMutation() throws {
        let sourceContainer = try makeInMemoryContainer()
        let sourceContext = ModelContext(sourceContainer)
        try seedCompleteBackupGraph(in: sourceContext)
        let incoming = try BackupManager.shared.createBackupData(modelContext: sourceContext)

        for modelType in requiredBackupModelTypes {
            let container = try makeInMemoryContainer()
            let context = ModelContext(container)
            let originalAccount = Account(name: "Keep existing", currency: "HKD", type: .cash, baseBalance: 321)
            context.insert(originalAccount)
            try context.save()
            let before = try BackupManager.shared.createBackupData(modelContext: context)
            let reader = FailingBackupReader(modelContext: context, failingType: modelType)

            XCTAssertThrowsError(
                try BackupManager.shared.restoreBackupData(incoming, modelContext: context, reader: reader),
                "Must stop before inserts or updates when \(modelType) cannot be read"
            ) { error in
                XCTAssertEqual(error as? BackupInjectedFailure, .read)
            }

            let after = try BackupManager.shared.createBackupData(modelContext: context)
            XCTAssertEqual(try backupPayload(before), try backupPayload(after))
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testAutoBackup_readFailureDoesNotWriteOrAdvanceSuccessDate() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let manager = BackupManager.shared
        let savedDate = manager.lastBackupDate
        defer { manager.lastBackupDate = savedDate }
        manager.lastBackupDate = 123
        var didWrite = false
        let reader = FailingBackupReader(modelContext: context, failingType: AdvanceRepayment.self)

        XCTAssertThrowsError(try manager.writeAutoBackup(
            modelContext: context,
            to: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            reader: reader,
            write: { _, _, _ in didWrite = true }
        )) { error in
            XCTAssertEqual(error as? BackupInjectedFailure, .read)
        }
        XCTAssertFalse(didWrite)
        XCTAssertEqual(123, manager.lastBackupDate)
    }

    func testAutoBackup_writeFailureRequestsAtomicReplacementAndPreservesPreviousBackup() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        try seedCompleteBackupGraph(in: context)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("backup-write-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let previous = Data("previous complete backup".utf8)
        try previous.write(to: url, options: .atomic)
        let manager = BackupManager.shared
        let savedDate = manager.lastBackupDate
        defer { manager.lastBackupDate = savedDate }
        manager.lastBackupDate = 123
        var attemptedWrite = false

        XCTAssertThrowsError(try manager.writeAutoBackup(
            modelContext: context,
            to: url,
            write: { _, destination, options in
                attemptedWrite = true
                XCTAssertEqual(url, destination)
                XCTAssertTrue(options.contains(.atomic))
                // Fail at the file-writing boundary, before Foundation replaces the destination.
                throw BackupInjectedFailure.write
            }
        )) { error in
            XCTAssertEqual(error as? BackupInjectedFailure, .write)
        }
        XCTAssertTrue(attemptedWrite)
        XCTAssertEqual(previous, try Data(contentsOf: url))
        XCTAssertEqual(123, manager.lastBackupDate)
    }

    func testAutoBackup_filesystemWriteFailurePreservesExistingBackup() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("backup.json")
        let manager = BackupManager.shared
        let savedDate = manager.lastBackupDate
        defer { manager.lastBackupDate = savedDate }
        try manager.writeAutoBackup(modelContext: context, to: url)
        let original = try Data(contentsOf: url)
        let originalDate = manager.lastBackupDate
        // A read-only directory prevents Foundation from creating/replacing its auxiliary file.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        XCTAssertThrowsError(try manager.writeAutoBackup(modelContext: context, to: url))
        XCTAssertEqual(original, try Data(contentsOf: url))
        XCTAssertEqual(originalDate, manager.lastBackupDate)
    }

    func testAutoBackup_successProducesDecodableBackupAndAdvancesDate() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        try seedCompleteBackupGraph(in: context)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("backup-success-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("old backup".utf8).write(to: url, options: .atomic)
        let manager = BackupManager.shared
        let savedDate = manager.lastBackupDate
        defer { manager.lastBackupDate = savedDate }
        manager.lastBackupDate = 123
        let started = Date().timeIntervalSince1970

        try manager.writeAutoBackup(modelContext: context, to: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(FullBackupData.self, from: Data(contentsOf: url))
        XCTAssertEqual("1.9", backup.version)
        XCTAssertEqual(13, BackupRecordCounts.fromBackup(backup).total)
        XCTAssertGreaterThanOrEqual(manager.lastBackupDate, started)
    }

    func testCompleteBackup_roundtripPreservesAllModelIDsCountsAndRelationships() throws {
        let sourceContainer = try makeInMemoryContainer()
        let sourceContext = ModelContext(sourceContainer)
        try seedCompleteBackupGraph(in: sourceContext)
        let original = try BackupManager.shared.createBackupData(modelContext: sourceContext)
        let targetContainer = try makeInMemoryContainer()
        let targetContext = ModelContext(targetContainer)

        let summary = try BackupManager.shared.restoreBackupData(original, modelContext: targetContext, replaceExisting: true)
        let restored = try BackupManager.shared.createBackupData(modelContext: targetContext)

        XCTAssertEqual(BackupRecordCounts.fromBackup(original), summary.afterRestoreCounts)
        XCTAssertEqual(13, summary.afterRestoreCounts.total)
        // Restore intentionally refreshes timestamps on derived budget history.
        XCTAssertEqual(try backupPayload(original, ignoringUpdatedAt: true), try backupPayload(restored, ignoringUpdatedAt: true))
        let transaction = try XCTUnwrap(targetContext.fetch(FetchDescriptor<FinancialTransaction>()).first)
        XCTAssertEqual(original.accounts.first?.id, transaction.account?.id)
        XCTAssertEqual(original.categories.first?.id, transaction.category?.id)
        XCTAssertEqual(original.tags.map(\.id), transaction.tags.map(\.id))
        let repayment = try XCTUnwrap(targetContext.fetch(FetchDescriptor<AdvanceRepayment>()).first)
        XCTAssertEqual(original.advanceCases?.first?.id, repayment.advanceCase?.id)
        XCTAssertEqual(original.advanceParticipants?.first?.id, repayment.participant?.id)
        XCTAssertEqual(original.accounts.first?.id, repayment.receivedAccount?.id)
    }

    private var requiredBackupModelTypes: [any PersistentModel.Type] {
        [Account.self, Category.self, Tag.self, FinancialTransaction.self, Shortcut.self,
         RecurringRule.self, RecurringOccurrence.self, CategoryMonthlyBudget.self,
         BudgetMonthlyHistory.self, BudgetSettings.self, AdvanceCase.self,
         AdvanceParticipant.self, AdvanceRepayment.self]
    }

    private func seedCompleteBackupGraph(in context: ModelContext) throws {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let account = Account(name: "Wallet", currency: "HKD", type: .cash, baseBalance: 321)
        let category = Category(name: "Food", icon: "fork.knife", colorHex: "FF8800", kind: .expense)
        let tag = Tag(name: "Shared")
        let advanceCase = AdvanceCase(title: "Lunch", date: date, currencyCode: "HKD", direction: .iAdvancedOthers, tagIDs: [tag.id], payerAccount: account, expenseCategory: category)
        let participant = AdvanceParticipant(name: "Friend", owedAmount: 50, repaidAmount: 10, advanceCase: advanceCase, debtAccount: account)
        let repayment = AdvanceRepayment(amount: 10, normalizedAmount: 10, date: date, advanceCase: advanceCase, participant: participant, receivedAccount: account)
        let transaction = FinancialTransaction(amount: -50, date: date, advanceCaseID: advanceCase.id, advanceParticipantID: participant.id, advanceEntryRole: .selfExpense, account: account, category: category, tags: [tag])
        let shortcut = Shortcut(name: "Lunch", icon: "bolt", amount: 50, type: .expense, note: "", account: account, category: category, tags: [tag])
        let rule = RecurringRule(title: "Lunch", amount: 50, type: .expense, nextDueDate: date, account: account, category: category, tags: [tag])
        let occurrence = RecurringOccurrence(dueDate: date, createdTransactionID: transaction.id, rule: rule)
        let budget = CategoryMonthlyBudget(monthKey: BudgetService.monthKey(from: date), amount: 500, category: category)
        let settings = BudgetSettings()
        context.insert(account)
        context.insert(category)
        context.insert(tag)
        context.insert(advanceCase)
        context.insert(participant)
        context.insert(repayment)
        context.insert(transaction)
        context.insert(shortcut)
        context.insert(rule)
        context.insert(occurrence)
        context.insert(budget)
        context.insert(settings)
        try BudgetHistoryService.shared.syncAll(modelContext: context, currencyService: CurrencyService.shared)
        try context.save()
    }

    private func backupPayload(_ backup: FullBackupData, ignoringUpdatedAt: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(backup)) as? [String: Any])
        payload.removeValue(forKey: "timestamp")
        for (key, value) in payload {
            guard var rows = value as? [[String: Any]] else { continue }
            if ignoringUpdatedAt {
                rows = rows.map { row in
                    var copy = row
                    copy.removeValue(forKey: "updatedAt")
                    return copy
                }
            }
            payload[key] = rows.sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    func testClearAllBackupData_removesEveryPersistedRecord() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let account = Account(name: "Old wallet", currency: "HKD", type: .cash, baseBalance: 100)
        let category = Category(name: "Old category", icon: "star", colorHex: "000000")
        let tag = Tag(name: "Old tag")
        let advanceCase = AdvanceCase(
            title: "Old advance",
            payerAccount: account,
            expenseCategory: category
        )
        let participant = AdvanceParticipant(
            name: "Old person",
            owedAmount: 50,
            advanceCase: advanceCase,
            debtAccount: account
        )
        let repayment = AdvanceRepayment(
            amount: 10,
            normalizedAmount: 10,
            advanceCase: advanceCase,
            participant: participant,
            receivedAccount: account
        )
        let shortcut = Shortcut(
            name: "Old shortcut",
            icon: "bolt",
            amount: 12,
            type: .expense,
            note: "old",
            account: account,
            category: category,
            tags: [tag]
        )
        let recurringRule = RecurringRule(
            title: "Old recurring",
            amount: 8,
            type: .expense,
            account: account,
            category: category,
            tags: [tag]
        )
        let recurringOccurrence = RecurringOccurrence(
            dueDate: Date(),
            rule: recurringRule
        )
        let budget = CategoryMonthlyBudget(
            monthKey: "2026-06",
            amount: 500,
            category: category
        )
        let budgetHistory = BudgetMonthlyHistory(
            historyKey: "2026-06-\(category.id.uuidString)",
            monthKey: "2026-06",
            categoryID: category.id,
            categoryNameSnapshot: category.name,
            budgetAmount: 500,
            spentAmount: 50,
            remainingAmount: 450,
            usageRatio: 0.1,
            isOverBudget: false,
            currencyCode: "HKD"
        )
        let budgetSettings = BudgetSettings()
        let transaction = FinancialTransaction(
            amount: -50,
            account: account,
            category: category,
            tags: [tag]
        )
        modelContext.insert(account)
        modelContext.insert(category)
        modelContext.insert(tag)
        modelContext.insert(advanceCase)
        modelContext.insert(participant)
        modelContext.insert(repayment)
        modelContext.insert(shortcut)
        modelContext.insert(recurringRule)
        modelContext.insert(recurringOccurrence)
        modelContext.insert(budget)
        modelContext.insert(budgetHistory)
        modelContext.insert(budgetSettings)
        modelContext.insert(transaction)
        try modelContext.save()

        let summary = try BackupManager.shared.clearAllBackupData(modelContext: modelContext)

        XCTAssertEqual(1, summary.beforeCounts.accounts)
        XCTAssertEqual(1, summary.beforeCounts.shortcuts)
        XCTAssertEqual(1, summary.beforeCounts.recurringRules)
        XCTAssertEqual(1, summary.beforeCounts.recurringOccurrences)
        XCTAssertEqual(1, summary.beforeCounts.budgets)
        XCTAssertEqual(1, summary.beforeCounts.budgetHistory)
        XCTAssertEqual(1, summary.beforeCounts.budgetSettings)
        XCTAssertEqual(.zero, summary.afterRestoreCounts)
        XCTAssertTrue(try modelContext.fetch(FetchDescriptor<Account>()).isEmpty)
        let backup = try BackupManager.shared.createBackupData(modelContext: modelContext)
        XCTAssertTrue(backup.categories.isEmpty)
        XCTAssertTrue(backup.tags.isEmpty)
        XCTAssertTrue(backup.transactions.isEmpty)
        XCTAssertTrue(backup.advanceCases?.isEmpty == true)
        XCTAssertTrue(backup.advanceParticipants?.isEmpty == true)
        XCTAssertTrue(backup.advanceRepayments?.isEmpty == true)
    }

    func testReplaceExistingBackup_removesOldIDsAndRestoresBackupIDs() throws {
        let sourceContainer = try makeInMemoryContainer()
        let sourceContext = ModelContext(sourceContainer)
        let replacementAccount = Account(
            id: UUID(),
            name: "Replacement wallet",
            currency: "JPY",
            type: .cash,
            baseBalance: 629
        )
        let replacementTransaction = FinancialTransaction(
            id: UUID(),
            amount: 43,
            currencyCode: "JPY",
            note: "[資產調整] Test replacement",
            type: .transfer,
            transferSide: .incoming,
            account: replacementAccount
        )
        sourceContext.insert(replacementAccount)
        sourceContext.insert(replacementTransaction)
        try sourceContext.save()
        let backup = try BackupManager.shared.createBackupData(modelContext: sourceContext)

        let targetContainer = try makeInMemoryContainer()
        let targetContext = ModelContext(targetContainer)
        let oldAccount = Account(
            id: UUID(),
            name: "Old wallet",
            currency: "HKD",
            type: .cash,
            baseBalance: 100
        )
        let oldTransaction = FinancialTransaction(
            id: UUID(),
            amount: -20,
            account: oldAccount
        )
        targetContext.insert(oldAccount)
        targetContext.insert(oldTransaction)
        try targetContext.save()

        let summary = try BackupManager.shared.restoreBackupData(
            backup,
            modelContext: targetContext,
            replaceExisting: true
        )

        let restoredAccounts = try targetContext.fetch(FetchDescriptor<Account>())
        let restoredTransactions = try targetContext.fetch(FetchDescriptor<FinancialTransaction>())
        XCTAssertEqual([replacementAccount.id], restoredAccounts.map(\.id))
        XCTAssertEqual([replacementTransaction.id], restoredTransactions.map(\.id))
        XCTAssertFalse(restoredAccounts.contains { $0.id == oldAccount.id })
        XCTAssertFalse(restoredTransactions.contains { $0.id == oldTransaction.id })
        XCTAssertEqual(1, summary.backupCounts.accounts)
        XCTAssertEqual(1, summary.backupCounts.transactions)
        XCTAssertEqual(.zero, summary.afterClearCounts)
        XCTAssertEqual(summary.backupCounts.accounts, summary.afterRestoreCounts.accounts)
        XCTAssertEqual(summary.backupCounts.transactions, summary.afterRestoreCounts.transactions)
    }

    func testReplaceExistingBackup_overwritesRecordsThatReuseExistingIDs() throws {
        let sharedAccountID = UUID()
        let sharedTransactionID = UUID()

        let sourceContainer = try makeInMemoryContainer()
        let sourceContext = ModelContext(sourceContainer)
        let correctedAccount = Account(
            id: sharedAccountID,
            name: "HSBC JPY",
            currency: "JPY",
            type: .bank,
            baseBalance: 629
        )
        let correctedTransaction = FinancialTransaction(
            id: sharedTransactionID,
            amount: 43,
            currencyCode: "JPY",
            note: "[資產調整] Reconciled balance",
            type: .transfer,
            transferSide: .incoming,
            account: correctedAccount
        )
        sourceContext.insert(correctedAccount)
        sourceContext.insert(correctedTransaction)
        try sourceContext.save()
        let correctedBackup = try BackupManager.shared.createBackupData(modelContext: sourceContext)

        let targetContainer = try makeInMemoryContainer()
        let targetContext = ModelContext(targetContainer)
        let staleAccount = Account(
            id: sharedAccountID,
            name: "HSBC JPY",
            currency: "JPY",
            type: .bank,
            baseBalance: -264
        )
        let staleTransaction = FinancialTransaction(
            id: sharedTransactionID,
            amount: -264,
            currencyCode: "JPY",
            note: "Stale value",
            account: staleAccount
        )
        targetContext.insert(staleAccount)
        targetContext.insert(staleTransaction)
        try targetContext.save()

        let summary = try BackupManager.shared.restoreBackupData(
            correctedBackup,
            modelContext: targetContext,
            replaceExisting: true
        )

        let restoredAccount = try XCTUnwrap(
            targetContext.fetch(FetchDescriptor<Account>()).first
        )
        let restoredTransaction = try XCTUnwrap(
            targetContext.fetch(FetchDescriptor<FinancialTransaction>()).first
        )
        XCTAssertEqual(sharedAccountID, restoredAccount.id)
        XCTAssertEqual(629, restoredAccount.baseBalance)
        XCTAssertEqual(sharedTransactionID, restoredTransaction.id)
        XCTAssertEqual(43, restoredTransaction.amount)
        XCTAssertEqual("[資產調整] Reconciled balance", restoredTransaction.note)
        XCTAssertEqual(summary.backupCounts, summary.afterRestoreCounts)
    }

    func testAdvanceCaseTagIDs_nilIsBackfilledAndExportedAsEmptyArray() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let advanceCase = AdvanceCase(title: "Legacy advance")
        advanceCase.tagIDs = nil
        modelContext.insert(advanceCase)
        try modelContext.save()

        XCTAssertNil(advanceCase.tagIDs)

        let repairedCount = try StoreMigrationSafetyService.backfillMissingAdvanceCaseTagIDs(
            modelContext: modelContext
        )

        XCTAssertEqual(1, repairedCount)
        XCTAssertEqual([], advanceCase.tagIDs)

        let backup = try BackupManager.shared.createBackupData(modelContext: modelContext)
        XCTAssertEqual([], backup.advanceCases?.first?.tagIDs)
    }

    func testPreMigrationBackup_copiesStoreFamilyAndReusesRecentCompleteBackup() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-backup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let storeURL = rootURL.appendingPathComponent("AI_Accounting_v3.store")
        let walURL = URL(fileURLWithPath: storeURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: storeURL.path + "-shm")
        try Data("store".utf8).write(to: storeURL)
        try Data("wal".utf8).write(to: walURL)
        try Data("shm".utf8).write(to: shmURL)
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        let firstBackup = try XCTUnwrap(
            StoreMigrationSafetyService.createPreMigrationBackupIfNeeded(
                storeURL: storeURL,
                now: now
            )
        )

        XCTAssertEqual(
            Data("store".utf8),
            try Data(contentsOf: firstBackup.appendingPathComponent(storeURL.lastPathComponent))
        )
        XCTAssertEqual(
            Data("wal".utf8),
            try Data(contentsOf: firstBackup.appendingPathComponent(walURL.lastPathComponent))
        )
        XCTAssertEqual(
            Data("shm".utf8),
            try Data(contentsOf: firstBackup.appendingPathComponent(shmURL.lastPathComponent))
        )

        let secondBackup = try StoreMigrationSafetyService.createPreMigrationBackupIfNeeded(
            storeURL: storeURL,
            now: now.addingTimeInterval(60)
        )

        XCTAssertEqual(firstBackup, secondBackup)
        let backupRoot = rootURL.appendingPathComponent("MigrationBackups", isDirectory: true)
        let backupDirectories = try FileManager.default.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(1, backupDirectories.count)
    }

    func testPreMigrationBackup_failureLeavesStoreUntouched() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-backup-failure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let storeURL = rootURL.appendingPathComponent("AI_Accounting_v3.store")
        let originalStore = Data("original-store".utf8)
        try originalStore.write(to: storeURL)
        try Data("not-a-directory".utf8).write(
            to: rootURL.appendingPathComponent("MigrationBackups")
        )

        XCTAssertThrowsError(
            try StoreMigrationSafetyService.createPreMigrationBackupIfNeeded(storeURL: storeURL)
        )
        XCTAssertEqual(originalStore, try Data(contentsOf: storeURL))
    }

    func testModelContainerErrorDescriptionIncludesUnderlyingFailureReason() {
        let underlying = NSError(
            domain: NSCocoaErrorDomain,
            code: 134110,
            userInfo: [NSLocalizedFailureReasonErrorKey: "missing AdvanceCase.tagIDs"]
        )
        let outer = NSError(
            domain: "SwiftData",
            code: 1,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )

        let description = StoreMigrationSafetyService.detailedDescription(for: outer)

        XCTAssertTrue(description.contains("SwiftData 1"))
        XCTAssertTrue(description.contains("NSCocoaErrorDomain 134110"))
        XCTAssertTrue(description.contains("missing AdvanceCase.tagIDs"))
    }

    func testLegacyStoreRepair_repairsInvalidFinancialTransactionEnumColumnsBeforeSwiftDataLoads() throws {
        let storeURL = try makeTemporarySQLiteStoreURL(named: "legacy-transaction-enums.sqlite")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        try withSQLiteDatabase(at: storeURL) { db in
            try execSQL(
                """
                CREATE TABLE ZFINANCIALTRANSACTION (
                    Z_PK INTEGER PRIMARY KEY,
                    ZTYPE VARCHAR,
                    ZAMOUNT NUMERIC,
                    ZLINKEDTRANSACTIONID VARCHAR,
                    ZTRANSFERGROUPID VARCHAR,
                    ZTRANSFERSIDE VARCHAR
                );
                INSERT INTO ZFINANCIALTRANSACTION (Z_PK, ZTYPE, ZAMOUNT, ZLINKEDTRANSACTIONID, ZTRANSFERGROUPID, ZTRANSFERSIDE)
                VALUES
                    (1, NULL, -120, NULL, NULL, NULL),
                    (2, '', 250, NULL, NULL, NULL),
                    (3, 'BadType', 500, NULL, 'group-1', NULL),
                    (4, 'Transfer', -10, NULL, NULL, 'BadSide'),
                    (5, 'Expense', -20, NULL, NULL, 'BadSide');
                """,
                db: db
            )
        }

        LegacyStoreRepairService.repairLegacyFinancialTransactionEnumsIfNeeded(storeURL: storeURL)

        let rows = try withSQLiteDatabase(at: storeURL) { db in
            try queryTransactionEnumRows(db: db)
        }

        XCTAssertEqual("Expense", rows[1]?.type)
        XCTAssertNil(rows[1]?.transferSide)
        XCTAssertEqual("Income", rows[2]?.type)
        XCTAssertNil(rows[2]?.transferSide)
        XCTAssertEqual("Transfer", rows[3]?.type)
        XCTAssertNil(rows[3]?.transferSide)
        XCTAssertEqual("Transfer", rows[4]?.type)
        XCTAssertEqual("Outgoing", rows[4]?.transferSide)
        XCTAssertEqual("Expense", rows[5]?.type)
        XCTAssertNil(rows[5]?.transferSide)
    }

    func testLegacyAdvanceFixture_roundTripsWithBorrowedAdvanceWarning() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let fixtureURL = fixtureURL(named: "legacy_bidirectional_advances.json")
        try await BackupManager.shared.restoreFromJSON(url: fixtureURL, modelContext: modelContext)

        let initialReport = DataHealthCheckService.run(modelContext: modelContext)
        XCTAssertEqual(0, initialReport.errorCount)
        XCTAssertEqual(1, initialReport.warningCount)
        XCTAssertTrue(initialReport.issues.contains { $0.title == "他人代墊我舊資料會虛增自己帳戶" })

        let exported = try BackupManager.shared.createBackupData(modelContext: modelContext)
        XCTAssertEqual(5, exported.accounts.count)
        XCTAssertEqual(2, exported.categories.count)
        XCTAssertEqual(16, exported.transactions.count)
        XCTAssertEqual(2, exported.advanceCases?.count)
        XCTAssertEqual(3, exported.advanceParticipants?.count)
        XCTAssertEqual(4, exported.advanceRepayments?.count)
        XCTAssertEqual("Both", exported.categories.first(where: { $0.name == "Salary" })?.kind)

        let secondContainer = try makeInMemoryContainer()
        let secondContext = ModelContext(secondContainer)
        let exportedURL = try writeBackup(exported, named: "legacy-advance-roundtrip.json")
        try await BackupManager.shared.restoreFromJSON(url: exportedURL, modelContext: secondContext)

        let secondReport = DataHealthCheckService.run(modelContext: secondContext)
        XCTAssertEqual(0, secondReport.errorCount)
        XCTAssertEqual(1, secondReport.warningCount)
        XCTAssertTrue(secondReport.issues.contains { $0.title == "他人代墊我舊資料會虛增自己帳戶" })

        let cases = try secondContext.fetch(FetchDescriptor<AdvanceCase>())
        XCTAssertEqual(2, cases.count)
    }

    func testLegacyDebtIncomeFixture_canRepairAndReimportCleanly() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let fixtureURL = fixtureURL(named: "legacy_debt_income_repair.json")
        try await BackupManager.shared.restoreFromJSON(url: fixtureURL, modelContext: modelContext)

        let initialReport = DataHealthCheckService.run(modelContext: modelContext)
        XCTAssertTrue(initialReport.issues.contains(where: { $0.title == "收入記到了借貸帳戶" }))
        XCTAssertTrue(initialReport.issues.contains(where: { $0.title == "收入捷徑綁到了借貸帳戶" }))

        let transactions = try modelContext.fetch(FetchDescriptor<FinancialTransaction>())
        let shortcuts = try modelContext.fetch(FetchDescriptor<Shortcut>())
        let convertedCount = try LegacyDebtIncomeRepairService.convertLegacyDebtIncomeTransactions(
            LegacyDebtIncomeRepairService.legacyDebtIncomeTransactions(from: transactions),
            modelContext: modelContext
        )
        let detachedCount = try LegacyDebtIncomeRepairService.detachLegacyDebtIncomeShortcuts(
            LegacyDebtIncomeRepairService.legacyDebtIncomeShortcuts(from: shortcuts),
            modelContext: modelContext
        )

        XCTAssertEqual(1, convertedCount)
        XCTAssertEqual(1, detachedCount)

        let repairedReport = DataHealthCheckService.run(modelContext: modelContext)
        XCTAssertFalse(repairedReport.issues.contains(where: { $0.title == "收入記到了借貸帳戶" }))
        XCTAssertFalse(repairedReport.issues.contains(where: { $0.title == "收入捷徑綁到了借貸帳戶" }))

        let exported = try BackupManager.shared.createBackupData(modelContext: modelContext)
        XCTAssertEqual("Both", exported.categories.first(where: { $0.name == "Salary" })?.kind)
        XCTAssertEqual(1, exported.budgetHistory?.count)
        XCTAssertNil(exported.shortcuts.first?.accountID)
        XCTAssertEqual("Transfer", exported.transactions.first(where: { $0.id == UUID(uuidString: "34343434-3434-3434-3434-343434343431") })?.type)
        XCTAssertTrue((exported.transactions.first(where: { $0.id == UUID(uuidString: "34343434-3434-3434-3434-343434343431") })?.note ?? "").contains("[免除債務]"))

        let secondContainer = try makeInMemoryContainer()
        let secondContext = ModelContext(secondContainer)
        let exportedURL = try writeBackup(exported, named: "legacy-debt-income-roundtrip.json")
        try await BackupManager.shared.restoreFromJSON(url: exportedURL, modelContext: secondContext)

        let secondReport = DataHealthCheckService.run(modelContext: secondContext)
        XCTAssertFalse(secondReport.issues.contains(where: { $0.title == "收入記到了借貸帳戶" }))
        XCTAssertFalse(secondReport.issues.contains(where: { $0.title == "收入捷徑綁到了借貸帳戶" }))
        XCTAssertEqual(0, secondReport.errorCount)
    }

    func testExportImport_preservesSameAccountCrossCurrencyTransferAndBudgetHistory_excludesUIPreferences() async throws {
        UserDefaults.standard.set("All", forKey: "sharedDateFilterType")
        UserDefaults.standard.set("2026-03-01T00:00:00Z", forKey: "sharedDateFilterCustomStartDate")
        UserDefaults.standard.set("2026-03-31T23:59:59Z", forKey: "sharedDateFilterCustomEndDate")
        UserDefaults.standard.set(false, forKey: "pinLedgerControls")
        defer {
            UserDefaults.standard.removeObject(forKey: "sharedDateFilterType")
            UserDefaults.standard.removeObject(forKey: "sharedDateFilterCustomStartDate")
            UserDefaults.standard.removeObject(forKey: "sharedDateFilterCustomEndDate")
            UserDefaults.standard.removeObject(forKey: "pinLedgerControls")
        }

        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let accountID = UUID(uuidString: "aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa")!
        let categoryID = UUID(uuidString: "bbbbbbbb-2222-2222-2222-bbbbbbbbbbbb")!
        let groupID = UUID(uuidString: "cccccccc-3333-3333-3333-cccccccccccc")!
        let outgoingID = UUID(uuidString: "dddddddd-4444-4444-4444-dddddddddddd")!
        let incomingID = UUID(uuidString: "eeeeeeee-5555-5555-5555-eeeeeeeeeeee")!
        let historyID = UUID(uuidString: "ffffffff-6666-6666-6666-ffffffffffff")!
        let expenseID = UUID(uuidString: "99999999-7777-7777-7777-999999999999")!
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-15T12:34:00Z"))

        let account = Account(
            id: accountID,
            name: "Multi-currency bank",
            currency: "HKD",
            type: .bank,
            baseBalance: 0,
            sortOrder: 0
        )
        let category = Category(
            id: categoryID,
            name: "Food",
            icon: "fork.knife",
            colorHex: "#FF8800",
            kind: .expense
        )
        let outgoing = FinancialTransaction(
            id: outgoingID,
            amount: -100,
            currencyCode: "HKD",
            date: date,
            note: "同帳戶跨幣種兌換",
            type: .transfer,
            linkedTransactionID: incomingID,
            transferGroupID: groupID,
            transferSide: .outgoing,
            account: account
        )
        let incoming = FinancialTransaction(
            id: incomingID,
            amount: 92,
            currencyCode: "CNY",
            date: date,
            note: "同帳戶跨幣種兌換",
            type: .transfer,
            linkedTransactionID: outgoingID,
            transferGroupID: groupID,
            transferSide: .incoming,
            account: account
        )
        let expense = FinancialTransaction(
            id: expenseID,
            amount: exactDecimal("-128.5"),
            currencyCode: "HKD",
            date: date,
            note: "Budget history sample",
            type: .expense,
            account: account,
            category: category
        )
        let budget = CategoryMonthlyBudget(
            monthKey: "2026-03",
            amount: 3000,
            currencyCode: "HKD",
            isEnabled: true,
            category: category
        )
        let history = BudgetMonthlyHistory(
            id: historyID,
            historyKey: "2026-03|\(categoryID.uuidString)",
            monthKey: "2026-03",
            categoryID: categoryID,
            categoryNameSnapshot: "Food",
            budgetAmount: 3000,
            spentAmount: exactDecimal("128.5"),
            remainingAmount: exactDecimal("2871.5"),
            usageRatio: Decimal(string: "0.042833")!,
            isOverBudget: false,
            currencyCode: "HKD",
            updatedAt: date
        )

        modelContext.insert(account)
        modelContext.insert(category)
        modelContext.insert(outgoing)
        modelContext.insert(incoming)
        modelContext.insert(expense)
        modelContext.insert(budget)
        modelContext.insert(history)
        try modelContext.save()

        let exported = try BackupManager.shared.createBackupData(modelContext: modelContext)
        XCTAssertEqual(3, exported.transactions.count)
        XCTAssertEqual(1, exported.budgetHistory?.count)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(exported)
        let jsonString = try XCTUnwrap(String(data: jsonData, encoding: .utf8))
        XCTAssertFalse(jsonString.contains("sharedDateFilter"))
        XCTAssertFalse(jsonString.contains("pinLedgerControls"))

        let secondContainer = try makeInMemoryContainer()
        let secondContext = ModelContext(secondContainer)
        let exportedURL = try writeBackup(exported, named: "same-account-cross-currency-roundtrip.json")
        try await BackupManager.shared.restoreFromJSON(url: exportedURL, modelContext: secondContext)

        let roundTrippedTransactions = try secondContext.fetch(FetchDescriptor<FinancialTransaction>())
        let transferGroup = roundTrippedTransactions.filter { $0.transferGroupID == groupID }
        XCTAssertEqual(2, transferGroup.count)
        XCTAssertEqual(Set([accountID]), Set(transferGroup.compactMap { $0.account?.id }))
        XCTAssertEqual(Set(["HKD", "CNY"]), Set(transferGroup.map(\.currencyCode)))
        XCTAssertEqual(incomingID, transferGroup.first(where: { $0.id == outgoingID })?.linkedTransactionID)
        XCTAssertEqual(outgoingID, transferGroup.first(where: { $0.id == incomingID })?.linkedTransactionID)
        XCTAssertEqual(.outgoing, transferGroup.first(where: { $0.id == outgoingID })?.transferSide)
        XCTAssertEqual(.incoming, transferGroup.first(where: { $0.id == incomingID })?.transferSide)

        let histories = try secondContext.fetch(FetchDescriptor<BudgetMonthlyHistory>())
        XCTAssertEqual(1, histories.count)
        XCTAssertEqual("2026-03|\(categoryID.uuidString)", histories.first?.historyKey)
        XCTAssertEqual(exactDecimal("128.5"), histories.first?.spentAmount)
    }

    func testBorrowedAdvanceCreation_recordsDebtExpenseWithoutInflatingOwnAccount() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-21T12:00:00Z"))

        let ownAccount = Account(name: "Wallet", currency: "HKD", type: .cash, baseBalance: 0)
        let debtAccount = Account(name: "Friend A", currency: "HKD", type: .debt, baseBalance: 0)
        let category = Category(name: "Food", icon: "fork.knife", colorHex: "#FF8800", kind: .expense)
        let tag = Tag(name: "Dinner")
        modelContext.insert(ownAccount)
        modelContext.insert(debtAccount)
        modelContext.insert(category)
        modelContext.insert(tag)

        let advanceCase = try AdvanceService.createAdvanceCase(
            title: "朋友代付晚餐",
            date: date,
            currencyCode: "HKD",
            myShareAmount: 0,
            note: "晚餐",
            payerAccount: nil,
            category: category,
            tags: [tag],
            participants: [.init(debtAccount: debtAccount, owedAmount: 150)],
            isBorrowedByMe: true,
            modelContext: modelContext
        )

        let transactions = try modelContext.fetch(FetchDescriptor<FinancialTransaction>())
        let ownAccountTransactions = transactions.filter { $0.account?.id == ownAccount.id }
        let debtTransactions = transactions.filter { $0.account?.id == debtAccount.id }

        XCTAssertNil(advanceCase.payerAccount)
        XCTAssertEqual(Decimal.zero, advanceCase.myShareAmount)
        XCTAssertNil(advanceCase.selfExpenseTransactionID)
        XCTAssertTrue(ownAccountTransactions.isEmpty)
        XCTAssertEqual(1, debtTransactions.count)
        XCTAssertEqual(.expense, debtTransactions.first?.type)
        XCTAssertEqual(.outgoing, debtTransactions.first?.transferSide)
        XCTAssertNil(debtTransactions.first?.linkedTransactionID)
        XCTAssertEqual(Decimal(-150), debtTransactions.first?.amount)
        XCTAssertEqual(category.id, debtTransactions.first?.category?.id)
        XCTAssertEqual([tag.id], debtTransactions.first?.tags.map(\.id))

        let report = DataHealthCheckService.run(modelContext: modelContext)
        XCTAssertEqual(0, report.errorCount)
        XCTAssertEqual(0, report.warningCount)

        let participant = try XCTUnwrap(advanceCase.participants.first)
        _ = try AdvanceService.recordRepayment(
            advanceCase: advanceCase,
            participant: participant,
            amount: 150,
            currencyCode: "HKD",
            date: date.addingTimeInterval(3_600),
            note: "還款",
            receiveAccount: ownAccount,
            category: nil,
            tags: [],
            currencyService: CurrencyService.shared,
            normalizedAmountOverride: 150,
            direction: .othersAdvancedMe,
            modelContext: modelContext
        )

        let transactionsAfterRepayment = try modelContext.fetch(FetchDescriptor<FinancialTransaction>())
        let ownAccountAfterRepayment = transactionsAfterRepayment.filter { $0.account?.id == ownAccount.id }
        let expenseTransactions = transactionsAfterRepayment.filter { $0.type == .expense }

        XCTAssertEqual(1, ownAccountAfterRepayment.count)
        XCTAssertEqual(.transfer, ownAccountAfterRepayment.first?.type)
        XCTAssertEqual(Decimal(-150), ownAccountAfterRepayment.first?.amount)
        XCTAssertEqual(1, expenseTransactions.count)
        XCTAssertEqual(Decimal(-150), expenseTransactions.first?.amount)
        XCTAssertEqual(Decimal.zero, participant.remainingAmount)
    }

    func testAdvancedOthersCreation_recordsFullOutflowAndOnlySelfShareExpense() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-21T12:00:00Z"))

        let ownAccount = Account(name: "Wallet", currency: "HKD", type: .cash, baseBalance: 0)
        let debtAccount = Account(name: "Friend A", currency: "HKD", type: .debt, baseBalance: 0)
        let category = Category(name: "Food", icon: "fork.knife", colorHex: "#FF8800", kind: .expense)
        modelContext.insert(ownAccount)
        modelContext.insert(debtAccount)
        modelContext.insert(category)

        let advanceCase = try AdvanceService.createAdvanceCase(
            title: "代付晚餐",
            date: date,
            currencyCode: "HKD",
            myShareAmount: 50,
            note: "晚餐",
            payerAccount: ownAccount,
            category: category,
            tags: [],
            participants: [.init(debtAccount: debtAccount, owedAmount: 100)],
            isBorrowedByMe: false,
            modelContext: modelContext
        )

        let transactions = try modelContext.fetch(FetchDescriptor<FinancialTransaction>())
        let ownAccountTransactions = transactions.filter { $0.account?.id == ownAccount.id }
        let debtTransactions = transactions.filter { $0.account?.id == debtAccount.id }
        let expenseTransactions = transactions.filter { $0.type == .expense }

        XCTAssertEqual(Decimal(-150), ownAccountTransactions.reduce(0) { $0 + $1.amount })
        XCTAssertEqual(1, expenseTransactions.count)
        XCTAssertEqual(Decimal(-50), expenseTransactions.first?.amount)
        XCTAssertEqual(category.id, expenseTransactions.first?.category?.id)
        XCTAssertEqual(1, debtTransactions.count)
        XCTAssertEqual(.transfer, debtTransactions.first?.type)
        XCTAssertEqual(Decimal(100), debtTransactions.first?.amount)
        XCTAssertEqual(Decimal(100), advanceCase.participants.first?.remainingAmount)
    }

    func testBorrowedAdvanceWithoutCategory_reportsUncategorisedExpenseWarning() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-21T12:00:00Z"))

        let debtAccount = Account(name: "Friend A", currency: "HKD", type: .debt, baseBalance: 0)
        modelContext.insert(debtAccount)
        try modelContext.save()

        _ = try AdvanceService.createAdvanceCase(
            title: "朋友代付晚餐",
            date: date,
            currencyCode: "HKD",
            myShareAmount: 0,
            note: "晚餐",
            payerAccount: nil,
            category: nil,
            tags: [],
            participants: [.init(debtAccount: debtAccount, owedAmount: 150)],
            isBorrowedByMe: true,
            modelContext: modelContext
        )

        let report = DataHealthCheckService.run(modelContext: modelContext)

        XCTAssertEqual(0, report.errorCount)
        XCTAssertTrue(report.issues.contains { issue in
            issue.title == "他人代墊我缺少支出分類" &&
            issue.detail.contains("1 筆")
        })
    }

    func testMutualDebtOffset_settlesBidirectionalAdvancesWithoutTransactions() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-21T12:00:00Z"))

        let ownAccount = Account(name: "Wallet", currency: "HKD", type: .cash, baseBalance: 0)
        let debtAccount = Account(name: "Friend A", currency: "HKD", type: .debt, baseBalance: 0)
        modelContext.insert(ownAccount)
        modelContext.insert(debtAccount)
        try modelContext.save()

        let receivableCase = try AdvanceService.createAdvanceCase(
            title: "我先付晚餐",
            date: date,
            currencyCode: "HKD",
            myShareAmount: 0,
            note: "",
            payerAccount: ownAccount,
            category: nil,
            tags: [],
            participants: [.init(debtAccount: debtAccount, owedAmount: 100)],
            isBorrowedByMe: false,
            modelContext: modelContext
        )
        let payableCase = try AdvanceService.createAdvanceCase(
            title: "朋友先付車費",
            date: date.addingTimeInterval(60),
            currencyCode: "HKD",
            myShareAmount: 0,
            note: "",
            payerAccount: nil,
            category: nil,
            tags: [],
            participants: [.init(debtAccount: debtAccount, owedAmount: 40)],
            isBorrowedByMe: true,
            modelContext: modelContext
        )

        let beforeTransactions = try modelContext.fetch(FetchDescriptor<FinancialTransaction>()).count
        let candidate = try XCTUnwrap(
            AdvanceService.mutualDebtOffsetCandidate(
                debtAccount: debtAccount,
                currencyCode: "HKD",
                advanceCases: [receivableCase, payableCase],
                modelContext: modelContext
            )
        )
        XCTAssertEqual(Decimal(40), candidate.amount)

        let result = try AdvanceService.recordMutualDebtOffset(
            debtAccount: debtAccount,
            currencyCode: "HKD",
            date: date,
            modelContext: modelContext
        )

        XCTAssertEqual(Decimal(40), result.amount)
        XCTAssertEqual(2, result.repaymentCount)
        XCTAssertEqual(beforeTransactions, try modelContext.fetch(FetchDescriptor<FinancialTransaction>()).count)
        XCTAssertEqual(Decimal(60), receivableCase.participants.first?.remainingAmount)
        XCTAssertEqual(Decimal.zero, payableCase.participants.first?.remainingAmount)

        let repayments = try modelContext.fetch(FetchDescriptor<AdvanceRepayment>())
        XCTAssertEqual(2, repayments.count)
        XCTAssertTrue(repayments.allSatisfy { AdvanceSemantics.mutualDebtOffsetID(from: $0.note) == result.offsetGroupID })
        XCTAssertThrowsError(
            try AdvanceService.rollbackRepayment(
                advanceCase: try XCTUnwrap(repayments.first?.advanceCase),
                repayment: try XCTUnwrap(repayments.first),
                modelContext: modelContext
            )
        ) { error in
            XCTAssertEqual(
                AdvanceServiceError.specialRepaymentRequiresGroupRollback.localizedDescription,
                error.localizedDescription
            )
        }

        let rollbackCount = try AdvanceService.rollbackMutualDebtOffset(
            offsetGroupID: result.offsetGroupID,
            modelContext: modelContext
        )
        XCTAssertEqual(2, rollbackCount)
        XCTAssertEqual(Decimal(100), receivableCase.participants.first?.remainingAmount)
        XCTAssertEqual(Decimal(40), payableCase.participants.first?.remainingAmount)
    }

    func testManualDebtSettlement_closesSingleCurrencyAdvanceWithoutTransactions() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-21T12:00:00Z"))

        let ownAccount = Account(name: "JPY Wallet", currency: "JPY", type: .cash, baseBalance: 0)
        let debtAccount = Account(name: "TKL", currency: "HKD", type: .debt, baseBalance: 0)
        modelContext.insert(ownAccount)
        modelContext.insert(debtAccount)
        try modelContext.save()

        let advanceCase = try AdvanceService.createAdvanceCase(
            title: "豬骨拉麵",
            date: date,
            currencyCode: "JPY",
            myShareAmount: 0,
            note: "",
            payerAccount: ownAccount,
            category: nil,
            tags: [],
            participants: [.init(debtAccount: debtAccount, owedAmount: 1230)],
            isBorrowedByMe: false,
            modelContext: modelContext
        )

        let beforeTransactionCount = try modelContext.fetch(FetchDescriptor<FinancialTransaction>()).count
        let result = try AdvanceService.recordManualDebtSettlement(
            debtAccount: debtAccount,
            currencyCode: "JPY",
            direction: .receivable,
            amount: 1230,
            date: date.addingTimeInterval(600),
            note: "手動結清日元餘額",
            modelContext: modelContext
        )

        XCTAssertEqual(Decimal(1230), result.amount)
        XCTAssertEqual(1, result.repaymentCount)
        XCTAssertEqual(beforeTransactionCount, try modelContext.fetch(FetchDescriptor<FinancialTransaction>()).count)
        XCTAssertEqual(Decimal.zero, advanceCase.participants.first?.remainingAmount)

        let repayments = try modelContext.fetch(FetchDescriptor<AdvanceRepayment>())
        XCTAssertEqual(1, repayments.count)
        XCTAssertTrue(AdvanceSemantics.isManualDebtSettlement(note: try XCTUnwrap(repayments.first?.note)))
        XCTAssertNil(repayments.first?.linkedTransferGroupID)
        XCTAssertNil(repayments.first?.receivedAccount)

        let semanticBalances = DebtSettlementBalanceService.balances(
            for: debtAccount,
            transactions: try modelContext.fetch(FetchDescriptor<FinancialTransaction>()),
            advanceCases: [advanceCase],
            modelContext: modelContext
        )
        XCTAssertTrue(semanticBalances.isEmpty)

        XCTAssertThrowsError(
            try AdvanceService.rollbackRepayment(
                advanceCase: advanceCase,
                repayment: try XCTUnwrap(repayments.first),
                modelContext: modelContext
            )
        ) { error in
            XCTAssertEqual(
                AdvanceServiceError.specialRepaymentRequiresGroupRollback.localizedDescription,
                error.localizedDescription
            )
        }

        let rollbackCount = try AdvanceService.rollbackManualDebtSettlement(
            settlementID: result.settlementID,
            modelContext: modelContext
        )
        XCTAssertEqual(1, rollbackCount)
        XCTAssertEqual(Decimal(1230), advanceCase.participants.first?.remainingAmount)
        XCTAssertTrue(try modelContext.fetch(FetchDescriptor<AdvanceRepayment>()).isEmpty)
    }

    func testRepaymentReconciliation_repairsUnderstatedParticipantTotal() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-05T12:00:00Z"))

        let debtAccount = Account(name: "TKL", currency: "HKD", type: .debt, baseBalance: 0)
        let advanceCase = AdvanceCase(
            title: "とり天定食",
            date: date,
            currencyCode: "JPY"
        )
        let participant = AdvanceParticipant(
            name: "TKL",
            owedAmount: 1510,
            repaidAmount: 0,
            advanceCase: advanceCase,
            debtAccount: debtAccount
        )
        let repayment = AdvanceRepayment(
            amount: 75,
            currencyCode: "HKD",
            normalizedAmount: 1510,
            date: date,
            note: "跨幣種還款",
            advanceCase: advanceCase,
            participant: participant
        )
        modelContext.insert(debtAccount)
        modelContext.insert(advanceCase)
        modelContext.insert(participant)
        modelContext.insert(repayment)
        try modelContext.save()

        let reportBeforeRepair = DataHealthCheckService.run(modelContext: modelContext)
        XCTAssertTrue(reportBeforeRepair.issues.contains { $0.title == "代墊還款累計偏低" })

        let result = try AdvanceMaintenance.reconcileUnderstatedRepaymentTotals(modelContext: modelContext)

        XCTAssertEqual(1, result.checkedParticipantCount)
        XCTAssertEqual(1, result.updatedParticipantCount)
        XCTAssertEqual(Decimal(1510), participant.repaidAmount)
        XCTAssertEqual(Decimal.zero, participant.remainingAmount)
        let reportAfterRepair = DataHealthCheckService.run(modelContext: modelContext)
        XCTAssertFalse(reportAfterRepair.issues.contains { $0.title == "代墊還款累計偏低" })
    }

    func testCrossCurrencyAdvanceRepayment_preservesActualCurrencyAndManualSettlementAmount() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-21T12:00:00Z"))

        let payerAccount = Account(name: "HKD Wallet", currency: "HKD", type: .cash, baseBalance: 0)
        let receiveAccount = Account(name: "CNY Wallet", currency: "CNY", type: .cash, baseBalance: 0)
        let debtAccount = Account(name: "Friend A", currency: "HKD", type: .debt, baseBalance: 0)
        modelContext.insert(payerAccount)
        modelContext.insert(receiveAccount)
        modelContext.insert(debtAccount)

        let advanceCase = try AdvanceService.createAdvanceCase(
            title: "晚餐代墊",
            date: date,
            currencyCode: "HKD",
            myShareAmount: 0,
            note: "",
            payerAccount: payerAccount,
            category: nil,
            tags: [],
            participants: [.init(debtAccount: debtAccount, owedAmount: 100)],
            isBorrowedByMe: false,
            modelContext: modelContext
        )
        let participant = try XCTUnwrap(advanceCase.participants.first)

        let repayment = try AdvanceService.recordRepayment(
            advanceCase: advanceCase,
            participant: participant,
            amount: 90,
            currencyCode: "CNY",
            date: date.addingTimeInterval(3600),
            note: "朋友用人民幣還款",
            receiveAccount: receiveAccount,
            category: nil,
            tags: [],
            currencyService: CurrencyService.shared,
            normalizedAmountOverride: 100,
            modelContext: modelContext
        )

        XCTAssertEqual(Decimal(90), repayment.amount)
        XCTAssertEqual("CNY", repayment.currencyCode)
        XCTAssertEqual(Decimal(100), repayment.normalizedAmount)
        XCTAssertEqual(Decimal.zero, participant.remainingAmount)

        let linkedTransfers = try modelContext.fetch(FetchDescriptor<FinancialTransaction>())
            .filter { $0.transferGroupID == repayment.linkedTransferGroupID }
        XCTAssertEqual(2, linkedTransfers.count)
        let incoming = try XCTUnwrap(linkedTransfers.first { $0.transferSide == .incoming })
        XCTAssertEqual(receiveAccount.id, incoming.account?.id)
        XCTAssertEqual(Decimal(90), incoming.amount)
        XCTAssertEqual("CNY", incoming.currencyCode)

        let exported = try BackupManager.shared.createBackupData(modelContext: modelContext)
        let exportedRepayment = try XCTUnwrap(exported.advanceRepayments?.first { $0.id == repayment.id })
        XCTAssertEqual(Decimal(90), exportedRepayment.amount)
        XCTAssertEqual("CNY", exportedRepayment.currencyCode)
        XCTAssertEqual(Decimal(100), exportedRepayment.normalizedAmount)
    }

    func testSplitAdvancePaymentLegs_roundTripExplicitLinks() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let wallet = Account(name: "Wallet", currency: "HKD", type: .cash, baseBalance: 0)
        let card = Account(name: "Card", currency: "USD", type: .creditCard, baseBalance: 0)
        let friend = Account(name: "Friend", currency: "JPY", type: .debt, baseBalance: 0)
        [wallet, card, friend].forEach(modelContext.insert)
        let advanceCase = try AdvanceService.createAdvanceCase(
            title: "Japan",
            date: Date(timeIntervalSince1970: 10),
            currencyCode: "JPY",
            myShareAmount: 0,
            note: "",
            payerAccount: wallet,
            category: nil,
            tags: [],
            participants: [.init(debtAccount: friend, owedAmount: 1_000)],
            modelContext: modelContext
        )
        let participant = try XCTUnwrap(advanceCase.participants.first)
        try AdvanceCaseEditingService.apply(
            AdvanceCaseEditDraft(
                advanceCase: advanceCase,
                title: advanceCase.title,
                date: advanceCase.date,
                direction: .iAdvancedOthers,
                currencyCode: advanceCase.currencyCode,
                note: "",
                category: nil,
                tags: [],
                share: nil,
                participants: [
                    AdvanceParticipantDraft(
                        participant: participant,
                        name: participant.name,
                        debtAccount: friend,
                        owedAmount: 1_000,
                        paymentLegs: [
                            AdvancePaymentLegDraft(
                                transactionID: nil,
                                account: wallet,
                                amount: 500,
                                currencyCode: "HKD"
                            ),
                            AdvancePaymentLegDraft(
                                transactionID: nil,
                                account: card,
                                amount: 30,
                                currencyCode: "USD"
                            ),
                        ]
                    )
                ],
                repayments: []
            ),
            modelContext: modelContext
        )

        let exported = try BackupManager.shared.createBackupData(modelContext: modelContext)
        let linked = exported.transactions.filter {
            $0.advanceCaseID == advanceCase.id &&
                $0.advanceParticipantID == participant.id
        }
        XCTAssertEqual(3, linked.count)
        XCTAssertEqual(2, linked.filter { $0.advanceEntryRole == "InitialAsset" }.count)

        let secondContainer = try makeInMemoryContainer()
        let secondContext = ModelContext(secondContainer)
        let url = try writeBackup(exported, named: "split-advance-roundtrip.json")
        try await BackupManager.shared.restoreFromJSON(url: url, modelContext: secondContext)
        let restored = try secondContext.fetch(FetchDescriptor<FinancialTransaction>())
            .filter {
                $0.advanceCaseID == advanceCase.id &&
                    $0.advanceParticipantID == participant.id
            }
        XCTAssertEqual(3, restored.count)
        XCTAssertEqual(2, restored.filter { $0.advanceEntryRole == .initialAsset }.count)
        XCTAssertEqual(
            Set(["HKD", "USD"]),
            Set(restored.filter { $0.advanceEntryRole == .initialAsset }.map(\.currencyCode))
        )
    }

    func testCrossCurrencyAdvanceRepayment_semanticDebtBalanceUsesCaseCurrencyRemainingOnly() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-21T12:00:00Z"))

        let payerAccount = Account(name: "JPY Wallet", currency: "JPY", type: .cash, baseBalance: 0)
        let receiveAccount = Account(name: "HKD Wallet", currency: "HKD", type: .cash, baseBalance: 0)
        let debtAccount = Account(name: "Friend A", currency: "HKD", type: .debt, baseBalance: 0)
        modelContext.insert(payerAccount)
        modelContext.insert(receiveAccount)
        modelContext.insert(debtAccount)

        let advanceCase = try AdvanceService.createAdvanceCase(
            title: "日本旅行代墊",
            date: date,
            currencyCode: "JPY",
            myShareAmount: 0,
            note: "",
            payerAccount: payerAccount,
            category: nil,
            tags: [],
            participants: [.init(debtAccount: debtAccount, owedAmount: 1000)],
            isBorrowedByMe: false,
            modelContext: modelContext
        )
        let participant = try XCTUnwrap(advanceCase.participants.first)

        _ = try AdvanceService.recordRepayment(
            advanceCase: advanceCase,
            participant: participant,
            amount: 50,
            currencyCode: "HKD",
            date: date.addingTimeInterval(3600),
            note: "朋友用港幣還款",
            receiveAccount: receiveAccount,
            category: nil,
            tags: [],
            currencyService: CurrencyService.shared,
            normalizedAmountOverride: 900,
            modelContext: modelContext
        )

        XCTAssertEqual(Decimal(100), participant.remainingAmount)

        let transactions = try modelContext.fetch(FetchDescriptor<FinancialTransaction>())
        let rawDebtBalances = DebtSettlementBalanceService.rawBalances(
            for: debtAccount,
            transactions: transactions
        )
        XCTAssertEqual(Decimal(1000), rawDebtBalances.first(where: { $0.currencyCode == "JPY" })?.amount)
        XCTAssertEqual(Decimal(-50), rawDebtBalances.first(where: { $0.currencyCode == "HKD" })?.amount)

        let semanticBalances = DebtSettlementBalanceService.balances(
            for: debtAccount,
            transactions: transactions,
            advanceCases: [advanceCase],
            modelContext: modelContext
        )
        XCTAssertEqual(1, semanticBalances.count)
        XCTAssertEqual("JPY", semanticBalances.first?.currencyCode)
        XCTAssertEqual(Decimal(100), semanticBalances.first?.amount)
    }

    func testLegacyBorrowedAdvanceRepair_removesInflatedIncomingLegAndKeepsExpense() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-21T12:00:00Z"))
        let groupID = UUID()
        let outID = UUID()
        let inID = UUID()

        let ownAccount = Account(name: "Wallet", currency: "HKD", type: .cash, baseBalance: 0)
        let debtAccount = Account(name: "Friend A", currency: "HKD", type: .debt, baseBalance: 0)
        let category = Category(name: "Food", icon: "fork.knife", colorHex: "#FF8800", kind: .expense)
        let advanceCase = AdvanceCase(
            title: "朋友代付晚餐",
            date: date,
            currencyCode: "HKD",
            myShareAmount: 0,
            note: "晚餐",
            payerAccount: ownAccount,
            expenseCategory: category
        )
        let participant = AdvanceParticipant(
            name: debtAccount.name,
            owedAmount: 150,
            initialTransferGroupID: groupID,
            advanceCase: advanceCase,
            debtAccount: debtAccount
        )
        let legacyOutgoing = FinancialTransaction(
            id: outID,
            amount: -150,
            currencyCode: "HKD",
            date: date,
            note: "晚餐 (他人代墊我)",
            type: .transfer,
            linkedTransactionID: inID,
            transferGroupID: groupID,
            transferSide: .outgoing,
            account: debtAccount
        )
        let inflatedIncoming = FinancialTransaction(
            id: inID,
            amount: 150,
            currencyCode: "HKD",
            date: date,
            note: "晚餐 (入到自己帳戶)",
            type: .transfer,
            linkedTransactionID: outID,
            transferGroupID: groupID,
            transferSide: .incoming,
            account: ownAccount
        )

        modelContext.insert(ownAccount)
        modelContext.insert(debtAccount)
        modelContext.insert(category)
        modelContext.insert(advanceCase)
        modelContext.insert(participant)
        modelContext.insert(legacyOutgoing)
        modelContext.insert(inflatedIncoming)
        try modelContext.save()

        let initialReport = DataHealthCheckService.run(modelContext: modelContext)
        XCTAssertTrue(initialReport.issues.contains { $0.title == "他人代墊我舊資料會虛增自己帳戶" })

        let result = try AdvanceMaintenance.repairLegacyBorrowedAdvanceAccountInflation(modelContext: modelContext)

        XCTAssertEqual(1, result.repairedParticipantCount)
        XCTAssertEqual(1, result.removedInflatedAccountTransactionCount)

        let transactions = try modelContext.fetch(FetchDescriptor<FinancialTransaction>())
        let repaired = try XCTUnwrap(transactions.first(where: { $0.id == outID }))
        XCTAssertNil(transactions.first(where: { $0.id == inID }))
        XCTAssertEqual(.expense, repaired.type)
        XCTAssertEqual(.outgoing, repaired.transferSide)
        XCTAssertNil(repaired.linkedTransactionID)
        XCTAssertEqual(category.id, repaired.category?.id)
        XCTAssertNil(advanceCase.payerAccount)

        let repairedReport = DataHealthCheckService.run(modelContext: modelContext)
        XCTAssertFalse(repairedReport.issues.contains { $0.title == "他人代墊我舊資料會虛增自己帳戶" })
        XCTAssertEqual(0, repairedReport.errorCount)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
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
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private func fixtureURL(named name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func writeBackup(_ backup: FullBackupData, named name: String) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(backup).write(to: tempURL, options: .atomic)
        return tempURL
    }

    private func makeTemporarySQLiteStoreURL(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func withSQLiteDatabase<T>(at url: URL, body: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let db else {
            let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown sqlite error"
            if db != nil {
                sqlite3_close(db)
            }
            throw NSError(domain: "BackupCompatibilitySQLite", code: Int(result), userInfo: [NSLocalizedDescriptionKey: message])
        }
        defer { sqlite3_close(db) }
        return try body(db)
    }

    private func execSQL(_ sql: String, db: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown sqlite exec error"
            if errorMessage != nil {
                sqlite3_free(errorMessage)
            }
            throw NSError(domain: "BackupCompatibilitySQLite", code: Int(result), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func queryTransactionEnumRows(db: OpaquePointer) throws -> [Int: (type: String?, transferSide: String?)] {
        let sql = "SELECT Z_PK, ZTYPE, ZTRANSFERSIDE FROM ZFINANCIALTRANSACTION ORDER BY Z_PK;"
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            let message = sqlite3_errmsg(db).map { String(cString: $0) } ?? "unknown sqlite prepare error"
            throw NSError(domain: "BackupCompatibilitySQLite", code: Int(prepareResult), userInfo: [NSLocalizedDescriptionKey: message])
        }
        defer { sqlite3_finalize(statement) }

        var rows: [Int: (type: String?, transferSide: String?)] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(statement, 0))
            let type = sqlite3_column_text(statement, 1).map { String(cString: $0) }
            let transferSide = sqlite3_column_text(statement, 2).map { String(cString: $0) }
            rows[id] = (type, transferSide)
        }
        return rows
    }
}

@MainActor
final class TransferPresentationServiceTests: XCTestCase {
    func testCounterpartMap_usesLinkedTransferPair() {
        let outgoingID = UUID()
        let incomingID = UUID()

        let result = TransferPresentationService.counterpartMap(inputs: [
            transferInput(id: outgoingID, amount: -100, currencyCode: "USD", linkedTransactionID: incomingID, transferSide: .outgoing),
            transferInput(id: incomingID, amount: 780, currencyCode: "HKD", linkedTransactionID: outgoingID, transferSide: .incoming),
        ])

        XCTAssertEqual(result[outgoingID]?.amount, 780)
        XCTAssertEqual(result[outgoingID]?.currencyCode, "HKD")
        XCTAssertEqual(result[incomingID]?.amount, -100)
        XCTAssertEqual(result[incomingID]?.currencyCode, "USD")
    }

    func testCounterpartMap_handlesTransferGroupSplitMerge() {
        let groupID = UUID()
        let outgoingID = UUID()
        let firstIncomingID = UUID()
        let secondIncomingID = UUID()

        let result = TransferPresentationService.counterpartMap(inputs: [
            transferInput(id: outgoingID, amount: -100, currencyCode: "HKD", transferGroupID: groupID, transferSide: .outgoing),
            transferInput(id: firstIncomingID, amount: 40, currencyCode: "HKD", transferGroupID: groupID, transferSide: .incoming),
            transferInput(id: secondIncomingID, amount: 60, currencyCode: "HKD", transferGroupID: groupID, transferSide: .incoming),
        ])

        XCTAssertNil(result[outgoingID])
        XCTAssertEqual(result[firstIncomingID]?.amount, -100)
        XCTAssertEqual(result[firstIncomingID]?.currencyCode, "HKD")
        XCTAssertEqual(result[secondIncomingID]?.amount, -100)
        XCTAssertEqual(result[secondIncomingID]?.currencyCode, "HKD")
    }

    func testCounterpartMap_ignoresMissingLinkedTransfer() {
        let result = TransferPresentationService.counterpartMap(inputs: [
            transferInput(id: UUID(), amount: -100, currencyCode: "HKD", linkedTransactionID: UUID(), transferSide: .outgoing),
        ])

        XCTAssertTrue(result.isEmpty)
    }

    func testCounterpartMap_supportsSameAccountCrossCurrencyTransferShape() {
        let outgoingID = UUID()
        let incomingID = UUID()

        let result = TransferPresentationService.counterpartMap(inputs: [
            transferInput(id: outgoingID, amount: -100, currencyCode: "HKD", linkedTransactionID: incomingID, transferSide: .outgoing),
            transferInput(id: incomingID, amount: 92, currencyCode: "CNY", linkedTransactionID: outgoingID, transferSide: .incoming),
        ])

        XCTAssertEqual(result[outgoingID]?.amount, 92)
        XCTAssertEqual(result[outgoingID]?.currencyCode, "CNY")
        XCTAssertEqual(result[incomingID]?.amount, -100)
        XCTAssertEqual(result[incomingID]?.currencyCode, "HKD")
    }

    private func transferInput(
        id: UUID,
        amount: Decimal,
        currencyCode: String,
        linkedTransactionID: UUID? = nil,
        transferGroupID: UUID? = nil,
        transferSide: TransferSide? = nil
    ) -> TransferCounterpartInput {
        TransferCounterpartInput(
            id: id,
            type: .transfer,
            amount: amount,
            currencyCode: currencyCode,
            linkedTransactionID: linkedTransactionID,
            transferGroupID: transferGroupID,
            transferSide: transferSide
        )
    }
}

private enum BackupInjectedFailure: Error, Equatable {
    case read
    case write
}

@MainActor
private struct FailingBackupReader: BackupModelReading {
    let modelContext: ModelContext
    let failingType: any PersistentModel.Type

    func fetch<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) throws -> [Model] {
        if ObjectIdentifier(Model.self) == ObjectIdentifier(failingType) {
            throw BackupInjectedFailure.read
        }
        return try modelContext.fetch(descriptor)
    }
}
