package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
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
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceParticipantEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.TagEntity
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateText
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

@Composable
fun AdvanceDetailScreen(caseId: String?) {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()
    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val categories by repository.categories.collectAsState(initial = emptyList())
    val tags by repository.tags.collectAsState(initial = emptyList())

    var advanceCase by remember { mutableStateOf<AdvanceCaseWithDetails?>(null) }

    LaunchedEffect(caseId) {
        val id = caseId?.let(UUID::fromString) ?: return@LaunchedEffect
        advanceCase = repository.getAdvanceCase(id)
    }

    val receiveAccounts = accounts.filter { it.type != AccountType.Debt }

    var selectedParticipant by remember { mutableStateOf<AdvanceParticipantEntity?>(null) }
    var selectedReceiveAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var selectedCategory by remember { mutableStateOf<CategoryEntity?>(null) }
    var selectedTags by remember { mutableStateOf<List<TagEntity>>(emptyList()) }
    var amountInput by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }

    if (advanceCase == null) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("載入中...", style = MaterialTheme.typography.bodyLarge)
        }
        return
    }

    val caseData = advanceCase ?: return

    LazyColumn(
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(caseData.advanceCase.title, style = MaterialTheme.typography.titleLarge)
                Text("日期：${caseData.advanceCase.date.toDateText()}")
                Text("幣種：${caseData.advanceCase.currencyCode}")
                Text("備註：${caseData.advanceCase.note.ifBlank { "-" }}")
            }
        }

        item {
            Text("代墊對象", style = MaterialTheme.typography.titleMedium)
        }
        items(caseData.participants) { participant ->
            ParticipantRow(participant = participant, currency = caseData.advanceCase.currencyCode)
        }

        item {
            Text("新增還款", style = MaterialTheme.typography.titleMedium)
        }
        item {
            ParticipantPicker(
                participants = caseData.participants,
                selected = selectedParticipant,
                onSelect = { selectedParticipant = it }
            )
        }
        item {
            AccountPicker(label = "入帳帳戶", accounts = receiveAccounts, selected = selectedReceiveAccount) { acc ->
                selectedReceiveAccount = acc
            }
        }
        item {
            OutlinedTextField(
                value = amountInput,
                onValueChange = { amountInput = sanitizeAmount(it) },
                label = { Text("還款金額") },
                modifier = Modifier.fillMaxWidth()
            )
        }
        item {
            CategoryPicker(categories = categories, selected = selectedCategory) { selectedCategory = it }
        }
        item {
            TagPicker(tags = tags, selected = selectedTags, onChange = { selectedTags = it })
        }
        item {
            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                label = { Text("備註") },
                modifier = Modifier.fillMaxWidth()
            )
        }
        item {
            Button(
                onClick = {
                    scope.launch {
                        val participant = selectedParticipant ?: return@launch
                        val receiveAccount = selectedReceiveAccount ?: return@launch
                        val amount = amountInput.toBigDecimalOrNull() ?: return@launch
                        repository.recordAdvanceRepayment(
                            advanceCase = caseData.advanceCase,
                            participant = participant,
                            amount = amount,
                            currencyCode = caseData.advanceCase.currencyCode,
                            date = Instant.now(),
                            note = note,
                            receiveAccount = receiveAccount,
                            category = selectedCategory,
                            tagIds = selectedTags.map { it.id }
                        )
                        amountInput = ""
                        note = ""
                        advanceCase = repository.getAdvanceCase(caseData.advanceCase.id)
                    }
                }
            ) {
                Text("記錄還款")
            }
        }
    }
}

@Composable
private fun ParticipantRow(participant: AdvanceParticipantEntity, currency: String) {
    val remaining = (participant.owedAmount - participant.repaidAmount).max(BigDecimal.ZERO)
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(participant.name, style = MaterialTheme.typography.bodyLarge)
        Text("欠款：${participant.owedAmount.asCurrencyText(currency)}")
        Text("已還：${participant.repaidAmount.asCurrencyText(currency)}")
        Text("未還：${remaining.asCurrencyText(currency)}")
    }
}

@Composable
private fun ParticipantPicker(
    participants: List<AdvanceParticipantEntity>,
    selected: AdvanceParticipantEntity?,
    onSelect: (AdvanceParticipantEntity?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("還款對象", style = MaterialTheme.typography.titleSmall)
        TextButton(onClick = { expanded = true }) {
            Text(selected?.name ?: "選擇對象")
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            participants.forEach { participant ->
                DropdownMenuItem(text = { Text(participant.name) }, onClick = {
                    expanded = false
                    onSelect(participant)
                })
            }
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
        TextButton(onClick = { expanded = true }) { Text(selected?.name ?: "選擇帳戶") }
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
