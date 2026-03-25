package org.duckdns.lhfser.aiaccounting.ui.screens

import android.app.DatePickerDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.ExperimentalFoundationApi
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.ShortcutWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.TransactionEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.PressableCard
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateText
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
import java.math.BigDecimal
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

private sealed interface LedgerItem {
    val stableId: String
    val date: Instant

    data class TransactionEntry(val item: TransactionWithDetails) : LedgerItem {
        override val stableId: String = "tx-${item.transaction.id}"
        override val date: Instant = item.transaction.date
    }

    data class AdvanceSummary(val item: AdvanceCaseWithDetails) : LedgerItem {
        override val stableId: String = "advance-${item.advanceCase.id}"
        override val date: Instant = item.advanceCase.date
    }
}

private data class DailySection(val date: LocalDate, val items: List<LedgerItem>)

@Composable
@OptIn(ExperimentalFoundationApi::class)
fun TransactionsScreen(
    onEdit: (String) -> Unit,
    onEditTransfer: (String) -> Unit,
    onOpenAdvanceCase: (String) -> Unit,
    onAddShortcut: () -> Unit
) {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val transactions by repository.transactions.collectAsState(initial = emptyList())
    val shortcuts by repository.shortcuts.collectAsState(initial = emptyList())
    val advanceCases by repository.advanceCases.collectAsState(initial = emptyList())

    var pendingShortcut by remember { mutableStateOf<ShortcutWithDetails?>(null) }
    var showShortcutConfirm by remember { mutableStateOf(false) }
    var shortcutToDelete by remember { mutableStateOf<ShortcutWithDetails?>(null) }
    var showShortcutDeleteConfirm by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var transactionToDelete by remember { mutableStateOf<TransactionWithDetails?>(null) }
    var showDeleteConfirm by remember { mutableStateOf(false) }

    var filterType by remember { mutableStateOf(DateFilterType.Month) }
    var selectedDate by remember { mutableStateOf(LocalDate.now()) }
    var customStartDate by remember { mutableStateOf(LocalDate.now()) }
    var customEndDate by remember { mutableStateOf(LocalDate.now()) }
    var showFilterDialog by remember { mutableStateOf(false) }
    var searchText by remember { mutableStateOf("") }

    val (rangeStart, rangeEnd) = remember(filterType, selectedDate, customStartDate, customEndDate) {
        resolveDateRange(filterType, selectedDate, customStartDate, customEndDate)
    }
    val initialAdvanceGroupIds = remember(advanceCases) {
        advanceCases.flatMap { it.participants.mapNotNull { participant -> participant.initialTransferGroupId } }.toSet()
    }
    val filteredTransactions = remember(transactions, rangeStart, rangeEnd, searchText, initialAdvanceGroupIds) {
        filterTransactions(transactions, rangeStart, rangeEnd, searchText, initialAdvanceGroupIds)
    }
    val filteredAdvanceCases = remember(advanceCases, rangeStart, rangeEnd, searchText) {
        filterAdvanceCases(advanceCases, rangeStart, rangeEnd, searchText)
    }
    val ledgerItems = remember(filteredTransactions, filteredAdvanceCases) {
        buildLedgerItems(filteredTransactions, filteredAdvanceCases)
    }
    val dailySections = remember(ledgerItems) {
        val zone = ZoneId.systemDefault()
        ledgerItems
            .groupBy { it.date.atZone(zone).toLocalDate() }
            .map { (date, items) -> DailySection(date, items) }
            .sortedByDescending { it.date }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = AppSpacing.inline),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Surface(
                modifier = Modifier.clickable { showFilterDialog = true },
                shape = RoundedCornerShape(50),
                color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = AppSpacing.tight),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Icon(Icons.Default.DateRange, contentDescription = null)
                    Text(filterLabel(filterType, selectedDate, customStartDate, customEndDate))
                }
            }
        }

        HorizontalDivider()

        ShortcutsBar(
            modifier = Modifier.padding(horizontal = AppSpacing.screenHorizontal),
            shortcuts = shortcuts,
            onAddShortcut = onAddShortcut,
            onShortcutTap = {
                pendingShortcut = it
                showShortcutConfirm = true
            },
            onShortcutLongPress = {
                shortcutToDelete = it
                showShortcutDeleteConfirm = true
            }
        )

        HorizontalDivider()

        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(
                horizontal = AppSpacing.screenHorizontal,
                vertical = AppSpacing.screenVertical
            ),
            verticalArrangement = Arrangement.spacedBy(AppSpacing.item)
        ) {
            item {
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

            if (ledgerItems.isEmpty()) {
                item {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text("沒有符合條件的帳目", style = MaterialTheme.typography.bodyMedium)
                    }
                }
            } else {
                dailySections.forEach { section ->
                    stickyHeader {
                        Surface(
                            color = MaterialTheme.colorScheme.background,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(
                                text = formatHeaderDate(section.date),
                                style = MaterialTheme.typography.titleSmall,
                                modifier = Modifier.padding(
                                    horizontal = AppSpacing.screenHorizontal,
                                    vertical = AppSpacing.inline
                                ),
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    items(section.items, key = { it.stableId }) { item ->
                        when (item) {
                            is LedgerItem.TransactionEntry -> {
                                val groupId = item.item.transaction.transferGroupId?.toString()
                                val isTransfer = item.item.transaction.type == TransactionType.Transfer && groupId != null
                                TransactionRow(
                                    item = item.item,
                                    onClick = {
                                        if (isTransfer) {
                                            onEditTransfer(groupId!!)
                                        } else {
                                            onEdit(item.item.transaction.id.toString())
                                        }
                                    },
                                    onLongClick = {
                                        transactionToDelete = item.item
                                        showDeleteConfirm = true
                                    }
                                )
                            }
                            is LedgerItem.AdvanceSummary -> {
                                AdvanceSummaryRow(
                                    item = item.item,
                                    onClick = { onOpenAdvanceCase(item.item.advanceCase.id.toString()) }
                                )
                            }
                        }
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

    if (showDeleteConfirm && transactionToDelete != null) {
        val target = transactionToDelete ?: return
        val groupId = target.transaction.transferGroupId?.toString()
        val isTransfer = target.transaction.type == TransactionType.Transfer && groupId != null
        val title = if (isTransfer) "刪除轉帳？" else "刪除交易？"
        val message = if (isTransfer) "將刪除此筆轉帳的所有分錄。" else "刪除後無法復原。"
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text(title) },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    scope.launch {
                        if (isTransfer) {
                            repository.deleteTransferGroup(UUID.fromString(groupId))
                        } else {
                            repository.deleteTransactionById(target.transaction.id)
                        }
                    }
                }) { Text("刪除", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("取消") }
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
private fun TransactionRow(
    item: TransactionWithDetails,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null
) {
    val amountColor = when (item.transaction.type) {
        TransactionType.Income -> Color(0xFF2E7D32)
        TransactionType.Expense -> Color(0xFFC62828)
        TransactionType.Transfer -> transferTintForNote(item.transaction.note)
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
        onClick = onClick,
        onLongClick = onLongClick
    ) {
        Row(
            modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = AppSpacing.inline),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    item.transaction.note.ifBlank { categoryText },
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold
                )
                Text(metaText, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(item.transaction.date.toDateText(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(amountText, color = amountColor, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                Text(item.transaction.currencyCode, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun AdvanceSummaryRow(
    item: AdvanceCaseWithDetails,
    onClick: () -> Unit
) {
    val totalAdvanced = item.advanceCase.myShareAmount + item.participants.fold(BigDecimal.ZERO) { acc, participant ->
        acc + participant.owedAmount
    }
    val outstanding = item.participants.fold(BigDecimal.ZERO) { acc, participant ->
        acc + (participant.owedAmount - participant.repaidAmount).max(BigDecimal.ZERO)
    }
    val payerText = item.payerAccount?.name ?: "未指定付款帳戶"

    PressableCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick
    ) {
        Row(
            modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = AppSpacing.inline),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    item.advanceCase.title,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    "${item.participants.size} 人 · $payerText",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    item.advanceCase.date.toDateText(),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    totalAdvanced.asCurrencyText(item.advanceCase.currencyCode),
                    color = Color(0xFFEF6C00),
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    "未清 ${outstanding.asCurrencyText(item.advanceCase.currencyCode)}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
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
    onShortcutLongPress: (ShortcutWithDetails) -> Unit
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)
    ) {
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = PaddingValues(vertical = AppSpacing.inline)
        ) {
            item {
                AddShortcutTile(onClick = onAddShortcut)
            }
            items(shortcuts, key = { it.shortcut.id }) { shortcut ->
                ShortcutTile(
                    shortcut = shortcut,
                    onClick = { onShortcutTap(shortcut) },
                    onLongClick = { onShortcutLongPress(shortcut) }
                )
            }
        }
    }
}

private val ShortcutTileWidth = 76.dp
private val ShortcutTileHeight = 82.dp

@Composable
private fun AddShortcutTile(onClick: () -> Unit) {
    PressableCard(
        modifier = Modifier
            .width(ShortcutTileWidth)
            .height(ShortcutTileHeight)
            .padding(vertical = 2.dp),
        onClick = onClick,
        containerColor = MaterialTheme.colorScheme.surfaceVariant,
        pressedContainerColor = MaterialTheme.colorScheme.surface,
        borderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.35f),
        pressedBorderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.5f)
    ) {
        Column(
            modifier = Modifier
                .padding(horizontal = 8.dp, vertical = 10.dp)
                .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text("+", fontSize = 20.sp, fontWeight = FontWeight.Medium)
            Text("捷徑", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Medium)
        }
    }
}

@Composable
@OptIn(ExperimentalFoundationApi::class)
private fun ShortcutTile(
    shortcut: ShortcutWithDetails,
    onClick: () -> Unit,
    onLongClick: () -> Unit
) {
    PressableCard(
        modifier = Modifier
            .width(ShortcutTileWidth)
            .height(ShortcutTileHeight)
            .padding(vertical = 2.dp),
        onClick = onClick,
        onLongClick = onLongClick,
        containerColor = MaterialTheme.colorScheme.surfaceVariant,
        pressedContainerColor = MaterialTheme.colorScheme.surface,
        borderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.35f),
        pressedBorderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.5f)
    ) {
        Column(
            modifier = Modifier
                .padding(horizontal = 8.dp, vertical = 10.dp)
                .fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                shortcut.shortcut.icon.ifBlank { "⚡" },
                fontSize = 20.sp,
                fontWeight = FontWeight.Medium
            )
            Text(
                shortcut.shortcut.name,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Medium,
                maxLines = 1
            )
        }
    }
}

@Composable
private fun transferTintForNote(note: String): Color {
    val compact = note.replace(" ", "")
    return when {
        compact.contains("(代墊給") || compact.contains("(代墊給我") -> Color(0xFFEF6C00)
        compact.contains("(還款至") || compact.contains("(還款給") -> Color(0xFF00897B)
        else -> MaterialTheme.colorScheme.onSurface
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
    query: String,
    excludedAdvanceGroupIds: Set<UUID>
): List<TransactionWithDetails> {
    val normalized = query.trim().lowercase()
    return transactions.filter { tx ->
        val dateOk = if (rangeStart != null && rangeEnd != null) {
            tx.transaction.date >= rangeStart && tx.transaction.date < rangeEnd
        } else true
        if (!dateOk) return@filter false
        if (tx.transaction.transferGroupId in excludedAdvanceGroupIds) return@filter false
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

private fun filterAdvanceCases(
    advanceCases: List<AdvanceCaseWithDetails>,
    rangeStart: Instant?,
    rangeEnd: Instant?,
    query: String
): List<AdvanceCaseWithDetails> {
    val normalized = query.trim().lowercase()
    return advanceCases.filter { advanceCase ->
        val dateOk = if (rangeStart != null && rangeEnd != null) {
            advanceCase.advanceCase.date >= rangeStart && advanceCase.advanceCase.date < rangeEnd
        } else true
        if (!dateOk) return@filter false
        if (normalized.isBlank()) return@filter true

        val title = advanceCase.advanceCase.title.lowercase()
        val note = advanceCase.advanceCase.note.lowercase()
        val payer = advanceCase.payerAccount?.name?.lowercase().orEmpty()
        val participants = advanceCase.participants.joinToString(" ") { it.name.lowercase() }
        listOf(title, note, payer, participants).any { it.contains(normalized) }
    }
}

private fun buildLedgerItems(
    transactions: List<TransactionWithDetails>,
    advanceCases: List<AdvanceCaseWithDetails>
): List<LedgerItem> {
    return (transactions.map { LedgerItem.TransactionEntry(it) } + advanceCases.map { LedgerItem.AdvanceSummary(it) })
        .sortedByDescending { it.date }
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
