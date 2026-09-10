import XCTest
import SwiftData
@testable import AI_記帳

@MainActor
final class StoreStartupRecoveryTests: XCTestCase {
    private enum Failure: Error { case injected }

    func testDocumentsFailureDoesNotPrepareBackupRepairOrOpen() async throws {
        var calls = 0
        let service = StoreStartupService(documents: { throw Failure.injected }, prepare: { _ in calls += 1 }, backup: { _ in calls += 1; return nil }, repair: { _ in calls += 1 }, open: { _ in calls += 1; throw Failure.injected })
        let failure = try failure(from: service.load())
        XCTAssertEqual(failure.stage, .documents)
        XCTAssertNil(failure.storeURL)
        XCTAssertEqual(calls, 0)
    }

    func testBackupFailureStopsRepairsAndOpenAndDiscoversExistingSnapshot() async throws {
        let directory = try makeStoreFamily()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("AI_Accounting_v3.store")
        let snapshot = try StoreMigrationSafetyService.createPreMigrationBackupIfNeeded(storeURL: store)
        var unsafeCalls = 0
        let service = StoreStartupService(documents: { directory }, prepare: { _ in }, backup: { _ in throw Failure.injected }, repair: { _ in unsafeCalls += 1 }, open: { _ in unsafeCalls += 1; throw Failure.injected })
        let failure = try failure(from: service.load())
        XCTAssertEqual(failure.stage, .backup)
        XCTAssertEqual(failure.backupURL, snapshot)
        XCTAssertEqual(unsafeCalls, 0)
        try assertOriginalFamily(directory)
    }

    func testOpenFailureEntersRecoveryAndRetryUsesSameStoreWithoutRepeatedReadyOpen() async throws {
        let directory = try makeStoreFamily()
        defer { try? FileManager.default.removeItem(at: directory) }
        var opened: [URL] = []
        var shouldFail = true
        let service = StoreStartupService(documents: { directory }, prepare: { _ in }, repair: { _ in }, open: { url in
            opened.append(url)
            if shouldFail { throw Failure.injected }
            return try StoreStartupService.makeInMemoryContainer()
        })
        let controller = StoreStartupController(load: service.load)
        await controller.startIfNeeded()
        guard case .failed(let failure) = controller.state else { return XCTFail("Expected recovery") }
        XCTAssertEqual(failure.stage, .container)
        let backup = try XCTUnwrap(failure.backupURL)
        XCTAssertTrue(failure.diagnosticText.contains((Failure.injected as NSError).domain))
        try assertOriginalFamily(directory)
        try assertOriginalFamily(backup)
        await controller.startIfNeeded()
        XCTAssertEqual(opened.count, 1)
        shouldFail = false
        await controller.retry()
        guard case .ready = controller.state else { return XCTFail("Expected ready") }
        await controller.retry()
        await controller.startIfNeeded()
        XCTAssertEqual(opened, Array(repeating: directory.appendingPathComponent("AI_Accounting_v3.store"), count: 2))
        try assertOriginalFamily(directory)
    }

    func testSnapshotDiscoveryIgnoresEmptyAndIncompleteDirectoriesAndExportCopiesZip() async throws {
        let directory = try makeStoreFamily()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("AI_Accounting_v3.store")
        let backup = try XCTUnwrap(StoreMigrationSafetyService.createPreMigrationBackupIfNeeded(storeURL: store))
        let incomplete = backup.deletingLastPathComponent().appendingPathComponent("SwiftDataMigrationBackup-incomplete")
        try FileManager.default.createDirectory(at: incomplete, withIntermediateDirectories: true)
        try Data().write(to: incomplete.appendingPathComponent(store.lastPathComponent))
        XCTAssertEqual(try StoreMigrationSafetyService.latestCompleteBackup(storeURL: store), backup)
        let zip = try StoreSnapshotExporter.export(backup, to: directory)
        let bytes = try Data(contentsOf: zip)
        XCTAssertEqual(Array(bytes.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
        try assertOriginalFamily(directory)
        try assertOriginalFamily(backup)
    }

    private func failure(from result: Result<ModelContainer, StoreStartupFailure>) throws -> StoreStartupFailure {
        guard case .failure(let failure) = result else { throw Failure.injected }
        return failure
    }

    private func makeStoreFamily() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            try Data("synthetic\(suffix)".utf8).write(to: directory.appendingPathComponent("AI_Accounting_v3.store\(suffix)"))
        }
        return directory
    }

    private func assertOriginalFamily(_ directory: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        for suffix in ["", "-wal", "-shm"] {
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("AI_Accounting_v3.store\(suffix)")), Data("synthetic\(suffix)".utf8), file: file, line: line)
        }
    }
}
