package org.duckdns.lhfser.aiaccounting.ui.screens

import android.app.DatePickerDialog
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.core.model.CategoryKind
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.TagEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionEntity
import org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository
import org.duckdns.lhfser.aiaccounting.data.repository.LedgerDeletionResult
import org.duckdns.lhfser.aiaccounting.ui.LocalCurrencyService
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyRateHint
import org.duckdns.lhfser.aiaccounting.core.transactions.TransactionSemantics
import org.duckdns.lhfser.aiaccounting.ui.components.ParityMenuField
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySegmentedControl
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTokens
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySectionHeader
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyPicker
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyButtonStyle
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateText
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

private enum class EntryMode(val label: String) {
    Normal("一般"),
    Split("分拆 (1 -> 多)"),
    Merge("合併 (多 -> 1)")
}

private data class SplitLeg(
    val id: UUID = UUID.randomUUID(),
    var account: AccountEntity? = null,
    var currency: String = "HKD",
    var amount: String = ""
)

private data class MergeLeg(
    val id: UUID = UUID.randomUUID(),
    var currency: String = "HKD",
    var amount: String = ""
)

@Composable
fun TransactionEditorScreen(
    transactionId: String? = null,
    initialType: TransactionType = TransactionType.Expense,
    locksTransactionType: Boolean = false,
    onDone: () -> Unit
) {
    val repository = LocalRepository.current
    val currencyService = LocalCurrencyService.current
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    var entryMode by remember { mutableStateOf(EntryMode.Normal) }
    var transactionType by remember { mutableStateOf(initialType) }
    var amountInput by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var selectedAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var selectedCategory by remember { mutableStateOf<CategoryEntity?>(null) }
    var selectedTags by remember { mutableStateOf<List<TagEntity>>(emptyList()) }
    var selectedCurrency by remember { mutableStateOf("HKD") }
    var date by remember { mutableStateOf(Instant.now()) }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var showCreateCategoryDialog by remember { mutableStateOf(false) }
    var newCategoryName by remember { mutableStateOf("") }
    var newCategoryIcon by remember { mutableStateOf("square.grid.2x2") }
    var newCategoryColorHex by remember { mutableStateOf("#90A4AE") }
    var newCategoryKind by remember { mutableStateOf(defaultCategoryKindFor(transactionType)) }

    var splitLegs by remember { mutableStateOf(listOf(SplitLeg())) }
    var mergeLegs by remember { mutableStateOf(listOf(MergeLeg())) }

    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val categories by repository.categories.collectAsState(initial = emptyList())
    val tags by repository.tags.collectAsState(initial = emptyList())
    val scrollState = rememberScrollState()
    val selectableAccountIds = buildSet {
        selectedAccount?.id?.let(::add)
        splitLegs.mapNotNullTo(this) { it.account?.id }
    }
    val selectableAccounts = remember(accounts, selectableAccountIds, transactionType) {
        val allowed = TransactionSemantics.allowedAccounts(transactionType, accounts)
        val preserved = accounts.filter { it.id in selectableAccountIds }
        (allowed + preserved).distinctBy { it.id }
    }

    LaunchedEffect(transactionId, accounts, categories, tags) {
        if (transactionId == null) return@LaunchedEffect
        val tx = repository.getTransaction(UUID.fromString(transactionId))
        tx?.let {
            entryMode = EntryMode.Normal
            transactionType = it.transaction.type
            amountInput = it.transaction.amount.abs().toPlainString()
            note = it.transaction.note
            selectedAccount = accounts.firstOrNull { acc -> acc.id == it.transaction.accountId }
            selectedCategory = categories.firstOrNull { cat -> cat.id == it.transaction.categoryId }
            selectedTags = tags.filter { tag -> it.tags.any { t -> t.id == tag.id } }
            selectedCurrency = it.transaction.currencyCode
            date = it.transaction.date
        }
    }

    val filteredCategories = categories.filter { it.kind.supports(transactionType) }

    LaunchedEffect(transactionType, filteredCategories, selectableAccounts) {
        if (selectedCategory != null && filteredCategories.none { it.id == selectedCategory?.id }) {
            selectedCategory = null
        }
        if (!newCategoryKind.supports(transactionType)) {
            newCategoryKind = defaultCategoryKindFor(transactionType)
        }
        if (selectedAccount != null && selectableAccounts.none { it.id == selectedAccount?.id }) {
            selectedAccount = selectableAccounts.firstOrNull()
            selectedAccount?.let { selectedCurrency = it.currency }
        }
        if (entryMode == EntryMode.Split) {
            splitLegs = splitLegs.map { leg ->
                if (leg.account != null && selectableAccounts.none { it.id == leg.account?.id }) {
                    leg.copy(account = null)
                } else {
                    leg
                }
            }
        }
    }

    LaunchedEffect(currencyService.mainCurrency) {
        currencyService.fetchRates()
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                start = AppSpacing.screenHorizontal,
                top = AppSpacing.screenVertical,
                end = AppSpacing.screenHorizontal,
                bottom = ParityTokens.FloatingContentBottomPadding
            )
            .verticalScroll(scrollState),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        ParitySectionHeader(
            title = "交易模式",
            detail = "先選記帳方式，再決定這筆是收入還是支出。"
        )
        SectionCard {
            ModePicker(entryMode = entryMode, onModeChange = { entryMode = it })
            if (locksTransactionType) {
                Text(
                    text = if (transactionType == TransactionType.Expense) "支出" else "收入",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold
                )
            } else {
                TypePicker(type = transactionType, onChange = { transactionType = it })
            }
        }

        ParitySectionHeader(
            title = "交易內容",
            detail = "帳戶、金額與拆分方式會跟著模式一起保存。"
        )
        SectionCard {
            when (entryMode) {
                EntryMode.Normal -> {
                    AmountRow(
                        label = "金額",
                        amount = amountInput,
                        onAmountChange = { amountInput = sanitizeAmount(it) },
                        currency = selectedCurrency,
                        onCurrencyChange = { selectedCurrency = it },
                        currencyService = currencyService
                    )
                    AccountPicker(
                        label = "帳戶",
                        accounts = selectableAccounts,
                        selected = selectedAccount,
                        onSelect = { acc ->
                            selectedAccount = acc
                            if (acc != null) {
                                selectedCurrency = acc.currency
                            }
                        }
                    )
                }
                EntryMode.Split -> {
                    splitLegs.forEachIndexed { index, leg ->
                        SplitLegEditor(
                            index = index,
                            leg = leg,
                            accounts = selectableAccounts,
                            currencyService = currencyService,
                            onUpdate = { updated ->
                                splitLegs = splitLegs.toMutableList().also { it[index] = updated }
                            },
                            onRemove = if (splitLegs.size > 1) {
                                {
                                    splitLegs = splitLegs.toMutableList().also { it.removeAt(index) }
                                }
                            } else null
                        )
                    }
                    TextButton(onClick = { splitLegs = splitLegs + SplitLeg() }) {
                        Text("新增分拆項")
                    }
                }
                EntryMode.Merge -> {
                    mergeLegs.forEachIndexed { index, leg ->
                        MergeLegEditor(
                            index = index,
                            leg = leg,
                            currencyService = currencyService,
                            onUpdate = { updated ->
                                mergeLegs = mergeLegs.toMutableList().also { it[index] = updated }
                            },
                            onRemove = if (mergeLegs.size > 1) {
                                {
                                    mergeLegs = mergeLegs.toMutableList().also { it.removeAt(index) }
                                }
                            } else null
                        )
                    }
                    TextButton(onClick = { mergeLegs = mergeLegs + MergeLeg(currency = selectedCurrency) }) {
                        Text("新增合併項")
                    }
                    AccountPicker(
                        label = "合併入帳戶",
                        accounts = selectableAccounts,
                        selected = selectedAccount,
                        onSelect = { acc ->
                            selectedAccount = acc
                            if (acc != null) selectedCurrency = acc.currency
                        }
                    )
                }
            }
        }

        ParitySectionHeader(
            title = "日期",
            detail = "預設使用現在時間，也可以改成過去或未來的日期。"
        )
        SectionCard {
            TextButton(onClick = {
                showDatePicker(context, date) { picked ->
                    date = picked
                }
            }) {
                Text(date.toDateText())
            }
        }

        ParitySectionHeader(
            title = "分類與標籤",
            detail = "分類會影響報表與預算，標籤則方便之後再查。"
        )
        SectionCard {
            CategoryPicker(
                categories = filteredCategories,
                selected = selectedCategory,
                onSelect = { selectedCategory = it }
            )
            TextButton(onClick = {
                newCategoryKind = defaultCategoryKindFor(transactionType)
                newCategoryColorHex = autoPickDistinctColor(categories.map { it.colorHex })
                showCreateCategoryDialog = true
            }) {
                Text("新增分類")
            }

            TagPicker(tags = tags, selected = selectedTags, onChange = { selectedTags = it })
        }

        ParitySectionHeader(
            title = "備註",
            detail = "補充這筆交易的背景，之後搜尋和回看會更清楚。"
        )
        SectionCard {
            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                label = { Text("備註") },
                modifier = Modifier.fillMaxWidth()
            )
        }

        Button(
            onClick = {
                scope.launch {
                    saveTransaction(
                        repository = repository,
                        entryMode = entryMode,
                        transactionId = transactionId,
                        type = transactionType,
                        amountInput = amountInput,
                        selectedAccount = selectedAccount,
                        selectedCategory = selectedCategory,
                        selectedTags = selectedTags,
                        selectedCurrency = selectedCurrency,
                        date = date,
                        note = note,
                        splitLegs = splitLegs,
                        mergeLegs = mergeLegs
                    )
                    onDone()
                }
            },
            enabled = canSubmit(
                entryMode = entryMode,
                amountInput = amountInput,
                selectedAccount = selectedAccount,
                splitLegs = splitLegs,
                mergeLegs = mergeLegs
            ),
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("儲存")
        }

        if (transactionId != null) {
            TextButton(onClick = { showDeleteConfirm = true }) {
                Text("刪除交易", color = MaterialTheme.colorScheme.error)
            }
        }
    }

    if (showDeleteConfirm && transactionId != null) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("確認刪除？") },
            text = { Text("刪除後無法復原。") },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    scope.launch {
                        val result = repository.deleteLedgerTransactionById(UUID.fromString(transactionId))
                        if (result == LedgerDeletionResult.AdvanceInitialRequiresCase) {
                            errorMessage = "這是代墊建立分錄，請進入代墊詳情刪除整個代墊案件。"
                        } else {
                            onDone()
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
            title = { Text("無法刪除") },
            text = { Text(errorMessage ?: "") },
            confirmButton = {
                TextButton(onClick = { errorMessage = null }) { Text("了解") }
            }
        )
    }

    if (showCreateCategoryDialog) {
        AlertDialog(
            onDismissRequest = { showCreateCategoryDialog = false },
            title = { Text("新增分類") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedTextField(
                        value = newCategoryName,
                        onValueChange = { newCategoryName = it },
                        label = { Text("分類名稱") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = newCategoryIcon,
                        onValueChange = { newCategoryIcon = it },
                        label = { Text("圖示（SF Symbol 名稱）") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        OutlinedTextField(
                            value = newCategoryColorHex,
                            onValueChange = { newCategoryColorHex = it },
                            label = { Text("顏色 Hex") },
                            modifier = Modifier.weight(1f)
                        )
                        TextButton(onClick = {
                            newCategoryColorHex = autoPickDistinctColor(categories.map { it.colorHex })
                        }) {
                            Text("自動選色")
                        }
                    }
                    KindPicker(kind = newCategoryKind, onChange = { newCategoryKind = it })
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        scope.launch {
                            val category = CategoryEntity(
                                id = UUID.randomUUID(),
                                name = newCategoryName.trim(),
                                icon = newCategoryIcon.ifBlank { "square.grid.2x2" },
                                colorHex = normalizeCategoryColor(newCategoryColorHex),
                                kind = newCategoryKind
                            )
                            repository.upsertCategory(category)
                            if (category.kind.supports(transactionType)) {
                                selectedCategory = category
                            }
                            newCategoryName = ""
                            newCategoryIcon = "square.grid.2x2"
                            newCategoryColorHex = "#90A4AE"
                            newCategoryKind = defaultCategoryKindFor(transactionType)
                            showCreateCategoryDialog = false
                        }
                    },
                    enabled = newCategoryName.trim().isNotEmpty()
                ) {
                    Text("新增")
                }
            },
            dismissButton = {
                TextButton(onClick = { showCreateCategoryDialog = false }) {
                    Text("取消")
                }
            }
        )
    }
}


@Composable
private fun ModePicker(entryMode: EntryMode, onModeChange: (EntryMode) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("記帳模式", style = MaterialTheme.typography.titleSmall)
        ParitySegmentedControl(
            options = EntryMode.values().toList(),
            selected = entryMode,
            label = { it.label },
            onSelect = onModeChange
        )
    }
}

@Composable
private fun TypePicker(type: TransactionType, onChange: (TransactionType) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        ParitySegmentedControl(
            options = listOf(TransactionType.Expense, TransactionType.Income),
            selected = type,
            label = { if (it == TransactionType.Expense) "支出" else "收入" },
            onSelect = onChange
        )
    }
}

@Composable
private fun AmountRow(
    label: String,
    amount: String,
    onAmountChange: (String) -> Unit,
    currency: String,
    onCurrencyChange: (String) -> Unit,
    currencyService: org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(label, style = MaterialTheme.typography.titleSmall)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            CurrencyPicker(selected = currency, onSelect = onCurrencyChange)
            OutlinedTextField(
                value = amount,
                onValueChange = onAmountChange,
                label = { Text("金額") },
                modifier = Modifier.weight(1f)
            )
        }
        CurrencyRateHint(
            currencyService = currencyService,
            amount = parsePositive(amount),
            currencyCode = currency
        )
    }
}

@Composable
private fun AccountPicker(
    label: String,
    accounts: List<AccountEntity>,
    selected: AccountEntity?,
    onSelect: (AccountEntity?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        ParityMenuField(
            label = label,
            value = selected?.name.orEmpty(),
            placeholder = "選擇帳戶",
            onClick = { expanded = true }
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            accounts.forEach { account ->
                DropdownMenuItem(
                    text = { Text(account.name) },
                    onClick = {
                        expanded = false
                        onSelect(account)
                    }
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
}

@Composable
private fun TagPicker(
    tags: List<TagEntity>,
    selected: List<TagEntity>,
    onChange: (List<TagEntity>) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("標籤", style = MaterialTheme.typography.titleSmall)
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp), contentPadding = PaddingValues(horizontal = 4.dp)) {
            items(tags) { tag ->
                val isSelected = selected.any { it.id == tag.id }
                FilterChip(
                    selected = isSelected,
                    onClick = {
                        val next = if (isSelected) {
                            selected.filterNot { it.id == tag.id }
                        } else {
                            selected + tag
                        }
                        onChange(next)
                    },
                    label = { Text(tag.name) }
                )
            }
        }
    }
}

@Composable
private fun CurrencyPicker(selected: String, onSelect: (String) -> Unit) {
    CurrencyPicker(
        selected = selected,
        onSelect = onSelect,
        buttonStyle = CurrencyButtonStyle.Tonal
    )
}

@Composable
private fun SplitLegEditor(
    index: Int,
    leg: SplitLeg,
    accounts: List<AccountEntity>,
    currencyService: org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService,
    onUpdate: (SplitLeg) -> Unit,
    onRemove: (() -> Unit)?
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        ParitySectionHeader(
            title = "分拆項 ${index + 1}",
            detail = "每一項都會變成獨立帳目，方便之後分開追蹤。"
        )
        AccountPicker(
            label = "帳戶",
            accounts = accounts,
            selected = leg.account,
            onSelect = { acc ->
                onUpdate(leg.copy(account = acc, currency = acc?.currency ?: leg.currency))
            }
        )
        AmountRow(
            label = "金額",
            amount = leg.amount,
            onAmountChange = { onUpdate(leg.copy(amount = sanitizeAmount(it))) },
            currency = leg.currency,
            onCurrencyChange = { onUpdate(leg.copy(currency = it)) },
            currencyService = currencyService
        )
        if (onRemove != null) {
            TextButton(onClick = onRemove) { Text("移除") }
        }
    }
}

@Composable
private fun MergeLegEditor(
    index: Int,
    leg: MergeLeg,
    currencyService: org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService,
    onUpdate: (MergeLeg) -> Unit,
    onRemove: (() -> Unit)?
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        ParitySectionHeader(
            title = "合併項 ${index + 1}",
            detail = "先填各來源金額，最後一起合併進目標帳戶。"
        )
        AmountRow(
            label = "金額",
            amount = leg.amount,
            onAmountChange = { onUpdate(leg.copy(amount = sanitizeAmount(it))) },
            currency = leg.currency,
            onCurrencyChange = { onUpdate(leg.copy(currency = it)) },
            currencyService = currencyService
        )
        if (onRemove != null) {
            TextButton(onClick = onRemove) { Text("移除") }
        }
    }
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

@Composable
private fun KindPicker(kind: CategoryKind, onChange: (CategoryKind) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("分類類型", style = MaterialTheme.typography.titleSmall)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CategoryKind.entries.forEach { item ->
                FilterChip(
                    selected = kind == item,
                    onClick = { onChange(item) },
                    label = { Text(item.rawValue) }
                )
            }
        }
    }
}

private fun defaultCategoryKindFor(type: TransactionType): CategoryKind {
    return when (type) {
        TransactionType.Expense -> CategoryKind.Expense
        TransactionType.Income -> CategoryKind.Income
        TransactionType.Transfer -> CategoryKind.Both
    }
}

private fun normalizeCategoryColor(input: String): String {
    val trimmed = input.trim().removePrefix("#")
    val normalized = trimmed.uppercase().take(6)
    return "#${normalized.ifEmpty { "90A4AE" }}"
}

private fun autoPickDistinctColor(existing: List<String>): String {
    val palette = listOf(
        "#EF5350",
        "#EC407A",
        "#AB47BC",
        "#7E57C2",
        "#5C6BC0",
        "#42A5F5",
        "#26A69A",
        "#66BB6A",
        "#FFCA28",
        "#FFA726",
        "#8D6E63",
        "#78909C"
    )
    return palette.firstOrNull { color -> existing.none { it.equals(color, ignoreCase = true) } }
        ?: palette.random()
}

private fun parsePositive(input: String): BigDecimal? {
    return input.toBigDecimalOrNull()?.takeIf { it > BigDecimal.ZERO }
}

private fun showDatePicker(
    context: android.content.Context,
    initial: Instant,
    onPicked: (Instant) -> Unit
) {
    val zone = ZoneId.systemDefault()
    val date = initial.atZone(zone).toLocalDate()
    DatePickerDialog(
        context,
        { _, year, month, day ->
            val picked = LocalDate.of(year, month + 1, day)
            onPicked(picked.atStartOfDay(zone).toInstant())
        },
        date.year,
        date.monthValue - 1,
        date.dayOfMonth
    ).show()
}

private fun canSubmit(
    entryMode: EntryMode,
    amountInput: String,
    selectedAccount: AccountEntity?,
    splitLegs: List<SplitLeg>,
    mergeLegs: List<MergeLeg>
): Boolean {
    return when (entryMode) {
        EntryMode.Normal -> selectedAccount != null && parsePositive(amountInput) != null
        EntryMode.Split -> splitLegs.isNotEmpty() && splitLegs.all { it.account != null && parsePositive(it.amount) != null }
        EntryMode.Merge -> selectedAccount != null && mergeLegs.isNotEmpty() && mergeLegs.all { parsePositive(it.amount) != null }
    }
}

private suspend fun saveTransaction(
    repository: AccountingRepository,
    entryMode: EntryMode,
    transactionId: String?,
    type: TransactionType,
    amountInput: String,
    selectedAccount: AccountEntity?,
    selectedCategory: CategoryEntity?,
    selectedTags: List<TagEntity>,
    selectedCurrency: String,
    date: Instant,
    note: String,
    splitLegs: List<SplitLeg>,
    mergeLegs: List<MergeLeg>
) {
    when (entryMode) {
        EntryMode.Normal -> {
            val account = selectedAccount ?: return
            val amount = parsePositive(amountInput) ?: return
            val finalAmount = if (type == TransactionType.Expense) amount.abs().negate() else amount.abs()
            val txId = transactionId?.let(UUID::fromString) ?: UUID.randomUUID()
            val transaction = TransactionEntity(
                id = txId,
                amount = finalAmount,
                currencyCode = selectedCurrency,
                date = date,
                note = note.trim(),
                photoPath = null,
                type = type,
                linkedTransactionId = null,
                transferGroupId = null,
                transferSide = null,
                createdAt = Instant.now(),
                updatedAt = Instant.now(),
                accountId = account.id,
                categoryId = selectedCategory?.id
            )
            repository.upsertTransaction(transaction, selectedTags.map { it.id })
        }
        EntryMode.Split -> {
            if (transactionId != null) {
                repository.deleteTransactionById(UUID.fromString(transactionId))
            }
            val legs = splitLegs.mapNotNull { leg ->
                val account = leg.account ?: return@mapNotNull null
                val amount = parsePositive(leg.amount) ?: return@mapNotNull null
                Triple(account, amount, leg.currency)
            }
            val transactions = legs.mapIndexed { index, (account, amount, currency) ->
                val finalAmount = if (type == TransactionType.Expense) amount.abs().negate() else amount.abs()
                TransactionEntity(
                    id = UUID.randomUUID(),
                    amount = finalAmount,
                    currencyCode = currency,
                    date = date,
                    note = indexedNote(note, "分拆", index, legs.size),
                    photoPath = null,
                    type = type,
                    linkedTransactionId = null,
                    transferGroupId = null,
                    transferSide = null,
                    createdAt = Instant.now(),
                    updatedAt = Instant.now(),
                    accountId = account.id,
                    categoryId = selectedCategory?.id
                )
            }
            repository.upsertTransactions(transactions, selectedTags.map { it.id })
        }
        EntryMode.Merge -> {
            if (transactionId != null) {
                repository.deleteTransactionById(UUID.fromString(transactionId))
            }
            val account = selectedAccount ?: return
            val legs = mergeLegs.mapNotNull { leg ->
                val amount = parsePositive(leg.amount) ?: return@mapNotNull null
                Pair(amount, leg.currency)
            }
            val transactions = legs.mapIndexed { index, (amount, currency) ->
                val finalAmount = if (type == TransactionType.Expense) amount.abs().negate() else amount.abs()
                TransactionEntity(
                    id = UUID.randomUUID(),
                    amount = finalAmount,
                    currencyCode = currency,
                    date = date,
                    note = indexedNote(note, "合併", index, legs.size),
                    photoPath = null,
                    type = type,
                    linkedTransactionId = null,
                    transferGroupId = null,
                    transferSide = null,
                    createdAt = Instant.now(),
                    updatedAt = Instant.now(),
                    accountId = account.id,
                    categoryId = selectedCategory?.id
                )
            }
            repository.upsertTransactions(transactions, selectedTags.map { it.id })
        }
    }
}

private fun indexedNote(base: String, mode: String, index: Int, count: Int): String {
    val suffix = "[$mode ${index + 1}/$count]"
    val trimmed = base.trim()
    return if (trimmed.isBlank()) suffix else "$trimmed $suffix"
}
