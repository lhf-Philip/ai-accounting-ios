package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySummaryCard
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTopSection
import org.duckdns.lhfser.aiaccounting.ui.components.PressableCard
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateTimeText
import java.math.BigDecimal
import java.util.UUID

@Composable
fun AccountDetailScreen(
    accountId: String?,
    onEditAccount: (String) -> Unit,
    onEditTransaction: (String) -> Unit,
    onEditTransfer: (String) -> Unit
) {
    val repository = LocalRepository.current
    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val transactions by repository.transactions.collectAsState(initial = emptyList())

    val resolvedId = remember(accountId) { accountId?.let(UUID::fromString) }
    val account = remember(accounts, resolvedId) { accounts.firstOrNull { it.id == resolvedId } }

    if (account == null) {
        Column(modifier = Modifier.padding(horizontal = AppSpacing.screenHorizontal, vertical = AppSpacing.screenVertical)) {
            ParityTopSection(title = "帳戶明細", subtitle = "找不到這個帳戶")
        }
        return
    }

    val accountTransactions = remember(transactions, account.id) {
        transactions
            .filter { it.transaction.accountId == account.id }
            .sortedByDescending { it.transaction.date }
    }
    val balances = remember(account, accountTransactions) { calculateBalances(account, accountTransactions) }

    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(horizontal = AppSpacing.screenHorizontal, vertical = AppSpacing.screenVertical),
        verticalArrangement = Arrangement.spacedBy(AppSpacing.section)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.section)) {
                ParityTopSection(
                    title = account.name,
                    subtitle = buildString {
                        append(account.type.rawValue)
                        append(" · ")
                        append(account.currency)
                        if (account.isArchived) {
                            append(" · 已歸檔")
                        }
                    },
                    accessory = {
                        TextButton(onClick = { onEditAccount(account.id.toString()) }) {
                            Text("編輯")
                        }
                    }
                )
                if (balances.isEmpty()) {
                    ParitySummaryCard(
                        title = "目前餘額",
                        value = BigDecimal.ZERO.asCurrencyText(account.currency),
                        supporting = "尚未有任何交易"
                    )
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)) {
                        balances.forEach { balance ->
                            ParitySummaryCard(
                                title = if (balances.size == 1) "目前餘額" else "${balance.currency} 餘額",
                                value = balance.amount.asCurrencyText(balance.currency),
                                supporting = "含初始餘額與所有已記錄交易",
                                accent = if (balance.amount.signum() >= 0) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error
                            )
                        }
                    }
                }
            }
        }

        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "帳戶明細",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f)
                )
                Text(
                    text = "${accountTransactions.size} 筆",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        if (accountTransactions.isEmpty()) {
            item {
                Text(
                    text = "這個帳戶還沒有任何交易。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        } else {
            items(accountTransactions, key = { it.transaction.id }) { item ->
                AccountTransactionRow(
                    item = item,
                    onClick = {
                        val groupId = item.transaction.transferGroupId?.toString()
                        if (item.transaction.type == TransactionType.Transfer && groupId != null) {
                            onEditTransfer(groupId)
                        } else {
                            onEditTransaction(item.transaction.id.toString())
                        }
                    }
                )
            }
        }
    }
}

@Composable
private fun AccountTransactionRow(
    item: TransactionWithDetails,
    onClick: () -> Unit
) {
    val transaction = item.transaction
    val amountColor = when {
        transaction.amount.signum() > 0 -> MaterialTheme.colorScheme.primary
        transaction.amount.signum() < 0 -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.onSurface
    }
    PressableCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick
    ) {
        Column(
            modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(AppSpacing.tight)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = item.category?.name ?: defaultTransactionTitle(transaction.type),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = transaction.note.ifBlank { "無備註" },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = transaction.amount.asCurrencyText(transaction.currencyCode),
                    style = MaterialTheme.typography.bodyLarge,
                    color = amountColor,
                    fontWeight = FontWeight.SemiBold
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = transaction.date.toDateTimeText(),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = if (transaction.type == TransactionType.Transfer) "編輯轉帳" else "查看 / 編輯",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary
                )
            }
        }
    }
}

private data class AccountCurrencyBalance(
    val currency: String,
    val amount: BigDecimal
)

private fun calculateBalances(
    account: AccountEntity,
    transactions: List<TransactionWithDetails>
): List<AccountCurrencyBalance> {
    val totals = linkedMapOf<String, BigDecimal>()
    if (account.baseBalance != BigDecimal.ZERO) {
        totals[account.currency] = account.baseBalance
    }
    transactions.forEach { tx ->
        val currency = tx.transaction.currencyCode
        totals[currency] = totals.getOrDefault(currency, BigDecimal.ZERO) + tx.transaction.amount
    }
    return totals.entries
        .filter { it.value != BigDecimal.ZERO }
        .sortedBy { it.key }
        .map { AccountCurrencyBalance(it.key, it.value) }
}

private fun defaultTransactionTitle(type: TransactionType): String = when (type) {
    TransactionType.Income -> "收入"
    TransactionType.Expense -> "支出"
    TransactionType.Transfer -> "轉帳"
}
