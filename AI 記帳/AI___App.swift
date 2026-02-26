import SwiftUI
import SwiftData

@main
struct AI___App: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Account.self,
            FinancialTransaction.self,
            Category.self,
            Tag.self,
            Shortcut.self
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
