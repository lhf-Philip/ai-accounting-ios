package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.repository.TransferLeg
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import java.math.BigDecimal
import java.time.Instant

private enum class AddTransferMode(val label: String) {
    OneToOne("一般 (1 -> 1)"),
    OneToMany("分拆 (1 -> 多)"),
    ManyToOne("合併 (多 -> 1)")
}

private data class AddTransferLegInput(
    val id: String = java.util.UUID.randomUUID().toString(),
    var account: AccountEntity? = null,
    var currency: String = "HKD",
    var amount: String = ""
)

@Composable
fun AddTransferScreen(onDone: () -> Unit) {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()
    val accounts by repository.accounts.collectAsState(initial = emptyList())

    var mode by remember { mutableStateOf(AddTransferMode.OneToOne) }

    var fromAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var toAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var currencyOut by remember { mutableStateOf("HKD") }
    var currencyIn by remember { mutableStateOf("HKD") }
    var amountOut by remember { mutableStateOf("") }
    var amountIn by remember { mutableStateOf("") }

    var sourceAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var sourceCurrency by remember { mutableStateOf("HKD") }
    var sourceAmount by remember { mutableStateOf("") }
    var destinationLegs by remember { mutableStateOf(listOf(AddTransferLegInput())) }

    var destinationAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var destinationCurrency by remember { mutableStateOf("HKD") }
    var destinationAmount by remember { mutableStateOf("") }
    var sourceLegs by remember { mutableStateOf(listOf(AddTransferLegInput())) }

    var note by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("模式", style = MaterialTheme.typography.titleSmall)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AddTransferMode.values().forEach { item ->
                FilterChip(
                    selected = mode == item,
                    onClick = { mode = item },
                    label = { Text(item.label) }
                )
            }
        }

        when (mode) {
            AddTransferMode.OneToOne -> {
                AccountPicker(label = "轉出帳戶", accounts = accounts, selected = fromAccount) { acc ->
                    fromAccount = acc
                    if (acc != null) currencyOut = acc.currency
                }
                AmountRow(
                    label = "轉出金額",
                    amount = amountOut,
                    onAmountChange = {
                        amountOut = sanitizeAmount(it)
                        if (currencyOut == currencyIn) amountIn = amountOut
                    },
                    currency = currencyOut,
                    onCurrencyChange = { currencyOut = it }
                )
                AccountPicker(label = "轉入帳戶", accounts = accounts, selected = toAccount) { acc ->
                    toAccount = acc
                    if (acc != null) currencyIn = acc.currency
                }
                AmountRow(
                    label = "轉入金額",
                    amount = amountIn,
                    onAmountChange = { amountIn = sanitizeAmount(it) },
                    currency = currencyIn,
                    onCurrencyChange = { currencyIn = it }
                )
            }
            AddTransferMode.OneToMany -> {
                AccountPicker(label = "轉出帳戶", accounts = accounts, selected = sourceAccount) { acc ->
                    sourceAccount = acc
                    if (acc != null) sourceCurrency = acc.currency
                }
                AmountRow(
                    label = "轉出總額",
                    amount = sourceAmount,
                    onAmountChange = { sourceAmount = sanitizeAmount(it) },
                    currency = sourceCurrency,
                    onCurrencyChange = { sourceCurrency = it }
                )
                destinationLegs.forEachIndexed { index, leg ->
                    TransferLegEditor(
                        title = "轉入帳戶 ${index + 1}",
                        leg = leg,
                        accounts = accounts.filter { it.id != sourceAccount?.id },
                        onUpdate = { updated ->
                            destinationLegs = destinationLegs.toMutableList().also { it[index] = updated }
                        },
                        onRemove = if (destinationLegs.size > 1) {
                            { destinationLegs = destinationLegs.toMutableList().also { it.removeAt(index) } }
                        } else null
                    )
                }
                TextButton(onClick = { destinationLegs = destinationLegs + AddTransferLegInput() }) {
                    Text("新增轉入帳戶")
                }
            }
            AddTransferMode.ManyToOne -> {
                AccountPicker(label = "轉入帳戶", accounts = accounts, selected = destinationAccount) { acc ->
                    destinationAccount = acc
                    if (acc != null) destinationCurrency = acc.currency
                }
                AmountRow(
                    label = "轉入總額",
                    amount = destinationAmount,
                    onAmountChange = { destinationAmount = sanitizeAmount(it) },
                    currency = destinationCurrency,
                    onCurrencyChange = { destinationCurrency = it }
                )
                sourceLegs.forEachIndexed { index, leg ->
                    TransferLegEditor(
                        title = "轉出帳戶 ${index + 1}",
                        leg = leg,
                        accounts = accounts.filter { it.id != destinationAccount?.id },
                        onUpdate = { updated ->
                            sourceLegs = sourceLegs.toMutableList().also { it[index] = updated }
                        },
                        onRemove = if (sourceLegs.size > 1) {
                            { sourceLegs = sourceLegs.toMutableList().also { it.removeAt(index) } }
                        } else null
                    )
                }
                TextButton(onClick = { sourceLegs = sourceLegs + AddTransferLegInput() }) {
                    Text("新增轉出帳戶")
                }
            }
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
                    when (mode) {
                        AddTransferMode.OneToOne -> {
                            val from = fromAccount ?: return@launch
                            val to = toAccount ?: return@launch
                            val amountOutValue = parsePositive(amountOut) ?: return@launch
                            val amountInValue = if (currencyOut == currencyIn) amountOutValue else parsePositive(amountIn)
                                ?: return@launch
                            repository.createTransferOneToOne(
                                from = from,
                                to = to,
                                amountOut = amountOutValue,
                                currencyOut = currencyOut,
                                amountIn = amountInValue,
                                currencyIn = currencyIn,
                                date = Instant.now(),
                                note = note
                            )
                        }
                        AddTransferMode.OneToMany -> {
                            val source = sourceAccount ?: return@launch
                            val sourceValue = parsePositive(sourceAmount) ?: return@launch
                            val legs = destinationLegs.mapNotNull { leg ->
                                val account = leg.account ?: return@mapNotNull null
                                val amount = parsePositive(leg.amount) ?: return@mapNotNull null
                                TransferLeg(account, leg.currency, amount)
                            }
                            if (legs.isEmpty()) return@launch
                            repository.createTransferOneToMany(
                                source = source,
                                sourceAmount = sourceValue,
                                sourceCurrency = sourceCurrency,
                                destinations = legs,
                                date = Instant.now(),
                                note = note
                            )
                        }
                        AddTransferMode.ManyToOne -> {
                            val destination = destinationAccount ?: return@launch
                            val destinationValue = parsePositive(destinationAmount) ?: return@launch
                            val legs = sourceLegs.mapNotNull { leg ->
                                val account = leg.account ?: return@mapNotNull null
                                val amount = parsePositive(leg.amount) ?: return@mapNotNull null
                                TransferLeg(account, leg.currency, amount)
                            }
                            if (legs.isEmpty()) return@launch
                            repository.createTransferManyToOne(
                                destination = destination,
                                destinationAmount = destinationValue,
                                destinationCurrency = destinationCurrency,
                                sources = legs,
                                date = Instant.now(),
                                note = note
                            )
                        }
                    }
                    onDone()
                }
            }
        ) {
            Text("儲存")
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
private fun CurrencyPicker(selected: String, onSelect: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    TextButton(onClick = { expanded = true }) { Text(selected) }
    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
        listOf("HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP").forEach { code ->
            DropdownMenuItem(text = { Text(code) }, onClick = {
                expanded = false
                onSelect(code)
            })
        }
    }
}

@Composable
private fun TransferLegEditor(
    title: String,
    leg: AddTransferLegInput,
    accounts: List<AccountEntity>,
    onUpdate: (AddTransferLegInput) -> Unit,
    onRemove: (() -> Unit)?
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, style = MaterialTheme.typography.titleSmall)
        AccountPicker(label = "帳戶", accounts = accounts, selected = leg.account) { acc ->
            onUpdate(leg.copy(account = acc, currency = acc?.currency ?: leg.currency))
        }
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
        Spacer(modifier = Modifier.padding(bottom = 4.dp))
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
