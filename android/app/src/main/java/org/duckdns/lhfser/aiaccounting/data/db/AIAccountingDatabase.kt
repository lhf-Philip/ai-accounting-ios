package org.duckdns.lhfser.aiaccounting.data.db

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [
        AccountEntity::class,
        CategoryEntity::class,
        TagEntity::class,
        TransactionEntity::class,
        TransactionTagCrossRef::class,
        ShortcutEntity::class,
        ShortcutTagCrossRef::class,
        CategoryMonthlyBudgetEntity::class,
        BudgetMonthlyHistoryEntity::class,
        AdvanceCaseEntity::class,
        AdvanceParticipantEntity::class,
        AdvanceRepaymentEntity::class
    ],
    version = 2,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class AIAccountingDatabase : RoomDatabase() {
    abstract fun accountDao(): AccountDao
    abstract fun categoryDao(): CategoryDao
    abstract fun tagDao(): TagDao
    abstract fun transactionDao(): TransactionDao
    abstract fun shortcutDao(): ShortcutDao
    abstract fun budgetDao(): BudgetDao
    abstract fun advanceDao(): AdvanceDao

    companion object {
        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `budget_monthly_history` (
                        `id` TEXT NOT NULL,
                        `historyKey` TEXT NOT NULL,
                        `monthKey` TEXT NOT NULL,
                        `categoryId` TEXT NOT NULL,
                        `categoryNameSnapshot` TEXT NOT NULL,
                        `budgetAmount` TEXT NOT NULL,
                        `spentAmount` TEXT NOT NULL,
                        `remainingAmount` TEXT NOT NULL,
                        `usageRatio` TEXT NOT NULL,
                        `isOverBudget` INTEGER NOT NULL,
                        `currencyCode` TEXT NOT NULL,
                        `updatedAt` INTEGER NOT NULL,
                        PRIMARY KEY(`id`)
                    )
                    """.trimIndent()
                )
                database.execSQL("CREATE INDEX IF NOT EXISTS `index_budget_monthly_history_monthKey` ON `budget_monthly_history` (`monthKey`)")
                database.execSQL("CREATE INDEX IF NOT EXISTS `index_budget_monthly_history_categoryId` ON `budget_monthly_history` (`categoryId`)")
                database.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_budget_monthly_history_historyKey` ON `budget_monthly_history` (`historyKey`)")
            }
        }
    }
}
