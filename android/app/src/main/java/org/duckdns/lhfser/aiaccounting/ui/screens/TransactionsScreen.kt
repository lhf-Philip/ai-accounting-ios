package org.duckdns.lhfser.aiaccounting.ui.screens

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
import androidx.compose.material3.Surface
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
import org.duckdns.lhfser.aiaccounting.core.preferences.resolveSharedDateRange
import org.duckdns.lhfser.aiaccounting.core.preferences.sharedDateFilterLabel
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.ShortcutWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.TransactionEntity
import org.duckdns.lhfser.aiaccounting.core.transactions.TransactionSemantics
import org.duckdns.lhfser.aiaccounting.data.repository.LedgerDeletionResult
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.routing.TransactionEditDestination
import org.duckdns.lhfser.aiaccounting.ui.routing.resolveTransactionEditDestination
import org.duckdns.lhfser.aiaccounting.ui.LocalUiPreferences
import org.duckdns.lhfser.aiaccounting.ui.components.ParityEmptyState
import org.duckdns.lhfser.aiaccounting.ui.components.ParityFilterCapsule
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySearchField
import org.duckdns.lhfser.aiaccounting.ui.components.ParityStatusPill
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTokens
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTopSection
import org.duckdns.lhfser.aiaccounting.ui.components.PressableCard
import org.duckdns.lhfser.aiaccounting.ui.components.SharedDateFilterSheet
import org.duckdns.lhfser.aiaccounting.ui.components.showSharedDatePicker
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

    data class AdvanceSummary(val summary: AdvanceLedgerSummary) : LedgerItem {
        override val stableId: String = "advance-${summary.item.advanceCase.id}"
        override val date: Instant = summary.activityDate
    }
}

private data class AdvanceCurrencyTotal(
    val currencyCode: String,
    val amount: BigDecimal
)

private data class AdvanceLedgerSummary(
    val item: AdvanceCaseWithDetails,
    val activityDate: Instant,
    val paymentTotals: List<AdvanceCurrencyTotal>
)

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
    val repaymentAdvanceGroupIds = remember(advanceCases) {
        advanceCases.flatMap { it.repayments.mapNotNull { repayment -> repayment.linkedTransferGroupId } }.toSet()
    }
    val advanceSelfExpenseIds = remember(advanceCases) {
        advanceCases.mapNotNull { it.advanceCase.selfExpenseTransactionId }.toSet()
    }
    val filteredTransactions = remember(
        transactions,
        rangeStart,
        rangeEnd,
        searchText,
        initialAdvanceGroupIds,
        repaymentAdvanceGroupIds,
        advanceSelfExpenseIds
    ) {
        filterTransactions(
            transactions = transactions,
            rangeStart = rangeStart,
            rangeEnd = rangeEnd,
            query = searchText,
            excludedAdvanceGroupIds = initialAdvanceGroupIds + repaymentAdvanceGroupIds,
            advanceSelfExpenseIds = advanceSelfExpenseIds
        )
    }
    val filteredAdvanceCases = remember(advanceCases, transactions, rangeStart, rangeEnd, searchText) {
        filterAdvanceCases(advanceCases, transactions, rangeStart, rangeEnd, searchText)
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
                                TransactionRow(
                                    item = item.item,
                                    onClick = {
                                        scope.launch {
                                            runCatching {
                                                resolveTransactionEditDestination(repository, item.item)
                                            }.onSuccess { destination ->
                                                when (destination) {
                                                    is TransactionEditDestination.Ordinary -> onEdit(destination.transactionId)
                                                    is TransactionEditDestination.Transfer -> onEditTransfer(destination.groupId)
                                                    is TransactionEditDestination.Debt -> onEditDebt(destination.transactionId)
                                                    is TransactionEditDestination.Advance -> onOpenAdvanceCase(destination.caseId)
                                                }
                                            }.onFailure {
                                                errorMessage = it.localizedMessage ?: "無法開啟編輯頁。"
                                            }
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
                                    summary = item.summary,
                                    onClick = {
                                        onOpenAdvanceCase(item.summary.item.advanceCase.id.toString())
                                    }
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
        SharedDateFilterSheet(
            title = "篩選區間",
            description = "選擇要在帳目頁固定顯示的日期範圍。",
            filterType = filterType,
            selectedDate = selectedDate,
            customStartDate = customStartDate,
            customEndDate = customEndDate,
            onSelectFilterType = uiPreferencesStore::setDateFilterType,
            onPickSelectedDate = {
                showSharedDatePicker(context, selectedDate, uiPreferencesStore::setDateFilterSelectedDate)
            },
            onPickCustomStart = {
                showSharedDatePicker(context, customStartDate, uiPreferencesStore::setDateFilterCustomStartDate)
            },
            onPickCustomEnd = {
                showSharedDatePicker(context, customEndDate, uiPreferencesStore::setDateFilterCustomEndDate)
            },
            onDismiss = { showFilterDialog = false },
            allSubtitle = "查看所有帳目與代墊摘要",
            yearSubtitle = "查看本年累積的收支紀錄",
            monthSubtitle = "聚焦本月帳目與代墊摘要",
            daySubtitle = "只查看指定日期的明細"
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
    summary: AdvanceLedgerSummary,
    onClick: () -> Unit
) {
    val item = summary.item
    val totalAdvanced = item.advanceCase.myShareAmount + item.participants.fold(BigDecimal.ZERO) { acc, participant ->
        acc + participant.owedAmount
    }
    val outstanding = item.participants.fold(BigDecimal.ZERO) { acc, participant ->
        acc + (participant.owedAmount - participant.repaidAmount).max(BigDecimal.ZERO)
    }
    val payerText = item.payerAccount?.name ?: "他人代付（不影響自己帳戶）"
    val isSettled = outstanding <= BigDecimal("0.0001")
    val directionLabel = if (item.advanceCase.direction == "OthersAdvancedMe") {
        "他人代墊我"
    } else {
        "我代墊他人"
    }
    val paymentText = if (summary.paymentTotals.isEmpty()) {
        if (item.advanceCase.direction == "OthersAdvancedMe") {
            "${totalAdvanced.asCurrencyText(item.advanceCase.currencyCode)}（他人代付）"
        } else {
            totalAdvanced.asCurrencyText(item.advanceCase.currencyCode)
        }
    } else {
        summary.paymentTotals.joinToString(" + ") {
            it.amount.asCurrencyText(it.currencyCode)
        }
    }

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
                        text = directionLabel,
                        tint = Color(0xFFEF6C00)
                    )
                }
                Text(
                    "${item.participants.size} 人 · $payerText",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    "最近活動 ${summary.activityDate.toDateText()}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    paymentText,
                    color = Color(0xFFEF6C00),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    if (isSettled) {
                        "已結清"
                    } else {
                        val label = if (item.advanceCase.direction == "OthersAdvancedMe") "待還" else "待收"
                        "$label ${outstanding.asCurrencyText(item.advanceCase.currencyCode)}"
                    },
                    style = MaterialTheme.typography.labelSmall,
                    color = if (isSettled) Color(0xFF2E7D32) else MaterialTheme.colorScheme.onSurfaceVariant
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
    excludedAdvanceGroupIds: Set<UUID>,
    advanceSelfExpenseIds: Set<UUID>
): List<TransactionWithDetails> {
    val normalized = query.trim().lowercase()
    return transactions.filter { tx ->
        val dateOk = if (rangeStart != null && rangeEnd != null) {
            tx.transaction.date >= rangeStart && tx.transaction.date < rangeEnd
        } else true
        if (!dateOk) return@filter false
        if (tx.transaction.advanceCaseId != null || tx.transaction.id in advanceSelfExpenseIds) {
            return@filter false
        }
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
    transactions: List<TransactionWithDetails>,
    rangeStart: Instant?,
    rangeEnd: Instant?,
    query: String
): List<AdvanceLedgerSummary> {
    val normalized = query.trim().lowercase()
    val transactionsByCaseId = transactions
        .mapNotNull { transaction ->
            transaction.transaction.advanceCaseId?.let { it to transaction }
        }
        .groupBy({ it.first }, { it.second })
    val transactionsByGroupId = transactions
        .mapNotNull { transaction ->
            transaction.transaction.transferGroupId?.let { it to transaction }
        }
        .groupBy({ it.first }, { it.second })
    val transactionById = transactions.associateBy { it.transaction.id }

    return advanceCases.mapNotNull { advanceCase ->
        var caseTransactions = transactionsByCaseId[advanceCase.advanceCase.id].orEmpty()
        val groupIds = advanceCase.participants.mapNotNull { it.initialTransferGroupId } +
            advanceCase.repayments.mapNotNull { it.linkedTransferGroupId }
        caseTransactions = (
            caseTransactions +
                groupIds.distinct().flatMap { transactionsByGroupId[it].orEmpty() } +
                listOfNotNull(
                    advanceCase.advanceCase.selfExpenseTransactionId?.let(transactionById::get)
                )
            ).distinctBy { it.transaction.id }

        val activityDates = listOf(advanceCase.advanceCase.date) +
            advanceCase.repayments.map { it.date } +
            caseTransactions.map { it.transaction.date }
        val matchingDates = activityDates.filter {
            rangeStart == null || rangeEnd == null || (it >= rangeStart && it < rangeEnd)
        }
        val activityDate = matchingDates.maxOrNull() ?: return@mapNotNull null

        if (normalized.isNotBlank()) {
            val searchable = listOf(
                advanceCase.advanceCase.title,
                advanceCase.advanceCase.note,
                advanceCase.payerAccount?.name.orEmpty(),
                advanceCase.expenseCategory?.name.orEmpty(),
                advanceCase.participants.joinToString(" ") { it.name },
                advanceCase.repayments.joinToString(" ") { it.note },
                caseTransactions.joinToString(" ") {
                    listOfNotNull(it.account?.name, it.category?.name)
                        .plus(it.tags.map { tag -> tag.name })
                        .joinToString(" ")
                }
            )
            if (searchable.none { it.lowercase().contains(normalized) }) {
                return@mapNotNull null
            }
        }

        val initialGroupIds = advanceCase.participants
            .mapNotNull { it.initialTransferGroupId }
            .toSet()
        val paymentTotals = caseTransactions
            .filter {
                (
                    it.transaction.advanceEntryRole == "InitialAsset" ||
                        (
                            it.transaction.advanceEntryRole == null &&
                                it.transaction.transferGroupId in initialGroupIds &&
                                (
                                    it.transaction.transferSide ==
                                        org.duckdns.lhfser.aiaccounting.core.model.TransferSide.Outgoing ||
                                        it.transaction.amount < BigDecimal.ZERO
                                    )
                            )
                    ) &&
                    it.transaction.amount < BigDecimal.ZERO
            }
            .groupBy { it.transaction.currencyCode }
            .map { (currency, entries) ->
                AdvanceCurrencyTotal(
                    currencyCode = currency,
                    amount = entries.fold(BigDecimal.ZERO) { acc, entry ->
                        acc + entry.transaction.amount.abs()
                    }
                )
            }
            .sortedBy { it.currencyCode }

        AdvanceLedgerSummary(
            item = advanceCase,
            activityDate = activityDate,
            paymentTotals = paymentTotals
        )
    }
}

private fun buildLedgerItems(
    transactions: List<TransactionWithDetails>,
    advanceCases: List<AdvanceLedgerSummary>
): List<LedgerItem> {
    return (
        transactions.map { LedgerItem.TransactionEntry(it) } +
            advanceCases.map { LedgerItem.AdvanceSummary(it) }
        )
        .sortedByDescending { it.date }
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
