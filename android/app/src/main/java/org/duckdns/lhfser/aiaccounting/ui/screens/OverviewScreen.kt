package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.BorderStroke
import kotlinx.coroutines.flow.map
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.ui.LocalCurrencyService
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

@Composable
fun OverviewScreen() {
    val repository = LocalRepository.current
    val currencyService = LocalCurrencyService.current
    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val transactions by repository.transactions.collectAsState(initial = emptyList())

    val baseCurrency = currencyService.mainCurrency
    val monthStart = LocalDate.now().withDayOfMonth(1)
        .atStartOfDay(ZoneId.systemDefault())
        .toInstant()

    val summary = rememberSummary(transactions, currencyService, baseCurrency, monthStart)
    val balances = rememberAccountBalances(accounts, transactions)

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.6f))
            ) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("本月重點", style = MaterialTheme.typography.titleMedium)
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                        SummaryTile(label = "收入", value = summary.income.asCurrencyText(baseCurrency), positive = true, modifier = Modifier.weight(1f))
                        SummaryTile(label = "支出", value = summary.expense.asCurrencyText(baseCurrency), positive = false, modifier = Modifier.weight(1f))
                        SummaryTile(label = "結餘", value = summary.net.asCurrencyText(baseCurrency), positive = summary.net >= BigDecimal.ZERO, modifier = Modifier.weight(1f))
                    }
                }
            }
        }

        item {
            Text("帳戶資產", style = MaterialTheme.typography.titleMedium)
            Spacer(modifier = Modifier.padding(4.dp))
        }

        items(balances) { row ->
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.6f))
            ) {
                Row(
                    modifier = Modifier.padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(row.name, style = MaterialTheme.typography.bodyLarge)
                        Text(row.currency, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Text(row.balance.asCurrencyText(row.currency), style = MaterialTheme.typography.titleMedium)
                }
            }
        }
    }
}

@Composable
private fun SummaryTile(
    label: String,
    value: String,
    positive: Boolean,
    modifier: Modifier = Modifier
) {
    val color = if (positive) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.4f))
    ) {
        Column(modifier = Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.titleSmall, color = color)
        }
    }
}

private data class MonthlySummary(
    val income: BigDecimal,
    val expense: BigDecimal,
    val net: BigDecimal
)

private data class AccountBalanceRow(
    val name: String,
    val currency: String,
    val balance: BigDecimal
)

@Composable
private fun rememberSummary(
    transactions: List<TransactionWithDetails>,
    currencyService: org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService,
    baseCurrency: String,
    monthStart: Instant
): MonthlySummary {
    val filtered = transactions.filter { tx ->
        tx.transaction.date >= monthStart &&
            tx.transaction.type != TransactionType.Transfer
    }

    var income = BigDecimal.ZERO
    var expense = BigDecimal.ZERO
    filtered.forEach { tx ->
        val converted = currencyService.convert(tx.transaction.amount.abs(), tx.transaction.currencyCode, baseCurrency)
        when (tx.transaction.type) {
            TransactionType.Income -> income = income + converted
            TransactionType.Expense -> expense = expense + converted
            else -> Unit
        }
    }

    val net = income - expense
    return MonthlySummary(income = income, expense = expense, net = net)
}

@Composable
private fun rememberAccountBalances(
    accounts: List<AccountEntity>,
    transactions: List<TransactionWithDetails>
): List<AccountBalanceRow> {
    val byAccount = transactions.groupBy { it.transaction.accountId }
    return accounts.map { account ->
        val total = byAccount[account.id]?.fold(account.baseBalance) { acc, tx ->
            acc + tx.transaction.amount
        } ?: account.baseBalance
        AccountBalanceRow(
            name = account.name,
            currency = account.currency,
            balance = total
        )
    }
}
