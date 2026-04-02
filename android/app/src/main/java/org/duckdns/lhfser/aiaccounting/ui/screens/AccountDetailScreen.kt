package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalanceWallet
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
import org.duckdns.lhfser.aiaccounting.ui.components.ParityEmptyState
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySectionHeader
import org.duckdns.lhfser.aiaccounting.ui.components.ParityStatusPill
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySummaryCard
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTopSection
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTokens
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
        Column(
            modifier = Modifier.padding(
                horizontal = AppSpacing.screenHorizontal,
                vertical = AppSpacing.screenVertical
            )
        ) {
            ParityTopSection(title = "帳戶明細", subtitle = "找不到這個帳戶")
            ParityEmptyState(
                title = "找不到帳戶",
                message = "這個帳戶可能已刪除、尚未同步，或目前沒有可顯示的資料。",
                icon = Icons.Default.AccountBalanceWallet
            )
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
        contentPadding = PaddingValues(
            start = AppSpacing.screenHorizontal,
            end = AppSpacing.screenHorizontal,
            top = AppSpacing.screenVertical,
            bottom = AppSpacing.screenVertical + ParityTokens.FloatingContentBottomPadding
        ),
        verticalArrangement = Arrangement.spacedBy(AppSpacing.section)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.section)) {
                ParityTopSection(
                    title = account.name,
                    subtitle = "${account.type.rawValue} · ${account.currency}",
                    accessory = {
                        if (account.isArchived) {
                            ParityStatusPill(
                                text = "已歸檔",
                                tint = MaterialTheme.colorScheme.tertiary
                            )
                        }
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
                                accent = if (balance.amount.signum() >= 0) {
                                    MaterialTheme.colorScheme.primary
                                } else {
                                    MaterialTheme.colorScheme.error
                                }
                            )
                        }
                    }
                }
            }
        }

        item {
            ParitySectionHeader(
                title = "交易紀錄",
                detail = "${accountTransactions.size} 筆 · 點擊即可查看或編輯"
            )
        }

        if (accountTransactions.isEmpty()) {
            item {
                ParityEmptyState(
                    title = "還沒有交易",
                    message = "這個帳戶目前只有初始資料，還沒有新增任何收入、支出或轉帳。",
                    icon = Icons.Default.AccountBalanceWallet
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
    val categoryText = item.category?.name ?: defaultTransactionTitle(transaction.type)
    val metaText = listOfNotNull(categoryText, item.account?.name)
        .distinct()
        .joinToString(" · ")
        .ifBlank { "未分類" }

    PressableCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick,
        containerColor = MaterialTheme.colorScheme.surface,
        pressedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
        borderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.35f),
        pressedBorderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.48f)
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
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = transaction.note.ifBlank { categoryText },
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = metaText,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = transaction.date.toDateTimeText(),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Column(
                    horizontalAlignment = Alignment.End,
                    verticalArrangement = Arrangement.spacedBy(3.dp)
                ) {
                    Text(
                        text = transaction.amount.asCurrencyText(transaction.currencyCode),
                        style = MaterialTheme.typography.titleSmall,
                        color = amountColor,
                        fontWeight = FontWeight.SemiBold
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
