package org.duckdns.lhfser.aiaccounting.data.db

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import kotlinx.coroutines.flow.Flow
import java.util.UUID

@Dao
interface AccountDao {
    @Query("SELECT * FROM accounts ORDER BY sortOrder ASC")
    fun observeAccounts(): Flow<List<AccountEntity>>

    @Query("SELECT * FROM accounts WHERE id = :accountId")
    suspend fun getAccount(accountId: UUID): AccountEntity?

    @Query("SELECT * FROM accounts")
    suspend fun getAll(): List<AccountEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(account: AccountEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(accounts: List<AccountEntity>)

    @Delete
    suspend fun delete(account: AccountEntity)

    @Query("DELETE FROM accounts")
    suspend fun deleteAll()
}

@Dao
interface CategoryDao {
    @Query("SELECT * FROM categories ORDER BY name ASC")
    fun observeCategories(): Flow<List<CategoryEntity>>

    @Query("SELECT * FROM categories")
    suspend fun getAll(): List<CategoryEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(category: CategoryEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(categories: List<CategoryEntity>)

    @Delete
    suspend fun delete(category: CategoryEntity)

    @Query("DELETE FROM categories")
    suspend fun deleteAll()
}

@Dao
interface TagDao {
    @Query("SELECT * FROM tags ORDER BY name ASC")
    fun observeTags(): Flow<List<TagEntity>>

    @Query("SELECT * FROM tags")
    suspend fun getAll(): List<TagEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(tag: TagEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(tags: List<TagEntity>)

    @Delete
    suspend fun delete(tag: TagEntity)

    @Query("DELETE FROM tags")
    suspend fun deleteAll()
}

@Dao
interface TransactionDao {
    @Transaction
    @Query("SELECT * FROM transactions ORDER BY date DESC, createdAt DESC")
    fun observeTransactions(): Flow<List<TransactionWithDetails>>

    @Transaction
    @Query("SELECT * FROM transactions WHERE id = :transactionId")
    suspend fun getTransaction(transactionId: UUID): TransactionWithDetails?

    @Transaction
    @Query("SELECT * FROM transactions ORDER BY date DESC, createdAt DESC")
    suspend fun getAllWithDetails(): List<TransactionWithDetails>

    @Transaction
    @Query("SELECT * FROM transactions WHERE transferGroupId = :groupId ORDER BY date DESC")
    suspend fun getTransferGroup(groupId: UUID): List<TransactionWithDetails>

    @Query("SELECT * FROM transactions")
    suspend fun getAll(): List<TransactionEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(transaction: TransactionEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(transactions: List<TransactionEntity>)

    @Delete
    suspend fun delete(transaction: TransactionEntity)

    @Query("DELETE FROM transaction_tag_cross_ref WHERE transactionId = :transactionId")
    suspend fun clearTransactionTags(transactionId: UUID)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertTransactionTags(tags: List<TransactionTagCrossRef>)

    @Query("SELECT * FROM transaction_tag_cross_ref")
    suspend fun getTransactionTags(): List<TransactionTagCrossRef>

    @Query("DELETE FROM transactions")
    suspend fun deleteAllTransactions()

    @Query("DELETE FROM transaction_tag_cross_ref")
    suspend fun deleteAllTransactionTags()
}

@Dao
interface ShortcutDao {
    @Transaction
    @Query("SELECT * FROM shortcuts ORDER BY name ASC")
    fun observeShortcuts(): Flow<List<ShortcutWithDetails>>

    @Query("SELECT * FROM shortcuts")
    suspend fun getAll(): List<ShortcutEntity>

    @Transaction
    @Query("SELECT * FROM shortcuts ORDER BY name ASC")
    suspend fun getAllWithDetails(): List<ShortcutWithDetails>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(shortcut: ShortcutEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(shortcuts: List<ShortcutEntity>)

    @Delete
    suspend fun delete(shortcut: ShortcutEntity)

    @Query("DELETE FROM shortcut_tag_cross_ref WHERE shortcutId = :shortcutId")
    suspend fun clearShortcutTags(shortcutId: UUID)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertShortcutTags(tags: List<ShortcutTagCrossRef>)

    @Query("SELECT * FROM shortcut_tag_cross_ref")
    suspend fun getShortcutTags(): List<ShortcutTagCrossRef>

    @Query("DELETE FROM shortcuts")
    suspend fun deleteAllShortcuts()

    @Query("DELETE FROM shortcut_tag_cross_ref")
    suspend fun deleteAllShortcutTags()
}

@Dao
interface BudgetDao {
    @Query("SELECT * FROM category_monthly_budgets ORDER BY monthKey DESC")
    fun observeBudgets(): Flow<List<CategoryMonthlyBudgetEntity>>

    @Query("SELECT * FROM budget_monthly_history ORDER BY monthKey DESC, categoryNameSnapshot ASC")
    fun observeBudgetHistory(): Flow<List<BudgetMonthlyHistoryEntity>>

    @Query("SELECT * FROM category_monthly_budgets")
    suspend fun getAll(): List<CategoryMonthlyBudgetEntity>

    @Query("SELECT * FROM budget_monthly_history")
    suspend fun getAllHistory(): List<BudgetMonthlyHistoryEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(budget: CategoryMonthlyBudgetEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(budgets: List<CategoryMonthlyBudgetEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertHistory(history: BudgetMonthlyHistoryEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAllHistory(history: List<BudgetMonthlyHistoryEntity>)

    @Delete
    suspend fun delete(budget: CategoryMonthlyBudgetEntity)

    @Delete
    suspend fun deleteHistory(history: BudgetMonthlyHistoryEntity)

    @Query("DELETE FROM category_monthly_budgets")
    suspend fun deleteAll()

    @Query("DELETE FROM budget_monthly_history")
    suspend fun deleteAllHistory()
}

@Dao
interface AdvanceDao {
    @Transaction
    @Query("SELECT * FROM advance_cases ORDER BY date DESC, createdAt DESC")
    fun observeAdvanceCases(): Flow<List<AdvanceCaseWithDetails>>

    @Transaction
    @Query("SELECT * FROM advance_cases WHERE id = :caseId")
    suspend fun getAdvanceCase(caseId: UUID): AdvanceCaseWithDetails?

    @Transaction
    @Query("SELECT * FROM advance_cases")
    suspend fun getAllCasesWithDetails(): List<AdvanceCaseWithDetails>

    @Query("SELECT * FROM advance_cases")
    suspend fun getAllCases(): List<AdvanceCaseEntity>

    @Query("SELECT * FROM advance_participants")
    suspend fun getAllParticipants(): List<AdvanceParticipantEntity>

    @Query("SELECT * FROM advance_repayments")
    suspend fun getAllRepayments(): List<AdvanceRepaymentEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertCase(advanceCase: AdvanceCaseEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertParticipants(participants: List<AdvanceParticipantEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertRepayment(repayment: AdvanceRepaymentEntity)

    @Delete
    suspend fun deleteCase(advanceCase: AdvanceCaseEntity)

    @Delete
    suspend fun deleteParticipant(participant: AdvanceParticipantEntity)

    @Delete
    suspend fun deleteRepayment(repayment: AdvanceRepaymentEntity)

    @Query("DELETE FROM advance_repayments")
    suspend fun deleteAllRepayments()

    @Query("DELETE FROM advance_participants")
    suspend fun deleteAllParticipants()

    @Query("DELETE FROM advance_cases")
    suspend fun deleteAllCases()
}
