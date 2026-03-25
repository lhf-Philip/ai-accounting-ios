package org.duckdns.lhfser.aiaccounting.ui.screens

import android.app.DatePickerDialog
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.ReceiptLong
import androidx.compose.material.icons.filled.PieChart
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.ui.LocalCurrencyService
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.PressableCard
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing

private enum class OverviewFilterType(val label: String) {
    All("全部"),
    Year("本年"),
    Month("本月"),
    Day("今日")
}

private val OverviewFilterShape = RoundedCornerShape(18.dp)

@Composable
fun OverviewScreen(
    onQuickAdd: () -> Unit,
    onOpenGuide: () -> Unit,
    onOpenLedger: () -> Unit,
    onOpenReports: () -> Unit,
    onOpenAccounts: () -> Unit
) {
    val repository = LocalRepository.current
    val currencyService = LocalCurrencyService.current
    val context = LocalContext.current
    val scrollState = rememberScrollState()

    val transactions by repository.transactions.collectAsState(initial = emptyList())
    val advanceCases by repository.advanceCases.collectAsState(initial = emptyList())

    var filterType by remember { mutableStateOf(OverviewFilterType.Month) }
    var selectedDate by remember { mutableStateOf(LocalDate.now()) }
    var showFilterDialog by remember { mutableStateOf(false) }

    val filteredTransactions = remember(transactions, filterType, selectedDate) {
        filterTransactions(transactions, filterType, selectedDate)
    }
    val filteredAdvanceCases = remember(advanceCases, filterType, selectedDate) {
        filterAdvanceCases(advanceCases, filterType, selectedDate)
    }

    val baseCurrency = currencyService.mainCurrency
    val incomeTotal = filteredTransactions.filter { it.transaction.type == TransactionType.Income }
        .fold(BigDecimal.ZERO) { acc, tx ->
            acc + currencyService.convert(tx.transaction.amount.abs(), tx.transaction.currencyCode, baseCurrency)
        }
    val expenseTotal = filteredTransactions.filter { it.transaction.type == TransactionType.Expense }
        .fold(BigDecimal.ZERO) { acc, tx ->
            acc + currencyService.convert(tx.transaction.amount.abs(), tx.transaction.currencyCode, baseCurrency)
        }
    val netTotal = incomeTotal - expenseTotal
    val recordCount = filteredTransactions.count { it.transaction.type != TransactionType.Transfer }
    val outstandingAdvance = filteredAdvanceCases.fold(BigDecimal.ZERO) { acc, advanceCase ->
        acc + currencyService.convert(outstandingAmount(advanceCase), advanceCase.advanceCase.currencyCode, baseCurrency)
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(scrollState)
            .padding(horizontal = AppSpacing.screenHorizontal, vertical = AppSpacing.screenVertical),
        verticalArrangement = Arrangement.spacedBy(AppSpacing.section)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.tight)) {
            Text("歡迎使用 AI 記帳", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(
                "今天是 ${LocalDate.now().format(DateTimeFormatter.ofPattern("yyyy年 M月d日"))}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                "${filterDisplayString(filterType, selectedDate)}已記錄 $recordCount 筆收入/支出",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Surface(
                modifier = Modifier.clickable { showFilterDialog = true },
                shape = OverviewFilterShape,
                color = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f),
                border = BorderStroke(0.8.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.12f))
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        filterDisplayString(filterType, selectedDate),
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OverviewFilterType.values().forEach { type ->
                    FilterChip(
                        selected = filterType == type,
                        onClick = { filterType = type },
                        label = { Text(type.label) }
                    )
                }
            }
        }

        PressableCard(
            modifier = Modifier.fillMaxWidth(),
            onClick = onQuickAdd,
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
            pressedContainerColor = MaterialTheme.colorScheme.surface
        ) {
            Column(modifier = Modifier.padding(AppSpacing.card), verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)) {
                Text("快速開始", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button(
                        onClick = onQuickAdd,
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary),
                        modifier = Modifier
                            .weight(1f)
                            .height(48.dp)
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ReceiptLong, contentDescription = null)
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("新增記錄")
                    }
                    Button(
                        onClick = onOpenGuide,
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.surface),
                        modifier = Modifier
                            .weight(1f)
                            .height(48.dp)
                    ) {
                        Icon(Icons.Default.Book, contentDescription = null)
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("使用教學")
                    }
                }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)) {
            Text(
                "${filterDisplayString(filterType, selectedDate)}重點（$baseCurrency）",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SummaryTile(label = "收入", value = incomeTotal.asCurrencyText(baseCurrency), tint = Color(0xFF2E7D32), modifier = Modifier.weight(1f))
                SummaryTile(label = "支出", value = expenseTotal.asCurrencyText(baseCurrency), tint = Color(0xFFC62828), modifier = Modifier.weight(1f))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SummaryTile(label = "淨收支", value = netTotal.asCurrencyText(baseCurrency), tint = if (netTotal >= BigDecimal.ZERO) Color(0xFF1565C0) else Color(0xFFF57C00), modifier = Modifier.weight(1f))
                SummaryTile(label = "代墊待收", value = outstandingAdvance.asCurrencyText(baseCurrency), tint = Color(0xFF6A5ACD), modifier = Modifier.weight(1f))
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)) {
            Text("功能入口", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            EntryButton(
                icon = Icons.AutoMirrored.Filled.List,
                title = "查看帳目明細",
                subtitle = "搜尋、篩選、編輯所有交易",
                onClick = onOpenLedger
            )
            EntryButton(
                icon = Icons.Default.PieChart,
                title = "查看收支報表",
                subtitle = "依分類與標籤分析收入/支出",
                onClick = onOpenReports
            )
            EntryButton(
                icon = Icons.Default.AccountBalanceWallet,
                title = "管理帳戶",
                subtitle = "查看資產估算與各幣別餘額",
                onClick = onOpenAccounts
            )
        }
    }

    if (showFilterDialog) {
        DatePickerDialog(
            context,
            { _, year, month, day ->
                selectedDate = LocalDate.of(year, month + 1, day)
            },
            selectedDate.year,
            selectedDate.monthValue - 1,
            selectedDate.dayOfMonth
        ).show()
        showFilterDialog = false
    }
}

@Composable
private fun SummaryTile(label: String, value: String, tint: Color, modifier: Modifier = Modifier) {
    PressableCard(
        modifier = modifier,
        onClick = {},
        containerColor = tint.copy(alpha = 0.08f),
        pressedContainerColor = tint.copy(alpha = 0.12f),
        borderColor = tint.copy(alpha = 0.12f),
        pressedBorderColor = tint.copy(alpha = 0.2f)
    ) {
        Column(modifier = Modifier.padding(AppSpacing.card), verticalArrangement = Arrangement.spacedBy(AppSpacing.tight)) {
            Text(
                label,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = tint)
        }
    }
}

@Composable
private fun EntryButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit
) {
    PressableCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick,
        containerColor = MaterialTheme.colorScheme.surfaceVariant,
        pressedContainerColor = MaterialTheme.colorScheme.surface
    ) {
        Row(
            modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(
                icon,
                contentDescription = null,
                modifier = Modifier.size(22.dp),
                tint = MaterialTheme.colorScheme.primary
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Text(subtitle, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Icon(Icons.Default.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private fun filterTransactions(
    transactions: List<TransactionWithDetails>,
    filterType: OverviewFilterType,
    selectedDate: LocalDate
): List<TransactionWithDetails> {
    val zone = ZoneId.systemDefault()
    return transactions.filter { tx ->
        val date = tx.transaction.date.atZone(zone).toLocalDate()
        when (filterType) {
            OverviewFilterType.All -> true
            OverviewFilterType.Year -> date.year == selectedDate.year
            OverviewFilterType.Month -> date.year == selectedDate.year && date.month == selectedDate.month
            OverviewFilterType.Day -> date == selectedDate
        }
    }
}

private fun filterAdvanceCases(
    advanceCases: List<AdvanceCaseWithDetails>,
    filterType: OverviewFilterType,
    selectedDate: LocalDate
): List<AdvanceCaseWithDetails> {
    val zone = ZoneId.systemDefault()
    return advanceCases.filter { advanceCase ->
        val date = advanceCase.advanceCase.date.atZone(zone).toLocalDate()
        when (filterType) {
            OverviewFilterType.All -> true
            OverviewFilterType.Year -> date.year == selectedDate.year
            OverviewFilterType.Month -> date.year == selectedDate.year && date.month == selectedDate.month
            OverviewFilterType.Day -> date == selectedDate
        }
    }
}

private fun outstandingAmount(advanceCase: AdvanceCaseWithDetails): BigDecimal {
    return advanceCase.participants.fold(BigDecimal.ZERO) { acc, participant ->
        val remaining = (participant.owedAmount - participant.repaidAmount).max(BigDecimal.ZERO)
        acc + remaining
    }.setScale(2, RoundingMode.HALF_UP)
}

private fun filterDisplayString(type: OverviewFilterType, date: LocalDate): String {
    return when (type) {
        OverviewFilterType.All -> "全部"
        OverviewFilterType.Year -> "${date.year}年"
        OverviewFilterType.Month -> date.format(DateTimeFormatter.ofPattern("yyyy年 M月"))
        OverviewFilterType.Day -> date.format(DateTimeFormatter.ofPattern("M月d日"))
    }
}
