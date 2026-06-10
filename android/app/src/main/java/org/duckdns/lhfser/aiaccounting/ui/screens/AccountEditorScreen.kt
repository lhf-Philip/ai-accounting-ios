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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.duckdns.lhfser.aiaccounting.data.repository.AccountDeletionImpact
import org.duckdns.lhfser.aiaccounting.data.repository.AccountEditDraft
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyPicker
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyButtonStyle
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
import java.math.BigDecimal
import java.util.UUID

@Composable
fun AccountEditorScreen(accountId: String?, onDone: () -> Unit) {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()
    val scrollState = rememberScrollState()

    var name by remember { mutableStateOf("") }
    var currency by remember { mutableStateOf("HKD") }
    var type by remember { mutableStateOf(AccountType.Cash) }
    var baseBalance by remember { mutableStateOf("") }
    var isArchived by remember { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var showArchiveRecommendation by remember { mutableStateOf(false) }
    var deleteImpact by remember { mutableStateOf<AccountDeletionImpact?>(null) }
    var isEditing by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(accountId) {
        val id = accountId?.let(UUID::fromString)
        val existing = id?.let { repository.getAccount(it) }
        if (existing != null) {
            isEditing = true
            name = existing.name
            currency = existing.currency
            type = existing.type
            baseBalance = existing.baseBalance.toPlainString()
            isArchived = existing.isArchived
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
        Text("帳戶資料", style = MaterialTheme.typography.titleMedium)
        SectionCard {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("帳戶名稱") },
                modifier = Modifier.fillMaxWidth()
            ,
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                keyboardActions = org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions())
            if (isEditing) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("主幣種", style = MaterialTheme.typography.titleSmall)
                    Text(currency, style = MaterialTheme.typography.bodyLarge)
                    Text(
                        "主幣種建立後不可修改；其他幣種請透過交易或餘額調整記錄。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            } else {
                CurrencyPicker(selected = currency, onSelect = { currency = it })
            }
            AccountTypePicker(type = type, onChange = { type = it })
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = baseBalance,
                    onValueChange = { baseBalance = sanitizeSignedAmount(it) },
                    label = { Text("初始餘額") },
                    modifier = Modifier.weight(1f),
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                        imeAction = androidx.compose.ui.text.input.ImeAction.Done
                    ),
                    keyboardActions = org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions()
                )
                TextButton(onClick = { baseBalance = toggleAmountSign(baseBalance) }) {
                    Text("+/-")
                }
            }
        }

        Text("其他設定", style = MaterialTheme.typography.titleMedium)
        SectionCard {
            FilterChip(
                selected = isArchived,
                onClick = { isArchived = !isArchived },
                label = { Text("歸檔帳戶") }
            )
        }
        Button(
            onClick = {
                scope.launch {
                    runCatching {
                        repository.saveAccountEdit(
                            AccountEditDraft(
                                accountId = accountId?.let(UUID::fromString),
                                name = name,
                                requestedCurrency = currency,
                                type = type,
                                baseBalance = baseBalance.ifBlank { "0" }.toBigDecimal(),
                                isArchived = isArchived
                            )
                        )
                    }.onSuccess {
                        onDone()
                    }.onFailure {
                        errorMessage = it.localizedMessage ?: "無法儲存帳戶"
                    }
                }
            },
            enabled = name.isNotBlank() && baseBalance.ifBlank { "0" }.toBigDecimalOrNull() != null
        ) {
            Text("儲存")
        }

        if (isEditing) {
            TextButton(onClick = {
                val id = accountId?.let(UUID::fromString) ?: return@TextButton
                scope.launch {
                    runCatching {
                        repository.previewAccountDeletion(id)
                    }.onSuccess { impact ->
                        val resolved = impact ?: return@onSuccess
                        deleteImpact = resolved
                        if (resolved.isEmptyAccount) {
                            showDeleteConfirm = true
                        } else {
                            showArchiveRecommendation = true
                        }
                    }.onFailure {
                        errorMessage = it.localizedMessage ?: "無法分析帳戶影響範圍"
                    }
                }
            }) {
                Text("刪除帳戶", color = MaterialTheme.colorScheme.error)
            }
        }
    }

    if (showArchiveRecommendation && deleteImpact != null) {
        val impact = deleteImpact ?: return
        AlertDialog(
            onDismissRequest = {
                showArchiveRecommendation = false
                deleteImpact = null
            },
            title = { Text("建議改用歸檔") },
            text = {
                Text(
                    "${impact.accountName} 已連結 ${impact.counts.transactionCount} 筆交易、" +
                        "${impact.counts.advanceCaseCount} 個代墊案件、${impact.counts.repaymentCount} 筆還款。"
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showArchiveRecommendation = false
                    scope.launch {
                        runCatching {
                            repository.archiveAccount(impact.accountId)
                        }.onSuccess {
                            onDone()
                        }.onFailure {
                            errorMessage = it.localizedMessage ?: "歸檔失敗"
                        }
                    }
                }) {
                    Text("歸檔帳戶")
                }
            },
            dismissButton = {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(onClick = {
                        showArchiveRecommendation = false
                        showDeleteConfirm = true
                    }) {
                        Text("繼續刪除", color = MaterialTheme.colorScheme.error)
                    }
                    TextButton(onClick = {
                        showArchiveRecommendation = false
                        deleteImpact = null
                    }) {
                        Text("取消")
                    }
                }
            }
        )
    }

    if (showDeleteConfirm && deleteImpact != null) {
        val impact = deleteImpact ?: return
        AlertDialog(
            onDismissRequest = {
                showDeleteConfirm = false
                deleteImpact = null
            },
            title = { Text(if (impact.isEmptyAccount) "刪除空帳戶？" else "刪除所有相關記賬？") },
            text = {
                Text(
                    if (impact.isEmptyAccount) {
                        if (impact.counts.shortcutDetachCount > 0) {
                            "這個帳戶沒有歷史記賬，但有 ${impact.counts.shortcutDetachCount} 個捷徑會解除帳戶綁定。"
                        } else {
                            "這個帳戶沒有任何歷史記賬。"
                        }
                    } else {
                        buildString {
                            append("將刪除 ${impact.counts.transactionCount} 筆交易")
                            if (impact.counts.advanceCaseCount > 0) {
                                append("、${impact.counts.advanceCaseCount} 個代墊案件")
                            }
                            if (impact.counts.repaymentCount > 0) {
                                append("、${impact.counts.repaymentCount} 筆還款")
                            }
                            if (impact.counts.shortcutDetachCount > 0) {
                                append("；${impact.counts.shortcutDetachCount} 個捷徑會解除帳戶綁定")
                            }
                            append("。")
                        }
                    }
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    scope.launch {
                        runCatching {
                            repository.deleteAccount(impact.accountId, deleteRelatedBookkeeping = true)
                        }.onSuccess {
                            onDone()
                        }.onFailure {
                            errorMessage = it.localizedMessage ?: "刪除失敗"
                        }
                    }
                }) {
                    Text("刪除", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    deleteImpact = null
                }) {
                    Text("取消")
                }
            }
        )
    }

    if (errorMessage != null) {
        AlertDialog(
            onDismissRequest = { errorMessage = null },
            title = { Text("操作失敗") },
            text = { Text(errorMessage ?: "") },
            confirmButton = {
                TextButton(onClick = { errorMessage = null }) {
                    Text("了解")
                }
            }
        )
    }
}

@Composable
private fun CurrencyPicker(selected: String, onSelect: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("幣別", style = MaterialTheme.typography.titleSmall)
        CurrencyPicker(
            selected = selected,
            onSelect = onSelect,
            buttonStyle = CurrencyButtonStyle.Tonal
        )
    }
}

@Composable
private fun AccountTypePicker(type: AccountType, onChange: (AccountType) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("帳戶類型", style = MaterialTheme.typography.titleSmall)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AccountType.values().forEach { item ->
                FilterChip(
                    selected = type == item,
                    onClick = { onChange(item) },
                    label = { Text(item.rawValue) }
                )
            }
        }
    }
}

internal fun sanitizeSignedAmount(input: String): String {
    val isNegative = input.trimStart().startsWith("-")
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
    val normalized = result.toString()
    return if (isNegative && normalized.isNotEmpty()) "-$normalized" else normalized
}

private fun toggleAmountSign(input: String): String {
    return when {
        input.startsWith("-") -> input.removePrefix("-")
        input.isBlank() -> "-"
        else -> "-$input"
    }
}
