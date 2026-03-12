package org.duckdns.lhfser.aiaccounting.ui.screens

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
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
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
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.TagEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionEntity
import org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard
import java.math.BigDecimal
import java.time.Instant
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
    onDone: () -> Unit
) {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()

    var entryMode by remember { mutableStateOf(EntryMode.Normal) }
    var transactionType by remember { mutableStateOf(TransactionType.Expense) }
    var amountInput by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var selectedAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var selectedCategory by remember { mutableStateOf<CategoryEntity?>(null) }
    var selectedTags by remember { mutableStateOf<List<TagEntity>>(emptyList()) }
    var selectedCurrency by remember { mutableStateOf("HKD") }
    var date by remember { mutableStateOf(Instant.now()) }

    var splitLegs by remember { mutableStateOf(listOf(SplitLeg())) }
    var mergeLegs by remember { mutableStateOf(listOf(MergeLeg())) }

    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val categories by repository.categories.collectAsState(initial = emptyList())
    val tags by repository.tags.collectAsState(initial = emptyList())

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

    LaunchedEffect(transactionType, filteredCategories) {
        if (selectedCategory != null && filteredCategories.none { it.id == selectedCategory?.id }) {
            selectedCategory = null
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("交易模式", style = MaterialTheme.typography.titleMedium)
        SectionCard {
            ModePicker(entryMode = entryMode, onModeChange = { entryMode = it })
            TypePicker(type = transactionType, onChange = { transactionType = it })
        }

        Text("交易內容", style = MaterialTheme.typography.titleMedium)
        SectionCard {
            when (entryMode) {
                EntryMode.Normal -> {
                    AmountRow(
                        label = "金額",
                        amount = amountInput,
                        onAmountChange = { amountInput = sanitizeAmount(it) },
                        currency = selectedCurrency,
                        onCurrencyChange = { selectedCurrency = it }
                    )
                    AccountPicker(
                        label = "帳戶",
                        accounts = accounts,
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
                            accounts = accounts,
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
                        accounts = accounts,
                        selected = selectedAccount,
                        onSelect = { acc ->
                            selectedAccount = acc
                            if (acc != null) selectedCurrency = acc.currency
                        }
                    )
                }
            }
        }

        Text("分類與標籤", style = MaterialTheme.typography.titleMedium)
        SectionCard {
            CategoryPicker(
                categories = filteredCategories,
                selected = selectedCategory,
                onSelect = { selectedCategory = it }
            )

            TagPicker(tags = tags, selected = selectedTags, onChange = { selectedTags = it })
        }

        Text("備註", style = MaterialTheme.typography.titleMedium)
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
            )
        ) {
            Text("儲存")
        }
    }
}


@Composable
private fun ModePicker(entryMode: EntryMode, onModeChange: (EntryMode) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("記帳模式", style = MaterialTheme.typography.titleSmall)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            EntryMode.values().forEach { mode ->
                FilterChip(
                    selected = entryMode == mode,
                    onClick = { onModeChange(mode) },
                    label = { Text(mode.label) }
                )
            }
        }
    }
}

@Composable
private fun TypePicker(type: TransactionType, onChange: (TransactionType) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("類型", style = MaterialTheme.typography.titleSmall)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = type == TransactionType.Expense,
                onClick = { onChange(TransactionType.Expense) },
                label = { Text("支出") }
            )
            FilterChip(
                selected = type == TransactionType.Income,
                onClick = { onChange(TransactionType.Income) },
                label = { Text("收入") }
            )
        }
    }
}

@Composable
private fun AmountRow(
    label: String,
    amount: String,
    onAmountChange: (String) -> Unit,
    currency: String,
    onCurrencyChange: (String) -> Unit
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
        Text(label, style = MaterialTheme.typography.titleSmall)
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
        TextButton(onClick = { expanded = true }) {
            Text(selected?.name ?: "無分類")
        }
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
    var expanded by remember { mutableStateOf(false) }
    TextButton(onClick = { expanded = true }) {
        Text(selected)
    }
    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
        listOf("HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP").forEach { code ->
            DropdownMenuItem(
                text = { Text(code) },
                onClick = {
                    expanded = false
                    onSelect(code)
                }
            )
        }
    }
}

@Composable
private fun SplitLegEditor(
    index: Int,
    leg: SplitLeg,
    accounts: List<AccountEntity>,
    onUpdate: (SplitLeg) -> Unit,
    onRemove: (() -> Unit)?
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("分拆項 ${index + 1}", style = MaterialTheme.typography.titleSmall)
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
            onCurrencyChange = { onUpdate(leg.copy(currency = it)) }
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
    onUpdate: (MergeLeg) -> Unit,
    onRemove: (() -> Unit)?
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("合併項 ${index + 1}", style = MaterialTheme.typography.titleSmall)
        AmountRow(
            label = "金額",
            amount = leg.amount,
            onAmountChange = { onUpdate(leg.copy(amount = sanitizeAmount(it))) },
            currency = leg.currency,
            onCurrencyChange = { onUpdate(leg.copy(currency = it)) }
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

private fun parsePositive(input: String): BigDecimal? {
    return input.toBigDecimalOrNull()?.takeIf { it > BigDecimal.ZERO }
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
            repository.upsertTransactions(transactions)
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
            repository.upsertTransactions(transactions)
        }
    }
}

private fun indexedNote(base: String, mode: String, index: Int, count: Int): String {
    val suffix = "[$mode ${index + 1}/$count]"
    val trimmed = base.trim()
    return if (trimmed.isBlank()) suffix else "$trimmed $suffix"
}
