package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyPicker
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyButtonStyle
import java.math.BigDecimal
import java.util.UUID

@Composable
fun AccountEditorScreen(accountId: String?, onDone: () -> Unit) {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()
    val accounts by repository.accounts.collectAsState(initial = emptyList())

    var name by remember { mutableStateOf("") }
    var currency by remember { mutableStateOf("HKD") }
    var type by remember { mutableStateOf(AccountType.Cash) }
    var baseBalance by remember { mutableStateOf("") }
    var isArchived by remember { mutableStateOf(false) }

    LaunchedEffect(accountId, accounts) {
        val id = accountId?.let(UUID::fromString)
        val existing = accounts.firstOrNull { it.id == id }
        if (existing != null) {
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
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("帳戶資料", style = MaterialTheme.typography.titleMedium)
        SectionCard {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("帳戶名稱") },
                modifier = Modifier.fillMaxWidth()
            )
            CurrencyPicker(selected = currency, onSelect = { currency = it })
            AccountTypePicker(type = type, onChange = { type = it })
            OutlinedTextField(
                value = baseBalance,
                onValueChange = { baseBalance = sanitizeAmount(it) },
                label = { Text("初始餘額") },
                modifier = Modifier.fillMaxWidth()
            )
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
                    val id = accountId?.let(UUID::fromString) ?: UUID.randomUUID()
                    val balanceValue = baseBalance.toBigDecimalOrNull() ?: BigDecimal.ZERO
                    val sortOrder = accounts.size
                    val account = AccountEntity(
                        id = id,
                        name = name.ifBlank { "帳戶" },
                        currency = currency,
                        type = type,
                        baseBalance = balanceValue,
                        sortOrder = sortOrder,
                        isArchived = isArchived
                    )
                    repository.upsertAccount(account)
                    onDone()
                }
            },
            enabled = name.isNotBlank()
        ) {
            Text("儲存")
        }
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
