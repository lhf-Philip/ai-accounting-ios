import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Combine
import UIKit

// 定義全機備份的資料結構 (JSON)
struct FullBackupData: Codable {
    let version: String
    let timestamp: Date
    let accounts: [AccountCodable]
    let categories: [CategoryCodable]
    let tags: [TagCodable]
    let transactions: [TransactionCodable]
    let shortcuts: [ShortcutCodable]
    let recurringRules: [RecurringRuleCodable]?
    let recurringOccurrences: [RecurringOccurrenceCodable]?
    let budgets: [BudgetCodable]?
    let budgetHistory: [BudgetHistoryCodable]?
    let budgetSettings: [BudgetSettingsCodable]?
    let advanceCases: [AdvanceCaseCodable]?
    let advanceParticipants: [AdvanceParticipantCodable]?
    let advanceRepayments: [AdvanceRepaymentCodable]?
    
    struct AccountCodable: Codable {
        let id: UUID; let name: String; let currency: String; let type: String; let baseBalance: Decimal; let sortOrder: Int
        // 🔥 新增 Optional，兼容舊 JSON
        let isArchived: Bool?
    }
    struct CategoryCodable: Codable {
        let id: UUID; let name: String; let icon: String; let colorHex: String
        let kind: String?
    }
    struct TagCodable: Codable {
        let id: UUID; let name: String
    }
    struct TransactionCodable: Codable {
        let id: UUID; let amount: Decimal; let currencyCode: String; let date: Date; let note: String
        let type: String; let linkedTransactionID: UUID?
        let transferGroupID: UUID?
        let transferSide: String?
        let photoPath: String?
        let createdAt: Date?
        let updatedAt: Date?
        let accountID: UUID?; let categoryID: UUID?; let tagIDs: [UUID]
        let advanceCaseID: UUID?
        let advanceParticipantID: UUID?
        let advanceRepaymentID: UUID?
        let advanceEntryRole: String?
    }
    struct ShortcutCodable: Codable {
        let id: UUID; let name: String; let icon: String; let amount: Decimal; let type: String; let note: String
        // 🔥 新增 Optional，兼容舊 JSON
        let currencyCode: String?
        let accountID: UUID?; let categoryID: UUID?; let tagIDs: [UUID]
    }
    struct RecurringRuleCodable: Codable {
        let id: UUID
        let title: String
        let amount: Decimal
        let currencyCode: String
        let type: String
        let note: String
        let frequency: String
        let intervalCount: Int
        let nextDueDate: Date
        let isPaused: Bool
        let accountID: UUID?
        let categoryID: UUID?
        let tagIDs: [UUID]
        let createdAt: Date?
        let updatedAt: Date?
    }
    struct RecurringOccurrenceCodable: Codable {
        let id: UUID
        let dueDate: Date
        let status: String
        let createdTransactionID: UUID?
        let ruleID: UUID?
        let createdAt: Date?
        let updatedAt: Date?
    }
    struct BudgetCodable: Codable {
        let id: UUID
        let monthKey: String
        let amount: Decimal
        let currencyCode: String
        let isEnabled: Bool?
        let categoryID: UUID?
        let createdAt: Date?
        let updatedAt: Date?
    }
    struct BudgetHistoryCodable: Codable {
        let id: UUID
        let historyKey: String
        let monthKey: String
        let categoryID: UUID
        let categoryNameSnapshot: String
        let budgetAmount: Decimal
        let spentAmount: Decimal
        let remainingAmount: Decimal
        let usageRatio: Decimal
        let isOverBudget: Bool
        let currencyCode: String
        let updatedAt: Date?
    }
    struct BudgetSettingsCodable: Codable {
        let id: String
        let carryOverMode: String
        let alertThresholdPercent: Decimal
        let forecastMode: String
        let updatedAt: Date?
    }
    struct AdvanceCaseCodable: Codable {
        let id: UUID
        let title: String
        let date: Date
        let currencyCode: String
        let myShareAmount: Decimal?
        let note: String?
        let selfExpenseTransactionID: UUID?
        let payerAccountID: UUID?
        let expenseCategoryID: UUID?
        let createdAt: Date?
        let updatedAt: Date?
        let direction: String?
        let tagIDs: [UUID]?
    }
    struct AdvanceParticipantCodable: Codable {
        let id: UUID
        let name: String
        let owedAmount: Decimal
        let repaidAmount: Decimal?
        let initialTransferGroupID: UUID?
        let advanceCaseID: UUID?
        let debtAccountID: UUID?
        let createdAt: Date?
        let updatedAt: Date?
    }
    struct AdvanceRepaymentCodable: Codable {
        let id: UUID
        let amount: Decimal
        let currencyCode: String
        let normalizedAmount: Decimal?
        let date: Date
        let note: String?
        let linkedTransferGroupID: UUID?
        let advanceCaseID: UUID?
        let participantID: UUID?
        let receivedAccountID: UUID?
        let createdAt: Date?
    }
}

enum BackupRestoreError: LocalizedError {
    case clearVerificationFailed
    case restoreVerificationFailed([String])
    case restoreFailedAndRecoveryFailed(importError: Error, recoveryError: Error)

    var errorDescription: String? {
        switch self {
        case .clearVerificationFailed:
            return "資料庫清除後仍然留有資料，已停止後續操作。"
        case .restoreVerificationFailed(let mismatches):
            return "資料還原後的數量驗證失敗：\n\(mismatches.joined(separator: "\n"))"
        case .restoreFailedAndRecoveryFailed(let importError, let recoveryError):
            return """
            覆蓋匯入失敗，而且無法自動恢復匯入前資料。
            匯入錯誤：\(importError.localizedDescription)
            恢復錯誤：\(recoveryError.localizedDescription)
            請保留 App，不要繼續修改資料，並使用最近的 JSON 備份恢復。
            """
        }
    }
}

enum BackupRestoreMode {
    case merge
    case replace
    case clearOnly
}

struct BackupRecordCounts: Equatable {
    var accounts: Int
    var categories: Int
    var tags: Int
    var transactions: Int
    var shortcuts: Int
    var recurringRules: Int
    var recurringOccurrences: Int
    var budgets: Int
    var budgetHistory: Int
    var budgetSettings: Int
    var advanceCases: Int
    var advanceParticipants: Int
    var advanceRepayments: Int

    static let zero = BackupRecordCounts(
        accounts: 0,
        categories: 0,
        tags: 0,
        transactions: 0,
        shortcuts: 0,
        recurringRules: 0,
        recurringOccurrences: 0,
        budgets: 0,
        budgetHistory: 0,
        budgetSettings: 0,
        advanceCases: 0,
        advanceParticipants: 0,
        advanceRepayments: 0
    )

    var total: Int {
        accounts + categories + tags + transactions + shortcuts + recurringRules + recurringOccurrences
            + budgets + budgetHistory + budgetSettings + advanceCases + advanceParticipants + advanceRepayments
    }

    var summaryText: String {
        """
        帳戶 \(accounts)、分類 \(categories)、標籤 \(tags)、交易 \(transactions)、捷徑 \(shortcuts)
        定期記帳 \(recurringRules)、定期項目 \(recurringOccurrences)、預算 \(budgets)、預算歷史 \(budgetHistory)、預算設定 \(budgetSettings)
        代墊案件 \(advanceCases)、代墊對象 \(advanceParticipants)、代墊還款 \(advanceRepayments)
        """
    }

    static func fromBackup(_ backup: FullBackupData) -> BackupRecordCounts {
        BackupRecordCounts(
            accounts: backup.accounts.count,
            categories: backup.categories.count,
            tags: backup.tags.count,
            transactions: backup.transactions.count,
            shortcuts: backup.shortcuts.count,
            recurringRules: backup.recurringRules?.count ?? 0,
            recurringOccurrences: backup.recurringOccurrences?.count ?? 0,
            budgets: backup.budgets?.count ?? 0,
            budgetHistory: backup.budgetHistory?.count ?? 0,
            budgetSettings: backup.budgetSettings?.count ?? 0,
            advanceCases: backup.advanceCases?.count ?? 0,
            advanceParticipants: backup.advanceParticipants?.count ?? 0,
            advanceRepayments: backup.advanceRepayments?.count ?? 0
        )
    }
}

struct BackupRestoreSummary {
    let mode: BackupRestoreMode
    let beforeCounts: BackupRecordCounts
    let backupCounts: BackupRecordCounts
    let afterClearCounts: BackupRecordCounts?
    let afterRestoreCounts: BackupRecordCounts

    var localizedSummary: String {
        switch mode {
        case .clearOnly:
            return """
            資料已清除並完成驗證。
            清除前共有 \(beforeCounts.total) 筆帳務資料；清除後共有 \(afterRestoreCounts.total) 筆。
            """
        case .merge:
            return """
            合併匯入完成並完成基本驗證。
            匯入檔案內容：
            \(backupCounts.summaryText)
            匯入後資料庫：
            \(afterRestoreCounts.summaryText)
            """
        case .replace:
            return """
            覆蓋匯入完成並完成驗證，舊帳務資料已清除。
            匯入檔案內容：
            \(backupCounts.summaryText)
            匯入後資料庫：
            \(afterRestoreCounts.summaryText)
            """
        }
    }
}

// A per-operation seam lets callers surface real fetch errors and tests inject store failures.
@MainActor
protocol BackupModelReading {
    func fetch<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) throws -> [Model]
}

@MainActor
private struct ModelContextBackupReader: BackupModelReading {
    let modelContext: ModelContext

    func fetch<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) throws -> [Model] {
        try modelContext.fetch(descriptor)
    }
}

class BackupManager: NSObject, ObservableObject {
    static let shared = BackupManager()
    
    @AppStorage("backupFolderBookmark") var backupFolderBookmark: Data?
    @AppStorage("lastBackupDate") var lastBackupDate: Double = 0
    @AppStorage("enableAutoBackup") var enableAutoBackup: Bool = false
    @AppStorage("backupRetentionDays") var backupRetentionDays: Int = 30
    
    private override init() {}
    private var folderPickCompletion: ((Bool) -> Void)?
    
    func pickFolderAndSavePermission(completion: @escaping (Bool) -> Void) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = self; picker.allowsMultipleSelection = false; self.folderPickCompletion = completion
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene, let rootVC = scene.windows.first?.rootViewController {
            DispatchQueue.main.async { rootVC.present(picker, animated: true) }
        }
    }
    
    @MainActor func performAutoBackup(modelContext: ModelContext) {
        guard enableAutoBackup, let bookmark = backupFolderBookmark else { return }
        let lastDate = Date(timeIntervalSince1970: lastBackupDate)
        if Calendar.current.isDateInToday(lastDate) { return }
        
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else { return }
        if isStale { enableAutoBackup = false; return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        
        let filename = "AutoBackup_\(Date().formatted(date: .numeric, time: .omitted)).json".replacingOccurrences(of: "/", with: "-")
        let fileURL = url.appendingPathComponent(filename)
        
        do {
            try writeAutoBackup(modelContext: modelContext, to: fileURL)
            print("✅ 自動備份成功: \(filename)")
            cleanOldBackups(in: url)
        } catch { print("❌ 備份失敗: \(error)") }
    }
    
    @MainActor
    func writeAutoBackup(
        modelContext: ModelContext,
        to fileURL: URL,
        reader: (any BackupModelReading)? = nil,
        write: (Data, URL, Data.WritingOptions) throws -> Void = { data, url, options in
            try data.write(to: url, options: options)
        }
    ) throws {
        let backup = try createBackupData(modelContext: modelContext, reader: reader)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try write(encoder.encode(backup), fileURL, .atomic)
        lastBackupDate = Date().timeIntervalSince1970
    }

    private func cleanOldBackups(in folderURL: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let expiration = Calendar.current.date(byAdding: .day, value: -backupRetentionDays, to: Date())!
        for file in files {
            if file.lastPathComponent.starts(with: "AutoBackup_"), let attrs = try? fm.attributesOfItem(atPath: file.path), let date = attrs[.creationDate] as? Date, date < expiration {
                try? fm.removeItem(at: file)
            }
        }
    }
    
    // MARK: - 匯入/匯出 邏輯
    
    @MainActor
    func createBackupData(
        modelContext: ModelContext,
        reader: (any BackupModelReading)? = nil
    ) throws -> FullBackupData {
        let reader = reader ?? ModelContextBackupReader(modelContext: modelContext)
        let accounts = try reader.fetch(FetchDescriptor<Account>())
        let categories = try reader.fetch(FetchDescriptor<Category>())
        let tags = try reader.fetch(FetchDescriptor<Tag>())
        let transactions = try reader.fetch(FetchDescriptor<FinancialTransaction>())
        let shortcuts = try reader.fetch(FetchDescriptor<Shortcut>())
        let recurringRules = try reader.fetch(FetchDescriptor<RecurringRule>())
        let recurringOccurrences = try reader.fetch(FetchDescriptor<RecurringOccurrence>())
        let budgets = try reader.fetch(FetchDescriptor<CategoryMonthlyBudget>())
        let budgetHistory = try reader.fetch(FetchDescriptor<BudgetMonthlyHistory>())
        let budgetSettings = try reader.fetch(FetchDescriptor<BudgetSettings>())
        let advanceCases = try reader.fetch(FetchDescriptor<AdvanceCase>())
        let advanceParticipants = try reader.fetch(FetchDescriptor<AdvanceParticipant>())
        let advanceRepayments = try reader.fetch(FetchDescriptor<AdvanceRepayment>())
        
        return FullBackupData(version: "1.9", timestamp: Date(),
            accounts: accounts.map { FullBackupData.AccountCodable(id: $0.id, name: $0.name, currency: $0.currency, type: $0.type.rawValue, baseBalance: $0.baseBalance, sortOrder: $0.sortOrder, isArchived: $0.isArchived) },
            categories: categories.map { FullBackupData.CategoryCodable(id: $0.id, name: $0.name, icon: $0.icon, colorHex: $0.colorHex, kind: $0.kind.rawValue) },
            tags: tags.map { FullBackupData.TagCodable(id: $0.id, name: $0.name) },
            transactions: transactions.map {
                FullBackupData.TransactionCodable(
                    id: $0.id,
                    amount: $0.amount,
                    currencyCode: $0.currencyCode,
                    date: $0.date,
                    note: $0.note,
                    type: $0.type.rawValue,
                    linkedTransactionID: $0.linkedTransactionID,
                    transferGroupID: $0.transferGroupID,
                    transferSide: $0.transferSide?.rawValue,
                    photoPath: $0.photoPath,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    accountID: $0.account?.id,
                    categoryID: $0.category?.id,
                    tagIDs: $0.tags.map { $0.id },
                    advanceCaseID: $0.advanceCaseID,
                    advanceParticipantID: $0.advanceParticipantID,
                    advanceRepaymentID: $0.advanceRepaymentID,
                    advanceEntryRole: $0.advanceEntryRoleRaw
                )
            },
            shortcuts: shortcuts.map { FullBackupData.ShortcutCodable(id: $0.id, name: $0.name, icon: $0.icon, amount: $0.amount, type: $0.type.rawValue, note: $0.note, currencyCode: $0.currencyCode, accountID: $0.account?.id, categoryID: $0.category?.id, tagIDs: $0.tags.map { $0.id }) },
            recurringRules: recurringRules.map {
                FullBackupData.RecurringRuleCodable(
                    id: $0.id,
                    title: $0.title,
                    amount: $0.amount,
                    currencyCode: $0.currencyCode,
                    type: $0.type.rawValue,
                    note: $0.note,
                    frequency: $0.frequencyRaw,
                    intervalCount: $0.intervalCount,
                    nextDueDate: $0.nextDueDate,
                    isPaused: $0.isPaused,
                    accountID: $0.account?.id,
                    categoryID: $0.category?.id,
                    tagIDs: $0.tags.map(\.id),
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            recurringOccurrences: recurringOccurrences.map {
                FullBackupData.RecurringOccurrenceCodable(
                    id: $0.id,
                    dueDate: $0.dueDate,
                    status: $0.statusRaw,
                    createdTransactionID: $0.createdTransactionID,
                    ruleID: $0.rule?.id,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            budgets: budgets.map {
                FullBackupData.BudgetCodable(
                    id: $0.id,
                    monthKey: $0.monthKey,
                    amount: $0.amount,
                    currencyCode: $0.currencyCode,
                    isEnabled: $0.isEnabled,
                    categoryID: $0.category?.id,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            budgetHistory: budgetHistory.map {
                FullBackupData.BudgetHistoryCodable(
                    id: $0.id,
                    historyKey: $0.historyKey,
                    monthKey: $0.monthKey,
                    categoryID: $0.categoryID,
                    categoryNameSnapshot: $0.categoryNameSnapshot,
                    budgetAmount: $0.budgetAmount,
                    spentAmount: $0.spentAmount,
                    remainingAmount: $0.remainingAmount,
                    usageRatio: $0.usageRatio,
                    isOverBudget: $0.isOverBudget,
                    currencyCode: $0.currencyCode,
                    updatedAt: $0.updatedAt
                )
            },
            budgetSettings: budgetSettings.map {
                FullBackupData.BudgetSettingsCodable(
                    id: $0.id,
                    carryOverMode: $0.carryOverModeRaw,
                    alertThresholdPercent: $0.alertThresholdPercent,
                    forecastMode: $0.forecastModeRaw,
                    updatedAt: $0.updatedAt
                )
            },
            advanceCases: advanceCases.map {
                FullBackupData.AdvanceCaseCodable(
                    id: $0.id,
                    title: $0.title,
                    date: $0.date,
                    currencyCode: $0.currencyCode,
                    myShareAmount: $0.myShareAmount,
                    note: $0.note,
                    selfExpenseTransactionID: $0.selfExpenseTransactionID,
                    payerAccountID: $0.payerAccount?.id,
                    expenseCategoryID: $0.expenseCategory?.id,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    direction: $0.directionRaw,
                    tagIDs: $0.tagIDs ?? []
                )
            },
            advanceParticipants: advanceParticipants.map {
                FullBackupData.AdvanceParticipantCodable(
                    id: $0.id,
                    name: $0.name,
                    owedAmount: $0.owedAmount,
                    repaidAmount: $0.repaidAmount,
                    initialTransferGroupID: $0.initialTransferGroupID,
                    advanceCaseID: $0.advanceCase?.id,
                    debtAccountID: $0.debtAccount?.id,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            advanceRepayments: advanceRepayments.map {
                FullBackupData.AdvanceRepaymentCodable(
                    id: $0.id,
                    amount: $0.amount,
                    currencyCode: $0.currencyCode,
                    normalizedAmount: $0.normalizedAmount,
                    date: $0.date,
                    note: $0.note,
                    linkedTransferGroupID: $0.linkedTransferGroupID,
                    advanceCaseID: $0.advanceCase?.id,
                    participantID: $0.participant?.id,
                    receivedAccountID: $0.receivedAccount?.id,
                    createdAt: $0.createdAt
                )
            }
        )
    }
    
    func restoreFromJSON(
        url: URL,
        modelContext: ModelContext,
        replaceExisting: Bool = false
    ) async throws {
        let backup = try await decodeBackup(from: url)

        try await MainActor.run {
            try restoreBackupData(
                backup,
                modelContext: modelContext,
                replaceExisting: replaceExisting
            )
        }
    }

    func decodeBackup(from url: URL) async throws -> FullBackupData {
        let data = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url)
        }.value

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FullBackupData.self, from: data)
    }

    @discardableResult
    @MainActor
    func restoreBackupData(
        _ backup: FullBackupData,
        modelContext: ModelContext,
        replaceExisting: Bool = false,
        reader: (any BackupModelReading)? = nil
    ) throws -> BackupRestoreSummary {
        let beforeCounts = try backupRecordCounts(modelContext: modelContext)
        let backupCounts = BackupRecordCounts.fromBackup(backup)

        guard replaceExisting else {
            try restoreDecodedBackup(backup, modelContext: modelContext, reader: reader)
            let afterCounts = try backupRecordCounts(modelContext: modelContext)
            return BackupRestoreSummary(
                mode: .merge,
                beforeCounts: beforeCounts,
                backupCounts: backupCounts,
                afterClearCounts: nil,
                afterRestoreCounts: afterCounts
            )
        }

        let recoveryBackup = try createBackupData(modelContext: modelContext, reader: reader)
        do {
            let clearSummary = try clearAllBackupData(modelContext: modelContext)
            try restoreDecodedBackup(backup, modelContext: modelContext, reader: reader)
            let afterCounts = try backupRecordCounts(modelContext: modelContext)
            try verifyRestoredState(backup, actualCounts: afterCounts)
            return BackupRestoreSummary(
                mode: .replace,
                beforeCounts: beforeCounts,
                backupCounts: backupCounts,
                afterClearCounts: clearSummary.afterRestoreCounts,
                afterRestoreCounts: afterCounts
            )
        } catch {
            let importError = error
            do {
                modelContext.rollback()
                try clearAllBackupData(modelContext: modelContext)
                try restoreDecodedBackup(recoveryBackup, modelContext: modelContext)
                let recoveredCounts = try backupRecordCounts(modelContext: modelContext)
                try verifyRestoredState(recoveryBackup, actualCounts: recoveredCounts)
            } catch {
                throw BackupRestoreError.restoreFailedAndRecoveryFailed(
                    importError: importError,
                    recoveryError: error
                )
            }
            throw importError
        }
    }

    @discardableResult
    @MainActor
    func clearAllBackupData(modelContext: ModelContext) throws -> BackupRestoreSummary {
        let beforeCounts = try backupRecordCounts(modelContext: modelContext)
        try deleteEach(FinancialTransaction.self, modelContext: modelContext)
        try deleteEach(Shortcut.self, modelContext: modelContext)
        try deleteEach(RecurringOccurrence.self, modelContext: modelContext)
        try deleteEach(RecurringRule.self, modelContext: modelContext)
        try deleteEach(CategoryMonthlyBudget.self, modelContext: modelContext)
        try deleteEach(BudgetMonthlyHistory.self, modelContext: modelContext)
        try deleteEach(BudgetSettings.self, modelContext: modelContext)
        try deleteEach(AdvanceRepayment.self, modelContext: modelContext)
        try deleteEach(AdvanceParticipant.self, modelContext: modelContext)
        try deleteEach(AdvanceCase.self, modelContext: modelContext)
        try deleteEach(Account.self, modelContext: modelContext)
        try deleteEach(Category.self, modelContext: modelContext)
        try deleteEach(Tag.self, modelContext: modelContext)
        try modelContext.save()

        let afterCounts = try backupRecordCounts(modelContext: modelContext)
        guard afterCounts == .zero else {
            throw BackupRestoreError.clearVerificationFailed
        }

        return BackupRestoreSummary(
            mode: .clearOnly,
            beforeCounts: beforeCounts,
            backupCounts: .zero,
            afterClearCounts: afterCounts,
            afterRestoreCounts: afterCounts
        )
    }

    @MainActor
    private func deleteEach<Model: PersistentModel>(
        _ modelType: Model.Type,
        modelContext: ModelContext
    ) throws {
        for model in try modelContext.fetch(FetchDescriptor<Model>()) {
            modelContext.delete(model)
        }
    }

    @MainActor
    private func backupRecordCounts(modelContext: ModelContext) throws -> BackupRecordCounts {
        BackupRecordCounts(
            accounts: try modelContext.fetch(FetchDescriptor<Account>()).count,
            categories: try modelContext.fetch(FetchDescriptor<Category>()).count,
            tags: try modelContext.fetch(FetchDescriptor<Tag>()).count,
            transactions: try modelContext.fetch(FetchDescriptor<FinancialTransaction>()).count,
            shortcuts: try modelContext.fetch(FetchDescriptor<Shortcut>()).count,
            recurringRules: try modelContext.fetch(FetchDescriptor<RecurringRule>()).count,
            recurringOccurrences: try modelContext.fetch(FetchDescriptor<RecurringOccurrence>()).count,
            budgets: try modelContext.fetch(FetchDescriptor<CategoryMonthlyBudget>()).count,
            budgetHistory: try modelContext.fetch(FetchDescriptor<BudgetMonthlyHistory>()).count,
            budgetSettings: try modelContext.fetch(FetchDescriptor<BudgetSettings>()).count,
            advanceCases: try modelContext.fetch(FetchDescriptor<AdvanceCase>()).count,
            advanceParticipants: try modelContext.fetch(FetchDescriptor<AdvanceParticipant>()).count,
            advanceRepayments: try modelContext.fetch(FetchDescriptor<AdvanceRepayment>()).count
        )
    }

    private func verifyRestoredState(_ backup: FullBackupData, actualCounts: BackupRecordCounts) throws {
        var mismatches: [String] = []

        func require(_ label: String, _ expected: Int, _ actual: Int) {
            if expected != actual {
                mismatches.append("\(label)：預期 \(expected)，實際 \(actual)")
            }
        }

        require("帳戶", backup.accounts.count, actualCounts.accounts)
        require("分類", backup.categories.count, actualCounts.categories)
        require("標籤", backup.tags.count, actualCounts.tags)
        require("交易", backup.transactions.count, actualCounts.transactions)
        require("捷徑", backup.shortcuts.count, actualCounts.shortcuts)
        if let recurringRules = backup.recurringRules {
            require("定期記帳", recurringRules.count, actualCounts.recurringRules)
        }
        if let recurringOccurrences = backup.recurringOccurrences {
            require("定期項目", recurringOccurrences.count, actualCounts.recurringOccurrences)
        }
        if let budgets = backup.budgets {
            require("預算", budgets.count, actualCounts.budgets)
        }
        if let budgetHistory = backup.budgetHistory {
            require("預算歷史", budgetHistory.count, actualCounts.budgetHistory)
        }
        if let budgetSettings = backup.budgetSettings {
            require("預算設定", budgetSettings.count, actualCounts.budgetSettings)
        }
        if let advanceCases = backup.advanceCases {
            require("代墊案件", advanceCases.count, actualCounts.advanceCases)
        }
        if let advanceParticipants = backup.advanceParticipants {
            require("代墊對象", advanceParticipants.count, actualCounts.advanceParticipants)
        }
        if let advanceRepayments = backup.advanceRepayments {
            require("代墊還款", advanceRepayments.count, actualCounts.advanceRepayments)
        }

        guard mismatches.isEmpty else {
            throw BackupRestoreError.restoreVerificationFailed(mismatches)
        }
    }

    @MainActor
    private func restoreDecodedBackup(
        _ backup: FullBackupData,
        modelContext: ModelContext,
        reader: (any BackupModelReading)? = nil
    ) throws {
        let reader = reader ?? ModelContextBackupReader(modelContext: modelContext)
        var accountByID = Dictionary(uniqueKeysWithValues: (try reader.fetch(FetchDescriptor<Account>())).map { ($0.id, $0) })
        var categoryByID = Dictionary(uniqueKeysWithValues: (try reader.fetch(FetchDescriptor<Category>())).map { ($0.id, $0) })
        var tagByID = Dictionary(uniqueKeysWithValues: (try reader.fetch(FetchDescriptor<Tag>())).map { ($0.id, $0) })
        var existingTransactionIDs = Set((try reader.fetch(FetchDescriptor<FinancialTransaction>())).map(\.id))
        var existingShortcutIDs = Set((try reader.fetch(FetchDescriptor<Shortcut>())).map(\.id))
        var recurringRuleByID = Dictionary(uniqueKeysWithValues: (try reader.fetch(FetchDescriptor<RecurringRule>())).map { ($0.id, $0) })
        var recurringOccurrenceByID = Dictionary(uniqueKeysWithValues: (try reader.fetch(FetchDescriptor<RecurringOccurrence>())).map { ($0.id, $0) })
        var existingBudgetIDs = Set((try reader.fetch(FetchDescriptor<CategoryMonthlyBudget>())).map(\.id))
        var historyByKey = Dictionary(uniqueKeysWithValues: (try reader.fetch(FetchDescriptor<BudgetMonthlyHistory>())).map { ($0.historyKey, $0) })
        var budgetSettingsByID = Dictionary(uniqueKeysWithValues: (try reader.fetch(FetchDescriptor<BudgetSettings>())).map { ($0.id, $0) })
        var advanceCaseByID = Dictionary(uniqueKeysWithValues: (try reader.fetch(FetchDescriptor<AdvanceCase>())).map { ($0.id, $0) })
        var participantByID = Dictionary(uniqueKeysWithValues: (try reader.fetch(FetchDescriptor<AdvanceParticipant>())).map { ($0.id, $0) })
        var existingRepaymentIDs = Set((try reader.fetch(FetchDescriptor<AdvanceRepayment>())).map(\.id))

        for accDTO in backup.accounts where accountByID[accDTO.id] == nil {
            let account = Account(
                id: accDTO.id,
                name: accDTO.name,
                currency: accDTO.currency,
                type: AccountType(rawValue: accDTO.type) ?? .cash,
                baseBalance: accDTO.baseBalance,
                sortOrder: accDTO.sortOrder,
                isArchived: accDTO.isArchived ?? false
            )
            modelContext.insert(account)
            accountByID[accDTO.id] = account
        }

        for catDTO in backup.categories where categoryByID[catDTO.id] == nil {
            let category = Category(
                id: catDTO.id,
                name: catDTO.name,
                icon: catDTO.icon,
                colorHex: catDTO.colorHex,
                kind: CategoryKind(rawValue: catDTO.kind ?? "") ?? .both
            )
            modelContext.insert(category)
            categoryByID[catDTO.id] = category
        }

        for tagDTO in backup.tags where tagByID[tagDTO.id] == nil {
            let tag = Tag(id: tagDTO.id, name: tagDTO.name)
            modelContext.insert(tag)
            tagByID[tagDTO.id] = tag
        }

        for txDTO in backup.transactions where !existingTransactionIDs.contains(txDTO.id) {
            let tagIDs = Set(txDTO.tagIDs)
            let transaction = FinancialTransaction(
                id: txDTO.id,
                amount: txDTO.amount,
                currencyCode: txDTO.currencyCode,
                date: txDTO.date,
                note: txDTO.note,
                photoPath: txDTO.photoPath,
                type: TransactionType(rawValue: txDTO.type) ?? .expense,
                linkedTransactionID: txDTO.linkedTransactionID,
                transferGroupID: txDTO.transferGroupID,
                transferSide: TransferSide(rawValue: txDTO.transferSide ?? ""),
                advanceCaseID: txDTO.advanceCaseID,
                advanceParticipantID: txDTO.advanceParticipantID,
                advanceRepaymentID: txDTO.advanceRepaymentID,
                advanceEntryRole: txDTO.advanceEntryRole.flatMap(AdvanceEntryRole.init(rawValue:)),
                account: txDTO.accountID.flatMap { accountByID[$0] },
                category: txDTO.categoryID.flatMap { categoryByID[$0] },
                tags: tagByID.values.filter { tagIDs.contains($0.id) },
                createdAt: txDTO.createdAt ?? txDTO.date,
                updatedAt: txDTO.updatedAt ?? (txDTO.createdAt ?? txDTO.date)
            )
            modelContext.insert(transaction)
            existingTransactionIDs.insert(txDTO.id)
        }

        for scDTO in backup.shortcuts where !existingShortcutIDs.contains(scDTO.id) {
            let account = scDTO.accountID.flatMap { accountByID[$0] }
            let tagIDs = Set(scDTO.tagIDs)
            let shortcut = Shortcut(
                id: scDTO.id,
                name: scDTO.name,
                icon: scDTO.icon,
                amount: scDTO.amount,
                currencyCode: scDTO.currencyCode ?? (account?.currency ?? "HKD"),
                type: TransactionType(rawValue: scDTO.type) ?? .expense,
                note: scDTO.note,
                account: account,
                category: scDTO.categoryID.flatMap { categoryByID[$0] },
                tags: tagByID.values.filter { tagIDs.contains($0.id) }
            )
            modelContext.insert(shortcut)
            existingShortcutIDs.insert(scDTO.id)
        }

        if let ruleDTOs = backup.recurringRules {
            for ruleDTO in ruleDTOs {
                let tagIDs = Set(ruleDTO.tagIDs)
                if let existing = recurringRuleByID[ruleDTO.id] {
                    existing.title = ruleDTO.title
                    existing.amount = ruleDTO.amount
                    existing.currencyCode = ruleDTO.currencyCode
                    existing.type = TransactionType(rawValue: ruleDTO.type) ?? .expense
                    existing.note = ruleDTO.note
                    existing.frequencyRaw = ruleDTO.frequency
                    existing.intervalCount = max(1, ruleDTO.intervalCount)
                    existing.nextDueDate = ruleDTO.nextDueDate
                    existing.isPaused = ruleDTO.isPaused
                    existing.account = ruleDTO.accountID.flatMap { accountByID[$0] }
                    existing.category = ruleDTO.categoryID.flatMap { categoryByID[$0] }
                    existing.tags = tagByID.values.filter { tagIDs.contains($0.id) }
                    existing.updatedAt = ruleDTO.updatedAt ?? Date()
                    continue
                }

                let rule = RecurringRule(
                    id: ruleDTO.id,
                    title: ruleDTO.title,
                    amount: ruleDTO.amount,
                    currencyCode: ruleDTO.currencyCode,
                    type: TransactionType(rawValue: ruleDTO.type) ?? .expense,
                    note: ruleDTO.note,
                    frequency: RecurringFrequency(rawValue: ruleDTO.frequency) ?? .monthly,
                    intervalCount: max(1, ruleDTO.intervalCount),
                    nextDueDate: ruleDTO.nextDueDate,
                    isPaused: ruleDTO.isPaused,
                    createdAt: ruleDTO.createdAt ?? Date(),
                    updatedAt: ruleDTO.updatedAt ?? (ruleDTO.createdAt ?? Date()),
                    account: ruleDTO.accountID.flatMap { accountByID[$0] },
                    category: ruleDTO.categoryID.flatMap { categoryByID[$0] },
                    tags: tagByID.values.filter { tagIDs.contains($0.id) }
                )
                modelContext.insert(rule)
                recurringRuleByID[ruleDTO.id] = rule
            }
        }

        if let occurrenceDTOs = backup.recurringOccurrences {
            for occurrenceDTO in occurrenceDTOs {
                if let existing = recurringOccurrenceByID[occurrenceDTO.id] {
                    existing.dueDate = occurrenceDTO.dueDate
                    existing.statusRaw = occurrenceDTO.status
                    existing.createdTransactionID = occurrenceDTO.createdTransactionID
                    existing.rule = occurrenceDTO.ruleID.flatMap { recurringRuleByID[$0] }
                    existing.updatedAt = occurrenceDTO.updatedAt ?? Date()
                    continue
                }

                let occurrence = RecurringOccurrence(
                    id: occurrenceDTO.id,
                    dueDate: occurrenceDTO.dueDate,
                    status: RecurringOccurrenceStatus(rawValue: occurrenceDTO.status) ?? .pending,
                    createdTransactionID: occurrenceDTO.createdTransactionID,
                    createdAt: occurrenceDTO.createdAt ?? Date(),
                    updatedAt: occurrenceDTO.updatedAt ?? (occurrenceDTO.createdAt ?? Date()),
                    rule: occurrenceDTO.ruleID.flatMap { recurringRuleByID[$0] }
                )
                modelContext.insert(occurrence)
                recurringOccurrenceByID[occurrenceDTO.id] = occurrence
            }
        }

        if let budgetDTOs = backup.budgets {
            for budgetDTO in budgetDTOs where !existingBudgetIDs.contains(budgetDTO.id) {
                let budget = CategoryMonthlyBudget(
                    id: budgetDTO.id,
                    monthKey: budgetDTO.monthKey,
                    amount: budgetDTO.amount,
                    currencyCode: budgetDTO.currencyCode,
                    isEnabled: budgetDTO.isEnabled ?? true,
                    createdAt: budgetDTO.createdAt ?? Date(),
                    updatedAt: budgetDTO.updatedAt ?? (budgetDTO.createdAt ?? Date()),
                    category: budgetDTO.categoryID.flatMap { categoryByID[$0] }
                )
                modelContext.insert(budget)
                existingBudgetIDs.insert(budgetDTO.id)
            }
        }

        if let historyDTOs = backup.budgetHistory {
            for historyDTO in historyDTOs {
                if let existing = historyByKey[historyDTO.historyKey] {
                    existing.monthKey = historyDTO.monthKey
                    existing.categoryID = historyDTO.categoryID
                    existing.categoryNameSnapshot = historyDTO.categoryNameSnapshot
                    existing.budgetAmount = historyDTO.budgetAmount
                    existing.spentAmount = historyDTO.spentAmount
                    existing.remainingAmount = historyDTO.remainingAmount
                    existing.usageRatio = historyDTO.usageRatio
                    existing.isOverBudget = historyDTO.isOverBudget
                    existing.currencyCode = historyDTO.currencyCode
                    existing.updatedAt = historyDTO.updatedAt ?? Date()
                    continue
                }

                let history = BudgetMonthlyHistory(
                    id: historyDTO.id,
                    historyKey: historyDTO.historyKey,
                    monthKey: historyDTO.monthKey,
                    categoryID: historyDTO.categoryID,
                    categoryNameSnapshot: historyDTO.categoryNameSnapshot,
                    budgetAmount: historyDTO.budgetAmount,
                    spentAmount: historyDTO.spentAmount,
                    remainingAmount: historyDTO.remainingAmount,
                    usageRatio: historyDTO.usageRatio,
                    isOverBudget: historyDTO.isOverBudget,
                    currencyCode: historyDTO.currencyCode,
                    updatedAt: historyDTO.updatedAt ?? Date()
                )
                modelContext.insert(history)
                historyByKey[historyDTO.historyKey] = history
            }
        }

        if let settingsDTOs = backup.budgetSettings {
            for settingsDTO in settingsDTOs {
                if let existing = budgetSettingsByID[settingsDTO.id] {
                    existing.carryOverModeRaw = settingsDTO.carryOverMode
                    existing.alertThresholdPercent = settingsDTO.alertThresholdPercent
                    existing.forecastModeRaw = settingsDTO.forecastMode
                    existing.updatedAt = settingsDTO.updatedAt ?? Date()
                    continue
                }

                let settings = BudgetSettings(
                    id: settingsDTO.id,
                    carryOverMode: BudgetCarryOverMode(rawValue: settingsDTO.carryOverMode) ?? .none,
                    alertThresholdPercent: settingsDTO.alertThresholdPercent,
                    forecastMode: BudgetForecastMode(rawValue: settingsDTO.forecastMode) ?? .spendingPace,
                    updatedAt: settingsDTO.updatedAt ?? Date()
                )
                modelContext.insert(settings)
                budgetSettingsByID[settingsDTO.id] = settings
            }
        }

        if let advanceCaseDTOs = backup.advanceCases {
            for caseDTO in advanceCaseDTOs where advanceCaseByID[caseDTO.id] == nil {
                let advanceCase = AdvanceCase(
                    id: caseDTO.id,
                    title: caseDTO.title,
                    date: caseDTO.date,
                    currencyCode: caseDTO.currencyCode,
                    myShareAmount: caseDTO.myShareAmount ?? 0,
                    note: caseDTO.note ?? "",
                    selfExpenseTransactionID: caseDTO.selfExpenseTransactionID,
                    direction: caseDTO.direction.flatMap(AdvanceDirection.init(rawValue:)),
                    tagIDs: caseDTO.tagIDs ?? [],
                    createdAt: caseDTO.createdAt ?? caseDTO.date,
                    updatedAt: caseDTO.updatedAt ?? (caseDTO.createdAt ?? caseDTO.date),
                    payerAccount: caseDTO.payerAccountID.flatMap { accountByID[$0] },
                    expenseCategory: caseDTO.expenseCategoryID.flatMap { categoryByID[$0] }
                )
                modelContext.insert(advanceCase)
                advanceCaseByID[caseDTO.id] = advanceCase
            }
        }

        if let participantDTOs = backup.advanceParticipants {
            for participantDTO in participantDTOs where participantByID[participantDTO.id] == nil {
                let participant = AdvanceParticipant(
                    id: participantDTO.id,
                    name: participantDTO.name,
                    owedAmount: participantDTO.owedAmount,
                    repaidAmount: participantDTO.repaidAmount ?? 0,
                    initialTransferGroupID: participantDTO.initialTransferGroupID,
                    createdAt: participantDTO.createdAt ?? Date(),
                    updatedAt: participantDTO.updatedAt ?? (participantDTO.createdAt ?? Date()),
                    advanceCase: participantDTO.advanceCaseID.flatMap { advanceCaseByID[$0] },
                    debtAccount: participantDTO.debtAccountID.flatMap { accountByID[$0] }
                )
                modelContext.insert(participant)
                participantByID[participantDTO.id] = participant
            }
        }

        if let repaymentDTOs = backup.advanceRepayments {
            for repaymentDTO in repaymentDTOs where !existingRepaymentIDs.contains(repaymentDTO.id) {
                let repayment = AdvanceRepayment(
                    id: repaymentDTO.id,
                    amount: repaymentDTO.amount,
                    currencyCode: repaymentDTO.currencyCode,
                    normalizedAmount: repaymentDTO.normalizedAmount ?? repaymentDTO.amount,
                    date: repaymentDTO.date,
                    note: repaymentDTO.note ?? "",
                    linkedTransferGroupID: repaymentDTO.linkedTransferGroupID,
                    createdAt: repaymentDTO.createdAt ?? repaymentDTO.date,
                    advanceCase: repaymentDTO.advanceCaseID.flatMap { advanceCaseByID[$0] },
                    participant: repaymentDTO.participantID.flatMap { participantByID[$0] },
                    receivedAccount: repaymentDTO.receivedAccountID.flatMap { accountByID[$0] }
                )
                modelContext.insert(repayment)
                existingRepaymentIDs.insert(repaymentDTO.id)
            }
        }

        try modelContext.save()
        _ = try AdvanceMaintenance.backfillExplicitLinks(modelContext: modelContext)
        _ = try AdvanceMaintenance.reconcileUnderstatedRepaymentTotals(modelContext: modelContext)
        do {
            try BudgetHistoryService.shared.syncAll(modelContext: modelContext, currencyService: CurrencyService.shared)
        } catch is CurrencyConversionError {
            // Restore the backup's ledger/history as recorded. Offline re-estimation is optional;
            // syncAll validates all conversions before changing any imported history.
            print("Budget history re-estimation deferred: exchange rates unavailable")
        }
        try modelContext.save()
    }
    
    @MainActor func generateCSV(modelContext: ModelContext) -> String {
        let transactions = (try? modelContext.fetch(FetchDescriptor<FinancialTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        var csv = "Date,Type,Amount,Currency,Category,Account,Note,Tags\n"
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        for tx in transactions {
            let tags = tx.tags.map { $0.name }.joined(separator: "|")
            let note = tx.note.replacingOccurrences(of: ",", with: "，").replacingOccurrences(of: "\n", with: " ")
            csv.append("\(f.string(from: tx.date)),\(tx.type.rawValue),\(tx.amount),\(tx.currencyCode),\(tx.category?.name ?? "Uncategorized"),\(tx.account?.name ?? "Unknown"),\(note),\(tags)\n")
        }
        return csv
    }
}

extension BackupManager: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { folderPickCompletion?(false); return }
        guard url.startAccessingSecurityScopedResource() else { folderPickCompletion?(false); return }
        do {
            let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            self.backupFolderBookmark = bookmark
            self.enableAutoBackup = true
            folderPickCompletion?(true)
        } catch { print("書籤錯誤: \(error)"); folderPickCompletion?(false) }
        url.stopAccessingSecurityScopedResource()
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { folderPickCompletion?(false) }
}
