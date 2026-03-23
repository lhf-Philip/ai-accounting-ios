package org.duckdns.lhfser.aiaccounting.ui.screens

import android.app.DatePickerDialog
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID
import kotlinx.coroutines.launch
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryMonthlyBudgetEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.ui.LocalCurrencyService
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyButtonStyle
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyPicker
import org.duckdns.lhfser.aiaccounting.ui.components.PressableCard
import org.duckdns.lhfser.aiaccounting.ui.components.SectionHeader
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing

private data class BudgetStatus(
    val budget: CategoryMonthlyBudgetEntity,
    val spent: BigDecimal,
    val remaining: BigDecimal,
    val ratio: BigDecimal,
    val categoryName: String
) {
    val isOverBudget: Boolean = remaining < BigDecimal.ZERO
}

@Composable
fun BudgetsScreen() {
    val repository = LocalRepository.current
    val currencyService = LocalCurrencyService.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val budgets by repository.budgets.collectAsState(initial = emptyList())
    val categories by repository.categories.collectAsState(initial = emptyList())
    val transactions by repository.transactions.collectAsState(initial = emptyList())

    val expenseCategories = categories.filter { it.kind.supports(TransactionType.Expense) }

    var selectedMonthDate by remember { mutableStateOf(LocalDate.now().withDayOfMonth(1)) }
    var showingOnlyAlerts by remember { mutableStateOf(false) }
    var selectedCategory by remember { mutableStateOf<CategoryEntity?>(null) }
    var amount by remember { mutableStateOf("") }
    var currency by remember { mutableStateOf(currencyService.mainCurrency) }
    var isEnabled by remember { mutableStateOf(true) }
    var editingBudget by remember { mutableStateOf<CategoryMonthlyBudgetEntity?>(null) }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var budgetToDelete by remember { mutableStateOf<CategoryMonthlyBudgetEntity?>(null) }

    val monthKey = monthKeyFromDate(selectedMonthDate)
    val statuses = remember(budgets, transactions, categories, currencyService, monthKey) {
        buildBudgetStatuses(budgets, transactions, categories, currencyService, monthKey)
    }
    val visibleStatuses = if (showingOnlyAlerts) {
        statuses.filter { it.ratio >= BigDecimal.ONE }
    } else statuses

    LaunchedEffect(editingBudget, expenseCategories) {
        if (editingBudget == null) {
            selectedCategory = null
            amount = ""
            currency = currencyService.mainCurrency
            isEnabled = true
            return@LaunchedEffect
        }
        val target = editingBudget ?: return@LaunchedEffect
        selectedCategory = expenseCategories.firstOrNull { it.id == target.categoryId }
        amount = target.amount.toPlainString()
        currency = target.currencyCode
        isEnabled = target.isEnabled
    }

    LazyColumn(
        modifier = Modifier.padding(horizontal = AppSpacing.screenHorizontal, vertical = AppSpacing.screenVertical),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(bottom = 20.dp)
    ) {
        item {
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier.padding(AppSpacing.card),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text("月份", style = MaterialTheme.typography.titleSmall)
                    TextButton(onClick = {
                        showMonthPicker(context, selectedMonthDate) { picked ->
                            selectedMonthDate = picked
                        }
                    }) {
                        Text(formatMonth(selectedMonthDate))
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("只顯示提醒", style = MaterialTheme.typography.titleSmall)
                            Text("僅顯示超支分類", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Switch(checked = showingOnlyAlerts, onCheckedChange = { showingOnlyAlerts = it })
                    }
                }
            }
        }

        item {
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier.padding(AppSpacing.card),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text(if (editingBudget == null) "新增預算" else "編輯預算", style = MaterialTheme.typography.titleSmall)
                    CategoryPicker(categories = expenseCategories, selected = selectedCategory) { selectedCategory = it }
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        CurrencyPicker(
                            selected = currency,
                            onSelect = { currency = it },
                            buttonStyle = CurrencyButtonStyle.Tonal
                        )
                        OutlinedTextField(
                            value = amount,
                            onValueChange = { amount = sanitizeAmount(it) },
                            label = { Text("預算金額") },
                            modifier = Modifier.weight(1f)
                        )
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("啟用", style = MaterialTheme.typography.titleSmall)
                            Text("暫停後不會觸發提醒", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Switch(checked = isEnabled, onCheckedChange = { isEnabled = it })
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = {
                                scope.launch {
                                    val category = selectedCategory ?: return@launch
                                    val amountValue = amount.toBigDecimalOrNull()?.takeIf { it > BigDecimal.ZERO } ?: return@launch
                                    val existing = editingBudget
                                    val duplicate = budgets.firstOrNull { budget ->
                                        budget.id != existing?.id &&
                                            budget.monthKey == monthKey &&
                                            budget.categoryId == category.id
                                    }
                                    val now = Instant.now()
                                    repository.upsertBudget(
                                        CategoryMonthlyBudgetEntity(
                                            id = existing?.id ?: duplicate?.id ?: UUID.randomUUID(),
                                            monthKey = monthKey,
                                            amount = amountValue,
                                            currencyCode = currency,
                                            isEnabled = isEnabled,
                                            createdAt = existing?.createdAt ?: now,
                                            updatedAt = now,
                                            categoryId = category.id
                                        )
                                    )
                                    editingBudget = null
                                    amount = ""
                                }
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(if (editingBudget == null) "儲存" else "更新")
                        }
                        if (editingBudget != null) {
                            TextButton(onClick = { editingBudget = null }) {
                                Text("取消編輯")
                            }
                        }
                    }
                }
            }
        }

        item {
            SectionHeader(title = "分類預算")
        }

        if (visibleStatuses.isEmpty()) {
            item {
                EmptyState(message = "本月無預算，請先新增分類月預算。")
            }
        } else {
            items(visibleStatuses) { status ->
                BudgetRow(
                    status = status,
                    onClick = { editingBudget = status.budget },
                    onLongClick = {
                        budgetToDelete = status.budget
                        showDeleteConfirm = true
                    }
                )
            }
        }
    }

    if (showDeleteConfirm && budgetToDelete != null) {
        val target = budgetToDelete ?: return
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("刪除預算？") },
            text = { Text("刪除後無法復原。") },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    scope.launch {
                        repository.deleteBudget(target)
                    }
                }) { Text("刪除", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("取消") }
            }
        )
    }
}

@Composable
private fun BudgetRow(status: BudgetStatus, onClick: () -> Unit, onLongClick: () -> Unit) {
    val progress = status.ratio
        .coerceIn(BigDecimal.ZERO, BigDecimal("1.5"))
        .toFloat()
        .coerceIn(0f, 1.5f)
    val color = when {
        status.isOverBudget -> MaterialTheme.colorScheme.error
        status.ratio >= BigDecimal("0.85") -> Color(0xFFFF9800)
        else -> Color(0xFF2E7D32)
    }

    PressableCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick,
        onLongClick = onLongClick
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    status.categoryName,
                    style = MaterialTheme.typography.bodyLarge,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                Text(
                    status.spent.asCurrencyText(status.budget.currencyCode),
                    style = MaterialTheme.typography.bodySmall,
                    color = if (status.isOverBudget) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface
                )
            }
            LinearProgressIndicator(
                progress = { progress.coerceIn(0f, 1f) },
                color = color,
                trackColor = MaterialTheme.colorScheme.surface
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "預算：${status.budget.amount.asCurrencyText(status.budget.currencyCode)}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.weight(1f))
                if (status.isOverBudget) {
                    Text(
                        "超支：${status.remaining.abs().asCurrencyText(status.budget.currencyCode)}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.error
                    )
                } else {
                    Text(
                        "剩餘：${status.remaining.asCurrencyText(status.budget.currencyCode)}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@Composable
private fun CategoryPicker(
    categories: List<CategoryEntity>,
    selected: CategoryEntity?,
    onSelect: (CategoryEntity?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("分類", style = MaterialTheme.typography.titleSmall)
        TextButton(onClick = { expanded = true }) { Text(selected?.name ?: "選擇分類") }
        androidx.compose.material3.DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            categories.forEach { category ->
                androidx.compose.material3.DropdownMenuItem(text = { Text(category.name) }, onClick = {
                    expanded = false
                    onSelect(category)
                })
            }
        }
    }
}

@Composable
private fun EmptyState(message: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private fun buildBudgetStatuses(
    budgets: List<CategoryMonthlyBudgetEntity>,
    transactions: List<TransactionWithDetails>,
    categories: List<CategoryEntity>,
    currencyService: org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService,
    monthKey: String
): List<BudgetStatus> {
    val monthStart = monthStartFromKey(monthKey)
    val monthEnd = monthStart.plusMonths(1)
    val start = monthStart.atStartOfDay(ZoneId.systemDefault()).toInstant()
    val end = monthEnd.atStartOfDay(ZoneId.systemDefault()).toInstant()

    val monthTransactions = transactions.filter { tx ->
        tx.transaction.type == TransactionType.Expense &&
            tx.transaction.date >= start &&
            tx.transaction.date < end
    }

    return budgets.filter { it.monthKey == monthKey && it.isEnabled }.map { budget ->
        val spent = monthTransactions.filter { it.transaction.categoryId == budget.categoryId }
            .fold(BigDecimal.ZERO) { acc, tx ->
                acc + currencyService.convert(tx.transaction.amount.abs(), tx.transaction.currencyCode, budget.currencyCode)
            }
        val remaining = budget.amount - spent
        val ratio = if (budget.amount > BigDecimal.ZERO) {
            spent.divide(budget.amount, 4, RoundingMode.HALF_UP)
        } else BigDecimal.ZERO
        val categoryName = categories.firstOrNull { it.id == budget.categoryId }?.name ?: "未分類"
        BudgetStatus(
            budget = budget,
            spent = spent,
            remaining = remaining,
            ratio = ratio,
            categoryName = categoryName
        )
    }.sortedByDescending { it.ratio }
}

private fun monthKeyFromDate(date: LocalDate): String {
    return DateTimeFormatter.ofPattern("yyyy-MM").format(date)
}

private fun monthStartFromKey(key: String): LocalDate {
    return LocalDate.parse("$key-01", DateTimeFormatter.ofPattern("yyyy-MM-dd"))
}

private fun formatMonth(date: LocalDate): String {
    return date.format(DateTimeFormatter.ofPattern("yyyy年 M月"))
}

private fun showMonthPicker(context: android.content.Context, initial: LocalDate, onPicked: (LocalDate) -> Unit) {
    DatePickerDialog(
        context,
        { _, year, month, _ ->
            onPicked(LocalDate.of(year, month + 1, 1))
        },
        initial.year,
        initial.monthValue - 1,
        1
    ).show()
}

private fun sanitizeAmount(input: String): String {
    val allowed = input.filter { it.isDigit() || it == '.' }
    var hasDot = false
    val result = StringBuilder()
    for (char in allowed) {
        if (char == '.') {
            if (hasDot) continue
            hasDot = true
        }
        result.append(char)
    }
    return result.toString()
}
