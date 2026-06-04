package org.duckdns.lhfser.aiaccounting.ui.screens

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.repository.TransferLeg
import org.duckdns.lhfser.aiaccounting.ui.LocalCurrencyService
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyButtonStyle
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyPicker
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyRateHint
import org.duckdns.lhfser.aiaccounting.ui.components.ParityMenuField
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySegmentedControl
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTokens
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySectionHeader
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard
import org.duckdns.lhfser.aiaccounting.ui.components.TransferRateHint
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateTimeText
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

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
    val currencyService = LocalCurrencyService.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val scrollState = rememberScrollState()
    val activeAccounts = accounts.filter { !it.isArchived }

    LaunchedEffect(currencyService.mainCurrency) {
        currencyService.fetchRates()
    }

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
    var date by remember { mutableStateOf(Instant.now()) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                start = AppSpacing.screenHorizontal,
                top = AppSpacing.screenVertical,
                end = AppSpacing.screenHorizontal,
                bottom = AppSpacing.screenVertical + ParityTokens.FloatingContentBottomPadding
            )
            .verticalScroll(scrollState)
            .imePadding(),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        ParitySectionHeader(
            title = "轉帳模式",
            detail = "一般、分拆與合併都會對齊 iOS 的轉帳建立方式。"
        )
        SectionCard {
            ParitySegmentedControl(
                options = AddTransferMode.values().toList(),
                selected = mode,
                label = { it.label },
                onSelect = { mode = it }
            )
        }

        ParitySectionHeader(
            title = "轉帳內容",
            detail = "先決定來源與目的，再補每個分錄的實際金額。"
        )
        SectionCard {
            when (mode) {
                AddTransferMode.OneToOne -> {
                    AccountPicker(label = "轉出帳戶", accounts = activeAccounts, selected = fromAccount) { acc ->
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
                        onCurrencyChange = { currencyOut = it },
                        currencyService = currencyService
                    )
                    AccountPicker(label = "轉入帳戶", accounts = activeAccounts, selected = toAccount) { acc ->
                        toAccount = acc
                        if (acc != null) currencyIn = acc.currency
                    }
                    AmountRow(
                        label = "轉入金額",
                        amount = amountIn,
                        onAmountChange = { amountIn = sanitizeAmount(it) },
                        currency = currencyIn,
                        onCurrencyChange = { currencyIn = it },
                        currencyService = currencyService
                    )
                    TransferRateHint(
                        currencyService = currencyService,
                        outgoingAmount = parsePositive(amountOut),
                        outgoingCurrency = currencyOut,
                        incomingAmount = parsePositive(amountIn),
                        incomingCurrency = currencyIn
                    )
                }
                AddTransferMode.OneToMany -> {
                    AccountPicker(label = "轉出帳戶", accounts = activeAccounts, selected = sourceAccount) { acc ->
                        sourceAccount = acc
                        if (acc != null) sourceCurrency = acc.currency
                    }
                    AmountRow(
                        label = "轉出總額",
                        amount = sourceAmount,
                        onAmountChange = { sourceAmount = sanitizeAmount(it) },
                        currency = sourceCurrency,
                        onCurrencyChange = { sourceCurrency = it },
                        currencyService = currencyService
                    )
                    destinationLegs.forEachIndexed { index, leg ->
                        TransferLegEditor(
                            title = "轉入帳戶 ${index + 1}",
                            leg = leg,
                            accounts = activeAccounts,
                            currencyService = currencyService,
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
                    AccountPicker(label = "轉入帳戶", accounts = activeAccounts, selected = destinationAccount) { acc ->
                        destinationAccount = acc
                        if (acc != null) destinationCurrency = acc.currency
                    }
                    AmountRow(
                        label = "轉入總額",
                        amount = destinationAmount,
                        onAmountChange = { destinationAmount = sanitizeAmount(it) },
                        currency = destinationCurrency,
                        onCurrencyChange = { destinationCurrency = it },
                        currencyService = currencyService
                    )
                    sourceLegs.forEachIndexed { index, leg ->
                        TransferLegEditor(
                            title = "轉出帳戶 ${index + 1}",
                            leg = leg,
                            accounts = activeAccounts,
                            currencyService = currencyService,
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
        }

        ParitySectionHeader(
            title = "備註",
            detail = "可補充用途、匯率或這次轉帳的背景。"
        )
        SectionCard {
            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                label = { Text("備註") },
                modifier = Modifier.fillMaxWidth()
            ,
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                keyboardActions = org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions())
        }

        ParitySectionHeader(
            title = "日期與時間",
            detail = "預設為現在，也可以補記過去的轉帳。"
        )
        SectionCard {
            TextButton(onClick = { showDateTimePicker(context, date) { picked -> date = picked } }) {
                Text(date.toDateTimeText())
            }
        }

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
                                date = date,
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
                                date = date,
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
                                date = date,
                                note = note
                            )
                        }
                    }
                    onDone()
                }
            },
            modifier = Modifier.fillMaxWidth()
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
            ,
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                keyboardActions = org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions())
        }
        CurrencyRateHint(
            currencyService = currencyService,
            amount = parsePositive(amount),
            currencyCode = currency
        )
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
    leg: AddTransferLegInput,
    accounts: List<AccountEntity>,
    currencyService: org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService,
    onUpdate: (AddTransferLegInput) -> Unit,
    onRemove: (() -> Unit)?
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        ParitySectionHeader(
            title = title,
            detail = "可用不同帳戶與幣別拆分這次轉帳。"
        )
        AccountPicker(label = "帳戶", accounts = accounts, selected = leg.account) { acc ->
            onUpdate(leg.copy(account = acc, currency = acc?.currency ?: leg.currency))
        }
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

private fun showDateTimePicker(
    context: android.content.Context,
    initial: Instant,
    onPicked: (Instant) -> Unit
) {
    val zone = ZoneId.systemDefault()
    val initialDateTime = initial.atZone(zone).toLocalDateTime()
    DatePickerDialog(
        context,
        { _, year, month, day ->
            val pickedDate = LocalDate.of(year, month + 1, day)
            TimePickerDialog(
                context,
                { _, hour, minute ->
                    onPicked(pickedDate.atTime(hour, minute).atZone(zone).toInstant())
                },
                initialDateTime.hour,
                initialDateTime.minute,
                true
            ).show()
        },
        initialDateTime.year,
        initialDateTime.monthValue - 1,
        initialDateTime.dayOfMonth
    ).show()
}
