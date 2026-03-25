package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.shape.RoundedCornerShape
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.ui.LocalCurrencyService
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.PressableCard
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
import java.math.BigDecimal

@Composable
fun AccountsScreen(onEdit: (String) -> Unit) {
    val repository = LocalRepository.current
    val currencyService = LocalCurrencyService.current
    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val transactions by repository.transactions.collectAsState(initial = emptyList())
    val rateSnapshot = currencyService.rates
    val mainCurrency = currencyService.mainCurrency

    val accountSummaries = remember(accounts, transactions) {
        calculateBalances(accounts, transactions)
    }
    val activeSummaries = remember(accountSummaries) {
        accountSummaries.filter { !it.account.isArchived }
    }
    val totalEstimatedAssets = remember(activeSummaries, mainCurrency, rateSnapshot) {
        activeSummaries.fold(BigDecimal.ZERO) { accountTotal, summary ->
            accountTotal + summary.balances.fold(BigDecimal.ZERO) { balanceTotal, balance ->
                balanceTotal + currencyService.convert(balance.amount, balance.currency, mainCurrency)
            }
        }
    }
    val currencyHoldings = remember(activeSummaries) {
        calculateCurrencyHoldings(activeSummaries)
    }

    LazyColumn(
        modifier = Modifier.padding(horizontal = AppSpacing.screenHorizontal, vertical = AppSpacing.screenVertical),
        verticalArrangement = Arrangement.spacedBy(AppSpacing.section)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.section)) {
                SectionCard {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            "總資產估算 ($mainCurrency)",
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Text(
                            totalEstimatedAssets.asCurrencyText(mainCurrency),
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            "根據目前主幣別與匯率換算",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)) {
                    Text(
                        "各幣種持有總額",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    if (currencyHoldings.isEmpty()) {
                        Text(
                            "目前沒有活動帳戶餘額",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    } else {
                        Row(
                            modifier = Modifier
                                .horizontalScroll(rememberScrollState())
                                .padding(horizontal = 2.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            currencyHoldings.forEach { holding ->
                                Surface(
                                    modifier = Modifier.width(152.dp),
                                    shape = RoundedCornerShape(16.dp),
                                    color = MaterialTheme.colorScheme.surfaceVariant,
                                    border = BorderStroke(0.6.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.35f))
                                ) {
                                    Column(
                                        modifier = Modifier.padding(AppSpacing.card),
                                        verticalArrangement = Arrangement.spacedBy(6.dp)
                                    ) {
                                        Text(
                                            holding.currency,
                                            style = MaterialTheme.typography.labelMedium,
                                            fontWeight = FontWeight.Bold,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                        Text(
                                            holding.amount.asCurrencyText(holding.currency),
                                            style = MaterialTheme.typography.titleSmall,
                                            fontWeight = FontWeight.SemiBold,
                                            color = if (holding.amount.signum() >= 0) {
                                                MaterialTheme.colorScheme.onSurface
                                            } else {
                                                MaterialTheme.colorScheme.error
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        items(accountSummaries) { row ->
            PressableCard(
                modifier = Modifier.fillMaxWidth(),
                onClick = { onEdit(row.account.id.toString()) }
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(row.account.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                            if (row.account.isArchived) {
                                Text(
                                    "已歸檔",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                        Text(
                            "${row.account.type.rawValue} · ${row.account.currency}",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        if (row.balances.isEmpty()) {
                            Text("0.00", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        } else if (row.balances.size == 1) {
                            val balance = row.balances.first()
                            Text(
                                balance.amount.asCurrencyText(balance.currency),
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                                color = if (balance.amount.signum() >= 0) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.error
                            )
                        } else {
                            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                row.balances.take(2).forEach { balance ->
                                    Text(
                                        balance.amount.asCurrencyText(balance.currency),
                                        style = MaterialTheme.typography.bodyMedium,
                                        fontWeight = FontWeight.SemiBold,
                                        color = if (balance.amount.signum() >= 0) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.error
                                    )
                                }
                                if (row.balances.size > 2) {
                                    Text(
                                        "...",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private data class CurrencyBalance(
    val currency: String,
    val amount: BigDecimal
)

private data class AccountBalance(
    val account: AccountEntity,
    val balances: List<CurrencyBalance>
)

private data class CurrencyHoldingSummary(
    val currency: String,
    val amount: BigDecimal
)

private fun calculateBalances(
    accounts: List<AccountEntity>,
    transactions: List<TransactionWithDetails>
): List<AccountBalance> {
    val grouped = transactions.groupBy { it.transaction.accountId }
    return accounts.map { account ->
        val totals = linkedMapOf<String, BigDecimal>()
        if (account.baseBalance != BigDecimal.ZERO) {
            totals[account.currency] = account.baseBalance
        }
        grouped[account.id]?.forEach { tx ->
            val currency = tx.transaction.currencyCode
            totals[currency] = totals.getOrDefault(currency, BigDecimal.ZERO) + tx.transaction.amount
        }

        val balances = totals.entries
            .filter { it.value != BigDecimal.ZERO }
            .sortedBy { it.key }
            .map { CurrencyBalance(currency = it.key, amount = it.value) }

        AccountBalance(account = account, balances = balances)
    }
}

private fun calculateCurrencyHoldings(summaries: List<AccountBalance>): List<CurrencyHoldingSummary> {
    val totals = linkedMapOf<String, BigDecimal>()
    summaries.forEach { summary ->
        summary.balances.forEach { balance ->
            totals[balance.currency] = totals.getOrDefault(balance.currency, BigDecimal.ZERO) + balance.amount
        }
    }
    return totals.entries
        .filter { it.value != BigDecimal.ZERO }
        .sortedBy { it.key }
        .map { CurrencyHoldingSummary(currency = it.key, amount = it.value) }
}
