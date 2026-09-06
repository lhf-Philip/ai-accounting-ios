import Foundation
import SQLite3

// Existing compatibility repairs, preserved unchanged while versioned migration is tracked in #169.
enum StartupLegacyStoreRepair {
    static func repairLegacyCategoryKindsIfNeeded(storeURL: URL) {
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
        
        if !columnExists("ZKIND", in: "ZCATEGORY", db: db) {
            let addColumnSQL = "ALTER TABLE ZCATEGORY ADD COLUMN ZKIND VARCHAR;"
            let addResult = sqlite3_exec(db, addColumnSQL, nil, nil, nil)
            if addResult != SQLITE_OK {
                if let errorMessage = sqlite3_errmsg(db) {
                    let message = String(cString: errorMessage)
                    // 避免極端情況重複加欄位時中斷流程
                    if !message.localizedCaseInsensitiveContains("duplicate column name") {
                        print("⚠️ 補建 Category.kind 欄位失敗: \(message)")
                        return
                    }
                } else {
                    return
                }
            }
            print("ℹ️ 已補建缺失欄位 ZCATEGORY.ZKIND")
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
    
    static func repairLegacyAssetAdjustmentTransactionsIfNeeded(storeURL: URL) {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return
        }
        
        var db: OpaquePointer?
        let openFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(storeURL.path, &db, openFlags, nil)
        guard openResult == SQLITE_OK, let db else {
            if let errorMessage = sqlite3_errmsg(db) {
                print("⚠️ 無法開啟資料庫修復資產調整資料: \(String(cString: errorMessage))")
            }
            if db != nil {
                sqlite3_close(db)
            }
            return
        }
        defer { sqlite3_close(db) }
        
        guard tableExists("ZFINANCIALTRANSACTION", db: db),
              columnExists("ZTYPE", in: "ZFINANCIALTRANSACTION", db: db),
              columnExists("ZNOTE", in: "ZFINANCIALTRANSACTION", db: db),
              columnExists("ZCATEGORY", in: "ZFINANCIALTRANSACTION", db: db) else {
            return
        }
        
        let beforeChanges = sqlite3_total_changes(db)
        
        let normalizeTypeSQL = """
        UPDATE ZFINANCIALTRANSACTION
        SET ZTYPE = 'Transfer'
        WHERE ZTYPE IN ('Income', 'Expense')
          AND ZCATEGORY IS NULL
          AND (
                ZNOTE LIKE '初始餘額 (%'
             OR ZNOTE = '餘額修正'
             OR ZNOTE LIKE '餘額修正 %'
             OR ZNOTE LIKE '[資產調整]%'
          );
        """
        
        let updateTypeResult = sqlite3_exec(db, normalizeTypeSQL, nil, nil, nil)
        guard updateTypeResult == SQLITE_OK else {
            if let errorMessage = sqlite3_errmsg(db) {
                print("⚠️ 舊資產調整交易修復失敗: \(String(cString: errorMessage))")
            }
            return
        }
        
        if columnExists("ZTRANSFERSIDE", in: "ZFINANCIALTRANSACTION", db: db),
           columnExists("ZAMOUNT", in: "ZFINANCIALTRANSACTION", db: db) {
            let repairSideSQL = """
            UPDATE ZFINANCIALTRANSACTION
            SET ZTRANSFERSIDE = CASE WHEN ZAMOUNT >= 0 THEN 'Incoming' ELSE 'Outgoing' END
            WHERE ZTYPE = 'Transfer'
              AND ZTRANSFERSIDE IS NULL
              AND (
                    ZNOTE LIKE '初始餘額 (%'
                 OR ZNOTE = '餘額修正'
                 OR ZNOTE LIKE '餘額修正 %'
                 OR ZNOTE LIKE '[資產調整]%'
              );
            """
            _ = sqlite3_exec(db, repairSideSQL, nil, nil, nil)
        }
        
        let repairedCount = sqlite3_total_changes(db) - beforeChanges
        if repairedCount > 0 {
            print("✅ 已修復舊版資產調整交易 \(repairedCount) 筆（不再計入收支）")
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
    
    private static func columnExists(_ columnName: String, in tableName: String, db: OpaquePointer) -> Bool {
        let sql = "PRAGMA table_info(\(tableName));"
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return false
        }
        
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let cString = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: cString) == columnName {
                return true
            }
        }
        return false
    }
    
}
