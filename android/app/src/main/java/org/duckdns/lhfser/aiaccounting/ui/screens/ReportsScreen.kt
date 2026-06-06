package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.launch
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.core.preferences.SharedDateFilterType
import org.duckdns.lhfser.aiaccounting.core.preferences.resolveSharedDateRange
import org.duckdns.lhfser.aiaccounting.core.preferences.sharedDateFilterLabel
import org.duckdns.lhfser.aiaccounting.core.report.CurrencyServiceReportConverter
import org.duckdns.lhfser.aiaccounting.core.report.ReportAggregationRequest
import org.duckdns.lhfser.aiaccounting.core.report.ReportAggregationResult
import org.duckdns.lhfser.aiaccounting.core.report.ReportAggregationService
import org.duckdns.lhfser.aiaccounting.core.report.ReportFlow
import org.duckdns.lhfser.aiaccounting.core.report.ReportGroupingMode
import org.duckdns.lhfser.aiaccounting.core.report.ReportTransactionSnapshot
import org.duckdns.lhfser.aiaccounting.core.transactions.TransactionSemantics
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryMonthlyBudgetEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.data.repository.LedgerDeletionResult
import org.duckdns.lhfser.aiaccounting.ui.LocalCurrencyService
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.LocalUiPreferences
import org.duckdns.lhfser.aiaccounting.ui.components.ParityEmptyState
import org.duckdns.lhfser.aiaccounting.ui.components.ParityFilterCapsule
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySectionHeader
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySegmentedControl
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySheetHandle
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTopSection
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTokens
import org.duckdns.lhfser.aiaccounting.ui.components.PressableCard
import org.duckdns.lhfser.aiaccounting.ui.components.SharedDateFilterSheet
import org.duckdns.lhfser.aiaccounting.ui.components.showSharedDatePicker
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateText

private enum class ReportChartMode(
    val label: String,
    val groupingMode: ReportGroupingMode
) {
    Category("依分類", ReportGroupingMode.Category),
    Tag("依標籤", ReportGroupingMode.Tag)
}

private enum class ReportFlowMode(
    val label: String,
    val reportFlow: ReportFlow
) {
    Expense("支出", ReportFlow.Expense),
    Income("收入", ReportFlow.Income)
}

private data class ReportChartSlice(
    val key: String,
    val name: String,
    val amount: BigDecimal,
    val color: Color,
    val transactions: List<TransactionWithDetails>,
    val originalCurrencySummary: String,
    val estimateFootnote: String?
)

private data class ReportDetail(
    val title: String,
    val estimatedAmount: BigDecimal,
    val baseCurrency: String,
    val originalCurrencySummary: String,
    val estimateFootnote: String?,
    val transactions: List<TransactionWithDetails>
)

private data class BudgetAlert(
    val budget: CategoryMonthlyBudgetEntity,
    val remaining: BigDecimal,
    val categoryName: String
)

@Composable
@OptIn(ExperimentalMaterial3Api::class)
fun ReportsScreen(
    onEdit: (String) -> Unit,
    onEditTransfer: (String) -> Unit,
    onEditDebt: (String) -> Unit
) {
    val repository = LocalRepository.current
    val currencyService = LocalCurrencyService.current
    val uiPreferencesStore = LocalUiPreferences.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val transactions by repository.transactions.collectAsState(initial = emptyList())
    val categories by repository.categories.collectAsState(initial = emptyList())
    val budgets by repository.budgets.collectAsState(initial = emptyList())
    val uiPreferences by uiPreferencesStore.state.collectAsState()

    var showFilterDialog by remember { mutableStateOf(false) }
    var chartMode by remember { mutableStateOf(ReportChartMode.Category) }
    var flowMode by remember { mutableStateOf(ReportFlowMode.Expense) }
    var selectedTag by remember { mutableStateOf<String?>(null) }
    var reportDetail by remember { mutableStateOf<ReportDetail?>(null) }
    var transactionToDelete by remember { mutableStateOf<TransactionWithDetails?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val dateFilter = uiPreferences.dateFilter
    val filterType = dateFilter.type
    val selectedDate = dateFilter.selectedDate
    val customStartDate = dateFilter.customStartDate
    val customEndDate = dateFilter.customEndDate

    val (rangeStart, rangeEnd) = remember(filterType, selectedDate, customStartDate, customEndDate) {
        resolveSharedDateRange(filterType, selectedDate, customStartDate, customEndDate)
    }
    val baseCurrency = currencyService.mainCurrency
    val reportConverter = remember(currencyService) {
        CurrencyServiceReportConverter(currencyService)
    }
    val reportSnapshots = remember(transactions) {
        transactions.map { it.toReportSnapshot() }
    }
    val transactionsById = remember(transactions) {
        transactions.associateBy { it.transaction.id }
    }
    val rateSourceState = currencyService.resolvedRateSourceState
    val rates = currencyService.rates

    val chartData = remember(
        reportSnapshots,
        transactionsById,
        flowMode,
        chartMode,
        rangeStart,
        rangeEnd,
        baseCurrency,
        rateSourceState,
        rates
    ) {
        val result = ReportAggregationService.aggregate(
            request = ReportAggregationRequest(
                transactions = reportSnapshots,
                flow = flowMode.reportFlow,
                grouping = chartMode.groupingMode,
                startDate = rangeStart,
                endDate = rangeEnd
            ),
            currencyConverter = reportConverter
        )
        result.toChartSlices(
            transactionsById = transactionsById,
            chartMode = chartMode
        )
    }

    val tagDetailData = remember(
        reportSnapshots,
        transactionsById,
        flowMode,
        selectedTag,
        rangeStart,
        rangeEnd,
        baseCurrency,
        rateSourceState,
        rates
    ) {
        if (chartMode == ReportChartMode.Tag && selectedTag != null) {
            ReportAggregationService.aggregate(
                request = ReportAggregationRequest(
                    transactions = reportSnapshots,
                    flow = flowMode.reportFlow,
                    grouping = ReportGroupingMode.Category,
                    startDate = rangeStart,
                    endDate = rangeEnd,
                    tagFilter = selectedTag
                ),
                currencyConverter = reportConverter
            ).toChartSlices(
                transactionsById = transactionsById,
                chartMode = ReportChartMode.Category
            )
        } else emptyList()
    }

    val budgetAlerts = remember(budgets, categories, transactions, currencyService) {
        buildBudgetAlerts(budgets, categories, transactions, currencyService)
    }

    @Composable
    fun ReportControls() {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = AppSpacing.screenHorizontal, vertical = AppSpacing.screenVertical),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            ParityTopSection(
                title = "報表",
                subtitle = "切換收支、分類與標籤，查看和 iOS 對齊的統計視圖。"
            )

            ParityFilterCapsule(
                label = sharedDateFilterLabel(filterType, selectedDate, customStartDate, customEndDate, allLabel = "全部時間"),
                icon = Icons.Default.DateRange,
                onClick = { showFilterDialog = true }
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(AppSpacing.inline)
            ) {
                ParitySegmentedControl(
                    modifier = Modifier.weight(1f),
                    options = ReportFlowMode.values().toList(),
                    selected = flowMode,
                    label = { it.label },
                    onSelect = {
                        flowMode = it
                        selectedTag = null
                    }
                )
                ParitySegmentedControl(
                    modifier = Modifier.weight(1f),
                    options = ReportChartMode.values().toList(),
                    selected = chartMode,
                    label = { it.label },
                    onSelect = {
                        chartMode = it
                        selectedTag = null
                    }
                )
            }
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        if (uiPreferences.pinReportsControls) {
            ReportControls()
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
            if (!uiPreferences.pinReportsControls) {
                item(key = "report-controls") {
                    ReportControls()
                }
            }

            if (chartMode == ReportChartMode.Tag && selectedTag != null) {
                item {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        IconButton(onClick = { selectedTag = null }) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                        }
                        Text(
                            selectedTag ?: "",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
                if (tagDetailData.isEmpty()) {
                    item { EmptyState(message = "此標籤無分類數據") }
                } else {
                    item {
                        DonutChart(data = tagDetailData, baseCurrency = baseCurrency, title = flowMode.label)
                    }
                    items(tagDetailData) { item ->
                        ReportRow(
                            item = item,
                            total = totalAmount(tagDetailData),
                            baseCurrency = baseCurrency,
                            trailingLabel = "明細"
                        ) {
                            reportDetail = presentTransactions(
                                flowMode = flowMode,
                                item = item,
                                tagName = selectedTag,
                                baseCurrency = baseCurrency
                            )
                        }
                    }
                }
            } else {
                if (chartData.isEmpty()) {
                    item { EmptyState(message = "試試切換日期或記一筆帳") }
                } else {
                    item {
                        DonutChart(data = chartData, baseCurrency = baseCurrency, title = flowMode.label)
                    }
                    items(chartData) { item ->
                        ReportRow(
                            item = item,
                            total = totalAmount(chartData),
                            baseCurrency = baseCurrency,
                            trailingLabel = if (chartMode == ReportChartMode.Tag) "查看分類" else "明細"
                        ) {
                            if (chartMode == ReportChartMode.Tag) {
                                selectedTag = item.name
                            } else {
                                reportDetail = presentTransactions(flowMode, item, null, baseCurrency)
                            }
                        }
                    }
                }
            }

            if (budgetAlerts.isNotEmpty() && flowMode == ReportFlowMode.Expense) {
                item {
                    BudgetAlertCard(alerts = budgetAlerts)
                }
            }
        }
    }


    if (transactionToDelete != null) {
        val target = transactionToDelete ?: return
        val groupId = target.transaction.transferGroupId?.toString()
        val isTransfer = target.transaction.type == TransactionType.Transfer && groupId != null
        AlertDialog(
            onDismissRequest = { transactionToDelete = null },
            title = { Text(if (isTransfer) "刪除轉帳？" else "刪除交易？") },
            text = { Text(if (isTransfer) "將刪除此筆轉帳的所有分錄。" else "刪除後無法復原。") },
            confirmButton = {
                TextButton(onClick = {
                    transactionToDelete = null
                    scope.launch {
                        val result = repository.deleteLedgerTransactionById(target.transaction.id)
                        if (result == LedgerDeletionResult.AdvanceInitialRequiresCase) {
                            errorMessage = "這是代墊建立分錄，請進入代墊詳情刪除整個代墊案件。"
                        }
                    }
                }) { Text("刪除", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { transactionToDelete = null }) { Text("取消") }
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
            title = "選擇區間",
            description = "切換報表統計區間，日期選擇維持和 iOS 一樣的片段化流程。",
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
            allSubtitle = "查看所有時間的累積統計",
            yearSubtitle = "聚焦本年收入與支出",
            monthSubtitle = "查看本月分類與標籤分佈",
            daySubtitle = "只看當日收支"
        )
    }

    if (reportDetail != null) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { reportDetail = null },
            sheetState = sheetState,
            containerColor = MaterialTheme.colorScheme.background,
            dragHandle = { ParitySheetHandle() }
        ) {
            ReportDetailSheet(
                detail = reportDetail ?: return@ModalBottomSheet,
                onEdit = { tx ->
                    reportDetail = null
                    routeTransactionEdit(tx, onEdit, onEditTransfer, onEditDebt)
                },
                onDelete = { tx ->
                    transactionToDelete = tx
                }
            )
        }
    }
}

@Composable
private fun ReportRow(
    item: ReportChartSlice,
    total: BigDecimal,
    baseCurrency: String,
    trailingLabel: String,
    onClick: () -> Unit
) {
    val progress = if (total > BigDecimal.ZERO) {
        item.amount.divide(total, 4, RoundingMode.HALF_UP).toFloat().coerceIn(0f, 1f)
    } else 0f
    val percent = if (total > BigDecimal.ZERO) {
        item.amount.multiply(BigDecimal(100)).divide(total, 1, RoundingMode.HALF_UP)
    } else BigDecimal.ZERO
    PressableCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick
    ) {
        Column(
            modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(AppSpacing.tight)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                ColorDot(color = item.color)
	                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
	                    Text(item.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
	                    Text(
	                        "${percent.stripTrailingZeros().toPlainString()}% · ${item.transactions.size} 筆",
	                        style = MaterialTheme.typography.labelSmall,
	                        color = MaterialTheme.colorScheme.onSurfaceVariant
	                    )
	                    Text(
	                        item.originalCurrencySummary,
	                        style = MaterialTheme.typography.labelSmall,
	                        color = MaterialTheme.colorScheme.onSurfaceVariant,
	                        maxLines = 1
	                    )
	                }
	                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
	                    Text(
	                        "約 ${item.amount.asCurrencyText(baseCurrency)}",
	                        style = MaterialTheme.typography.bodyLarge,
	                        fontWeight = FontWeight.SemiBold,
	                        color = MaterialTheme.colorScheme.onSurface
	                    )
	                    Text(
	                        item.estimateFootnote?.let { "$trailingLabel · $it" } ?: trailingLabel,
	                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Medium,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
            LinearProgressIndicator(
                progress = { progress },
                color = item.color,
                trackColor = MaterialTheme.colorScheme.surfaceVariant,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(999.dp))
            )
        }
    }
}

@Composable
private fun DonutChart(data: List<ReportChartSlice>, baseCurrency: String, title: String) {
    val total = totalAmount(data)
    val trackColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.72f)
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceVariant,
        border = androidx.compose.foundation.BorderStroke(0.6.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.28f))
    ) {
        Column(
            modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 18.dp),
            verticalArrangement = Arrangement.spacedBy(AppSpacing.inline),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(contentAlignment = Alignment.Center) {
                Canvas(modifier = Modifier.size(228.dp)) {
                    val stroke = Stroke(width = 24.dp.toPx(), cap = StrokeCap.Butt)
                    val diameter = minOf(size.width, size.height)
                    val topLeft = Offset((size.width - diameter) / 2f, (size.height - diameter) / 2f)
                    val rect = Rect(topLeft, Size(diameter, diameter))
                    drawArc(
                        color = trackColor,
                        startAngle = 0f,
                        sweepAngle = 360f,
                        useCenter = false,
                        topLeft = rect.topLeft,
                        size = rect.size,
                        style = stroke
                    )
                    var startAngle = -90f
                    data.forEach { slice ->
                        val sweep = if (total > BigDecimal.ZERO) {
                            slice.amount.divide(total, 6, RoundingMode.HALF_UP).toFloat() * 360f
                        } else 0f
                        drawArc(
                            color = slice.color,
                            startAngle = startAngle,
                            sweepAngle = sweep,
                            useCenter = false,
                            topLeft = rect.topLeft,
                            size = rect.size,
                            style = stroke
                        )
                        startAngle += sweep
                    }
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(
                        total.asCurrencyText(baseCurrency),
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface,
                        textAlign = TextAlign.Center
                    )
                    Text(
                        "${data.size} 個項目",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@Composable
private fun ColorDot(color: Color) {
    Box(
        modifier = Modifier
            .size(16.dp)
            .background(color = color, shape = MaterialTheme.shapes.small)
    )
}

@Composable
private fun EmptyState(message: String) {
    ParityEmptyState(
        title = "暫時沒有可顯示的圖表",
        message = message
    )
}

@Composable
private fun BudgetAlertCard(alerts: List<BudgetAlert>) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.error.copy(alpha = 0.06f),
        border = androidx.compose.foundation.BorderStroke(0.6.dp, MaterialTheme.colorScheme.error.copy(alpha = 0.18f))
    ) {
        Column(
            modifier = Modifier.padding(AppSpacing.card),
            verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)
        ) {
            ParitySectionHeader(
                title = "本月超支提醒",
                detail = "${alerts.size} 個分類"
            )
            alerts.take(3).forEach { alert ->
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = MaterialTheme.shapes.medium,
                    color = MaterialTheme.colorScheme.background.copy(alpha = 0.82f)
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(
                                alert.categoryName,
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.SemiBold
                            )
                            Text(
                                "預算 ${alert.budget.amount.asCurrencyText(alert.budget.currencyCode)}",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        Text(
                            "超支 ${alert.remaining.abs().asCurrencyText(alert.budget.currencyCode)}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ReportDetailSheet(
    detail: ReportDetail,
    onEdit: (TransactionWithDetails) -> Unit,
    onDelete: (TransactionWithDetails) -> Unit
) {
    val grouped = remember(detail.transactions) {
        val formatter = DateTimeFormatter.ofPattern("yyyy/MM/dd (E)")
        detail.transactions.groupBy { tx ->
            tx.transaction.date.atZone(ZoneId.systemDefault()).toLocalDate().format(formatter)
        }.entries.sortedByDescending { it.key }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = AppSpacing.screenHorizontal, vertical = AppSpacing.screenVertical),
        verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)
    ) {
        ParitySectionHeader(
            title = detail.title,
            detail = "${detail.transactions.size} 筆"
        )
        ReportDetailSummaryCard(detail = detail)
        LazyColumn(
            contentPadding = PaddingValues(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)
        ) {
            grouped.forEach { (title, items) ->
                item {
                    Text(
                        title,
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 2.dp, vertical = 2.dp)
                    )
                }
                items(items, key = { it.transaction.id }) { tx ->
                    PressableCard(
                        modifier = Modifier.fillMaxWidth(),
                        onClick = { onEdit(tx) },
                        onLongClick = { onDelete(tx) },
                        containerColor = MaterialTheme.colorScheme.surfaceVariant,
                        pressedContainerColor = MaterialTheme.colorScheme.surface,
                        borderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.20f),
                        pressedBorderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.42f)
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 12.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(
                                modifier = Modifier.weight(1f),
                                verticalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                Text(
                                    tx.transaction.note.ifBlank { tx.category?.name ?: "未分類" },
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.SemiBold
                                )
                                Text(
                                    listOfNotNull(tx.category?.name, tx.account?.name)
                                        .joinToString(" · ")
                                        .ifBlank { "未分類" },
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                Text(
                                    tx.transaction.date.toDateText(),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                Text(
                                    "點擊編輯 · 長按刪除",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.primary
                                )
                            }
                            Text(
                                tx.transaction.amount.asCurrencyText(tx.transaction.currencyCode),
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.onSurface
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ReportDetailSummaryCard(detail: ReportDetail) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceVariant,
        border = androidx.compose.foundation.BorderStroke(
            0.6.dp,
            MaterialTheme.colorScheme.outline.copy(alpha = 0.24f)
        )
    ) {
        Column(
            modifier = Modifier.padding(AppSpacing.card),
            verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        "明細總額",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        "約 ${detail.estimatedAmount.asCurrencyText(detail.baseCurrency)}",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                }
                Surface(
                    shape = RoundedCornerShape(999.dp),
                    color = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)
                ) {
                    Text(
                        "${detail.transactions.size} 筆",
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    "原幣種合計",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    detail.originalCurrencySummary.ifBlank { "沒有金額資料" },
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.onSurface
                )
            }

            detail.estimateFootnote?.let { footnote ->
                Text(
                    footnote,
                    style = MaterialTheme.typography.labelSmall,
                    color = if (footnote == "估算不完整") {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    fontWeight = FontWeight.Medium
                )
            }
        }
    }
}

private fun routeTransactionEdit(
    item: TransactionWithDetails,
    onEdit: (String) -> Unit,
    onEditTransfer: (String) -> Unit,
    onEditDebt: (String) -> Unit
) {
    val groupId = item.transaction.transferGroupId?.toString()
    when {
        item.transaction.type == TransactionType.Transfer && TransactionSemantics.isDebtForgiveness(item.transaction.note) -> {
            onEditDebt(item.transaction.id.toString())
        }
        item.transaction.type == TransactionType.Transfer && groupId != null -> {
            onEditTransfer(groupId)
        }
        else -> {
            onEdit(item.transaction.id.toString())
        }
    }
}

private fun TransactionWithDetails.toReportSnapshot(): ReportTransactionSnapshot {
    return ReportTransactionSnapshot(
        id = transaction.id,
        amount = transaction.amount,
        currencyCode = transaction.currencyCode,
        date = transaction.date,
        type = transaction.type,
        categoryId = category?.id,
        categoryName = category?.name,
        categoryColorHex = category?.colorHex,
        tagNames = tags.map { it.name }
    )
}

private fun ReportAggregationResult.toChartSlices(
    transactionsById: Map<java.util.UUID, TransactionWithDetails>,
    chartMode: ReportChartMode
): List<ReportChartSlice> {
    return slices.mapIndexed { index, slice ->
        val detail = slice.detailSummary
        ReportChartSlice(
            key = slice.key,
            name = slice.name,
            amount = detail.estimatedAmount,
            color = when {
                slice.categoryColorHex != null -> parseColor(slice.categoryColorHex)
                chartMode == ReportChartMode.Tag -> generateDistinctColor(index)
                else -> parseColor("#90A4AE")
            },
            transactions = detail.transactionIds.mapNotNull(transactionsById::get),
            originalCurrencySummary = detail.originalCurrencyTotals.joinToString(" · ") {
                it.amount.asCurrencyText(it.currencyCode)
            },
            estimateFootnote = detail.estimateStatus.label
        )
    }
}

private fun totalAmount(data: List<ReportChartSlice>): BigDecimal {
    return data.fold(BigDecimal.ZERO) { acc, row -> acc + row.amount }
}

private fun presentTransactions(
    flowMode: ReportFlowMode,
    item: ReportChartSlice,
    tagName: String?,
    baseCurrency: String
): ReportDetail {
    val title = if (tagName != null) {
        "${flowMode.label}・$tagName・${item.name}"
    } else {
        "${flowMode.label}・${item.name}"
    }
    val sorted = item.transactions.sortedByDescending { it.transaction.date }
    return ReportDetail(
        title = title,
        estimatedAmount = item.amount,
        baseCurrency = baseCurrency,
        originalCurrencySummary = item.originalCurrencySummary,
        estimateFootnote = item.estimateFootnote,
        transactions = sorted
    )
}

private fun parseColor(hex: String): Color {
    return runCatching { Color(android.graphics.Color.parseColor(hex)) }
        .getOrElse { Color(0xFF90A4AE) }
}

private fun generateDistinctColor(index: Int): Color {
    val goldenRatio = 0.618033988749895
    val hue = ((index * goldenRatio) % 1.0).toFloat()
    return Color.hsv(hue * 360f, 0.75f, 0.95f)
}

private fun buildBudgetAlerts(
    budgets: List<CategoryMonthlyBudgetEntity>,
    categories: List<CategoryEntity>,
    transactions: List<TransactionWithDetails>,
    currencyService: org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService
): List<BudgetAlert> {
    if (budgets.isEmpty()) return emptyList()
    val monthKey = DateTimeFormatter.ofPattern("yyyy-MM").format(LocalDate.now())
    val range = resolveSharedDateRange(
        SharedDateFilterType.Month,
        LocalDate.now(),
        LocalDate.now(),
        LocalDate.now()
    )
    val (start, end) = range
    val monthTransactions = if (start != null && end != null) {
        transactions.filter { it.transaction.date >= start && it.transaction.date < end }
    } else transactions

    return budgets.filter { it.monthKey == monthKey && it.isEnabled }.mapNotNull { budget ->
        val spent = monthTransactions.filter {
            it.transaction.type == TransactionType.Expense && it.transaction.categoryId == budget.categoryId
        }.fold(BigDecimal.ZERO) { acc, tx ->
            acc + currencyService.convert(tx.transaction.amount.abs(), tx.transaction.currencyCode, budget.currencyCode)
        }
        val remaining = budget.amount - spent
        if (remaining < BigDecimal.ZERO) {
            val name = categories.firstOrNull { it.id == budget.categoryId }?.name ?: "未分類"
            BudgetAlert(budget = budget, remaining = remaining, categoryName = name)
        } else null
    }
}
