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
    
    struct AccountCodable: Codable {
        let id: UUID; let name: String; let currency: String; let type: String; let baseBalance: Decimal; let sortOrder: Int
        // 🔥 新增 Optional，兼容舊 JSON
        let isArchived: Bool?
    }
    struct CategoryCodable: Codable {
        let id: UUID; let name: String; let icon: String; let colorHex: String
    }
    struct TagCodable: Codable {
        let id: UUID; let name: String
    }
    struct TransactionCodable: Codable {
        let id: UUID; let amount: Decimal; let currencyCode: String; let date: Date; let note: String
        let type: String; let linkedTransactionID: UUID?
        let accountID: UUID?; let categoryID: UUID?; let tagIDs: [UUID]
    }
    struct ShortcutCodable: Codable {
        let id: UUID; let name: String; let icon: String; let amount: Decimal; let type: String; let note: String
        // 🔥 新增 Optional，兼容舊 JSON
        let currencyCode: String?
        let accountID: UUID?; let categoryID: UUID?; let tagIDs: [UUID]
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
        
        return FullBackupData(version: "1.1", timestamp: Date(),
            accounts: accounts.map { FullBackupData.AccountCodable(id: $0.id, name: $0.name, currency: $0.currency, type: $0.type.rawValue, baseBalance: $0.baseBalance, sortOrder: $0.sortOrder, isArchived: $0.isArchived) },
            categories: categories.map { FullBackupData.CategoryCodable(id: $0.id, name: $0.name, icon: $0.icon, colorHex: $0.colorHex) },
            tags: tags.map { FullBackupData.TagCodable(id: $0.id, name: $0.name) },
            transactions: transactions.map { FullBackupData.TransactionCodable(id: $0.id, amount: $0.amount, currencyCode: $0.currencyCode, date: $0.date, note: $0.note, type: $0.type.rawValue, linkedTransactionID: $0.linkedTransactionID, accountID: $0.account?.id, categoryID: $0.category?.id, tagIDs: $0.tags.map { $0.id }) },
            shortcuts: shortcuts.map { FullBackupData.ShortcutCodable(id: $0.id, name: $0.name, icon: $0.icon, amount: $0.amount, type: $0.type.rawValue, note: $0.note, currencyCode: $0.currencyCode, accountID: $0.account?.id, categoryID: $0.category?.id, tagIDs: $0.tags.map { $0.id }) }
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
                modelContext.insert(Category(id: catDTO.id, name: catDTO.name, icon: catDTO.icon, colorHex: catDTO.colorHex))
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
                let tx = FinancialTransaction(id: txDTO.id, amount: txDTO.amount, currencyCode: txDTO.currencyCode, date: txDTO.date, note: txDTO.note, type: TransactionType(rawValue: txDTO.type) ?? .expense, linkedTransactionID: txDTO.linkedTransactionID, account: account, category: category, tags: tags)
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
        try? modelContext.save()
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
