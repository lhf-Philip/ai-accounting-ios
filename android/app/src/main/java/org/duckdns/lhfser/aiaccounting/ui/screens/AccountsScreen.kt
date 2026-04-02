package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.BorderStroke
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.ui.LocalCurrencyService
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.ParityEmptyState
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySectionHeader
import org.duckdns.lhfser.aiaccounting.ui.components.ParityStatusPill
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySummaryCard
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTopSection
import org.duckdns.lhfser.aiaccounting.ui.components.PressableCard
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import java.math.BigDecimal

@Composable
fun AccountsScreen(
    onOpenDetail: (String) -> Unit,
    onAddAccount: () -> Unit
) {
    val repository = LocalRepository.current
    val currencyService = LocalCurrencyService.current
    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val transactions by repository.transactions.collectAsState(initial = emptyList())
    val rateSnapshot = currencyService.rates
    val mainCurrency = currencyService.mainCurrency
    var showArchived by rememberSaveable { mutableStateOf(false) }

    val accountSummaries = remember(accounts, transactions) {
        calculateBalances(accounts, transactions)
    }
    val activeSummaries = remember(accountSummaries) {
        accountSummaries.filter { !it.account.isArchived }
    }
    val visibleSummaries = remember(accountSummaries, showArchived) {
        if (showArchived) accountSummaries else activeSummaries
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
        modifier = Modifier.fillMaxWidth(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(
            horizontal = AppSpacing.screenHorizontal,
            vertical = AppSpacing.screenVertical
        ),
        verticalArrangement = Arrangement.spacedBy(AppSpacing.section)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.section)) {
                ParityTopSection(
                    title = "帳戶",
                    subtitle = if (showArchived) {
                        "目前顯示所有帳戶，包含已歸檔項目。"
                    } else {
                        "總資產與幣別持有只計入未歸檔帳戶。"
                    },
                    accessory = {
                        TextButton(onClick = { showArchived = !showArchived }) {
                            Text(if (showArchived) "隱藏歸檔" else "顯示歸檔")
                        }
                        TextButton(onClick = onAddAccount) {
                            Text("新增")
                        }
                    }
                )

                if (!showArchived) {
                    ParitySummaryCard(
                        title = "總資產估算 ($mainCurrency)",
                        value = totalEstimatedAssets.asCurrencyText(mainCurrency),
                        supporting = "根據目前主幣別與匯率換算"
                    )

                    Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)) {
                        ParitySectionHeader(
                            title = "各幣種持有總額",
                            detail = if (currencyHoldings.isEmpty()) null else "${currencyHoldings.size} 種幣別"
                        )
                        if (currencyHoldings.isEmpty()) {
                            ParityEmptyState(
                                title = "暫時沒有持有總額",
                                message = "活動帳戶目前沒有可計算的餘額。",
                                icon = Icons.Default.AccountBalanceWallet
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
                                        modifier = Modifier.width(168.dp),
                                        shape = MaterialTheme.shapes.large,
                                        color = MaterialTheme.colorScheme.surfaceVariant,
                                        border = BorderStroke(
                                            0.6.dp,
                                            MaterialTheme.colorScheme.outline.copy(alpha = 0.35f)
                                        )
                                    ) {
                                        Column(
                                            modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 14.dp),
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
        }

        if (visibleSummaries.isEmpty()) {
            item {
                ParityEmptyState(
                    title = if (showArchived) "沒有已歸檔帳戶" else "尚未建立帳戶",
                    message = if (showArchived) {
                        "切回活動帳戶，或先把現有帳戶歸檔後再回來查看。"
                    } else {
                        "先新增一個帳戶，之後就能記錄資產、轉帳與日常交易。"
                    },
                    icon = Icons.Default.AccountBalanceWallet
                )
            }
        } else {
            items(visibleSummaries, key = { it.account.id }) { row ->
                PressableCard(
                    modifier = Modifier.fillMaxWidth(),
                    onClick = { onOpenDetail(row.account.id.toString()) },
                    containerColor = MaterialTheme.colorScheme.surface,
                    pressedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                    borderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.35f),
                    pressedBorderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.48f)
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 15.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(5.dp)
                        ) {
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    row.account.name,
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.SemiBold
                                )
                                if (row.account.isArchived) {
                                    ParityStatusPill(
                                        text = "已歸檔",
                                        tint = MaterialTheme.colorScheme.tertiary
                                    )
                                }
                            }
                            Text(
                                "${row.account.type.rawValue} · ${row.account.currency}",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        Column(
                            horizontalAlignment = Alignment.End,
                            verticalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            when {
                                row.balances.isEmpty() -> {
                                    Text(
                                        BigDecimal.ZERO.asCurrencyText(row.account.currency),
                                        style = MaterialTheme.typography.titleSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                row.balances.size == 1 -> {
                                    val balance = row.balances.first()
                                    Text(
                                        balance.amount.asCurrencyText(balance.currency),
                                        style = MaterialTheme.typography.titleSmall,
                                        fontWeight = FontWeight.SemiBold,
                                        color = if (balance.amount.signum() >= 0) {
                                            MaterialTheme.colorScheme.onSurface
                                        } else {
                                            MaterialTheme.colorScheme.error
                                        }
                                    )
                                }
                                else -> {
                                    Column(
                                        horizontalAlignment = Alignment.End,
                                        verticalArrangement = Arrangement.spacedBy(2.dp)
                                    ) {
                                        row.balances.take(2).forEach { balance ->
                                            Text(
                                                balance.amount.asCurrencyText(balance.currency),
                                                style = MaterialTheme.typography.bodyMedium,
                                                fontWeight = FontWeight.SemiBold,
                                                color = if (balance.amount.signum() >= 0) {
                                                    MaterialTheme.colorScheme.onSurface
                                                } else {
                                                    MaterialTheme.colorScheme.error
                                                }
                                            )
                                        }
                                        if (row.balances.size > 2) {
                                            Text(
                                                "共 ${row.balances.size} 種幣別",
                                                style = MaterialTheme.typography.labelSmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        }
                                    }
                                }
                            }
                            Text(
                                "查看明細",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.primary,
                                fontWeight = FontWeight.Medium
                            )
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
