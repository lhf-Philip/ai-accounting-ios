package org.duckdns.lhfser.aiaccounting.ui.screens

import android.app.DatePickerDialog
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.duckdns.lhfser.aiaccounting.core.ai.BudgetSuggestionItem
import org.duckdns.lhfser.aiaccounting.core.ai.BudgetSuggestionRequest
import org.duckdns.lhfser.aiaccounting.core.ai.BudgetSuggestionService
import org.duckdns.lhfser.aiaccounting.core.ai.GeminiSettingsStore
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.backup.BackupJsonAdapter
import org.duckdns.lhfser.aiaccounting.data.backup.FullBackupData
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryMonthlyBudgetEntity
import org.duckdns.lhfser.aiaccounting.data.db.BudgetMonthlyHistoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.BudgetSettingsEntity
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

private data class BudgetForecast(
    val projectedSpent: BigDecimal,
    val projectedRemaining: BigDecimal,
    val projectedRatio: BigDecimal
) {
    val isProjectedOverBudget: Boolean = projectedRemaining < BigDecimal.ZERO
}

@Composable
fun BudgetsScreen() {
    val repository = LocalRepository.current
    val currencyService = LocalCurrencyService.current
    val context = LocalContext.current
    val geminiSettingsStore = remember(context) { GeminiSettingsStore(context) }
    val budgetSuggestionService = remember(context, currencyService) {
        BudgetSuggestionService(geminiSettingsStore, currencyService)
    }
    val scope = rememberCoroutineScope()

    val budgets by repository.budgets.collectAsState(initial = emptyList())
    val budgetHistories by repository.budgetHistories.collectAsState(initial = emptyList())
    val budgetSettings by repository.budgetSettings.collectAsState(initial = null)
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
    var message by remember { mutableStateOf<String?>(null) }
    var aiStartDate by remember { mutableStateOf(LocalDate.now().minusMonths(3).withDayOfMonth(1)) }
    var includeIncomeContext by remember { mutableStateOf(false) }
    var uploadedBackup by remember { mutableStateOf<FullBackupData?>(null) }
    var uploadedBackupName by remember { mutableStateOf<String?>(null) }
    var isAnalyzingSuggestions by remember { mutableStateOf(false) }
    var aiSuggestions by remember { mutableStateOf<List<BudgetSuggestionItem>>(emptyList()) }
    var selectedSuggestionIds by remember { mutableStateOf<Set<String>>(emptySet()) }

    val backupImportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        scope.launch {
            runCatching {
                val text = withContext(Dispatchers.IO) {
                    context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
                }.orEmpty()
                require(text.isNotBlank()) { "備份檔內容為空。" }
                BackupJsonAdapter.gson.fromJson(text, FullBackupData::class.java)
            }.onSuccess { backup ->
                uploadedBackup = backup
                uploadedBackupName = uri.lastPathSegment ?: "Backup.json"
                message = "已載入補充資料。"
            }.onFailure { error ->
                message = "讀取 JSON 備份失敗：${error.message}"
            }
        }
    }

    val monthKey = monthKeyFromDate(selectedMonthDate)
    val effectiveBudgetSettings = budgetSettings ?: BudgetSettingsEntity()
    val statuses = remember(budgets, transactions, categories, currencyService, monthKey) {
        buildBudgetStatuses(budgets, transactions, categories, currencyService, monthKey)
    }
    val visibleStatuses = if (showingOnlyAlerts) {
        statuses.filter { it.ratio >= BigDecimal.ONE }
    } else statuses

    LaunchedEffect(budgetSettings) {
        if (budgetSettings == null) {
            repository.upsertBudgetSettings(BudgetSettingsEntity())
        }
    }

    LaunchedEffect(monthKey, effectiveBudgetSettings.carryOverMode, budgets, transactions, categories) {
        applyBudgetCarryOverIfNeeded(
            repository = repository,
            settings = effectiveBudgetSettings,
            selectedMonthDate = selectedMonthDate,
            budgets = budgets,
            transactions = transactions,
            categories = categories,
            currencyService = currencyService
        )
    }

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
        modifier = Modifier
            .imePadding()
            .padding(horizontal = AppSpacing.screenHorizontal, vertical = AppSpacing.screenVertical),
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
                    Text("預算規則", style = MaterialTheme.typography.titleSmall)
                    TextButton(onClick = {
                        scope.launch {
                            repository.upsertBudgetSettings(
                                effectiveBudgetSettings.copy(
                                    carryOverMode = nextCarryOverMode(effectiveBudgetSettings.carryOverMode),
                                    updatedAt = Instant.now()
                                )
                            )
                        }
                    }) {
                        Text("結轉方式：${carryOverModeLabel(effectiveBudgetSettings.carryOverMode)}")
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            "提醒門檻：${effectiveBudgetSettings.alertThresholdPercent.toPlainString()}%",
                            modifier = Modifier.weight(1f),
                            style = MaterialTheme.typography.bodyMedium
                        )
                        TextButton(onClick = {
                            scope.launch {
                                repository.upsertBudgetSettings(
                                    effectiveBudgetSettings.copy(
                                        alertThresholdPercent = (effectiveBudgetSettings.alertThresholdPercent - BigDecimal("5")).coerceAtLeast(BigDecimal("50")),
                                        updatedAt = Instant.now()
                                    )
                                )
                            }
                        }) { Text("-5") }
                        TextButton(onClick = {
                            scope.launch {
                                repository.upsertBudgetSettings(
                                    effectiveBudgetSettings.copy(
                                        alertThresholdPercent = (effectiveBudgetSettings.alertThresholdPercent + BigDecimal("5")).coerceAtMost(BigDecimal("100")),
                                        updatedAt = Instant.now()
                                    )
                                )
                            }
                        }) { Text("+5") }
                    }
                    Text(
                        "預測方式：按本月使用速度。${carryOverModeDescription(effectiveBudgetSettings.carryOverMode)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
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
                        ,
                            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                            keyboardActions = org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions())
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
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier.padding(AppSpacing.card),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text("AI 建議本月預算", style = MaterialTheme.typography.titleSmall)
                    Text(
                        "會先讀目前帳本資料，也可額外上傳 JSON 備份作補充。AI 只會建議支出分類預算。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    TextButton(onClick = {
                        showDatePicker(context, aiStartDate) { picked ->
                            aiStartDate = picked
                        }
                    }) {
                        Text("分析起始日：${aiStartDate.format(DateTimeFormatter.ISO_LOCAL_DATE)}")
                    }
                    Text(
                        "分析截至現在，目標月份為 ${formatMonth(selectedMonthDate)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("加入收入資料", style = MaterialTheme.typography.titleSmall)
                            Text("讓 AI 在建議支出預算時能參考收入波動", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Switch(checked = includeIncomeContext, onCheckedChange = { includeIncomeContext = it })
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Button(onClick = { backupImportLauncher.launch(arrayOf("application/json")) }) {
                            Text(if (uploadedBackup == null) "上傳 JSON 備份" else "更換補充資料")
                        }
                        if (uploadedBackup != null) {
                            TextButton(onClick = {
                                uploadedBackup = null
                                uploadedBackupName = null
                            }) {
                                Text("移除")
                            }
                        }
                    }
                    if (uploadedBackupName != null) {
                        Text(
                            "已附加：$uploadedBackupName",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Button(
                        onClick = {
                            scope.launch {
                                isAnalyzingSuggestions = true
                                runCatching {
                                    budgetSuggestionService.suggestBudgets(
                                        BudgetSuggestionRequest(
                                            startDate = aiStartDate,
                                            endInstant = Instant.now(),
                                            targetMonthDate = selectedMonthDate,
                                            includeIncomeContext = includeIncomeContext,
                                            mainCurrency = currencyService.mainCurrency,
                                            transactions = transactions,
                                            budgetHistories = budgetHistories,
                                            budgets = budgets,
                                            targetCategories = expenseCategories,
                                            backupData = uploadedBackup
                                        )
                                    )
                                }.onSuccess { suggestions ->
                                    aiSuggestions = suggestions
                                    selectedSuggestionIds = suggestions.map { it.categoryId }.toSet()
                                    message = if (suggestions.isEmpty()) {
                                        "AI 沒有回傳可套用的預算建議。"
                                    } else {
                                        "AI 建議已產生，請先審核後再套用。"
                                    }
                                }.onFailure { error ->
                                    message = error.message ?: "AI 分析失敗。"
                                }
                                isAnalyzingSuggestions = false
                            }
                        },
                        enabled = !isAnalyzingSuggestions && expenseCategories.isNotEmpty(),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        if (isAnalyzingSuggestions) {
                            CircularProgressIndicator(
                                modifier = Modifier.height(18.dp),
                                strokeWidth = 2.dp
                            )
                        } else {
                            Text("開始 AI 分析")
                        }
                    }
                    if (message != null) {
                        Text(
                            message ?: "",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }

        if (aiSuggestions.isNotEmpty()) {
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
                        Text("AI 建議結果", style = MaterialTheme.typography.titleSmall)
                        aiSuggestions.forEach { suggestion ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.Top
                            ) {
                                Checkbox(
                                    checked = selectedSuggestionIds.contains(suggestion.categoryId),
                                    onCheckedChange = { checked ->
                                        selectedSuggestionIds = if (checked == true) {
                                            selectedSuggestionIds + suggestion.categoryId
                                        } else {
                                            selectedSuggestionIds - suggestion.categoryId
                                        }
                                    }
                                )
                                Column(
                                    modifier = Modifier.weight(1f),
                                    verticalArrangement = Arrangement.spacedBy(4.dp)
                                ) {
                                    Text(
                                        expenseCategories.firstOrNull { it.id.toString() == suggestion.categoryId }?.name ?: "未分類",
                                        style = MaterialTheme.typography.titleSmall
                                    )
                                    Text(
                                        suggestion.suggestedAmount.asCurrencyText(suggestion.currencyCode),
                                        style = MaterialTheme.typography.bodyMedium
                                    )
                                    Text(
                                        suggestion.reason,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(
                                onClick = {
                                    scope.launch {
                                        val selectedItems = aiSuggestions.filter { selectedSuggestionIds.contains(it.categoryId) }
                                        val now = Instant.now()
                                        selectedItems.forEach { suggestion ->
                                            val categoryId = runCatching { UUID.fromString(suggestion.categoryId) }.getOrNull() ?: return@forEach
                                            val existing = budgets.firstOrNull {
                                                it.monthKey == monthKey && it.categoryId == categoryId
                                            }
                                            if (existing != null) {
                                                repository.upsertBudget(
                                                    existing.copy(
                                                        amount = currencyService.convert(
                                                            suggestion.suggestedAmount,
                                                            suggestion.currencyCode,
                                                            existing.currencyCode
                                                        ),
                                                        isEnabled = true,
                                                        updatedAt = now
                                                    )
                                                )
                                            } else {
                                                repository.upsertBudget(
                                                    CategoryMonthlyBudgetEntity(
                                                        id = UUID.randomUUID(),
                                                        monthKey = monthKey,
                                                        amount = suggestion.suggestedAmount,
                                                        currencyCode = suggestion.currencyCode,
                                                        isEnabled = true,
                                                        createdAt = now,
                                                        updatedAt = now,
                                                        categoryId = categoryId
                                                    )
                                                )
                                            }
                                        }
                                        aiSuggestions = emptyList()
                                        selectedSuggestionIds = emptySet()
                                        message = "已套用選取的 AI 預算建議。"
                                    }
                                },
                                enabled = selectedSuggestionIds.isNotEmpty(),
                                modifier = Modifier.weight(1f)
                            ) {
                                Text("套用所選")
                            }
                            TextButton(onClick = {
                                selectedSuggestionIds = aiSuggestions.map { it.categoryId }.toSet()
                            }) {
                                Text("全選")
                            }
                            TextButton(onClick = {
                                aiSuggestions = emptyList()
                                selectedSuggestionIds = emptySet()
                            }) {
                                Text("清除")
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
                    alertThresholdPercent = effectiveBudgetSettings.alertThresholdPercent,
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
private fun BudgetRow(
    status: BudgetStatus,
    alertThresholdPercent: BigDecimal,
    onClick: () -> Unit,
    onLongClick: () -> Unit
) {
    val progress = status.ratio
        .coerceIn(BigDecimal.ZERO, BigDecimal("1.5"))
        .toFloat()
        .coerceIn(0f, 1.5f)
    val alertRatio = alertThresholdPercent.divide(BigDecimal("100"), 4, RoundingMode.HALF_UP)
    val forecast = buildBudgetForecast(status)
    val color = when {
        status.isOverBudget -> MaterialTheme.colorScheme.error
        status.ratio >= alertRatio -> Color(0xFFFF9800)
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
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "月底預測：${forecast.projectedSpent.asCurrencyText(status.budget.currencyCode)}",
                    style = MaterialTheme.typography.labelSmall,
                    color = if (forecast.isProjectedOverBudget) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.weight(1f))
                Text(
                    if (forecast.isProjectedOverBudget) {
                        "預計超支 ${forecast.projectedRemaining.abs().asCurrencyText(status.budget.currencyCode)}"
                    } else {
                        "預計剩餘 ${forecast.projectedRemaining.asCurrencyText(status.budget.currencyCode)}"
                    },
                    style = MaterialTheme.typography.labelSmall,
                    color = if (forecast.isProjectedOverBudget) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant
                )
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

private suspend fun applyBudgetCarryOverIfNeeded(
    repository: org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository,
    settings: BudgetSettingsEntity,
    selectedMonthDate: LocalDate,
    budgets: List<CategoryMonthlyBudgetEntity>,
    transactions: List<TransactionWithDetails>,
    categories: List<CategoryEntity>,
    currencyService: org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService
) {
    if (settings.carryOverMode == "None") return

    val monthKey = monthKeyFromDate(selectedMonthDate)
    val previousMonthDate = selectedMonthDate.minusMonths(1).withDayOfMonth(1)
    val previousMonthKey = monthKeyFromDate(previousMonthDate)
    val existingCategoryIds = budgets
        .filter { it.monthKey == monthKey }
        .mapNotNull { it.categoryId }
        .toSet()

    val previousStatuses = buildBudgetStatuses(
        budgets = budgets,
        transactions = transactions,
        categories = categories,
        currencyService = currencyService,
        monthKey = previousMonthKey
    )
    val now = Instant.now()

    previousStatuses.forEach { status ->
        val categoryId = status.budget.categoryId ?: return@forEach
        if (categoryId in existingCategoryIds) return@forEach

        val amount = carryOverAmount(
            previousBudgetAmount = status.budget.amount,
            previousRemaining = status.remaining,
            mode = settings.carryOverMode
        )
        if (amount <= BigDecimal.ZERO) return@forEach

        repository.upsertBudget(
            CategoryMonthlyBudgetEntity(
                id = UUID.randomUUID(),
                monthKey = monthKey,
                amount = amount,
                currencyCode = status.budget.currencyCode,
                isEnabled = status.budget.isEnabled,
                createdAt = now,
                updatedAt = now,
                categoryId = categoryId
            )
        )
    }
}

private fun carryOverAmount(
    previousBudgetAmount: BigDecimal,
    previousRemaining: BigDecimal,
    mode: String
): BigDecimal {
    return when (mode) {
        "UnusedOnly" -> previousBudgetAmount + previousRemaining.max(BigDecimal.ZERO)
        "OverspendOnly" -> (previousBudgetAmount + previousRemaining.min(BigDecimal.ZERO)).max(BigDecimal.ZERO)
        "NetBalance" -> (previousBudgetAmount + previousRemaining).max(BigDecimal.ZERO)
        else -> previousBudgetAmount
    }
}

private fun buildBudgetForecast(status: BudgetStatus, today: LocalDate = LocalDate.now()): BudgetForecast {
    val monthStart = monthStartFromKey(status.budget.monthKey)
    val daysInMonth = monthStart.lengthOfMonth()
    val projectedSpent = if (monthKeyFromDate(today) == status.budget.monthKey) {
        val elapsed = today.dayOfMonth.coerceIn(1, daysInMonth)
        status.spent
            .divide(BigDecimal(elapsed), 6, RoundingMode.HALF_UP)
            .multiply(BigDecimal(daysInMonth))
    } else {
        status.spent
    }
    val projectedRemaining = status.budget.amount - projectedSpent
    val projectedRatio = if (status.budget.amount > BigDecimal.ZERO) {
        projectedSpent.divide(status.budget.amount, 6, RoundingMode.HALF_UP)
    } else {
        BigDecimal.ZERO
    }
    return BudgetForecast(projectedSpent, projectedRemaining, projectedRatio)
}

private fun nextCarryOverMode(current: String): String {
    val modes = listOf("None", "UnusedOnly", "OverspendOnly", "NetBalance")
    val index = modes.indexOf(current).takeIf { it >= 0 } ?: 0
    return modes[(index + 1) % modes.size]
}

private fun carryOverModeLabel(mode: String): String {
    return when (mode) {
        "UnusedOnly" -> "只結轉剩餘"
        "OverspendOnly" -> "只扣減超支"
        "NetBalance" -> "結轉淨額"
        else -> "不結轉"
    }
}

private fun carryOverModeDescription(mode: String): String {
    return when (mode) {
        "UnusedOnly" -> "新月份會把上月剩餘金額加到同分類預算。"
        "OverspendOnly" -> "新月份會扣減上月超支金額。"
        "NetBalance" -> "新月份會把上月剩餘或超支都結轉。"
        else -> "新月份不會自動建立預算。"
    }
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
