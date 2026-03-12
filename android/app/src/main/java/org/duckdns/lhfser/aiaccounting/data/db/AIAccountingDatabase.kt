package org.duckdns.lhfser.aiaccounting.data.db

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters

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
        AdvanceCaseEntity::class,
        AdvanceParticipantEntity::class,
        AdvanceRepaymentEntity::class
    ],
    version = 1,
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
}
