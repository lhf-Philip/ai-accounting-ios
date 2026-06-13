import Foundation
import SwiftData

enum StoreMigrationSafetyService {
    private static let backupDirectoryName = "MigrationBackups"
    private static let backupPrefix = "SwiftDataMigrationBackup-"
    private static let recentBackupInterval: TimeInterval = 24 * 60 * 60

    @discardableResult
    static func createPreMigrationBackupIfNeeded(
        storeURL: URL,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> URL? {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return nil
        }

        let backupRoot = storeURL.deletingLastPathComponent()
            .appendingPathComponent(backupDirectoryName, isDirectory: true)
        try fileManager.createDirectory(
            at: backupRoot,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )

        if let recentBackup = try mostRecentCompleteBackup(
            in: backupRoot,
            storeName: storeURL.lastPathComponent,
            fileManager: fileManager
        ), now.timeIntervalSince(recentBackup.date) < recentBackupInterval {
            return recentBackup.url
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: now)
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = backupRoot
            .appendingPathComponent("\(backupPrefix)\(timestamp)", isDirectory: true)
        try fileManager.createDirectory(
            at: backupURL,
            withIntermediateDirectories: false,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )

        do {
            for sourceURL in storeFamilyURLs(for: storeURL) where fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.copyItem(
                    at: sourceURL,
                    to: backupURL.appendingPathComponent(sourceURL.lastPathComponent)
                )
            }
            guard isCompleteBackup(
                backupURL,
                storeName: storeURL.lastPathComponent,
                fileManager: fileManager
            ) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return backupURL
        } catch {
            try? fileManager.removeItem(at: backupURL)
            throw error
        }
    }

    @MainActor
    @discardableResult
    static func backfillMissingAdvanceCaseTagIDs(modelContext: ModelContext) throws -> Int {
        let advanceCases = try modelContext.fetch(FetchDescriptor<AdvanceCase>())
        var repairedCount = 0
        for advanceCase in advanceCases where advanceCase.tagIDs == nil {
            advanceCase.tagIDs = []
            repairedCount += 1
        }
        if repairedCount > 0 {
            try modelContext.save()
        }
        return repairedCount
    }

    static func detailedDescription(for error: Error) -> String {
        describe(error as NSError, visited: [])
    }

    private static func storeFamilyURLs(for storeURL: URL) -> [URL] {
        [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm"),
        ]
    }

    private static func mostRecentCompleteBackup(
        in backupRoot: URL,
        storeName: String,
        fileManager: FileManager
    ) throws -> (url: URL, date: Date)? {
        let candidates = try fileManager.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return candidates.compactMap { url -> (URL, Date)? in
            guard url.lastPathComponent.hasPrefix(backupPrefix),
                  isCompleteBackup(url, storeName: storeName, fileManager: fileManager),
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                  values.isDirectory == true,
                  let date = values.contentModificationDate else {
                return nil
            }
            return (url, date)
        }
        .max(by: { $0.1 < $1.1 })
    }

    private static func isCompleteBackup(
        _ backupURL: URL,
        storeName: String,
        fileManager: FileManager
    ) -> Bool {
        let storeCopyURL = backupURL.appendingPathComponent(storeName)
        guard fileManager.fileExists(atPath: storeCopyURL.path),
              let attributes = try? fileManager.attributesOfItem(atPath: storeCopyURL.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > 0
    }

    private static func describe(_ error: NSError, visited: Set<ObjectIdentifier>) -> String {
        let identifier = ObjectIdentifier(error)
        guard !visited.contains(identifier) else {
            return "\(error.domain) \(error.code): \(error.localizedDescription)"
        }

        var nextVisited = visited
        nextVisited.insert(identifier)
        var components = ["\(error.domain) \(error.code): \(error.localizedDescription)"]

        if let reason = error.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
            components.append("reason: \(reason)")
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            components.append("underlying: \(describe(underlying, visited: nextVisited))")
        }
        return components.joined(separator: " | ")
    }
}
