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
        RecurringRuleEntity::class,
        RecurringRuleTagCrossRef::class,
        RecurringOccurrenceEntity::class,
        CategoryMonthlyBudgetEntity::class,
        BudgetMonthlyHistoryEntity::class,
        BudgetSettingsEntity::class,
        AdvanceCaseEntity::class,
        AdvanceCaseTagCrossRef::class,
        AdvanceParticipantEntity::class,
        AdvanceRepaymentEntity::class
    ],
    version = 6,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class AIAccountingDatabase : RoomDatabase() {
    abstract fun accountDao(): AccountDao
    abstract fun categoryDao(): CategoryDao
    abstract fun tagDao(): TagDao
    abstract fun transactionDao(): TransactionDao
    abstract fun shortcutDao(): ShortcutDao
    abstract fun recurringDao(): RecurringDao
    abstract fun budgetDao(): BudgetDao
    abstract fun advanceDao(): AdvanceDao

    companion object {
        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
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
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_budget_monthly_history_monthKey` ON `budget_monthly_history` (`monthKey`)")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_budget_monthly_history_categoryId` ON `budget_monthly_history` (`categoryId`)")
                db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_budget_monthly_history_historyKey` ON `budget_monthly_history` (`historyKey`)")
            }
        }

        val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `budget_settings` (
                        `id` TEXT NOT NULL,
                        `carryOverMode` TEXT NOT NULL,
                        `alertThresholdPercent` TEXT NOT NULL,
                        `forecastMode` TEXT NOT NULL,
                        `updatedAt` INTEGER NOT NULL,
                        PRIMARY KEY(`id`)
                    )
                    """.trimIndent()
                )
            }
        }

        val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `recurring_rules` (
                        `id` TEXT NOT NULL,
                        `title` TEXT NOT NULL,
                        `amount` TEXT NOT NULL,
                        `currencyCode` TEXT NOT NULL,
                        `type` TEXT NOT NULL,
                        `note` TEXT NOT NULL,
                        `frequency` TEXT NOT NULL,
                        `intervalCount` INTEGER NOT NULL,
                        `nextDueDate` INTEGER NOT NULL,
                        `isPaused` INTEGER NOT NULL,
                        `createdAt` INTEGER NOT NULL,
                        `updatedAt` INTEGER NOT NULL,
                        `accountId` TEXT,
                        `categoryId` TEXT,
                        PRIMARY KEY(`id`)
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_recurring_rules_accountId` ON `recurring_rules` (`accountId`)")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_recurring_rules_categoryId` ON `recurring_rules` (`categoryId`)")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_recurring_rules_nextDueDate` ON `recurring_rules` (`nextDueDate`)")
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `recurring_occurrences` (
                        `id` TEXT NOT NULL,
                        `dueDate` INTEGER NOT NULL,
                        `status` TEXT NOT NULL,
                        `createdTransactionId` TEXT,
                        `createdAt` INTEGER NOT NULL,
                        `updatedAt` INTEGER NOT NULL,
                        `ruleId` TEXT,
                        PRIMARY KEY(`id`)
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_recurring_occurrences_ruleId` ON `recurring_occurrences` (`ruleId`)")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_recurring_occurrences_dueDate` ON `recurring_occurrences` (`dueDate`)")
                db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_recurring_occurrences_ruleId_dueDate` ON `recurring_occurrences` (`ruleId`, `dueDate`)")
            }
        }

        val MIGRATION_4_5 = object : Migration(4, 5) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `recurring_rule_tag_cross_ref` (
                        `ruleId` TEXT NOT NULL,
                        `tagId` TEXT NOT NULL,
                        PRIMARY KEY(`ruleId`, `tagId`)
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_recurring_rule_tag_cross_ref_tagId` ON `recurring_rule_tag_cross_ref` (`tagId`)")
            }
        }

        val MIGRATION_5_6 = object : Migration(5, 6) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE `transactions` ADD COLUMN `advanceCaseId` TEXT")
                db.execSQL("ALTER TABLE `transactions` ADD COLUMN `advanceParticipantId` TEXT")
                db.execSQL("ALTER TABLE `transactions` ADD COLUMN `advanceRepaymentId` TEXT")
                db.execSQL("ALTER TABLE `transactions` ADD COLUMN `advanceEntryRole` TEXT")
                db.execSQL("ALTER TABLE `advance_cases` ADD COLUMN `direction` TEXT")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_transactions_advanceCaseId` ON `transactions` (`advanceCaseId`)")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_transactions_advanceParticipantId` ON `transactions` (`advanceParticipantId`)")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_transactions_advanceRepaymentId` ON `transactions` (`advanceRepaymentId`)")
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `advance_case_tag_cross_ref` (
                        `advanceCaseId` TEXT NOT NULL,
                        `tagId` TEXT NOT NULL,
                        PRIMARY KEY(`advanceCaseId`, `tagId`)
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_advance_case_tag_cross_ref_tagId` ON `advance_case_tag_cross_ref` (`tagId`)")
            }
        }
    }
}
