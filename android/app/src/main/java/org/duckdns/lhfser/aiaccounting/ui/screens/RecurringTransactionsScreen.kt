package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.launch
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.RecurringOccurrenceEntity
import org.duckdns.lhfser.aiaccounting.data.db.RecurringRuleEntity
import org.duckdns.lhfser.aiaccounting.data.db.TagEntity
import org.duckdns.lhfser.aiaccounting.ui.LocalCurrencyService
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyButtonStyle
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyPicker
import org.duckdns.lhfser.aiaccounting.ui.components.ParityMenuField
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySectionHeader
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySegmentedControl
import org.duckdns.lhfser.aiaccounting.ui.components.ParityStatusPill
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTokens
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTopSection
import org.duckdns.lhfser.aiaccounting.ui.components.PressableCard
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateText

private enum class RecurringFrequencyOption(val rawValue: String, val label: String) {
    Daily("Daily", "每日"),
    Weekly("Weekly", "每週"),
    Monthly("Monthly", "每月");

    companion object {
        fun fromRaw(rawValue: String): RecurringFrequencyOption {
            return entries.firstOrNull { it.rawValue == rawValue } ?: Monthly
        }
    }
}

@Composable
fun RecurringTransactionsScreen(
    onAddRule: () -> Unit,
    onEditRule: (UUID) -> Unit
) {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()
    val rules by repository.recurringRules.collectAsState(initial = emptyList())
    val occurrences by repository.recurringOccurrences.collectAsState(initial = emptyList())
    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val categories by repository.categories.collectAsState(initial = emptyList())
    val scrollState = rememberScrollState()

    LaunchedEffect(Unit) {
        repository.syncDueRecurringOccurrences()
    }

    val rulesById = remember(rules) { rules.associateBy { it.id } }
    val pendingOccurrences = remember(occurrences) {
        occurrences
            .filter { it.status == "Pending" }
            .sortedBy { it.dueDate }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(scrollState)
            .imePadding()
            .padding(
                start = AppSpacing.screenHorizontal,
                end = AppSpacing.screenHorizontal,
                top = AppSpacing.screenVertical,
                bottom = AppSpacing.screenVertical + ParityTokens.FloatingContentBottomPadding
            ),
        verticalArrangement = Arrangement.spacedBy(AppSpacing.section)
    ) {
        ParityTopSection(
            title = "定期記帳",
            subtitle = "先產生待確認項目，確認後才會寫入正式帳目。",
            accessory = {
                TextButton(onClick = onAddRule) { Text("新增") }
            }
        )

        Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)) {
            ParitySectionHeader(
                title = "待確認",
                detail = if (pendingOccurrences.isEmpty()) "目前沒有到期項目。" else "確認後會建立正式收入或支出。"
            )
            if (pendingOccurrences.isEmpty()) {
                SectionCard {
                    Text(
                        "沒有待確認的定期記帳。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(AppSpacing.card)
                    )
                }
            } else {
                pendingOccurrences.forEach { occurrence ->
                    val rule = occurrence.ruleId?.let { rulesById[it] }
                    PendingOccurrenceCard(
                        occurrence = occurrence,
                        rule = rule,
                        account = rule?.accountId?.let { id -> accounts.firstOrNull { it.id == id } },
                        category = rule?.categoryId?.let { id -> categories.firstOrNull { it.id == id } },
                        onConfirm = {
                            scope.launch { repository.confirmRecurringOccurrence(occurrence.id) }
                        },
                        onSkip = {
                            scope.launch { repository.skipRecurringOccurrence(occurrence.id) }
                        }
                    )
                }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)) {
            ParitySectionHeader(
                title = "規則",
                detail = "支援收入與支出；轉帳、代墊與借貸先保持手動確認。"
            )
            if (rules.isEmpty()) {
                SectionCard {
                    Text(
                        "尚未建立定期記帳規則。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(AppSpacing.card)
                    )
                }
            } else {
                rules.sortedBy { it.nextDueDate }.forEach { rule ->
                    RuleCard(
                        rule = rule,
                        account = rule.accountId?.let { id -> accounts.firstOrNull { it.id == id } },
                        category = rule.categoryId?.let { id -> categories.firstOrNull { it.id == id } },
                        onClick = { onEditRule(rule.id) }
                    )
                }
            }
        }
    }
}

@Composable
private fun PendingOccurrenceCard(
    occurrence: RecurringOccurrenceEntity,
    rule: RecurringRuleEntity?,
    account: AccountEntity?,
    category: CategoryEntity?,
    onConfirm: () -> Unit,
    onSkip: () -> Unit
) {
    SectionCard {
        Column(
            modifier = Modifier.padding(AppSpacing.card),
            verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(AppSpacing.inline), modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(rule?.title ?: "定期記帳", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text(
                        listOfNotNull(account?.name, category?.name, occurrence.dueDate.toDateText()).joinToString(" · "),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                ParityStatusPill(text = "待確認", tint = MaterialTheme.colorScheme.primary)
            }
            Text(
                rule?.let { signedRuleAmount(it) } ?: "資料不完整",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold
            )
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                TextButton(onClick = onSkip, modifier = Modifier.weight(1f)) { Text("略過") }
                Button(onClick = onConfirm, enabled = rule != null && account != null, modifier = Modifier.weight(1f)) {
                    Text("確認入帳")
                }
            }
        }
    }
}

@Composable
private fun RuleCard(
    rule: RecurringRuleEntity,
    account: AccountEntity?,
    category: CategoryEntity?,
    onClick: () -> Unit
) {
    PressableCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick
    ) {
        Column(
            modifier = Modifier.padding(AppSpacing.card),
            verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(AppSpacing.inline), modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(rule.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text(
                        listOfNotNull(account?.name, category?.name, RecurringFrequencyOption.fromRaw(rule.frequency).label).joinToString(" · "),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                if (rule.isPaused) {
                    ParityStatusPill(text = "已暫停", tint = MaterialTheme.colorScheme.outline)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(AppSpacing.inline), modifier = Modifier.fillMaxWidth()) {
                Text(signedRuleAmount(rule), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                Text(
                    "下次 ${rule.nextDueDate.toDateText()}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
fun RecurringRuleEditorScreen(
    ruleId: String?,
    onDone: () -> Unit
) {
    val repository = LocalRepository.current
    val currencyService = LocalCurrencyService.current
    val scope = rememberCoroutineScope()
    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val categories by repository.categories.collectAsState(initial = emptyList())
    val tags by repository.tags.collectAsState(initial = emptyList())
    val rules by repository.recurringRules.collectAsState(initial = emptyList())
    val scrollState = rememberScrollState()

    val parsedRuleId = remember(ruleId) { ruleId?.let { runCatching { UUID.fromString(it) }.getOrNull() } ?: UUID.randomUUID() }
    val existingRule = rules.firstOrNull { it.id == parsedRuleId }
    val ownAccounts = accounts.filter { it.type != AccountType.Debt && !it.isArchived }

    var loaded by remember(parsedRuleId) { mutableStateOf(false) }
    var title by remember { mutableStateOf("") }
    var amount by remember { mutableStateOf("") }
    var currencyCode by remember { mutableStateOf(currencyService.mainCurrency) }
    var type by remember { mutableStateOf(TransactionType.Expense) }
    var note by remember { mutableStateOf("") }
    var frequency by remember { mutableStateOf(RecurringFrequencyOption.Monthly) }
    var intervalCount by remember { mutableStateOf("1") }
    var nextDueDate by remember { mutableStateOf(LocalDate.now().toString()) }
    var isPaused by remember { mutableStateOf(false) }
    var selectedAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var selectedCategory by remember { mutableStateOf<CategoryEntity?>(null) }
    var selectedTags by remember { mutableStateOf<List<TagEntity>>(emptyList()) }
    var showDeleteConfirm by remember { mutableStateOf(false) }

    val filteredCategories = categories.filter { it.kind.supports(type) }

    LaunchedEffect(existingRule, ownAccounts, filteredCategories) {
        if (loaded) return@LaunchedEffect
        if (existingRule != null) {
            title = existingRule.title
            amount = existingRule.amount.toPlainString()
            currencyCode = existingRule.currencyCode
            type = existingRule.type
            note = existingRule.note
            frequency = RecurringFrequencyOption.fromRaw(existingRule.frequency)
            intervalCount = existingRule.intervalCount.toString()
            nextDueDate = existingRule.nextDueDate.atZone(ZoneId.systemDefault()).toLocalDate().toString()
            isPaused = existingRule.isPaused
            selectedAccount = ownAccounts.firstOrNull { it.id == existingRule.accountId }
            selectedCategory = filteredCategories.firstOrNull { it.id == existingRule.categoryId }
            val existingTagIds = repository.getRecurringRuleTagIds(existingRule.id).toSet()
            selectedTags = tags.filter { it.id in existingTagIds }
            loaded = true
        } else if (ownAccounts.isNotEmpty()) {
            selectedAccount = ownAccounts.first()
            currencyCode = selectedAccount?.currency ?: currencyService.mainCurrency
            selectedCategory = filteredCategories.firstOrNull()
            loaded = true
        }
    }

    LaunchedEffect(type, filteredCategories) {
        if (selectedCategory != null && filteredCategories.none { it.id == selectedCategory?.id }) {
            selectedCategory = filteredCategories.firstOrNull()
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(scrollState)
            .imePadding()
            .padding(
                start = AppSpacing.screenHorizontal,
                end = AppSpacing.screenHorizontal,
                top = AppSpacing.screenVertical,
                bottom = AppSpacing.screenVertical + ParityTokens.FloatingContentBottomPadding
            ),
        verticalArrangement = Arrangement.spacedBy(AppSpacing.section)
    ) {
        ParityTopSection(
            title = if (existingRule == null) "新增定期記帳" else "編輯定期記帳",
            subtitle = "到期後先進待確認，不會偷偷寫入帳目。"
        )

        SectionCard {
            Column(modifier = Modifier.padding(AppSpacing.card), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                ParitySegmentedControl(
                    options = listOf(TransactionType.Expense, TransactionType.Income),
                    selected = type,
                    label = { if (it == TransactionType.Expense) "支出" else "收入" },
                    onSelect = { type = it }
                )
                OutlinedTextField(
                    value = title,
                    onValueChange = { title = it },
                    label = { Text("名稱") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                ,
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                    keyboardActions = org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions())
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                    CurrencyPicker(
                        selected = currencyCode,
                        onSelect = { currencyCode = it },
                        buttonStyle = CurrencyButtonStyle.Tonal
                    )
                    OutlinedTextField(
                        value = amount,
                        onValueChange = { amount = sanitizeAmountInput(it) },
                        label = { Text("金額") },
                        modifier = Modifier.weight(1f),
                        singleLine = true
                    ,
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                        keyboardActions = org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions())
                }
                AccountDropdown(
                    accounts = ownAccounts,
                    selected = selectedAccount,
                    onSelect = {
                        selectedAccount = it
                        currencyCode = it.currency
                    }
                )
                CategoryDropdown(
                    categories = filteredCategories,
                    selected = selectedCategory,
                    onSelect = { selectedCategory = it }
                )
                RecurringTagPicker(tags = tags, selected = selectedTags, onChange = { selectedTags = it })
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text("備註") },
                    modifier = Modifier.fillMaxWidth()
                ,
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                    keyboardActions = org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions())
            }
        }

        ParitySectionHeader(title = "週期", detail = "先支援每日、每週、每月；每次到期都需要你確認。")
        SectionCard {
            Column(modifier = Modifier.padding(AppSpacing.card), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                ParitySegmentedControl(
                    options = RecurringFrequencyOption.entries,
                    selected = frequency,
                    label = { it.label },
                    onSelect = { frequency = it }
                )
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                    OutlinedTextField(
                        value = intervalCount,
                        onValueChange = { intervalCount = it.filter(Char::isDigit).take(3) },
                        label = { Text("間隔") },
                        modifier = Modifier.weight(0.35f),
                        singleLine = true
                    ,
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                        keyboardActions = org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions())
                    OutlinedTextField(
                        value = nextDueDate,
                        onValueChange = { nextDueDate = it },
                        label = { Text("下次日期 yyyy-MM-dd") },
                        modifier = Modifier.weight(0.65f),
                        singleLine = true
                    ,
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                        keyboardActions = org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions())
                }
                TextButton(onClick = { isPaused = !isPaused }) {
                    Text(if (isPaused) "目前已暫停，點擊恢復" else "目前啟用中，點擊暫停")
                }
            }
        }

        Button(
            onClick = {
                val nextDueInstant = parseDateInput(nextDueDate)
                val parsedAmount = amount.toBigDecimalOrNull()
                val account = selectedAccount
                if (nextDueInstant != null && parsedAmount != null && parsedAmount > BigDecimal.ZERO && account != null) {
                    val now = Instant.now()
                    val rule = RecurringRuleEntity(
                        id = parsedRuleId,
                        title = title.trim().ifBlank { if (type == TransactionType.Expense) "定期支出" else "定期收入" },
                        amount = parsedAmount.abs(),
                        currencyCode = currencyCode,
                        type = type,
                        note = note.trim(),
                        frequency = frequency.rawValue,
                        intervalCount = intervalCount.toIntOrNull()?.coerceAtLeast(1) ?: 1,
                        nextDueDate = nextDueInstant,
                        isPaused = isPaused,
                        createdAt = existingRule?.createdAt ?: now,
                        updatedAt = now,
                        accountId = account.id,
                        categoryId = selectedCategory?.id
                    )
                    scope.launch {
                        repository.upsertRecurringRule(rule, selectedTags.map { it.id })
                        repository.syncDueRecurringOccurrences()
                        onDone()
                    }
                }
            },
            enabled = selectedAccount != null && amount.toBigDecimalOrNull()?.let { it > BigDecimal.ZERO } == true && parseDateInput(nextDueDate) != null,
            modifier = Modifier.fillMaxWidth().height(52.dp)
        ) {
            Text("儲存")
        }

        if (existingRule != null) {
            TextButton(onClick = { showDeleteConfirm = true }, modifier = Modifier.fillMaxWidth()) {
                Text("刪除規則", color = MaterialTheme.colorScheme.error)
            }
        }
    }

    if (showDeleteConfirm && existingRule != null) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("刪除定期規則？") },
            text = { Text("此操作會一併刪除尚未確認的到期項目；已確認產生的正式帳目不會被刪除。") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDeleteConfirm = false
                        scope.launch {
                            repository.deleteRecurringRule(existingRule)
                            onDone()
                        }
                    }
                ) { Text("刪除", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("取消") }
            }
        )
    }
}

@Composable
private fun AccountDropdown(
    accounts: List<AccountEntity>,
    selected: AccountEntity?,
    onSelect: (AccountEntity) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    ParityMenuField(
        label = "帳戶",
        value = selected?.name.orEmpty(),
        placeholder = "選擇自己的帳戶",
        onClick = { expanded = true }
    )
    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
        accounts.forEach { account ->
            DropdownMenuItem(
                text = { Text("${account.name} · ${account.currency}") },
                onClick = {
                    expanded = false
                    onSelect(account)
                }
            )
        }
    }
}

@Composable
private fun CategoryDropdown(
    categories: List<CategoryEntity>,
    selected: CategoryEntity?,
    onSelect: (CategoryEntity?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    ParityMenuField(
        label = "分類",
        value = selected?.name.orEmpty(),
        placeholder = "無分類",
        onClick = { expanded = true }
    )
    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
        DropdownMenuItem(
            text = { Text("無分類") },
            onClick = {
                expanded = false
                onSelect(null)
            }
        )
        categories.forEach { category ->
            DropdownMenuItem(
                text = { Text(category.name) },
                onClick = {
                    expanded = false
                    onSelect(category)
                }
            )
        }
    }
}

@Composable
private fun RecurringTagPicker(
    tags: List<TagEntity>,
    selected: List<TagEntity>,
    onChange: (List<TagEntity>) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("標籤", style = MaterialTheme.typography.titleSmall)
        if (tags.isEmpty()) {
            Text("尚未建立標籤", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            tags.forEach { tag ->
                val isSelected = selected.any { it.id == tag.id }
                TextButton(
                    onClick = {
                        onChange(
                            if (isSelected) {
                                selected.filterNot { it.id == tag.id }
                            } else {
                                selected + tag
                            }
                        )
                    }
                ) {
                    Text(if (isSelected) "✓ ${tag.name}" else tag.name)
                }
            }
        }
    }
}

private fun signedRuleAmount(rule: RecurringRuleEntity): String {
    val prefix = if (rule.type == TransactionType.Expense) "-" else "+"
    return prefix + rule.amount.asCurrencyText(rule.currencyCode)
}

private fun sanitizeAmountInput(input: String): String {
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

private fun parseDateInput(input: String): Instant? {
    return runCatching {
        LocalDate.parse(input.trim()).atStartOfDay(ZoneId.systemDefault()).toInstant()
    }.getOrNull()
}
