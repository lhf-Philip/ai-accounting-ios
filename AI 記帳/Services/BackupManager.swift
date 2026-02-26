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
        let advanceCases = (try? modelContext.fetch(FetchDescriptor<AdvanceCase>())) ?? []
        let advanceParticipants = (try? modelContext.fetch(FetchDescriptor<AdvanceParticipant>())) ?? []
        let advanceRepayments = (try? modelContext.fetch(FetchDescriptor<AdvanceRepayment>())) ?? []
        
        return FullBackupData(version: "1.5", timestamp: Date(),
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
    
    @MainActor func restoreFromJSON(url: URL, modelContext: ModelContext) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(FullBackupData.self, from: data)
        
        let allAccounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
        let allCategories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        let allTags = (try? modelContext.fetch(FetchDescriptor<Tag>())) ?? []
        
        // 1. 還原帳戶
        for accDTO in backup.accounts {
            if !allAccounts.contains(where: { $0.id == accDTO.id }) {
                // 🔥 兼容處理：如果 isArchived 為 nil，預設 false
                let isArchived = accDTO.isArchived ?? false
                modelContext.insert(Account(id: accDTO.id, name: accDTO.name, currency: accDTO.currency, type: AccountType(rawValue: accDTO.type) ?? .cash, baseBalance: accDTO.baseBalance, sortOrder: accDTO.sortOrder, isArchived: isArchived))
            }
        }
        for catDTO in backup.categories {
            if !allCategories.contains(where: { $0.id == catDTO.id }) {
                let kind = CategoryKind(rawValue: catDTO.kind ?? "") ?? .both
                modelContext.insert(Category(id: catDTO.id, name: catDTO.name, icon: catDTO.icon, colorHex: catDTO.colorHex, kind: kind))
            }
        }
        for tagDTO in backup.tags {
            if !allTags.contains(where: { $0.id == tagDTO.id }) {
                modelContext.insert(Tag(id: tagDTO.id, name: tagDTO.name))
            }
        }
        
        let updatedAccounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
        let updatedCategories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        let updatedTags = (try? modelContext.fetch(FetchDescriptor<Tag>())) ?? []
        
        for txDTO in backup.transactions {
            if (try? modelContext.fetch(FetchDescriptor<FinancialTransaction>(predicate: #Predicate { $0.id == txDTO.id })).first) == nil {
                let account = updatedAccounts.first(where: { $0.id == txDTO.accountID })
                let category = updatedCategories.first(where: { $0.id == txDTO.categoryID })
                let tags = updatedTags.filter { txDTO.tagIDs.contains($0.id) }
                let createdAt = txDTO.createdAt ?? txDTO.date
                let updatedAt = txDTO.updatedAt ?? createdAt
                let tx = FinancialTransaction(
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
                    account: account,
                    category: category,
                    tags: tags,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
                modelContext.insert(tx)
            }
        }
        
        // 5. 還原捷徑
        for scDTO in backup.shortcuts {
            if (try? modelContext.fetch(FetchDescriptor<Shortcut>(predicate: #Predicate { $0.id == scDTO.id })).first) == nil {
                let account = updatedAccounts.first(where: { $0.id == scDTO.accountID })
                let category = updatedCategories.first(where: { $0.id == scDTO.categoryID })
                let tags = updatedTags.filter { scDTO.tagIDs.contains($0.id) }
                
                // 🔥 兼容處理：如果 currencyCode 為 nil (舊備份)，使用帳戶幣種或 HKD
                let currency = scDTO.currencyCode ?? (account?.currency ?? "HKD")
                
                let sc = Shortcut(id: scDTO.id, name: scDTO.name, icon: scDTO.icon, amount: scDTO.amount, currencyCode: currency, type: TransactionType(rawValue: scDTO.type) ?? .expense, note: scDTO.note, account: account, category: category, tags: tags)
                modelContext.insert(sc)
            }
        }
        
        // 6. 還原預算 (向下兼容：舊 JSON 可能沒有 budgets)
        if let budgetDTOs = backup.budgets {
            let existingBudgets = (try? modelContext.fetch(FetchDescriptor<CategoryMonthlyBudget>())) ?? []
            for budgetDTO in budgetDTOs {
                if existingBudgets.contains(where: { $0.id == budgetDTO.id }) {
                    continue
                }
                
                let category = updatedCategories.first(where: { $0.id == budgetDTO.categoryID })
                let budget = CategoryMonthlyBudget(
                    id: budgetDTO.id,
                    monthKey: budgetDTO.monthKey,
                    amount: budgetDTO.amount,
                    currencyCode: budgetDTO.currencyCode,
                    isEnabled: budgetDTO.isEnabled ?? true,
                    createdAt: budgetDTO.createdAt ?? Date(),
                    updatedAt: budgetDTO.updatedAt ?? (budgetDTO.createdAt ?? Date()),
                    category: category
                )
                modelContext.insert(budget)
            }
        }
        
        // 7. 還原代墊主檔
        if let advanceCaseDTOs = backup.advanceCases {
            let existingCases = (try? modelContext.fetch(FetchDescriptor<AdvanceCase>())) ?? []
            for caseDTO in advanceCaseDTOs {
                if existingCases.contains(where: { $0.id == caseDTO.id }) {
                    continue
                }
                
                let payerAccount = updatedAccounts.first(where: { $0.id == caseDTO.payerAccountID })
                let expenseCategory = updatedCategories.first(where: { $0.id == caseDTO.expenseCategoryID })
                
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
                    payerAccount: payerAccount,
                    expenseCategory: expenseCategory
                )
                modelContext.insert(advanceCase)
            }
        }
        
        // 8. 還原代墊對象
        if let participantDTOs = backup.advanceParticipants {
            let restoredCases = (try? modelContext.fetch(FetchDescriptor<AdvanceCase>())) ?? []
            let existingParticipants = (try? modelContext.fetch(FetchDescriptor<AdvanceParticipant>())) ?? []
            
            for participantDTO in participantDTOs {
                if existingParticipants.contains(where: { $0.id == participantDTO.id }) {
                    continue
                }
                
                let advanceCase = restoredCases.first(where: { $0.id == participantDTO.advanceCaseID })
                let debtAccount = updatedAccounts.first(where: { $0.id == participantDTO.debtAccountID })
                
                let participant = AdvanceParticipant(
                    id: participantDTO.id,
                    name: participantDTO.name,
                    owedAmount: participantDTO.owedAmount,
                    repaidAmount: participantDTO.repaidAmount ?? 0,
                    initialTransferGroupID: participantDTO.initialTransferGroupID,
                    createdAt: participantDTO.createdAt ?? Date(),
                    updatedAt: participantDTO.updatedAt ?? (participantDTO.createdAt ?? Date()),
                    advanceCase: advanceCase,
                    debtAccount: debtAccount
                )
                modelContext.insert(participant)
            }
        }
        
        // 9. 還原代墊還款紀錄
        if let repaymentDTOs = backup.advanceRepayments {
            let restoredCases = (try? modelContext.fetch(FetchDescriptor<AdvanceCase>())) ?? []
            let restoredParticipants = (try? modelContext.fetch(FetchDescriptor<AdvanceParticipant>())) ?? []
            let existingRepayments = (try? modelContext.fetch(FetchDescriptor<AdvanceRepayment>())) ?? []
            
            for repaymentDTO in repaymentDTOs {
                if existingRepayments.contains(where: { $0.id == repaymentDTO.id }) {
                    continue
                }
                
                let advanceCase = restoredCases.first(where: { $0.id == repaymentDTO.advanceCaseID })
                let participant = restoredParticipants.first(where: { $0.id == repaymentDTO.participantID })
                let receiveAccount = updatedAccounts.first(where: { $0.id == repaymentDTO.receivedAccountID })
                
                let normalized = repaymentDTO.normalizedAmount ?? repaymentDTO.amount
                let repayment = AdvanceRepayment(
                    id: repaymentDTO.id,
                    amount: repaymentDTO.amount,
                    currencyCode: repaymentDTO.currencyCode,
                    normalizedAmount: normalized,
                    date: repaymentDTO.date,
                    note: repaymentDTO.note ?? "",
                    linkedTransferGroupID: repaymentDTO.linkedTransferGroupID,
                    createdAt: repaymentDTO.createdAt ?? repaymentDTO.date,
                    advanceCase: advanceCase,
                    participant: participant,
                    receivedAccount: receiveAccount
                )
                modelContext.insert(repayment)
            }
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
