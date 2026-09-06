import Foundation
import Observation
import SwiftData

enum StoreStartupStage: String {
    case documents, backup, container

    var title: String {
        switch self {
        case .documents: String(localized: "無法存取資料資料夾")
        case .backup: String(localized: "無法建立遷移前備份")
        case .container: String(localized: "無法開啟帳目資料")
        }
    }
}

struct StoreStartupFailure: Error {
    let stage: StoreStartupStage
    let error: Error
    var storeURL: URL?
    var backupURL: URL?

    var diagnosticText: String {
        ["AI Accounting startup: \(stage.rawValue)",
         "Store: \(storeURL?.path ?? "unavailable")",
         "Snapshot: \(backupURL?.path ?? "unavailable")",
         StoreMigrationSafetyService.detailedDescription(for: error)].joined(separator: "\n")
    }
}

@MainActor
struct StoreStartupService {
    var documents: () throws -> URL = {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }
    var prepare: (URL) -> Void = { url in
        do {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        } catch {
            print("File protection: \(error.localizedDescription)")
        }
    }
    var backup: (URL) throws -> URL? = { try StoreMigrationSafetyService.createPreMigrationBackupIfNeeded(storeURL: $0) }
    var discoverBackup: (URL) throws -> URL? = { try StoreMigrationSafetyService.latestCompleteBackup(storeURL: $0) }
    var repair: (URL) -> Void = {
        StartupLegacyStoreRepair.repairLegacyCategoryKindsIfNeeded(storeURL: $0)
        LegacyStoreRepairService.repairLegacyFinancialTransactionEnumsIfNeeded(storeURL: $0)
        StartupLegacyStoreRepair.repairLegacyAssetAdjustmentTransactionsIfNeeded(storeURL: $0)
    }
    var open: (URL) throws -> ModelContainer = { url in
        let schema = schema()
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)])
        do {
            try StoreMigrationSafetyService.backfillMissingAdvanceCaseTagIDs(modelContext: container.mainContext)
        } catch {
            print("AdvanceCase.tagIDs: \(error.localizedDescription)")
        }
        return container
    }

    func load() -> Result<ModelContainer, StoreStartupFailure> {
        let directory: URL
        do { directory = try documents() }
        catch { return .failure(StoreStartupFailure(stage: .documents, error: error)) }
        prepare(directory)
        // Keep the existing production path. Never create a replacement path after failure.
        let storeURL = directory.appendingPathComponent("AI_Accounting_v3.store")
        let snapshot: URL?
        do { snapshot = try backup(storeURL) }
        catch {
            return .failure(StoreStartupFailure(stage: .backup, error: error, storeURL: storeURL, backupURL: try? discoverBackup(storeURL)))
        }
        repair(storeURL)
        do { return .success(try open(storeURL)) }
        catch { return .failure(StoreStartupFailure(stage: .container, error: error, storeURL: storeURL, backupURL: snapshot)) }
    }

    static func schema() -> Schema {
        Schema([Account.self, FinancialTransaction.self, Category.self, Tag.self, Shortcut.self,
                RecurringRule.self, RecurringOccurrence.self, CategoryMonthlyBudget.self,
                BudgetMonthlyHistory.self, BudgetSettings.self, AdvanceCase.self,
                AdvanceParticipant.self, AdvanceRepayment.self])
    }

    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = schema()
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }
}

@Observable @MainActor
final class StoreStartupController {
    enum State {
        case idle, opening, ready(ModelContainer), failed(StoreStartupFailure)
    }
    private(set) var state: State = .idle
    private let load: () -> Result<ModelContainer, StoreStartupFailure>

    init(load: @escaping () -> Result<ModelContainer, StoreStartupFailure>) { self.load = load }

    func startIfNeeded() async {
        guard case .idle = state else { return }
        state = .opening
        await Task.yield()
        switch load() {
        case .success(let container): state = .ready(container)
        case .failure(let failure): state = .failed(failure)
        }
    }

    func retry() async {
        guard case .failed = state else { return }
        state = .idle
        await startIfNeeded()
    }
}

enum StoreSnapshotExporter {
    static func export(_ snapshot: URL, to directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let destination = directory.appendingPathComponent("Account-Recovery-\(UUID().uuidString).zip")
        var coordinationError: NSError?
        var result: Result<URL, Error>?
        NSFileCoordinator().coordinate(readingItemAt: snapshot, options: .forUploading, error: &coordinationError) { zippedURL in
            result = Result {
                // The coordinated snapshot is temporary. Keep a separate copy for the share sheet.
                try FileManager.default.copyItem(at: zippedURL, to: destination)
                return destination
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
}
