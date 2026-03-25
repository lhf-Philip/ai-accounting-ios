package org.duckdns.lhfser.aiaccounting.ui.screens

import android.app.DatePickerDialog
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.shape.RoundedCornerShape
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryMonthlyBudgetEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.ui.LocalCurrencyService
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.PressableCard
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateText
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private enum class ReportFilterType(val label: String) {
    All("全部時間"),
    Year("本年"),
    Month("本月"),
    Day("今日")
}

private enum class ReportChartMode(val label: String) {
    Category("依分類"),
    Tag("依標籤")
}

private enum class ReportFlowMode(val label: String, val type: TransactionType) {
    Expense("支出", TransactionType.Expense),
    Income("收入", TransactionType.Income)
}

private data class ReportSlice(
    val key: String,
    val name: String,
    val amount: BigDecimal,
    val color: Color,
    val transactions: List<TransactionWithDetails>
)

private data class ReportDetail(
    val title: String,
    val transactions: List<TransactionWithDetails>
)

private data class BudgetAlert(
    val budget: CategoryMonthlyBudgetEntity,
    val remaining: BigDecimal,
    val categoryName: String
)

private val ReportFilterShape = RoundedCornerShape(18.dp)

@Composable
@OptIn(ExperimentalMaterial3Api::class)
fun ReportsScreen() {
    val repository = LocalRepository.current
    val currencyService = LocalCurrencyService.current
    val context = LocalContext.current

    val transactions by repository.transactions.collectAsState(initial = emptyList())
    val categories by repository.categories.collectAsState(initial = emptyList())
    val budgets by repository.budgets.collectAsState(initial = emptyList())

    var filterType by remember { mutableStateOf(ReportFilterType.Month) }
    var selectedDate by remember { mutableStateOf(LocalDate.now()) }
    var showFilterDialog by remember { mutableStateOf(false) }
    var chartMode by remember { mutableStateOf(ReportChartMode.Category) }
    var flowMode by remember { mutableStateOf(ReportFlowMode.Expense) }
    var selectedTag by remember { mutableStateOf<String?>(null) }
    var reportDetail by remember { mutableStateOf<ReportDetail?>(null) }

    val (rangeStart, rangeEnd) = remember(filterType, selectedDate) {
        resolveDateRange(filterType, selectedDate)
    }
    val filteredTransactions = remember(transactions, flowMode, rangeStart, rangeEnd) {
        filterTransactions(transactions, flowMode.type, rangeStart, rangeEnd)
    }
    val baseCurrency = currencyService.mainCurrency

    val chartData = remember(filteredTransactions, categories, chartMode, baseCurrency) {
        when (chartMode) {
            ReportChartMode.Category -> categoryBreakdown(filteredTransactions, categories, currencyService, baseCurrency)
            ReportChartMode.Tag -> tagBreakdown(filteredTransactions, currencyService, baseCurrency)
        }
    }

    val tagDetailData = remember(filteredTransactions, categories, selectedTag, baseCurrency) {
        if (chartMode == ReportChartMode.Tag && selectedTag != null) {
            categoryBreakdown(
                transactions = filteredTransactions.filter { tx ->
                    if (selectedTag == "無標籤") tx.tags.isEmpty() else tx.tags.any { it.name == selectedTag }
                },
                categories = categories,
                currencyService = currencyService,
                baseCurrency = baseCurrency
            )
        } else emptyList()
    }

    val budgetAlerts = remember(budgets, categories, filteredTransactions, currencyService) {
        buildBudgetAlerts(budgets, categories, filteredTransactions, currencyService)
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = AppSpacing.screenHorizontal, vertical = AppSpacing.screenVertical),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Surface(
                    modifier = Modifier.clickable { showFilterDialog = true },
                    shape = ReportFilterShape,
                    color = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f),
                    border = BorderStroke(0.8.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.12f))
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Icon(Icons.Default.DateRange, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                        Text(
                            filterLabel(filterType, selectedDate),
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.primary
                        )
                    }
                }
                Spacer(modifier = Modifier.weight(1f))
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(AppSpacing.inline)
            ) {
                SegmentedOptionGroup(
                    modifier = Modifier.weight(1f),
                    options = ReportFlowMode.values().toList(),
                    selected = flowMode,
                    label = { it.label },
                    onSelect = {
                        flowMode = it
                        selectedTag = null
                    }
                )
                SegmentedOptionGroup(
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

        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(
                horizontal = AppSpacing.screenHorizontal,
                vertical = AppSpacing.screenVertical
            ),
            verticalArrangement = Arrangement.spacedBy(AppSpacing.item)
        ) {
            if (chartMode == ReportChartMode.Tag && selectedTag != null) {
                item {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        IconButton(onClick = { selectedTag = null }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                        }
                        Text(
                            selectedTag ?: "",
                            style = MaterialTheme.typography.titleSmall,
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
                                tagName = selectedTag
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
                                reportDetail = presentTransactions(flowMode, item, null)
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

    if (showFilterDialog) {
        AlertDialog(
            onDismissRequest = { showFilterDialog = false },
            title = { Text("選擇區間") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    ReportFilterType.values().forEach { type ->
                        TextButton(onClick = { filterType = type }) {
                            Text(type.label)
                        }
                    }
                    Spacer(modifier = Modifier.height(6.dp))
                    TextButton(onClick = {
                        showDatePicker(context, selectedDate) { selectedDate = it }
                    }) {
                        Text(selectedDate.format(DateTimeFormatter.ISO_DATE))
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showFilterDialog = false }) { Text("完成") }
            }
        )
    }

    if (reportDetail != null) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { reportDetail = null },
            sheetState = sheetState
        ) {
            ReportDetailSheet(detail = reportDetail ?: return@ModalBottomSheet)
        }
    }
}

@Composable
private fun <T> SegmentedOptionGroup(
    modifier: Modifier = Modifier,
    options: List<T>,
    selected: T,
    label: (T) -> String,
    onSelect: (T) -> Unit
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(14.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
        border = BorderStroke(0.6.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.24f))
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(4.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            options.forEach { option ->
                val isSelected = option == selected
                Surface(
                    modifier = Modifier.weight(1f),
                    onClick = { onSelect(option) },
                    shape = RoundedCornerShape(10.dp),
                    color = if (isSelected) {
                        MaterialTheme.colorScheme.primaryContainer
                    } else {
                        Color.Transparent
                    }
                ) {
                    Text(
                        text = label(option),
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 10.dp),
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Medium,
                        color = if (isSelected) {
                            MaterialTheme.colorScheme.onPrimaryContainer
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        },
                        textAlign = TextAlign.Center,
                        maxLines = 1
                    )
                }
            }
        }
    }
}

@Composable
private fun ReportRow(
    item: ReportSlice,
    total: BigDecimal,
    baseCurrency: String,
    trailingLabel: String,
    onClick: () -> Unit
) {
    val progress = if (total > BigDecimal.ZERO) {
        item.amount.divide(total, 4, RoundingMode.HALF_UP).toFloat().coerceIn(0f, 1f)
    } else 0f
    PressableCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick
    ) {
        Column(
            modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(AppSpacing.tight)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ColorDot(color = item.color)
                Column(modifier = Modifier.weight(1f)) {
                    Text(item.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    Text(
                        item.amount.asCurrencyText(baseCurrency),
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                }
                Text(
                    trailingLabel,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.primary
                )
            }
            LinearProgressIndicator(progress = { progress }, color = item.color, trackColor = MaterialTheme.colorScheme.surface)
        }
    }
}

@Composable
private fun DonutChart(data: List<ReportSlice>, baseCurrency: String, title: String) {
    val total = totalAmount(data)
    Column(
        verticalArrangement = Arrangement.spacedBy(AppSpacing.inline),
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.padding(top = 4.dp)
    ) {
        Box(contentAlignment = Alignment.Center) {
            Canvas(modifier = Modifier.size(212.dp)) {
                val stroke = Stroke(width = 22.dp.toPx(), cap = StrokeCap.Butt)
                val diameter = minOf(size.width, size.height)
                val topLeft = Offset((size.width - diameter) / 2f, (size.height - diameter) / 2f)
                val rect = Rect(topLeft, Size(diameter, diameter))
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
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(
                    total.asCurrencyText(baseCurrency),
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface
                )
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
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun BudgetAlertCard(alerts: List<BudgetAlert>) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.error.copy(alpha = 0.06f), shape = MaterialTheme.shapes.medium)
            .padding(AppSpacing.card),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text("本月超支提醒", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        alerts.take(3).forEach { alert ->
            Row {
                Text(alert.categoryName, style = MaterialTheme.typography.bodySmall)
                Spacer(modifier = Modifier.weight(1f))
                Text(
                    "超支 ${alert.remaining.abs().asCurrencyText(alert.budget.currencyCode)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }
        }
    }
}

@Composable
private fun ReportDetailSheet(detail: ReportDetail) {
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
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(detail.title, style = MaterialTheme.typography.titleMedium)
        LazyColumn(
            contentPadding = PaddingValues(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            grouped.forEach { (title, items) ->
                item {
                    Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                items(items) { tx ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(tx.transaction.note.ifBlank { tx.category?.name ?: "未分類" }, style = MaterialTheme.typography.bodyMedium)
                            Text(tx.transaction.date.toDateText(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Text(
                            tx.transaction.amount.asCurrencyText(tx.transaction.currencyCode),
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
            }
        }
    }
}

private fun filterLabel(filterType: ReportFilterType, selectedDate: LocalDate): String {
    return when (filterType) {
        ReportFilterType.All -> "全部時間"
        ReportFilterType.Year -> "${selectedDate.year}年"
        ReportFilterType.Month -> selectedDate.format(DateTimeFormatter.ofPattern("yyyy年 M月"))
        ReportFilterType.Day -> selectedDate.format(DateTimeFormatter.ofPattern("M月d日"))
    }
}

private fun resolveDateRange(type: ReportFilterType, date: LocalDate): Pair<Instant?, Instant?> {
    val zone = ZoneId.systemDefault()
    return when (type) {
        ReportFilterType.All -> null to null
        ReportFilterType.Year -> {
            val start = LocalDate.of(date.year, 1, 1).atStartOfDay(zone).toInstant()
            val end = LocalDate.of(date.year + 1, 1, 1).atStartOfDay(zone).toInstant()
            start to end
        }
        ReportFilterType.Month -> {
            val start = date.withDayOfMonth(1).atStartOfDay(zone).toInstant()
            val end = date.withDayOfMonth(1).plusMonths(1).atStartOfDay(zone).toInstant()
            start to end
        }
        ReportFilterType.Day -> {
            val start = date.atStartOfDay(zone).toInstant()
            val end = date.plusDays(1).atStartOfDay(zone).toInstant()
            start to end
        }
    }
}

private fun filterTransactions(
    transactions: List<TransactionWithDetails>,
    type: TransactionType,
    rangeStart: Instant?,
    rangeEnd: Instant?
): List<TransactionWithDetails> {
    return transactions.filter { tx ->
        if (tx.transaction.type != type) return@filter false
        val date = tx.transaction.date
        val inRange = when {
            rangeStart == null || rangeEnd == null -> true
            else -> date >= rangeStart && date < rangeEnd
        }
        inRange
    }
}

private fun categoryBreakdown(
    transactions: List<TransactionWithDetails>,
    categories: List<CategoryEntity>,
    currencyService: org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService,
    baseCurrency: String
): List<ReportSlice> {
    val grouped = transactions.groupBy { it.category?.id }
    return grouped.mapNotNull { (categoryId, items) ->
        val category = categories.firstOrNull { it.id == categoryId }
        val total = items.fold(BigDecimal.ZERO) { acc, tx ->
            acc + currencyService.convert(tx.transaction.amount.abs(), tx.transaction.currencyCode, baseCurrency)
        }
        ReportSlice(
            key = categoryId?.toString() ?: "uncategorized",
            name = category?.name ?: "未分類",
            amount = total,
            color = parseColor(category?.colorHex ?: "#90A4AE"),
            transactions = items
        )
    }.sortedByDescending { it.amount }
}

private fun tagBreakdown(
    transactions: List<TransactionWithDetails>,
    currencyService: org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService,
    baseCurrency: String
): List<ReportSlice> {
    val tagTotals = mutableMapOf<String, BigDecimal>()
    val tagTransactions = mutableMapOf<String, MutableList<TransactionWithDetails>>()
    transactions.forEach { tx ->
        val amount = currencyService.convert(tx.transaction.amount.abs(), tx.transaction.currencyCode, baseCurrency)
        if (tx.tags.isEmpty()) {
            tagTotals["無標籤"] = (tagTotals["無標籤"] ?: BigDecimal.ZERO) + amount
            tagTransactions.getOrPut("無標籤") { mutableListOf() }.add(tx)
        } else {
            tx.tags.forEach { tag ->
                tagTotals[tag.name] = (tagTotals[tag.name] ?: BigDecimal.ZERO) + amount
                tagTransactions.getOrPut(tag.name) { mutableListOf() }.add(tx)
            }
        }
    }
    val sorted = tagTotals.entries.sortedByDescending { it.value }
    return sorted.mapIndexed { index, entry ->
        ReportSlice(
            key = entry.key,
            name = entry.key,
            amount = entry.value,
            color = generateDistinctColor(index),
            transactions = tagTransactions[entry.key]?.toList().orEmpty()
        )
    }
}

private fun totalAmount(data: List<ReportSlice>): BigDecimal {
    return data.fold(BigDecimal.ZERO) { acc, row -> acc + row.amount }
}

private fun presentTransactions(
    flowMode: ReportFlowMode,
    item: ReportSlice,
    tagName: String?
): ReportDetail {
    val title = if (tagName != null) {
        "${flowMode.label}・$tagName・${item.name}"
    } else {
        "${flowMode.label}・${item.name}"
    }
    val sorted = item.transactions.sortedByDescending { it.transaction.date }
    return ReportDetail(title = title, transactions = sorted)
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
    val range = resolveDateRange(ReportFilterType.Month, LocalDate.now())
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

private fun showDatePicker(context: android.content.Context, initial: LocalDate, onPicked: (LocalDate) -> Unit) {
    DatePickerDialog(
        context,
        { _, year, month, day ->
            onPicked(LocalDate.of(year, month + 1, day))
        },
        initial.year,
        initial.monthValue - 1,
        initial.dayOfMonth
    ).show()
}
