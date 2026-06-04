package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
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
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.core.transactions.TransactionSemantics
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.ShortcutEntity
import org.duckdns.lhfser.aiaccounting.data.db.TagEntity
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyPicker
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyButtonStyle
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
import java.util.UUID

@Composable
fun ShortcutEditorScreen(shortcutId: String?, onDone: () -> Unit) {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()
    val shortcuts by repository.shortcuts.collectAsState(initial = emptyList())
    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val categories by repository.categories.collectAsState(initial = emptyList())
    val tags by repository.tags.collectAsState(initial = emptyList())
    val scrollState = rememberScrollState()

    var name by remember { mutableStateOf("") }
    var icon by remember { mutableStateOf("⚡") }
    var amount by remember { mutableStateOf("") }
    var currency by remember { mutableStateOf("HKD") }
    var type by remember { mutableStateOf(TransactionType.Expense) }
    var note by remember { mutableStateOf("") }
    val availableAccounts = TransactionSemantics.allowedAccounts(type, accounts)
    var selectedAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var selectedCategory by remember { mutableStateOf<CategoryEntity?>(null) }
    var selectedTags by remember { mutableStateOf<List<TagEntity>>(emptyList()) }
    var isEditing by remember { mutableStateOf(false) }

    val filteredCategories = categories.filter { it.kind.supports(type) }

    LaunchedEffect(shortcutId, shortcuts, availableAccounts) {
        val id = shortcutId?.let(UUID::fromString)
        val existing = shortcuts.firstOrNull { it.shortcut.id == id }
        if (existing != null) {
            isEditing = true
            name = existing.shortcut.name
            icon = existing.shortcut.icon
            amount = existing.shortcut.amount.toPlainString()
            currency = existing.shortcut.currencyCode
            type = existing.shortcut.type
            note = existing.shortcut.note
            selectedAccount = existing.account
            selectedCategory = existing.category
            selectedTags = existing.tags
        } else if (selectedAccount == null) {
            selectedAccount = availableAccounts.firstOrNull()
            selectedAccount?.let { currency = it.currency }
        }
    }

    LaunchedEffect(type, filteredCategories, availableAccounts) {
        if (selectedCategory != null && filteredCategories.none { it.id == selectedCategory?.id }) {
            selectedCategory = null
        }
        if (selectedAccount != null && availableAccounts.none { it.id == selectedAccount?.id }) {
            selectedAccount = availableAccounts.firstOrNull()
            selectedAccount?.let { currency = it.currency }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = AppSpacing.screenHorizontal, vertical = AppSpacing.screenVertical)
            .verticalScroll(scrollState)
            .imePadding(),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("捷徑外觀", style = MaterialTheme.typography.titleMedium)
        SectionCard {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("捷徑名稱") },
                modifier = Modifier.fillMaxWidth()
            ,
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                keyboardActions = org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions())
            OutlinedTextField(
                value = icon,
                onValueChange = { icon = it },
                label = { Text("圖示（Emoji 或簡短文字）") },
                modifier = Modifier.fillMaxWidth()
            ,
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                keyboardActions = org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions())
        }

        Text("預設交易內容", style = MaterialTheme.typography.titleMedium)
        SectionCard {
            TypePicker(type = type, onChange = { type = it })
            AmountRow(
                amount = amount,
                onAmountChange = { amount = sanitizeAmount(it) },
                currency = currency,
                onCurrencyChange = { currency = it }
            )
            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                label = { Text("備註（選填）") },
                modifier = Modifier.fillMaxWidth()
            ,
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                keyboardActions = org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions())
            AccountPicker(
                accounts = availableAccounts,
                selected = selectedAccount,
                onSelect = { acc ->
                    selectedAccount = acc
                    if (acc != null) currency = acc.currency
                }
            )
            CategoryPicker(categories = filteredCategories, selected = selectedCategory) { selectedCategory = it }
            TagPicker(tags = tags, selected = selectedTags, onChange = { selectedTags = it })
        }

        Button(
            onClick = {
                scope.launch {
                    val account = selectedAccount ?: return@launch
                    val amountValue = parsePositive(amount) ?: return@launch
                    val id = shortcutId?.let(UUID::fromString) ?: UUID.randomUUID()
                    val shortcut = ShortcutEntity(
                        id = id,
                        name = name.ifBlank { "捷徑" },
                        icon = icon.ifBlank { "⚡" },
                        amount = amountValue.abs(),
                        currencyCode = currency,
                        type = type,
                        note = note.trim(),
                        accountId = account.id,
                        categoryId = selectedCategory?.id
                    )
                    repository.upsertShortcut(shortcut, selectedTags.map { it.id })
                    onDone()
                }
            },
            enabled = name.isNotBlank() && parsePositive(amount) != null && selectedAccount != null
        ) {
            Text("儲存")
        }

        if (isEditing) {
            TextButton(onClick = {
                scope.launch {
                    val existing = shortcuts.firstOrNull { it.shortcut.id == shortcutId?.let(UUID::fromString) }
                    if (existing != null) {
                        repository.deleteShortcut(existing.shortcut)
                        onDone()
                    }
                }
            }) {
                Text("刪除捷徑")
            }
        }
    }
}


@Composable
private fun TypePicker(type: TransactionType, onChange: (TransactionType) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("類型", style = MaterialTheme.typography.titleSmall)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(TransactionType.Expense, TransactionType.Income).forEach { item ->
                FilterChip(
                    selected = type == item,
                    onClick = { onChange(item) },
                    label = { Text(if (item == TransactionType.Expense) "支出" else "收入") }
                )
            }
        }
    }
}

@Composable
private fun AmountRow(
    amount: String,
    onAmountChange: (String) -> Unit,
    currency: String,
    onCurrencyChange: (String) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("金額", style = MaterialTheme.typography.titleSmall)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            CurrencyPicker(selected = currency, onSelect = onCurrencyChange)
            OutlinedTextField(
                value = amount,
                onValueChange = onAmountChange,
                label = { Text("金額") },
                modifier = Modifier.weight(1f)
            ,
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                keyboardActions = org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions())
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
private fun AccountPicker(
    accounts: List<AccountEntity>,
    selected: AccountEntity?,
    onSelect: (AccountEntity?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("帳戶", style = MaterialTheme.typography.titleSmall)
        TextButton(onClick = { expanded = true }) {
            Text(selected?.name ?: "選擇帳戶")
        }
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
        Text("分類", style = MaterialTheme.typography.titleSmall)
        TextButton(onClick = { expanded = true }) { Text(selected?.name ?: "無分類") }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text("無分類") }, onClick = {
                expanded = false
                onSelect(null)
            })
            categories.forEach { category ->
                DropdownMenuItem(text = { Text(category.name) }, onClick = {
                    expanded = false
                    onSelect(category)
                })
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
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            tags.forEach { tag ->
                val isSelected = selected.any { it.id == tag.id }
                FilterChip(
                    selected = isSelected,
                    onClick = {
                        val next = if (isSelected) selected.filterNot { it.id == tag.id } else selected + tag
                        onChange(next)
                    },
                    label = { Text(tag.name) }
                )
            }
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

private fun parsePositive(input: String): java.math.BigDecimal? {
    return input.toBigDecimalOrNull()?.takeIf { it > java.math.BigDecimal.ZERO }
}
