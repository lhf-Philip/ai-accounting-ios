package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.TagEntity
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceParticipantInput
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyPicker
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyButtonStyle
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

private data class ParticipantDraft(
    val id: String = UUID.randomUUID().toString(),
    var debtAccount: AccountEntity? = null,
    var amount: String = ""
)

private enum class AdvanceDirection(val label: String) {
    IAdvanceOthers("我代墊他人"),
    OthersAdvanceMe("他人代墊我")
}

@Composable
fun AddAdvanceCaseScreen(onDone: () -> Unit) {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()

    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val categories by repository.categories.collectAsState(initial = emptyList())
    val tags by repository.tags.collectAsState(initial = emptyList())

    val payerAccounts = accounts.filter { !it.isArchived && it.type != AccountType.Debt }
    val debtAccounts = accounts.filter { !it.isArchived && it.type == AccountType.Debt }
    val scrollState = rememberScrollState()

    var title by remember { mutableStateOf("") }
    var myShare by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var currency by remember { mutableStateOf("HKD") }
    var direction by remember { mutableStateOf(AdvanceDirection.IAdvanceOthers) }

    var payerAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var expenseCategory by remember { mutableStateOf<CategoryEntity?>(null) }
    var selectedTags by remember { mutableStateOf<List<TagEntity>>(emptyList()) }
    var participants by remember { mutableStateOf(listOf(ParticipantDraft())) }
    var showCreateDebtDialog by remember { mutableStateOf(false) }
    var newDebtName by remember { mutableStateOf("") }

    val flowCategories = when (direction) {
        AdvanceDirection.IAdvanceOthers -> categories.filter { it.kind.supports(org.duckdns.lhfser.aiaccounting.core.model.TransactionType.Expense) }
        AdvanceDirection.OthersAdvanceMe -> categories.filter { it.kind.supports(org.duckdns.lhfser.aiaccounting.core.model.TransactionType.Income) }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = AppSpacing.screenHorizontal, vertical = AppSpacing.screenVertical)
            .verticalScroll(scrollState),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("基本資料", style = MaterialTheme.typography.titleMedium)
        SectionCard {
            Text("方向", style = MaterialTheme.typography.titleSmall)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AdvanceDirection.values().forEach { mode ->
                    FilterChip(
                        selected = direction == mode,
                        onClick = {
                            direction = mode
                            if (expenseCategory != null && flowCategories.none { it.id == expenseCategory?.id }) {
                                expenseCategory = null
                            }
                        },
                        label = { Text(mode.label) }
                    )
                }
            }
            OutlinedTextField(
                value = title,
                onValueChange = { title = it },
                label = { Text("標題") },
                modifier = Modifier.fillMaxWidth()
            )
            AccountPicker(label = "付款帳戶", accounts = payerAccounts, selected = payerAccount) { acc ->
                payerAccount = acc
                if (acc != null) currency = acc.currency
            }
        AmountRow(
            label = "自己的份額",
            amount = myShare,
            onAmountChange = { myShare = sanitizeAmount(it) },
            currency = currency
        )
        }

        Text("分類與標籤", style = MaterialTheme.typography.titleMedium)
        SectionCard {
            CategoryPicker(
                categories = flowCategories,
                selected = expenseCategory,
                label = if (direction == AdvanceDirection.IAdvanceOthers) "支出分類" else "收入分類"
            ) {
                expenseCategory = it
            }
            TagPicker(tags = tags, selected = selectedTags, onChange = { selectedTags = it })
        }

        Text(if (direction == AdvanceDirection.IAdvanceOthers) "代墊對象" else "借款對象", style = MaterialTheme.typography.titleMedium)
        SectionCard {
            participants.forEachIndexed { index, participant ->
                key(participant.id) {
                    ParticipantEditor(
                        index = index,
                        participant = participant,
                        debtAccounts = debtAccounts,
                        onUpdate = { updated ->
                            participants = participants.toMutableList().also { list ->
                                val targetIndex = list.indexOfFirst { it.id == participant.id }
                                if (targetIndex >= 0) {
                                    list[targetIndex] = updated
                                }
                            }
                        },
                        onRemove = if (participants.size > 1) {
                            { participants = participants.filterNot { it.id == participant.id } }
                        } else null
                    )
                }
            }
            TextButton(onClick = { participants = participants + ParticipantDraft() }) {
                Text("新增對象")
            }
            TextButton(onClick = { showCreateDebtDialog = true }) {
                Text("新增債務人物")
            }
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
                    val payer = payerAccount ?: return@launch
                    val myShareValue = myShare.toBigDecimalOrNull() ?: BigDecimal.ZERO
                    val inputs = participants.mapNotNull { draft ->
                        val account = draft.debtAccount ?: return@mapNotNull null
                        val amount = draft.amount.toBigDecimalOrNull() ?: return@mapNotNull null
                        AdvanceParticipantInput(account, amount)
                    }
                    if (inputs.isEmpty()) return@launch
                    repository.createAdvanceCase(
                        title = title,
                        date = Instant.now(),
                        currencyCode = currency,
                        myShareAmount = myShareValue,
                        note = note,
                        payerAccount = payer,
                        expenseCategory = expenseCategory,
                        tagIds = selectedTags.map { it.id },
                        participants = inputs,
                        isBorrowedByMe = direction == AdvanceDirection.OthersAdvanceMe
                    )
                    onDone()
                }
            }
        ) {
            Text("儲存")
        }
    }

    if (showCreateDebtDialog) {
        AlertDialog(
            onDismissRequest = {
                showCreateDebtDialog = false
                newDebtName = ""
            },
            title = { Text("新增債務人物") },
            text = {
                OutlinedTextField(
                    value = newDebtName,
                    onValueChange = { newDebtName = it },
                    label = { Text("人物名稱") },
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    val trimmed = newDebtName.trim()
                    if (trimmed.isNotEmpty()) {
                        scope.launch {
                            val existing = debtAccounts.firstOrNull { it.name == trimmed }
                            val created = existing ?: AccountEntity(
                                id = UUID.randomUUID(),
                                name = trimmed,
                                currency = currency,
                                type = AccountType.Debt,
                                baseBalance = BigDecimal.ZERO,
                                sortOrder = (accounts.maxOfOrNull { it.sortOrder } ?: -1) + 1,
                                isArchived = false
                            ).also { repository.upsertAccount(it) }
                            participants = participants.toMutableList().also { list ->
                                val emptyIndex = list.indexOfFirst { it.debtAccount == null }
                                if (emptyIndex >= 0) {
                                    list[emptyIndex] = list[emptyIndex].copy(debtAccount = created)
                                } else {
                                    list.add(ParticipantDraft(debtAccount = created))
                                }
                            }
                            showCreateDebtDialog = false
                            newDebtName = ""
                        }
                    }
                }) { Text("新增") }
            },
            dismissButton = {
                TextButton(onClick = {
                    showCreateDebtDialog = false
                    newDebtName = ""
                }) { Text("取消") }
            }
        )
    }
}


@Composable
private fun ParticipantEditor(
    index: Int,
    participant: ParticipantDraft,
    debtAccounts: List<AccountEntity>,
    onUpdate: (ParticipantDraft) -> Unit,
    onRemove: (() -> Unit)?
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("對象 ${index + 1}", style = MaterialTheme.typography.titleSmall)
        AccountPicker(label = "欠款帳戶", accounts = debtAccounts, selected = participant.debtAccount) { acc ->
            onUpdate(participant.copy(debtAccount = acc))
        }
        AmountRow(
            label = "代墊金額",
            amount = participant.amount,
            onAmountChange = { onUpdate(participant.copy(amount = sanitizeAmount(it))) },
            currency = participant.debtAccount?.currency ?: "HKD"
        )
        if (onRemove != null) {
            TextButton(onClick = onRemove) { Text("移除") }
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
                DropdownMenuItem(text = { Text(account.name) }, onClick = {
                    expanded = false
                    onSelect(account)
                })
            }
        }
    }
}

@Composable
private fun AmountRow(
    label: String,
    amount: String,
    onAmountChange: (String) -> Unit,
    currency: String
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(label, style = MaterialTheme.typography.titleSmall)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            CurrencyPicker(
                selected = currency,
                onSelect = { },
                buttonStyle = CurrencyButtonStyle.Tonal
            )
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
private fun CategoryPicker(
    categories: List<CategoryEntity>,
    selected: CategoryEntity?,
    label: String = "分類",
    onSelect: (CategoryEntity?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(label, style = MaterialTheme.typography.titleSmall)
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
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(tags) { tag ->
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
