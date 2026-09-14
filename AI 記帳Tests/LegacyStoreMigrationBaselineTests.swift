import XCTest
import SwiftData
import CryptoKit
@testable import AI_記帳

@MainActor
final class LegacyStoreMigrationBaselineTests: XCTestCase {
    private struct Manifest: Decodable {
        let sourceCommit: String
        let modelSHA256: String
        let generatorSHA256: String
        let fixtures: [String: Fixture]
        struct Fixture: Decodable { let files: [String: String] }
    }
    private enum InjectedFailure: Error { case open }
    private let storeName = "AI_Accounting_v3.store"

    func testFrozenSourceAndStoreFamiliesMatchManifest() async throws {
        let manifest = try readManifest()
        XCTAssertEqual(manifest.sourceCommit, "9063807944d1b46e2125711338c73acfa20f32e9")
        XCTAssertEqual(try hash(fixtures.appendingPathComponent("V101Models.swift.source")), manifest.modelSHA256)
        XCTAssertEqual(try hash(fixtures.appendingPathComponent("V101Generator.swift.source")), manifest.generatorSHA256)
        for entry in manifest.fixtures.values {
            for (name, expected) in entry.files {
                XCTAssertEqual(try hash(fixtures.appendingPathComponent(name)), expected, name)
            }
        }
    }

    func testEmptyV101StoreOpensTwiceWithoutCreatingLedgerRecords() async throws {
        let directory = try copyFixture("empty")
        defer { try? FileManager.default.removeItem(at: directory) }
        for _ in 0..<2 {
            try autoreleasepool {
                let container = try open(directory)
                let context = ModelContext(container)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<Account>()), 0)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<FinancialTransaction>()), 0)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<AI_記帳.Category>()), 0)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<Tag>()), 0)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<Shortcut>()), 0)
            }
        }
    }

    func testPopulatedV101StorePreservesSemanticsOnTwoOpensAndJSONRoundtrip() async throws {
        let directory = try copyFixture("populated")
        defer { try? FileManager.default.removeItem(at: directory) }
        for _ in 0..<2 {
            try autoreleasepool { try assertPopulation(ModelContext(open(directory))) }
        }
        let exported = try autoreleasepool {
            let container = try open(directory)
            return try BackupManager.shared.createBackupData(modelContext: ModelContext(container))
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(exported)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FullBackupData.self, from: encoded)

        let restoredDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: restoredDirectory) }
        try FileManager.default.createDirectory(at: restoredDirectory, withIntermediateDirectories: true)
        try autoreleasepool {
            let container = try open(restoredDirectory)
            let context = ModelContext(container)
            _ = try BackupManager.shared.restoreBackupData(decoded, modelContext: context, replaceExisting: true)
            try assertPopulation(context)
        }
        // The JSON roundtrip writes today's schema; verify that on-disk store reopens too.
        try autoreleasepool { try assertPopulation(ModelContext(open(restoredDirectory))) }
    }

    func testOpenFailureAfterRealRepairsLeavesUsableOriginalSnapshot() async throws {
        let directory = try copyFixture("populated")
        defer { try? FileManager.default.removeItem(at: directory) }
        // Keep real backup and repair closures; fail exactly at the container-open boundary.
        let service = StoreStartupService(documents: { directory }, prepare: { _ in }, open: { _ in throw InjectedFailure.open })
        guard case .failure(let failure) = service.load() else { return XCTFail("Expected injected open failure") }
        XCTAssertEqual(failure.stage, .container)
        let snapshot = try XCTUnwrap(failure.backupURL)
        let manifest = try readManifest()
        let entry = try XCTUnwrap(manifest.fixtures["populated"])
        for (name, expected) in entry.files {
            let suffix = String(name.dropFirst("v1.0.1-populated.store".count))
            XCTAssertEqual(try hash(snapshot.appendingPathComponent(storeName + suffix)), expected)
        }
        let recovered = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: recovered) }
        try FileManager.default.copyItem(at: snapshot, to: recovered)
        for _ in 0..<2 {
            try autoreleasepool { try assertPopulation(ModelContext(open(recovered))) }
        }
        // Restoring a copy must not alter the recovery snapshot itself.
        for (name, expected) in entry.files {
            let suffix = String(name.dropFirst("v1.0.1-populated.store".count))
            XCTAssertEqual(try hash(snapshot.appendingPathComponent(storeName + suffix)), expected)
        }
    }

    private func assertPopulation(_ context: ModelContext) throws {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(Set(accounts.map(\.id)), [id(1), id(6)])
        let cash = try XCTUnwrap(accounts.first { $0.id == id(1) })
        let bank = try XCTUnwrap(accounts.first { $0.id == id(6) })
        XCTAssertEqual(cash.name, "Synthetic cash")
        XCTAssertEqual(cash.currency, "HKD")
        XCTAssertEqual(cash.type, .cash)
        XCTAssertEqual(cash.baseBalance, exactDecimal("1000.00"))
        XCTAssertEqual(cash.currentBalance, exactDecimal("1114.41"))
        XCTAssertFalse(cash.isArchived)
        XCTAssertEqual(bank.currency, "USD")
        XCTAssertEqual(bank.type, .bank)
        XCTAssertEqual(bank.baseBalance, exactDecimal("50.00"))
        XCTAssertEqual(bank.currentBalance, exactDecimal("62.80"))
        XCTAssertEqual(bank.sortOrder, 1)

        let transactions = try context.fetch(FetchDescriptor<FinancialTransaction>())
        XCTAssertEqual(Set(transactions.map(\.id)), [id(4), id(7), id(8), id(9)])
        for (index, amount, currency, type, account, note) in [
            (4, "-35.59", "HKD", TransactionType.expense, 1, "Synthetic expense"),
            (7, "250.00", "HKD", .income, 1, "Synthetic income"),
            (8, "-100.00", "HKD", .transfer, 1, "Synthetic transfer out"),
            (9, "12.80", "USD", .transfer, 6, "Synthetic transfer in")
        ] {
            let transaction = try XCTUnwrap(transactions.first { $0.id == id(index) })
            XCTAssertEqual(transaction.amount, exactDecimal(amount))
            XCTAssertEqual(transaction.currencyCode, currency)
            XCTAssertEqual(transaction.type, type)
            XCTAssertEqual(transaction.account?.id, id(account))
            XCTAssertEqual(transaction.note, note)
            XCTAssertEqual(transaction.date, Date(timeIntervalSince1970: 1700000000))
            XCTAssertNil(transaction.photoPath)
            XCTAssertNil(transaction.advanceCaseID)
        }
        let expense = try XCTUnwrap(transactions.first { $0.id == id(4) })
        XCTAssertEqual(expense.category?.id, id(2))
        XCTAssertEqual(Set(expense.tags.map(\.id)), [id(3)])
        XCTAssertEqual(transactions.first { $0.id == id(8) }?.linkedTransactionID, id(9))
        XCTAssertEqual(transactions.first { $0.id == id(9) }?.linkedTransactionID, id(8))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AI_記帳.Category>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Tag>()), 1)
        XCTAssertEqual(expense.category?.name, "Synthetic food")
        XCTAssertEqual(expense.category?.kind, .both)
        XCTAssertEqual(expense.tags.first?.name, "Synthetic fixture")
        let shortcuts = try context.fetch(FetchDescriptor<Shortcut>())
        XCTAssertEqual(shortcuts.count, 1)
        let shortcut = try XCTUnwrap(shortcuts.first)
        XCTAssertEqual(shortcut.id, id(5))
        XCTAssertEqual(shortcut.amount, exactDecimal("35.59"))
        XCTAssertEqual(shortcut.currencyCode, "HKD")
        XCTAssertEqual(shortcut.type, .expense)
        XCTAssertEqual(shortcut.account?.id, id(1))
        XCTAssertEqual(shortcut.category?.id, id(2))
        XCTAssertEqual(Set(shortcut.tags.map(\.id)), [id(3)])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AdvanceCase>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CategoryMonthlyBudget>()), 0)
    }

    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/SwiftData")
    }
    private func readManifest() throws -> Manifest {
        try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: fixtures.appendingPathComponent("v101-manifest.json")))
    }
    private func copyFixture(_ mode: String) throws -> URL {
        let manifest = try readManifest()
        let entry = try XCTUnwrap(manifest.fixtures[mode])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in entry.files.keys {
            let suffix = String(name.dropFirst("v1.0.1-\(mode).store".count))
            try FileManager.default.copyItem(at: fixtures.appendingPathComponent(name), to: directory.appendingPathComponent(storeName + suffix))
        }
        return directory
    }
    private func open(_ directory: URL) throws -> ModelContainer {
        switch StoreStartupService(documents: { directory }, prepare: { _ in }).load() {
        case .success(let container): return container
        case .failure(let failure):
            XCTFail(failure.diagnosticText)
            throw failure
        }
    }
    private func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }
    private func hash(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }
}
