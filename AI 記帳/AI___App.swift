import SwiftUI
import SwiftData
import SQLite3

@main
struct AI___App: App {
    private static func repairLegacyCategoryKindsIfNeeded(storeURL: URL) {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return
        }
        
        var db: OpaquePointer?
        let openFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(storeURL.path, &db, openFlags, nil)
        guard openResult == SQLITE_OK, let db else {
            if let errorMessage = sqlite3_errmsg(db) {
                print("⚠️ 無法開啟資料庫進行舊資料修復: \(String(cString: errorMessage))")
            }
            if db != nil {
                sqlite3_close(db)
            }
            return
        }
        defer { sqlite3_close(db) }
        
        guard tableExists("ZCATEGORY", db: db) else {
            return
        }
        
        let sql = """
        UPDATE ZCATEGORY
        SET ZKIND = 'Both'
        WHERE ZKIND IS NULL
           OR TRIM(ZKIND) = ''
           OR ZKIND NOT IN ('Expense', 'Income', 'Both');
        """
        
        let execResult = sqlite3_exec(db, sql, nil, nil, nil)
        guard execResult == SQLITE_OK else {
            if let errorMessage = sqlite3_errmsg(db) {
                print("⚠️ Category.kind 舊資料修復失敗: \(String(cString: errorMessage))")
            }
            return
        }
        
        let changed = sqlite3_changes(db)
        if changed > 0 {
            print("✅ 已修復 Category.kind 舊資料 \(changed) 筆")
        }
    }
    
    private static func tableExists(_ name: String, db: OpaquePointer) -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;"
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return false
        }
        
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, name, -1, transient)
        return sqlite3_step(statement) == SQLITE_ROW
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Account.self,
            FinancialTransaction.self,
            Category.self,
            Tag.self,
            Shortcut.self,
            CategoryMonthlyBudget.self,
            AdvanceCase.self,
            AdvanceParticipant.self,
            AdvanceRepayment.self
        ])
        
        // 1. 獲取 Documents 資料夾
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("無法存取 Documents 資料夾")
        }
        
        // 2. 使用較安全的檔案保護，避免 FileProtection.none
        do {
            let attributes = [FileAttributeKey.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            try fileManager.setAttributes(attributes, ofItemAtPath: documentsURL.path)
        } catch {
            print("⚠️ 無法設定檔案保護屬性: \(error)")
        }
        
        // 3. 使用新檔名 (v3) 避開舊的損壞檔案
        let storeURL = documentsURL.appendingPathComponent("AI_Accounting_v3.store")
        print("📂 資料庫路徑: \(storeURL.path)")
        
        // 4. 啟動前先修復舊資料的 Category.kind，避免 enum 強制轉型崩潰
        repairLegacyCategoryKindsIfNeeded(storeURL: storeURL)
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            allowsSave: true, // 強制允許儲存
            cloudKitDatabase: .none // 絕對禁止 CloudKit
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
