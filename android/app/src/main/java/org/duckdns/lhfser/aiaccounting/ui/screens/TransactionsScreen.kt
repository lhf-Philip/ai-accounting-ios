package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.ExperimentalFoundationApi
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.db.ShortcutWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.TransactionEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateText
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.launch

@Composable
fun TransactionsScreen(
    onEdit: (String) -> Unit,
    onEditTransfer: (String) -> Unit,
    onAddShortcut: () -> Unit,
    onEditShortcut: (String) -> Unit
) {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()
    val transactions by repository.transactions.collectAsState(initial = emptyList())
    val shortcuts by repository.shortcuts.collectAsState(initial = emptyList())

    var pendingShortcut by remember { mutableStateOf<ShortcutWithDetails?>(null) }
    var showShortcutConfirm by remember { mutableStateOf(false) }
    var shortcutToDelete by remember { mutableStateOf<ShortcutWithDetails?>(null) }
    var showShortcutDeleteConfirm by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    LazyColumn(
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            ShortcutsBar(
                shortcuts = shortcuts,
                onAddShortcut = onAddShortcut,
                onShortcutTap = {
                    pendingShortcut = it
                    showShortcutConfirm = true
                },
                onShortcutLongPress = {
                    shortcutToDelete = it
                    showShortcutDeleteConfirm = true
                },
                onShortcutEdit = { onEditShortcut(it.shortcut.id.toString()) }
            )
        }
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

    if (showShortcutConfirm && pendingShortcut != null) {
        val shortcut = pendingShortcut ?: return
        AlertDialog(
            onDismissRequest = { showShortcutConfirm = false },
            title = { Text("確認快速記帳？") },
            text = {
                val typeLabel = if (shortcut.shortcut.type == TransactionType.Expense) "支出" else "收入"
                Text("${shortcut.shortcut.name}\n$typeLabel ${shortcut.shortcut.amount.asCurrencyText(shortcut.shortcut.currencyCode)}")
            },
            confirmButton = {
                TextButton(onClick = {
                    val target = pendingShortcut ?: return@TextButton
                    showShortcutConfirm = false
                    scope.launch {
                        val account = target.account
                        if (account == null) {
                            errorMessage = "捷徑尚未指定帳戶，請先編輯。"
                            return@launch
                        }
                        val finalAmount = if (target.shortcut.type == TransactionType.Expense) {
                            target.shortcut.amount.abs().negate()
                        } else {
                            target.shortcut.amount.abs()
                        }
                        val transaction = TransactionEntity(
                            id = UUID.randomUUID(),
                            amount = finalAmount,
                            currencyCode = target.shortcut.currencyCode,
                            date = Instant.now(),
                            note = target.shortcut.note.ifBlank { target.shortcut.name },
                            photoPath = null,
                            type = target.shortcut.type,
                            linkedTransactionId = null,
                            transferGroupId = null,
                            transferSide = null,
                            createdAt = Instant.now(),
                            updatedAt = Instant.now(),
                            accountId = account.id,
                            categoryId = target.shortcut.categoryId
                        )
                        repository.upsertTransaction(transaction, target.tags.map { it.id })
                    }
                }) {
                    Text("確認")
                }
            },
            dismissButton = {
                TextButton(onClick = { showShortcutConfirm = false }) { Text("取消") }
            }
        )
    }

    if (showShortcutDeleteConfirm && shortcutToDelete != null) {
        val shortcut = shortcutToDelete ?: return
        AlertDialog(
            onDismissRequest = { showShortcutDeleteConfirm = false },
            title = { Text("刪除捷徑？") },
            text = { Text(shortcut.shortcut.name) },
            confirmButton = {
                TextButton(onClick = {
                    val target = shortcutToDelete ?: return@TextButton
                    showShortcutDeleteConfirm = false
                    scope.launch {
                        repository.deleteShortcut(target.shortcut)
                    }
                }) {
                    Text("刪除")
                }
            },
            dismissButton = {
                TextButton(onClick = { showShortcutDeleteConfirm = false }) { Text("取消") }
            }
        )
    }

    if (errorMessage != null) {
        AlertDialog(
            onDismissRequest = { errorMessage = null },
            title = { Text("無法執行捷徑") },
            text = { Text(errorMessage ?: "") },
            confirmButton = {
                TextButton(onClick = { errorMessage = null }) { Text("了解") }
            }
        )
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

@Composable
private fun ShortcutsBar(
    shortcuts: List<ShortcutWithDetails>,
    onAddShortcut: () -> Unit,
    onShortcutTap: (ShortcutWithDetails) -> Unit,
    onShortcutLongPress: (ShortcutWithDetails) -> Unit,
    onShortcutEdit: (ShortcutWithDetails) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("捷徑", style = MaterialTheme.typography.titleMedium)
            TextButton(onClick = onAddShortcut) { Text("新增") }
        }
        LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                AddShortcutTile(onClick = onAddShortcut)
            }
            items(shortcuts, key = { it.shortcut.id }) { shortcut ->
                ShortcutTile(
                    shortcut = shortcut,
                    onClick = { onShortcutTap(shortcut) },
                    onLongClick = { onShortcutLongPress(shortcut) },
                    onEdit = { onShortcutEdit(shortcut) }
                )
            }
        }
    }
}

@Composable
private fun AddShortcutTile(onClick: () -> Unit) {
    ElevatedCard(
        modifier = Modifier
            .size(72.dp)
            .clickable(onClick = onClick)
    ) {
        Column(
            modifier = Modifier.padding(8.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text("+", style = MaterialTheme.typography.titleLarge)
            Text("捷徑", style = MaterialTheme.typography.labelSmall)
        }
    }
}

@Composable
@OptIn(ExperimentalFoundationApi::class)
private fun ShortcutTile(
    shortcut: ShortcutWithDetails,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    onEdit: () -> Unit
) {
    ElevatedCard(
        modifier = Modifier
            .width(86.dp)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
    ) {
        Column(
            modifier = Modifier.padding(8.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(shortcut.shortcut.icon.ifBlank { "⚡" }, style = MaterialTheme.typography.titleLarge)
            Text(shortcut.shortcut.name, style = MaterialTheme.typography.labelSmall, maxLines = 1)
            TextButton(onClick = onEdit) { Text("編輯") }
        }
    }
}
