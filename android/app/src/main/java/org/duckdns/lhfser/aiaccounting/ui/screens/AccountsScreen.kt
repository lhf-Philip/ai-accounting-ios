package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.PressableCard
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
import java.math.BigDecimal

@Composable
fun AccountsScreen(onEdit: (String) -> Unit) {
    val repository = LocalRepository.current
    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val transactions by repository.transactions.collectAsState(initial = emptyList())

    val balances = calculateBalances(accounts, transactions)

    LazyColumn(
        modifier = Modifier.padding(horizontal = AppSpacing.screenHorizontal, vertical = AppSpacing.screenVertical),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        items(balances) { row ->
            PressableCard(
                modifier = Modifier.fillMaxWidth(),
                onClick = { onEdit(row.account.id.toString()) }
            ) {
                Row(
                    modifier = Modifier.padding(AppSpacing.card),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(row.account.name, style = MaterialTheme.typography.bodyLarge)
                            if (row.account.isArchived) {
                                Text("已歸檔", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        Text(
                            "${row.account.type.rawValue} · ${row.account.currency}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        Text(row.balance.asCurrencyText(row.account.currency), style = MaterialTheme.typography.titleMedium)
                    }
                }
            }
        }
    }
}

private data class AccountBalance(
    val account: AccountEntity,
    val balance: BigDecimal
)

private fun calculateBalances(
    accounts: List<AccountEntity>,
    transactions: List<TransactionWithDetails>
): List<AccountBalance> {
    val grouped = transactions.groupBy { it.transaction.accountId }
    return accounts.map { account ->
        val total = grouped[account.id]?.fold(account.baseBalance) { acc, tx ->
            acc + tx.transaction.amount
        } ?: account.baseBalance
        AccountBalance(account, total)
    }
}
