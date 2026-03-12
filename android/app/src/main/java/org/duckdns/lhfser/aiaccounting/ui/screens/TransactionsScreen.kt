package org.duckdns.lhfser.aiaccounting.ui.screens

import android.app.DatePickerDialog
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.foundation.BorderStroke
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.ExperimentalFoundationApi
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.db.ShortcutWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.TransactionEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.PressableCard
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateText
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID
import kotlinx.coroutines.launch

private enum class DateFilterType(val label: String) {
    Month("本月"),
    Year("本年"),
    Custom("自訂區間")
}

private data class DailySection(val date: LocalDate, val items: List<TransactionWithDetails>)

@Composable
@OptIn(ExperimentalFoundationApi::class)
fun TransactionsScreen(
    onEdit: (String) -> Unit,
    onEditTransfer: (String) -> Unit,
    onAddShortcut: () -> Unit,
    onEditShortcut: (String) -> Unit
) {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val transactions by repository.transactions.collectAsState(initial = emptyList())
    val shortcuts by repository.shortcuts.collectAsState(initial = emptyList())

    var pendingShortcut by remember { mutableStateOf<ShortcutWithDetails?>(null) }
    var showShortcutConfirm by remember { mutableStateOf(false) }
    var shortcutToDelete by remember { mutableStateOf<ShortcutWithDetails?>(null) }
    var showShortcutDeleteConfirm by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    var filterType by remember { mutableStateOf(DateFilterType.Month) }
    var selectedDate by remember { mutableStateOf(LocalDate.now()) }
    var customStartDate by remember { mutableStateOf(LocalDate.now()) }
    var customEndDate by remember { mutableStateOf(LocalDate.now()) }
    var showFilterDialog by remember { mutableStateOf(false) }
    var searchText by remember { mutableStateOf("") }

    val (rangeStart, rangeEnd) = remember(filterType, selectedDate, customStartDate, customEndDate) {
        resolveDateRange(filterType, selectedDate, customStartDate, customEndDate)
    }
    val filteredTransactions = remember(transactions, rangeStart, rangeEnd, searchText) {
        filterTransactions(transactions, rangeStart, rangeEnd, searchText)
    }
    val dailySections = remember(filteredTransactions) {
        val zone = ZoneId.systemDefault()
        filteredTransactions
            .groupBy { it.transaction.date.atZone(zone).toLocalDate() }
            .map { (date, items) -> DailySection(date, items) }
            .sortedByDescending { it.date }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Card(
            modifier = Modifier
                .padding(horizontal = 16.dp, vertical = 12.dp)
                .fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
            border = BorderStroke(0.6.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.5f))
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text("篩選與搜尋", style = MaterialTheme.typography.titleMedium)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    DateFilterType.values().forEach { type ->
                        FilterChip(
                            selected = filterType == type,
                            onClick = { filterType = type },
                            label = { Text(type.label) }
                        )
                    }
                }
                TextButton(onClick = { showFilterDialog = true }) {
                    Icon(Icons.Default.DateRange, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(filterLabel(filterType, selectedDate, customStartDate, customEndDate))
                }
                OutlinedTextField(
                    value = searchText,
                    onValueChange = { searchText = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("搜尋備註、分類、標籤、金額") },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                    trailingIcon = {
                        if (searchText.isNotBlank()) {
                            IconButton(onClick = { searchText = "" }) {
                                Icon(Icons.Default.Clear, contentDescription = "清除")
                            }
                        }
                    },
                    singleLine = true
                )
            }
        }

        ShortcutsBar(
            modifier = Modifier.padding(horizontal = 16.dp),
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

        if (filteredTransactions.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("沒有符合條件的帳目", style = MaterialTheme.typography.bodyMedium)
            }
        } else {
            LazyColumn(
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                dailySections.forEach { section ->
                    stickyHeader {
                        Surface(
                            color = MaterialTheme.colorScheme.background,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(
                                text = formatHeaderDate(section.date),
                                style = MaterialTheme.typography.titleSmall,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    items(section.items, key = { it.transaction.id }) { item ->
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

    if (showFilterDialog) {
        AlertDialog(
            onDismissRequest = { showFilterDialog = false },
            title = { Text("篩選區間") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    DateFilterType.values().forEach { type ->
                        TextButton(onClick = {
                            filterType = type
                        }) {
                            Text(type.label)
                        }
                    }
                    if (filterType == DateFilterType.Custom) {
                        Spacer(modifier = Modifier.padding(top = 4.dp))
                        Text("開始日期", style = MaterialTheme.typography.labelMedium)
                        TextButton(onClick = {
                            showDatePicker(context, customStartDate) { customStartDate = it }
                        }) {
                            Text(customStartDate.format(DateTimeFormatter.ISO_DATE))
                        }
                        Text("結束日期", style = MaterialTheme.typography.labelMedium)
                        TextButton(onClick = {
                            showDatePicker(context, customEndDate) { customEndDate = it }
                        }) {
                            Text(customEndDate.format(DateTimeFormatter.ISO_DATE))
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showFilterDialog = false }) { Text("完成") }
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
    val metaText = listOfNotNull(
        categoryText.takeIf { it.isNotBlank() },
        accountText.takeIf { it.isNotBlank() }
    ).joinToString(" · ")

    PressableCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    item.transaction.note.ifBlank { categoryText },
                    style = MaterialTheme.typography.titleMedium
                )
                Text(metaText, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(item.transaction.date.toDateText(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(amountText, color = amountColor, style = MaterialTheme.typography.titleMedium)
                Text(item.transaction.currencyCode, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun ShortcutsBar(
    modifier: Modifier = Modifier,
    shortcuts: List<ShortcutWithDetails>,
    onAddShortcut: () -> Unit,
    onShortcutTap: (ShortcutWithDetails) -> Unit,
    onShortcutLongPress: (ShortcutWithDetails) -> Unit,
    onShortcutEdit: (ShortcutWithDetails) -> Unit
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        border = BorderStroke(0.6.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.5f))
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("捷徑", style = MaterialTheme.typography.titleMedium)
                Spacer(modifier = Modifier.weight(1f))
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
}

@Composable
private fun AddShortcutTile(onClick: () -> Unit) {
    PressableCard(
        modifier = Modifier.size(84.dp),
        onClick = onClick,
        containerColor = MaterialTheme.colorScheme.surfaceVariant,
        pressedContainerColor = MaterialTheme.colorScheme.surface,
        borderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.35f),
        pressedBorderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.5f)
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
    PressableCard(
        modifier = Modifier
            .width(92.dp)
            .padding(vertical = 2.dp),
        onClick = onClick,
        onLongClick = onLongClick,
        containerColor = MaterialTheme.colorScheme.surfaceVariant,
        pressedContainerColor = MaterialTheme.colorScheme.surface,
        borderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.35f),
        pressedBorderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.5f)
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

private fun filterLabel(
    filterType: DateFilterType,
    selectedDate: LocalDate,
    customStart: LocalDate,
    customEnd: LocalDate
): String {
    return when (filterType) {
        DateFilterType.Month -> selectedDate.format(DateTimeFormatter.ofPattern("yyyy-MM"))
        DateFilterType.Year -> selectedDate.year.toString()
        DateFilterType.Custom -> {
            val start = customStart
            val end = customEnd
            "${start.format(DateTimeFormatter.ISO_DATE)} ~ ${end.format(DateTimeFormatter.ISO_DATE)}"
        }
    }
}

private fun resolveDateRange(
    filterType: DateFilterType,
    selectedDate: LocalDate,
    customStart: LocalDate,
    customEnd: LocalDate
): Pair<Instant?, Instant?> {
    val zone = ZoneId.systemDefault()
    return when (filterType) {
        DateFilterType.Month -> {
            val start = selectedDate.withDayOfMonth(1).atStartOfDay(zone).toInstant()
            val end = selectedDate.withDayOfMonth(1).plusMonths(1).atStartOfDay(zone).toInstant()
            start to end
        }
        DateFilterType.Year -> {
            val start = LocalDate.of(selectedDate.year, 1, 1).atStartOfDay(zone).toInstant()
            val end = LocalDate.of(selectedDate.year + 1, 1, 1).atStartOfDay(zone).toInstant()
            start to end
        }
        DateFilterType.Custom -> {
            val startDate = if (customEnd.isBefore(customStart)) customEnd else customStart
            val endDate = if (customEnd.isBefore(customStart)) customStart else customEnd
            val start = startDate.atStartOfDay(zone).toInstant()
            val end = endDate.plusDays(1).atStartOfDay(zone).toInstant()
            start to end
        }
    }
}

private fun filterTransactions(
    transactions: List<TransactionWithDetails>,
    rangeStart: Instant?,
    rangeEnd: Instant?,
    query: String
): List<TransactionWithDetails> {
    val normalized = query.trim().lowercase()
    return transactions.filter { tx ->
        val dateOk = if (rangeStart != null && rangeEnd != null) {
            tx.transaction.date >= rangeStart && tx.transaction.date < rangeEnd
        } else true
        if (!dateOk) return@filter false
        if (normalized.isBlank()) return@filter true
        val note = tx.transaction.note.lowercase()
        val category = tx.category?.name?.lowercase().orEmpty()
        val account = tx.account?.name?.lowercase().orEmpty()
        val tags = tx.tags.joinToString(" ") { it.name.lowercase() }
        val amount = tx.transaction.amount.abs().toPlainString()
        val currency = tx.transaction.currencyCode.lowercase()
        listOf(note, category, account, tags, amount, currency).any { it.contains(normalized) }
    }
}

private fun showDatePicker(
    context: android.content.Context,
    initialDate: LocalDate,
    onSelected: (LocalDate) -> Unit
) {
    DatePickerDialog(
        context,
        { _, year, month, day ->
            onSelected(LocalDate.of(year, month + 1, day))
        },
        initialDate.year,
        initialDate.monthValue - 1,
        initialDate.dayOfMonth
    ).show()
}

private fun formatHeaderDate(date: LocalDate): String {
    val today = LocalDate.now()
    return when (date) {
        today -> "今天"
        today.minusDays(1) -> "昨天"
        else -> date.format(DateTimeFormatter.ofPattern("yyyy/MM/dd"))
    }
}
