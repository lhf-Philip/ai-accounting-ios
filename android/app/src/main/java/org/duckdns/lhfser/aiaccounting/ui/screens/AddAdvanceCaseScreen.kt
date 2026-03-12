package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
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
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

private data class ParticipantDraft(
    val id: String = UUID.randomUUID().toString(),
    var debtAccount: AccountEntity? = null,
    var amount: String = ""
)

@Composable
fun AddAdvanceCaseScreen(onDone: () -> Unit) {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()

    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val categories by repository.categories.collectAsState(initial = emptyList())
    val tags by repository.tags.collectAsState(initial = emptyList())

    val payerAccounts = accounts.filter { it.type != AccountType.Debt }
    val debtAccounts = accounts.filter { it.type == AccountType.Debt }

    var title by remember { mutableStateOf("") }
    var myShare by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var currency by remember { mutableStateOf("HKD") }

    var payerAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var expenseCategory by remember { mutableStateOf<CategoryEntity?>(null) }
    var selectedTags by remember { mutableStateOf<List<TagEntity>>(emptyList()) }
    var participants by remember { mutableStateOf(listOf(ParticipantDraft())) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
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
            currency = currency,
            onCurrencyChange = { currency = it }
        )
        CategoryPicker(categories = categories, selected = expenseCategory) { expenseCategory = it }
        TagPicker(tags = tags, selected = selectedTags, onChange = { selectedTags = it })

        Text("代墊對象", style = MaterialTheme.typography.titleSmall)
        participants.forEachIndexed { index, participant ->
            ParticipantEditor(
                index = index,
                participant = participant,
                debtAccounts = debtAccounts,
                onUpdate = { updated ->
                    participants = participants.toMutableList().also { it[index] = updated }
                },
                onRemove = if (participants.size > 1) {
                    { participants = participants.toMutableList().also { it.removeAt(index) } }
                } else null
            )
        }
        TextButton(onClick = { participants = participants + ParticipantDraft() }) {
            Text("新增對象")
        }

        OutlinedTextField(
            value = note,
            onValueChange = { note = it },
            label = { Text("備註") },
            modifier = Modifier.fillMaxWidth()
        )

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
                        participants = inputs
                    )
                    onDone()
                }
            }
        ) {
            Text("儲存")
        }
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
            currency = participant.debtAccount?.currency ?: "HKD",
            onCurrencyChange = {}
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
    currency: String,
    onCurrencyChange: (String) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(label, style = MaterialTheme.typography.titleSmall)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            TextButton(onClick = { }) { Text(currency) }
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
