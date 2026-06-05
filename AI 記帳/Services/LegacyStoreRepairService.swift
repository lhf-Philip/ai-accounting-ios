import Foundation
import SQLite3

enum LegacyStoreRepairService {
    static func repairLegacyFinancialTransactionEnumsIfNeeded(storeURL: URL) {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return
        }

        var db: OpaquePointer?
        let openFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(storeURL.path, &db, openFlags, nil)
        guard openResult == SQLITE_OK, let db else {
            if let errorMessage = sqlite3_errmsg(db) {
                print("⚠️ 無法開啟資料庫修復交易 enum 欄位: \(String(cString: errorMessage))")
            }
            if db != nil {
                sqlite3_close(db)
            }
            return
        }
        defer { sqlite3_close(db) }

        repairLegacyFinancialTransactionEnums(db: db)
    }

    private static func repairLegacyFinancialTransactionEnums(db: OpaquePointer) {
        guard tableExists("ZFINANCIALTRANSACTION", db: db) else {
            return
        }

        if !columnExists("ZTYPE", in: "ZFINANCIALTRANSACTION", db: db) {
            let addColumnSQL = "ALTER TABLE ZFINANCIALTRANSACTION ADD COLUMN ZTYPE VARCHAR;"
            let addResult = sqlite3_exec(db, addColumnSQL, nil, nil, nil)
            if addResult != SQLITE_OK {
                if let errorMessage = sqlite3_errmsg(db) {
                    let message = String(cString: errorMessage)
                    if !message.localizedCaseInsensitiveContains("duplicate column name") {
                        print("⚠️ 補建 FinancialTransaction.type 欄位失敗: \(message)")
                        return
                    }
                } else {
                    return
                }
            }
            print("ℹ️ 已補建缺失欄位 ZFINANCIALTRANSACTION.ZTYPE")
        }

        let beforeChanges = sqlite3_total_changes(db)
        repairTransactionType(db: db)
        repairTransferSide(db: db)

        let changed = sqlite3_total_changes(db) - beforeChanges
        if changed > 0 {
            print("✅ 已修復 FinancialTransaction enum 舊資料 \(changed) 筆")
        }
    }

    private static func repairTransactionType(db: OpaquePointer) {
        guard columnExists("ZTYPE", in: "ZFINANCIALTRANSACTION", db: db) else {
            return
        }

        let amountExpression = columnExists("ZAMOUNT", in: "ZFINANCIALTRANSACTION", db: db)
            ? "COALESCE(ZAMOUNT, 0)"
            : "0"
        let transferPredicate = transferShapePredicates(db: db).joined(separator: " OR ")
        let transferCondition = transferPredicate.isEmpty ? "0" : transferPredicate

        let sql = """
        UPDATE ZFINANCIALTRANSACTION
        SET ZTYPE = CASE
            WHEN \(transferCondition) THEN 'Transfer'
            WHEN \(amountExpression) >= 0 THEN 'Income'
            ELSE 'Expense'
        END
        WHERE ZTYPE IS NULL
           OR TRIM(CAST(ZTYPE AS TEXT)) = ''
           OR ZTYPE NOT IN ('Income', 'Expense', 'Transfer');
        """

        let result = sqlite3_exec(db, sql, nil, nil, nil)
        if result != SQLITE_OK, let errorMessage = sqlite3_errmsg(db) {
            print("⚠️ FinancialTransaction.type 舊資料修復失敗: \(String(cString: errorMessage))")
        }
    }

    private static func repairTransferSide(db: OpaquePointer) {
        guard columnExists("ZTRANSFERSIDE", in: "ZFINANCIALTRANSACTION", db: db) else {
            return
        }

        let amountExpression = columnExists("ZAMOUNT", in: "ZFINANCIALTRANSACTION", db: db)
            ? "COALESCE(ZAMOUNT, 0)"
            : "0"

        let sql = """
        UPDATE ZFINANCIALTRANSACTION
        SET ZTRANSFERSIDE = CASE
            WHEN ZTYPE = 'Transfer' AND \(amountExpression) >= 0 THEN 'Incoming'
            WHEN ZTYPE = 'Transfer' THEN 'Outgoing'
            ELSE NULL
        END
        WHERE ZTRANSFERSIDE IS NOT NULL
          AND (
                TRIM(CAST(ZTRANSFERSIDE AS TEXT)) = ''
             OR ZTRANSFERSIDE NOT IN ('Incoming', 'Outgoing')
          );
        """

        let result = sqlite3_exec(db, sql, nil, nil, nil)
        if result != SQLITE_OK, let errorMessage = sqlite3_errmsg(db) {
            print("⚠️ FinancialTransaction.transferSide 舊資料修復失敗: \(String(cString: errorMessage))")
        }
    }

    private static func transferShapePredicates(db: OpaquePointer) -> [String] {
        var predicates: [String] = []
        if columnExists("ZLINKEDTRANSACTIONID", in: "ZFINANCIALTRANSACTION", db: db) {
            predicates.append("(ZLINKEDTRANSACTIONID IS NOT NULL AND TRIM(CAST(ZLINKEDTRANSACTIONID AS TEXT)) <> '')")
        }
        if columnExists("ZTRANSFERGROUPID", in: "ZFINANCIALTRANSACTION", db: db) {
            predicates.append("(ZTRANSFERGROUPID IS NOT NULL AND TRIM(CAST(ZTRANSFERGROUPID AS TEXT)) <> '')")
        }
        if columnExists("ZTRANSFERSIDE", in: "ZFINANCIALTRANSACTION", db: db) {
            predicates.append("ZTRANSFERSIDE IN ('Incoming', 'Outgoing')")
        }
        return predicates
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
