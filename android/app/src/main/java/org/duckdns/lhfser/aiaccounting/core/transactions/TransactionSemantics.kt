package org.duckdns.lhfser.aiaccounting.core.transactions

import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.ShortcutWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import java.math.BigDecimal

enum class DebtForgivenessDirection(val label: String, val detail: String, val amountSign: BigDecimal) {
    ForgivenByOthers(
        label = "別人免除我欠的",
        detail = "這會減少你對對方的負債，不計入收入。",
        amountSign = BigDecimal.ONE
    ),
    ForgiveOthers(
        label = "我免除別人欠我的",
        detail = "這會減少對方欠你的金額，不計入收入。",
        amountSign = BigDecimal.ONE.negate()
    )
}

enum class RateSourceState(val label: String) {
    Live("即時匯率"),
    Cached("上次匯率"),
    Unavailable("暫無匯率")
}

object TransactionSemantics {
    const val DEBT_FORGIVENESS_MARKER = "[免除債務]"
    const val ASSET_ADJUSTMENT_MARKER = "[資產調整]"

    fun ownAccounts(accounts: List<AccountEntity>): List<AccountEntity> {
        return accounts.filter { it.type != AccountType.Debt && !it.isArchived }
    }

    fun debtAccounts(accounts: List<AccountEntity>): List<AccountEntity> {
        return accounts.filter { it.type == AccountType.Debt && !it.isArchived }
    }

    fun allowedAccounts(type: TransactionType, accounts: List<AccountEntity>): List<AccountEntity> {
        return when (type) {
            TransactionType.Income, TransactionType.Expense -> ownAccounts(accounts)
            TransactionType.Transfer -> accounts.filter { !it.isArchived }
        }
    }

    fun isDebtForgiveness(note: String): Boolean {
        return note.trim().startsWith(DEBT_FORGIVENESS_MARKER)
    }

    fun debtForgivenessDirection(note: String): DebtForgivenessDirection? {
        if (!isDebtForgiveness(note)) return null
        return when {
            note.contains("對方免除") -> DebtForgivenessDirection.ForgivenByOthers
            note.contains("我方免除") -> DebtForgivenessDirection.ForgiveOthers
            else -> null
        }
    }

    fun debtForgivenessNote(baseNote: String, debtAccountName: String, direction: DebtForgivenessDirection): String {
        val trimmed = baseNote.trim()
        val suffix = when (direction) {
            DebtForgivenessDirection.ForgivenByOthers -> "(對方免除：$debtAccountName)"
            DebtForgivenessDirection.ForgiveOthers -> "(我方免除：$debtAccountName)"
        }
        return if (trimmed.isBlank()) {
            "$DEBT_FORGIVENESS_MARKER $suffix"
        } else {
            "$DEBT_FORGIVENESS_MARKER $trimmed $suffix"
        }
    }

    fun debtForgivenessDisplayTitle(note: String): String {
        val trimmed = note.trim()
        if (!isDebtForgiveness(trimmed)) return trimmed
        val withoutMarker = trimmed.removePrefix(DEBT_FORGIVENESS_MARKER).trim()
        return withoutMarker.ifBlank { "免除債務" }
    }

    fun isLegacyDebtIncome(transaction: TransactionWithDetails): Boolean {
        return transaction.transaction.type == TransactionType.Income && transaction.account?.type == AccountType.Debt
    }

    fun isLegacyDebtIncome(shortcut: ShortcutWithDetails): Boolean {
        return shortcut.shortcut.type == TransactionType.Income && shortcut.account?.type == AccountType.Debt
    }
}
