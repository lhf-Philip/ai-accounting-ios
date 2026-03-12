package org.duckdns.lhfser.aiaccounting.ui.screens

import android.app.DatePickerDialog
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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
import org.duckdns.lhfser.aiaccounting.core.model.TransferSide
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.data.repository.TransferLeg
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyButtonStyle
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyPicker
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateText
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

private enum class TransferEditMode(val label: String) {
    OneToOne("一般 (1 -> 1)"),
    OneToMany("分拆 (1 -> 多)"),
    ManyToOne("合併 (多 -> 1)")
}

private data class TransferEditLegInput(
    val id: String = UUID.randomUUID().toString(),
    var account: AccountEntity? = null,
    var currency: String = "HKD",
    var amount: String = ""
)

@Composable
fun TransferEditorScreen(groupId: String?, onDone: () -> Unit) {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val scrollState = rememberScrollState()

    var mode by remember { mutableStateOf(TransferEditMode.OneToOne) }

    var fromAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var toAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var currencyOut by remember { mutableStateOf("HKD") }
    var currencyIn by remember { mutableStateOf("HKD") }
    var amountOut by remember { mutableStateOf("") }
    var amountIn by remember { mutableStateOf("") }

    var sourceAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var sourceCurrency by remember { mutableStateOf("HKD") }
    var sourceAmount by remember { mutableStateOf("") }
    var destinationLegs by remember { mutableStateOf(listOf(TransferEditLegInput())) }

    var destinationAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var destinationCurrency by remember { mutableStateOf("HKD") }
    var destinationAmount by remember { mutableStateOf("") }
    var sourceLegs by remember { mutableStateOf(listOf(TransferEditLegInput())) }

    var note by remember { mutableStateOf("") }
    var date by remember { mutableStateOf(Instant.now()) }
    var showDeleteConfirm by remember { mutableStateOf(false) }

    LaunchedEffect(groupId, accounts) {
        val id = groupId?.let(UUID::fromString) ?: return@LaunchedEffect
        val group = repository.getTransferGroup(id)
        if (group.isEmpty()) return@LaunchedEffect

        val outgoing = group.filter { it.transaction.transferSide == TransferSide.Outgoing }
        val incoming = group.filter { it.transaction.transferSide == TransferSide.Incoming }
        val firstNote = group.firstOrNull { it.transaction.note.isNotBlank() }?.transaction?.note ?: ""
        note = firstNote
        date = (outgoing.firstOrNull() ?: incoming.first()).transaction.date
        when {
            outgoing.size == 1 && incoming.size == 1 -> {
                mode = TransferEditMode.OneToOne
                val outTx = outgoing.first()
                val inTx = incoming.first()
                fromAccount = accounts.firstOrNull { it.id == outTx.transaction.accountId }
                toAccount = accounts.firstOrNull { it.id == inTx.transaction.accountId }
                currencyOut = outTx.transaction.currencyCode
                currencyIn = inTx.transaction.currencyCode
                amountOut = outTx.transaction.amount.abs().toPlainString()
                amountIn = inTx.transaction.amount.abs().toPlainString()
            }
            outgoing.size == 1 && incoming.size > 1 -> {
                mode = TransferEditMode.OneToMany
                val outTx = outgoing.first()
                sourceAccount = accounts.firstOrNull { it.id == outTx.transaction.accountId }
                sourceCurrency = outTx.transaction.currencyCode
                sourceAmount = outTx.transaction.amount.abs().toPlainString()
                destinationLegs = incoming.map { tx ->
                    TransferEditLegInput(
                        account = accounts.firstOrNull { it.id == tx.transaction.accountId },
                        currency = tx.transaction.currencyCode,
                        amount = tx.transaction.amount.abs().toPlainString()
                    )
                }
            }
            outgoing.size > 1 && incoming.size == 1 -> {
                mode = TransferEditMode.ManyToOne
                val inTx = incoming.first()
                destinationAccount = accounts.firstOrNull { it.id == inTx.transaction.accountId }
                destinationCurrency = inTx.transaction.currencyCode
                destinationAmount = inTx.transaction.amount.abs().toPlainString()
                sourceLegs = outgoing.map { tx ->
                    TransferEditLegInput(
                        account = accounts.firstOrNull { it.id == tx.transaction.accountId },
                        currency = tx.transaction.currencyCode,
                        amount = tx.transaction.amount.abs().toPlainString()
                    )
                }
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .verticalScroll(scrollState),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("轉帳模式", style = MaterialTheme.typography.titleMedium)
        SectionCard {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TransferEditMode.values().forEach { item ->
                    FilterChip(
                        selected = mode == item,
                        onClick = { mode = item },
                        label = { Text(item.label) }
                    )
                }
            }
        }

        Text("轉帳內容", style = MaterialTheme.typography.titleMedium)
        SectionCard {
            when (mode) {
                TransferEditMode.OneToOne -> {
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
                TransferEditMode.OneToMany -> {
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
                    TextButton(onClick = { destinationLegs = destinationLegs + TransferEditLegInput() }) {
                        Text("新增轉入帳戶")
                    }
                }
                TransferEditMode.ManyToOne -> {
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
                    TextButton(onClick = { sourceLegs = sourceLegs + TransferEditLegInput() }) {
                        Text("新增轉出帳戶")
                    }
                }
            }
        }

        Text("日期", style = MaterialTheme.typography.titleMedium)
        SectionCard {
            TextButton(onClick = {
                showDatePicker(context, date) { picked ->
                    date = picked
                }
            }) {
                Text(date.toDateText())
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
                    val id = groupId?.let(UUID::fromString) ?: return@launch
                    repository.deleteTransferGroup(id)
                    when (mode) {
                        TransferEditMode.OneToOne -> {
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
                                date = date,
                                note = note
                            )
                        }
                        TransferEditMode.OneToMany -> {
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
                                date = date,
                                note = note
                            )
                        }
                        TransferEditMode.ManyToOne -> {
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
                                date = date,
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

        TextButton(onClick = { showDeleteConfirm = true }) {
            Text("刪除轉帳", color = MaterialTheme.colorScheme.error)
        }
    }

    if (showDeleteConfirm && groupId != null) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("確認刪除轉帳？") },
            text = { Text("刪除後無法復原。") },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    scope.launch {
                        repository.deleteTransferGroup(UUID.fromString(groupId))
                        onDone()
                    }
                }) { Text("刪除", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("取消") }
            }
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
    CurrencyPicker(
        selected = selected,
        onSelect = onSelect,
        buttonStyle = CurrencyButtonStyle.Tonal
    )
}

@Composable
private fun TransferLegEditor(
    title: String,
    leg: TransferEditLegInput,
    accounts: List<AccountEntity>,
    onUpdate: (TransferEditLegInput) -> Unit,
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
