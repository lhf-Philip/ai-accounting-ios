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
    }
    struct ShortcutCodable: Codable {
        let id: UUID; let name: String; let icon: String; let amount: Decimal; let type: String; let note: String
        // 🔥 新增 Optional，兼容舊 JSON
        let currencyCode: String?
        let accountID: UUID?; let categoryID: UUID?; let tagIDs: [UUID]
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
        
        let data = createBackupData(modelContext: modelContext)
        let filename = "AutoBackup_\(Date().formatted(date: .numeric, time: .omitted)).json".replacingOccurrences(of: "/", with: "-")
        let fileURL = url.appendingPathComponent(filename)
        
        do {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(data).write(to: fileURL)
            print("✅ 自動備份成功: \(filename)")
            cleanOldBackups(in: url)
            lastBackupDate = Date().timeIntervalSince1970
        } catch { print("❌ 備份失敗: \(error)") }
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
    
    @MainActor func createBackupData(modelContext: ModelContext) -> FullBackupData {
        let accounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
        let categories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        let tags = (try? modelContext.fetch(FetchDescriptor<Tag>())) ?? []
        let transactions = (try? modelContext.fetch(FetchDescriptor<FinancialTransaction>())) ?? []
        let shortcuts = (try? modelContext.fetch(FetchDescriptor<Shortcut>())) ?? []
        let budgets = (try? modelContext.fetch(FetchDescriptor<CategoryMonthlyBudget>())) ?? []
        let budgetHistory = (try? modelContext.fetch(FetchDescriptor<BudgetMonthlyHistory>())) ?? []
        let budgetSettings = (try? modelContext.fetch(FetchDescriptor<BudgetSettings>())) ?? []
        let advanceCases = (try? modelContext.fetch(FetchDescriptor<AdvanceCase>())) ?? []
        let advanceParticipants = (try? modelContext.fetch(FetchDescriptor<AdvanceParticipant>())) ?? []
        let advanceRepayments = (try? modelContext.fetch(FetchDescriptor<AdvanceRepayment>())) ?? []
        
        return FullBackupData(version: "1.7", timestamp: Date(),
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
                    tagIDs: $0.tags.map { $0.id }
                )
            },
            shortcuts: shortcuts.map { FullBackupData.ShortcutCodable(id: $0.id, name: $0.name, icon: $0.icon, amount: $0.amount, type: $0.type.rawValue, note: $0.note, currencyCode: $0.currencyCode, accountID: $0.account?.id, categoryID: $0.category?.id, tagIDs: $0.tags.map { $0.id }) },
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
                    updatedAt: $0.updatedAt
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
    
    func restoreFromJSON(url: URL, modelContext: ModelContext) async throws {
        let data = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url)
        }.value

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(FullBackupData.self, from: data)

        try await MainActor.run {
            try restoreDecodedBackup(backup, modelContext: modelContext)
        }
    }

    @MainActor
    private func restoreDecodedBackup(_ backup: FullBackupData, modelContext: ModelContext) throws {
        var accountByID = Dictionary(uniqueKeysWithValues: ((try? modelContext.fetch(FetchDescriptor<Account>())) ?? []).map { ($0.id, $0) })
        var categoryByID = Dictionary(uniqueKeysWithValues: ((try? modelContext.fetch(FetchDescriptor<Category>())) ?? []).map { ($0.id, $0) })
        var tagByID = Dictionary(uniqueKeysWithValues: ((try? modelContext.fetch(FetchDescriptor<Tag>())) ?? []).map { ($0.id, $0) })
        var existingTransactionIDs = Set(((try? modelContext.fetch(FetchDescriptor<FinancialTransaction>())) ?? []).map(\.id))
        var existingShortcutIDs = Set(((try? modelContext.fetch(FetchDescriptor<Shortcut>())) ?? []).map(\.id))
        var existingBudgetIDs = Set(((try? modelContext.fetch(FetchDescriptor<CategoryMonthlyBudget>())) ?? []).map(\.id))
        var historyByKey = Dictionary(uniqueKeysWithValues: ((try? modelContext.fetch(FetchDescriptor<BudgetMonthlyHistory>())) ?? []).map { ($0.historyKey, $0) })
        var budgetSettingsByID = Dictionary(uniqueKeysWithValues: ((try? modelContext.fetch(FetchDescriptor<BudgetSettings>())) ?? []).map { ($0.id, $0) })
        var advanceCaseByID = Dictionary(uniqueKeysWithValues: ((try? modelContext.fetch(FetchDescriptor<AdvanceCase>())) ?? []).map { ($0.id, $0) })
        var participantByID = Dictionary(uniqueKeysWithValues: ((try? modelContext.fetch(FetchDescriptor<AdvanceParticipant>())) ?? []).map { ($0.id, $0) })
        var existingRepaymentIDs = Set(((try? modelContext.fetch(FetchDescriptor<AdvanceRepayment>())) ?? []).map(\.id))

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

        try BudgetHistoryService.shared.syncAll(modelContext: modelContext, currencyService: CurrencyService.shared)
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
