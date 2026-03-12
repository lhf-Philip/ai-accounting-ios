package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.ui.LocalCurrencyService
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateText
import java.math.BigDecimal

@Composable
fun ReportsScreen() {
    val repository = LocalRepository.current
    val currencyService = LocalCurrencyService.current
    val transactions by repository.transactions.collectAsState(initial = emptyList())
    val categories by repository.categories.collectAsState(initial = emptyList())

    var selectedCategory by remember { mutableStateOf<CategoryEntity?>(null) }
    var selectedType by remember { mutableStateOf(TransactionType.Expense) }

    val baseCurrency = currencyService.mainCurrency
    val expenseBreakdown = categoryBreakdown(transactions, categories, currencyService, baseCurrency, TransactionType.Expense)
    val incomeBreakdown = categoryBreakdown(transactions, categories, currencyService, baseCurrency, TransactionType.Income)

    LazyColumn(
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item { Text("支出分類", style = MaterialTheme.typography.titleMedium) }
        items(expenseBreakdown) { row ->
            CategoryBreakdownRow(row) {
                selectedCategory = row.category
                selectedType = TransactionType.Expense
            }
        }
        item { Text("收入分類", style = MaterialTheme.typography.titleMedium) }
        items(incomeBreakdown) { row ->
            CategoryBreakdownRow(row) {
                selectedCategory = row.category
                selectedType = TransactionType.Income
            }
        }
    }

    if (selectedCategory != null) {
        val detail = selectedCategory ?: return
        val detailTransactions = transactions.filter { tx ->
            tx.category?.id == detail.id && tx.transaction.type == selectedType
        }
        AlertDialog(
            onDismissRequest = { selectedCategory = null },
            title = { Text("${detail.name} 明細") },
            text = {
                if (detailTransactions.isEmpty()) {
                    Text("沒有相關交易。")
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        detailTransactions.take(20).forEach { tx ->
                            Text("${tx.transaction.date.toDateText()} · ${tx.transaction.amount.asCurrencyText(tx.transaction.currencyCode)}")
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { selectedCategory = null }) { Text("關閉") }
            }
        )
    }
}

private data class CategoryBreakdownRow(
    val category: CategoryEntity,
    val total: BigDecimal,
    val currency: String
)

@Composable
private fun CategoryBreakdownRow(row: CategoryBreakdownRow, onClick: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(row.category.name, style = MaterialTheme.typography.bodyLarge)
            Text(row.total.asCurrencyText(row.currency))
        }
    }
}

private fun categoryBreakdown(
    transactions: List<TransactionWithDetails>,
    categories: List<CategoryEntity>,
    currencyService: org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService,
    baseCurrency: String,
    type: TransactionType
): List<CategoryBreakdownRow> {
    val filtered = transactions.filter { it.transaction.type == type }
    val grouped = filtered.groupBy { it.category?.id }
    return grouped.mapNotNull { (categoryId, items) ->
        val category = categories.firstOrNull { it.id == categoryId } ?: CategoryEntity(
            id = categoryId ?: java.util.UUID.randomUUID(),
            name = "未分類",
            icon = "square.grid.2x2",
            colorHex = "#90A4AE",
            kind = org.duckdns.lhfser.aiaccounting.core.model.CategoryKind.Both
        )
        val total = items.fold(BigDecimal.ZERO) { acc, tx ->
            acc + currencyService.convert(tx.transaction.amount.abs(), tx.transaction.currencyCode, baseCurrency)
        }
        CategoryBreakdownRow(category, total, baseCurrency)
    }.sortedByDescending { it.total }
}
