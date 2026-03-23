package org.duckdns.lhfser.aiaccounting.data.db

import androidx.room.Embedded
import androidx.room.Junction
import androidx.room.Relation

data class TransactionWithDetails(
    @Embedded val transaction: TransactionEntity,
    @Relation(
        parentColumn = "accountId",
        entityColumn = "id"
    )
    val account: AccountEntity?,
    @Relation(
        parentColumn = "categoryId",
        entityColumn = "id"
    )
    val category: CategoryEntity?,
    @Relation(
        parentColumn = "id",
        entityColumn = "id",
        associateBy = Junction(
            value = TransactionTagCrossRef::class,
            parentColumn = "transactionId",
            entityColumn = "tagId"
        )
    )
    val tags: List<TagEntity>
)

data class ShortcutWithDetails(
    @Embedded val shortcut: ShortcutEntity,
    @Relation(
        parentColumn = "accountId",
        entityColumn = "id"
    )
    val account: AccountEntity?,
    @Relation(
        parentColumn = "categoryId",
        entityColumn = "id"
    )
    val category: CategoryEntity?,
    @Relation(
        parentColumn = "id",
        entityColumn = "id",
        associateBy = Junction(
            value = ShortcutTagCrossRef::class,
            parentColumn = "shortcutId",
            entityColumn = "tagId"
        )
    )
    val tags: List<TagEntity>
)

data class AdvanceCaseWithDetails(
    @Embedded val advanceCase: AdvanceCaseEntity,
    @Relation(
        parentColumn = "payerAccountId",
        entityColumn = "id"
    )
    val payerAccount: AccountEntity?,
    @Relation(
        parentColumn = "expenseCategoryId",
        entityColumn = "id"
    )
    val expenseCategory: CategoryEntity?,
    @Relation(
        parentColumn = "id",
        entityColumn = "advanceCaseId"
    )
    val participants: List<AdvanceParticipantEntity>,
    @Relation(
        parentColumn = "id",
        entityColumn = "advanceCaseId"
    )
    val repayments: List<AdvanceRepaymentEntity>
)
