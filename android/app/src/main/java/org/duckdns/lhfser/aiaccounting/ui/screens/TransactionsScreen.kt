package org.duckdns.lhfser.aiaccounting.ui.screens

import android.app.DatePickerDialog
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID
import kotlinx.coroutines.launch
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.core.preferences.SharedDateFilterType
import org.duckdns.lhfser.aiaccounting.core.preferences.resolveSharedDateRange
import org.duckdns.lhfser.aiaccounting.core.preferences.sharedDateFilterLabel
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.ShortcutWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.TransactionEntity
import org.duckdns.lhfser.aiaccounting.core.transactions.TransactionSemantics
import org.duckdns.lhfser.aiaccounting.data.repository.LedgerDeletionResult
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.LocalUiPreferences
import org.duckdns.lhfser.aiaccounting.ui.components.ParityEmptyState
import org.duckdns.lhfser.aiaccounting.ui.components.ParityFilterCapsule
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySearchField
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySelectionSheetRow
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySheetHandle
import org.duckdns.lhfser.aiaccounting.ui.components.ParityStatusPill
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTokens
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTopSection
import org.duckdns.lhfser.aiaccounting.ui.components.PressableCard
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateText

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
@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
fun TransactionsScreen(
    onEdit: (String) -> Unit,
    onEditTransfer: (String) -> Unit,
    onEditDebt: (String) -> Unit,
    onOpenAdvanceCase: (String) -> Unit,
    onAddShortcut: () -> Unit
) {
    val repository = LocalRepository.current
    val uiPreferencesStore = LocalUiPreferences.current
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val transactions by repository.transactions.collectAsState(initial = emptyList())
    val shortcuts by repository.shortcuts.collectAsState(initial = emptyList())
    val advanceCases by repository.advanceCases.collectAsState(initial = emptyList())
    val uiPreferences by uiPreferencesStore.state.collectAsState()

    var pendingShortcut by remember { mutableStateOf<ShortcutWithDetails?>(null) }
    var showShortcutConfirm by remember { mutableStateOf(false) }
    var shortcutToDelete by remember { mutableStateOf<ShortcutWithDetails?>(null) }
    var showShortcutDeleteConfirm by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var transactionToDelete by remember { mutableStateOf<TransactionWithDetails?>(null) }
    var showDeleteConfirm by remember { mutableStateOf(false) }

    var showFilterDialog by remember { mutableStateOf(false) }
    var searchText by remember { mutableStateOf("") }
    val dateFilter = uiPreferences.dateFilter
    val filterType = dateFilter.type
    val selectedDate = dateFilter.selectedDate
    val customStartDate = dateFilter.customStartDate
    val customEndDate = dateFilter.customEndDate

    val (rangeStart, rangeEnd) = remember(filterType, selectedDate, customStartDate, customEndDate) {
        resolveSharedDateRange(filterType, selectedDate, customStartDate, customEndDate)
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

    @Composable
    fun LedgerControls(modifier: Modifier = Modifier) {
        Column(modifier = modifier.fillMaxWidth()) {
            ParityTopSection(
                title = "帳目明細",
                modifier = Modifier.padding(horizontal = AppSpacing.screenHorizontal, vertical = 4.dp),
                subtitle = "搜尋、篩選、編輯所有交易與代墊摘要。"
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = AppSpacing.screenHorizontal, vertical = 10.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                ParityFilterCapsule(
                    label = sharedDateFilterLabel(filterType, selectedDate, customStartDate, customEndDate, allLabel = "全部紀錄"),
                    icon = Icons.Default.DateRange,
                    onClick = { showFilterDialog = true }
                )
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

            ParitySearchField(
                value = searchText,
                onValueChange = { searchText = it },
                placeholder = "搜尋備註、分類、標籤、金額",
                modifier = Modifier.padding(horizontal = AppSpacing.screenHorizontal, vertical = 12.dp)
            )

            HorizontalDivider()
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        if (uiPreferences.pinLedgerControls) {
            LedgerControls()
        }

        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(
                start = AppSpacing.screenHorizontal,
                end = AppSpacing.screenHorizontal,
                top = AppSpacing.screenVertical,
                bottom = AppSpacing.screenVertical + ParityTokens.FloatingContentBottomPadding
            ),
            verticalArrangement = Arrangement.spacedBy(AppSpacing.item)
        ) {
            if (!uiPreferences.pinLedgerControls) {
                item(key = "ledger-controls") {
                    LedgerControls(
                        modifier = Modifier
                            .background(MaterialTheme.colorScheme.background)
                            .padding(bottom = AppSpacing.inline)
                    )
                }
            }

            if (ledgerItems.isEmpty()) {
                item {
                    ParityEmptyState(
                        title = if (searchText.isBlank()) "還沒有帳目" else "沒有符合條件的帳目",
                        message = if (searchText.isBlank()) {
                            "先新增一筆交易，或切換日期區間看看。"
                        } else {
                            "可以調整搜尋關鍵字或日期篩選，再試一次。"
                        }
                    )
                }
            } else {
                dailySections.forEach { section ->
                    if (uiPreferences.pinLedgerControls) {
                        stickyHeader {
                            LedgerDateHeader(section.date)
                        }
                    } else {
                        item(key = "section-${section.date}") {
                            LedgerDateHeader(section.date)
                        }
                    }
                    items(section.items, key = { it.stableId }) { item ->
                        when (item) {
                            is LedgerItem.TransactionEntry -> {
                                val groupId = item.item.transaction.transferGroupId?.toString()
                                val isDebtForgiveness = TransactionSemantics.isDebtForgiveness(item.item.transaction.note)
                                val isTransfer = item.item.transaction.type == TransactionType.Transfer && groupId != null
                                TransactionRow(
                                    item = item.item,
                                    onClick = {
                                        when {
                                            isDebtForgiveness -> onEditDebt(item.item.transaction.id.toString())
                                            isTransfer -> onEditTransfer(groupId!!)
                                            else -> onEdit(item.item.transaction.id.toString())
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
                        val result = repository.deleteLedgerTransactionById(target.transaction.id)
                        if (result == LedgerDeletionResult.AdvanceInitialRequiresCase) {
                            errorMessage = "這是代墊建立分錄，請進入代墊詳情刪除整個代墊案件。"
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
            title = { Text("無法執行操作") },
            text = { Text(errorMessage ?: "") },
            confirmButton = {
                TextButton(onClick = { errorMessage = null }) { Text("了解") }
            }
        )
    }

    if (showFilterDialog) {
        TransactionFilterSheet(
            filterType = filterType,
            selectedDate = selectedDate,
            customStartDate = customStartDate,
            customEndDate = customEndDate,
            onSelectFilterType = uiPreferencesStore::setDateFilterType,
            onPickSelectedDate = {
                showDatePicker(context, selectedDate, uiPreferencesStore::setDateFilterSelectedDate)
            },
            onPickCustomStart = {
                showDatePicker(context, customStartDate, uiPreferencesStore::setDateFilterCustomStartDate)
            },
            onPickCustomEnd = {
                showDatePicker(context, customEndDate, uiPreferencesStore::setDateFilterCustomEndDate)
            },
            onDismiss = { showFilterDialog = false }
        )
    }
}

@Composable
private fun LedgerDateHeader(date: LocalDate) {
    Surface(
        color = MaterialTheme.colorScheme.background,
        modifier = Modifier.fillMaxWidth()
    ) {
        Text(
            text = formatHeaderDate(date),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(vertical = 8.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TransactionFilterSheet(
    filterType: SharedDateFilterType,
    selectedDate: LocalDate,
    customStartDate: LocalDate,
    customEndDate: LocalDate,
    onSelectFilterType: (SharedDateFilterType) -> Unit,
    onPickSelectedDate: () -> Unit,
    onPickCustomStart: () -> Unit,
    onPickCustomEnd: () -> Unit,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.background,
        dragHandle = { ParitySheetHandle() }
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text("篩選區間", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(
                "選擇要在帳目頁固定顯示的日期範圍。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            SharedDateFilterType.entries.forEach { type ->
                ParitySelectionSheetRow(
                    title = type.label,
                    subtitle = transactionFilterSubtitle(type),
                    selected = filterType == type,
                    onClick = { onSelectFilterType(type) }
                )
            }

            when (filterType) {
                SharedDateFilterType.Month, SharedDateFilterType.Year, SharedDateFilterType.Day -> {
                    PressableCard(
                        modifier = Modifier.fillMaxWidth(),
                        onClick = onPickSelectedDate,
                        containerColor = MaterialTheme.colorScheme.surfaceVariant,
                        pressedContainerColor = MaterialTheme.colorScheme.surface
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 14.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Text("基準日期", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                                Text(
                                    if (filterType == SharedDateFilterType.Year) {
                                        "${selectedDate.year}年"
                                    } else if (filterType == SharedDateFilterType.Day) {
                                        selectedDate.format(DateTimeFormatter.ofPattern("yyyy年 M月d日"))
                                    } else {
                                        selectedDate.format(DateTimeFormatter.ofPattern("yyyy年 M月"))
                                    },
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            Text("調整", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
                SharedDateFilterType.Custom -> {
                    PressableCard(
                        modifier = Modifier.fillMaxWidth(),
                        onClick = onPickCustomStart,
                        containerColor = MaterialTheme.colorScheme.surfaceVariant,
                        pressedContainerColor = MaterialTheme.colorScheme.surface
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 14.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Text("開始日期", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                                Text(customStartDate.format(DateTimeFormatter.ISO_DATE), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Text("選擇", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                        }
                    }
                    PressableCard(
                        modifier = Modifier.fillMaxWidth(),
                        onClick = onPickCustomEnd,
                        containerColor = MaterialTheme.colorScheme.surfaceVariant,
                        pressedContainerColor = MaterialTheme.colorScheme.surface
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 14.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Text("結束日期", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                                Text(customEndDate.format(DateTimeFormatter.ISO_DATE), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Text("選擇", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
                SharedDateFilterType.All -> Unit
            }

            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = onDismiss) { Text("完成") }
            }
            Spacer(modifier = Modifier.height(8.dp))
        }
    }
}

private fun transactionFilterSubtitle(type: SharedDateFilterType): String {
    return when (type) {
        SharedDateFilterType.All -> "查看所有帳目與代墊摘要"
        SharedDateFilterType.Year -> "查看本年累積的收支紀錄"
        SharedDateFilterType.Month -> "聚焦本月帳目與代墊摘要"
        SharedDateFilterType.Day -> "只查看指定日期的明細"
        SharedDateFilterType.Custom -> "自訂開始與結束日期"
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
    val isDebtForgiveness = item.transaction.type == TransactionType.Transfer && TransactionSemantics.isDebtForgiveness(item.transaction.note)
    val displayTitle = if (isDebtForgiveness) {
        TransactionSemantics.debtForgivenessDisplayTitle(item.transaction.note)
    } else {
        item.transaction.note.ifBlank { categoryText }
    }
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
            modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        displayTitle,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    if (isDebtForgiveness) {
                        ParityStatusPill(
                            text = "免除債務",
                            tint = Color(0xFF8E24AA)
                        )
                    }
                }
                Text(
                    metaText,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    item.transaction.date.toDateText(),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Column(
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    amountText,
                    color = amountColor,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    "${transactionTypeLabel(item)} · ${item.transaction.currencyCode}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
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
            modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        item.advanceCase.title,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    ParityStatusPill(
                        text = "代墊",
                        tint = Color(0xFFEF6C00)
                    )
                }
                Text(
                    "${item.participants.size} 人 · $payerText",
                    style = MaterialTheme.typography.labelMedium,
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
                    style = MaterialTheme.typography.titleSmall,
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
        verticalArrangement = Arrangement.spacedBy(AppSpacing.tight)
    ) {
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = PaddingValues(vertical = 12.dp)
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

@Composable
private fun AddShortcutTile(onClick: () -> Unit) {
    PressableCard(
        modifier = Modifier
            .width(ParityTokens.ShortcutTileWidth)
            .height(ParityTokens.ShortcutTileHeight)
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
            verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Surface(
                modifier = Modifier.size(ParityTokens.ShortcutIconSize),
                shape = RoundedCornerShape(14.dp),
                color = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        "+",
                        fontSize = 22.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
            Text(
                "捷徑",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
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
            .width(ParityTokens.ShortcutTileWidth)
            .height(ParityTokens.ShortcutTileHeight)
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
            verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Surface(
                modifier = Modifier.size(ParityTokens.ShortcutIconSize),
                shape = RoundedCornerShape(14.dp),
                color = MaterialTheme.colorScheme.surface
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        shortcut.shortcut.icon.ifBlank { "⚡" },
                        fontSize = 22.sp,
                        fontWeight = FontWeight.Medium
                    )
                }
            }
            Text(
                shortcut.shortcut.name,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                color = MaterialTheme.colorScheme.onSurface
            )
        }
    }
}

@Composable
private fun transferTintForNote(note: String): Color {
    val compact = note.replace(" ", "")
    return when {
        TransactionSemantics.isDebtForgiveness(note) -> Color(0xFF8E24AA)
        compact.contains("(代墊給") || compact.contains("(代墊給我") -> Color(0xFFEF6C00)
        compact.contains("(還款至") || compact.contains("(還款給") -> Color(0xFF00897B)
        else -> MaterialTheme.colorScheme.onSurface
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

private fun transactionTypeLabel(item: TransactionWithDetails): String = when {
    item.transaction.type == TransactionType.Transfer && TransactionSemantics.isDebtForgiveness(item.transaction.note) -> "免除債務"
    item.transaction.type == TransactionType.Income -> "收入"
    item.transaction.type == TransactionType.Expense -> "支出"
    else -> "轉帳"
}
