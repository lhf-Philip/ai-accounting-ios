package org.duckdns.lhfser.aiaccounting.data.db

import android.content.Context
import androidx.room.RoomDatabase
import androidx.sqlite.db.SupportSQLiteDatabase
import org.duckdns.lhfser.aiaccounting.core.model.CategoryKind
import java.util.UUID

object SeedData {
    fun callback(context: Context): RoomDatabase.Callback {
        return object : RoomDatabase.Callback() {
            override fun onCreate(db: SupportSQLiteDatabase) {
                super.onCreate(db)
                seedDefaults(db)
            }
        }
    }

    private fun seedDefaults(db: SupportSQLiteDatabase) {
        val accountId = UUID.randomUUID().toString()
        db.execSQL(
            """
            INSERT INTO accounts (id, name, currency, type, baseBalance, sortOrder, isArchived)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
            arrayOf(accountId, "現金", "HKD", "Cash", "0", 0, 0)
        )

        insertCategory(db, "餐飲", "fork.knife", "#FF8A65", CategoryKind.Expense)
        insertCategory(db, "交通", "bus", "#4DB6AC", CategoryKind.Expense)
        insertCategory(db, "薪資", "banknote", "#81C784", CategoryKind.Income)
        insertCategory(db, "其他", "square.grid.2x2", "#90A4AE", CategoryKind.Both)
    }

    private fun insertCategory(
        db: SupportSQLiteDatabase,
        name: String,
        icon: String,
        colorHex: String,
        kind: CategoryKind
    ) {
        db.execSQL(
            """
            INSERT INTO categories (id, name, icon, colorHex, kind)
            VALUES (?, ?, ?, ?, ?)
            """.trimIndent(),
            arrayOf(UUID.randomUUID().toString(), name, icon, colorHex, kind.rawValue)
        )
    }
}
