package org.duckdns.lhfser.aiaccounting.core.backup

import org.duckdns.lhfser.aiaccounting.core.model.CategoryKind
import java.math.BigDecimal

data class BackupAccountInput(val isArchived: Boolean?)
data class BackupCategoryInput(val kind: String?)
data class BackupShortcutInput(val currencyCode: String?)
data class BackupBudgetInput(val isEnabled: Boolean?)
data class BackupAdvanceCaseInput(val myShareAmount: BigDecimal?)
data class BackupAdvanceRepaymentInput(val amount: BigDecimal, val normalizedAmount: BigDecimal?)

object BackupDefaults {
    fun accountIsArchived(input: BackupAccountInput): Boolean = input.isArchived ?: false

    fun categoryKind(input: BackupCategoryInput): CategoryKind =
        CategoryKind.fromRawOrDefault(input.kind)

    fun shortcutCurrency(input: BackupShortcutInput, accountCurrency: String?): String {
        return input.currencyCode?.takeIf { it.isNotBlank() }
            ?: accountCurrency?.takeIf { it.isNotBlank() }
            ?: "HKD"
    }

    fun budgetIsEnabled(input: BackupBudgetInput): Boolean = input.isEnabled ?: true

    fun myShareAmount(input: BackupAdvanceCaseInput): BigDecimal =
        input.myShareAmount ?: BigDecimal.ZERO

    fun normalizedAmount(input: BackupAdvanceRepaymentInput): BigDecimal =
        input.normalizedAmount ?: input.amount
}
