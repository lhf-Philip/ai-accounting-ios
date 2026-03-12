package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateText

@Composable
fun TransactionsScreen(onEdit: (String) -> Unit, onEditTransfer: (String) -> Unit) {
    val repository = LocalRepository.current
    val transactions by repository.transactions.collectAsState(initial = emptyList())

    LazyColumn(
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        items(transactions) { item ->
            val groupId = item.transaction.transferGroupId?.toString()
            val isTransfer = item.transaction.type == TransactionType.Transfer && groupId != null
            TransactionRow(
                item = item,
                onClick = {
                    if (isTransfer) {
                        onEditTransfer(groupId!!)
                    } else {
                        onEdit(item.transaction.id.toString())
                    }
                }
            )
        }
    }
}

@Composable
private fun TransactionRow(item: TransactionWithDetails, onClick: () -> Unit) {
    val amountColor = when (item.transaction.type) {
        TransactionType.Income -> Color(0xFF2E7D32)
        TransactionType.Expense -> Color(0xFFC62828)
        TransactionType.Transfer -> MaterialTheme.colorScheme.onSurface
    }
    val amountText = item.transaction.amount.asCurrencyText(item.transaction.currencyCode)
    val categoryText = item.category?.name ?: "未分類"
    val accountText = item.account?.name ?: "未指定帳戶"

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(item.transaction.note.ifBlank { categoryText }, style = MaterialTheme.typography.bodyLarge)
            Text("${item.transaction.date.toDateText()} · $accountText", style = MaterialTheme.typography.bodySmall)
            Text(amountText, color = amountColor, style = MaterialTheme.typography.titleMedium)
        }
    }
}
