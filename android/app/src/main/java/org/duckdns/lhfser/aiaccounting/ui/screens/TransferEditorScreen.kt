package org.duckdns.lhfser.aiaccounting.ui.screens

import android.app.DatePickerDialog
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
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
import org.duckdns.lhfser.aiaccounting.core.model.TransferSide
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.repository.TransferGroupReplacementDraft
import org.duckdns.lhfser.aiaccounting.data.repository.TransferGroupSemantic
import org.duckdns.lhfser.aiaccounting.data.repository.TransferReplacementLeg
import org.duckdns.lhfser.aiaccounting.ui.LocalCurrencyService
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyButtonStyle
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyPicker
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyRateHint
import org.duckdns.lhfser.aiaccounting.ui.components.ParityMenuField
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySectionHeader
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySegmentedControl
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTokens
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard
import org.duckdns.lhfser.aiaccounting.ui.components.TransferRateHint
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateText
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
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
    val currencyService = LocalCurrencyService.current
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
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var isLoaded by remember { mutableStateOf(false) }
    var isEditable by remember { mutableStateOf(false) }
    val selectableAccountIds = buildSet {
        fromAccount?.id?.let(::add)
        toAccount?.id?.let(::add)
        sourceAccount?.id?.let(::add)
        destinationAccount?.id?.let(::add)
        destinationLegs.mapNotNullTo(this) { it.account?.id }
        sourceLegs.mapNotNullTo(this) { it.account?.id }
    }
    val selectableAccounts = accounts.filter { !it.isArchived || it.id in selectableAccountIds }

    LaunchedEffect(currencyService.mainCurrency) {
        currencyService.fetchRates()
    }

    LaunchedEffect(groupId) {
        val id = groupId?.let(UUID::fromString) ?: return@LaunchedEffect
        val classification = repository.classifyTransferGroup(id)
        if (classification?.semantic != TransferGroupSemantic.Ordinary) {
            errorMessage = when (classification?.semantic) {
                TransferGroupSemantic.Debt -> "這是債務管理分錄，請從債務管理編輯。"
                TransferGroupSemantic.AdvanceInitial,
                TransferGroupSemantic.AdvanceRepayment -> "這是代墊關聯分錄，請從代墊詳情編輯。"
                else -> "找不到可編輯的轉帳。"
            }
            isLoaded = true
            return@LaunchedEffect
        }
        val group = repository.getTransferGroup(id)
        if (group.isEmpty()) {
            errorMessage = "找不到可編輯的轉帳。"
            isLoaded = true
            return@LaunchedEffect
        }

        val outgoing = group.filter {
            it.transaction.transferSide == TransferSide.Outgoing || (
                it.transaction.transferSide == null && it.transaction.amount < BigDecimal.ZERO
            )
        }
        val incoming = group.filter {
            it.transaction.transferSide == TransferSide.Incoming || (
                it.transaction.transferSide == null && it.transaction.amount >= BigDecimal.ZERO
            )
        }
        val firstNote = group.firstOrNull { it.transaction.note.isNotBlank() }?.transaction?.note ?: ""
        note = firstNote
        date = (outgoing.firstOrNull() ?: incoming.first()).transaction.date
        when {
            outgoing.size == 1 && incoming.size == 1 -> {
                mode = TransferEditMode.OneToOne
                val outTx = outgoing.first()
                val inTx = incoming.first()
                fromAccount = outTx.account
                toAccount = inTx.account
                currencyOut = outTx.transaction.currencyCode
                currencyIn = inTx.transaction.currencyCode
                amountOut = outTx.transaction.amount.abs().toPlainString()
                amountIn = inTx.transaction.amount.abs().toPlainString()
            }
            outgoing.size == 1 && incoming.size > 1 -> {
                mode = TransferEditMode.OneToMany
                val outTx = outgoing.first()
                sourceAccount = outTx.account
                sourceCurrency = outTx.transaction.currencyCode
                sourceAmount = outTx.transaction.amount.abs().toPlainString()
                destinationLegs = incoming.map { tx ->
                    TransferEditLegInput(
                        account = tx.account,
                        currency = tx.transaction.currencyCode,
                        amount = tx.transaction.amount.abs().toPlainString()
                    )
                }
            }
            outgoing.size > 1 && incoming.size == 1 -> {
                mode = TransferEditMode.ManyToOne
                val inTx = incoming.first()
                destinationAccount = inTx.account
                destinationCurrency = inTx.transaction.currencyCode
                destinationAmount = inTx.transaction.amount.abs().toPlainString()
                sourceLegs = outgoing.map { tx ->
                    TransferEditLegInput(
                        account = tx.account,
                        currency = tx.transaction.currencyCode,
                        amount = tx.transaction.amount.abs().toPlainString()
                    )
                }
            }
            else -> errorMessage = "這組轉帳的分錄結構不完整，無法安全編輯。"
        }
        isEditable = errorMessage == null
        isLoaded = true
    }

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
        SectionCard {
            ParitySectionHeader(
                title = "轉帳模式",
                detail = "一般、分拆與合併都可以直接在這裡重新調整。"
            )
            ParitySegmentedControl(
                options = TransferEditMode.values().toList(),
                selected = mode,
                label = { it.label },
                onSelect = { mode = it }
            )
        }

        SectionCard {
            ParitySectionHeader(
                title = "轉帳內容",
                detail = "跨幣種時會顯示輸入匯率與目前可用的參考匯率。"
            )
            when (mode) {
                TransferEditMode.OneToOne -> {
                    AccountPicker(label = "轉出帳戶", accounts = selectableAccounts, selected = fromAccount) { acc ->
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
                    AccountPicker(label = "轉入帳戶", accounts = selectableAccounts, selected = toAccount) { acc ->
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
                TransferEditMode.OneToMany -> {
                    AccountPicker(label = "轉出帳戶", accounts = selectableAccounts, selected = sourceAccount) { acc ->
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
                            accounts = selectableAccounts,
                            currencyService = currencyService,
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
                    AccountPicker(label = "轉入帳戶", accounts = selectableAccounts, selected = destinationAccount) { acc ->
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
                            accounts = selectableAccounts,
                            currencyService = currencyService,
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

        SectionCard {
            ParitySectionHeader(
                title = "日期",
                detail = "修改後會重新建立這組轉帳，日期與備註會一起套用。"
            )
            TextButton(onClick = {
                showDatePicker(context, date) { picked ->
                    date = picked
                }
            }) {
                Text(date.toDateText())
            }
        }

        SectionCard {
            ParitySectionHeader(
                title = "備註",
                detail = "可補充用途、手動匯率或這次修改的原因。"
            )
            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                label = { Text("備註") },
                modifier = Modifier.fillMaxWidth()
            ,
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                keyboardActions = org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions())
        }

        Button(
            onClick = {
                scope.launch {
                    runCatching {
                        val id = requireNotNull(groupId?.let(UUID::fromString)) { "缺少轉帳識別資料。" }
                        val legs = when (mode) {
                            TransferEditMode.OneToOne -> listOf(
                                TransferReplacementLeg(
                                    accountId = requireNotNull(fromAccount?.id) { "請選擇轉出帳戶。" },
                                    currencyCode = currencyOut,
                                    amount = requireNotNull(parsePositive(amountOut)) { "請輸入有效轉出金額。" },
                                    side = TransferSide.Outgoing
                                ),
                                TransferReplacementLeg(
                                    accountId = requireNotNull(toAccount?.id) { "請選擇轉入帳戶。" },
                                    currencyCode = currencyIn,
                                    amount = requireNotNull(parsePositive(amountIn)) { "請輸入有效轉入金額。" },
                                    side = TransferSide.Incoming
                                )
                            )
                            TransferEditMode.OneToMany -> {
                                val source = requireNotNull(sourceAccount) { "請選擇轉出帳戶。" }
                                val sourceValue = requireNotNull(parsePositive(sourceAmount)) { "請輸入有效轉出總額。" }
                                listOf(
                                    TransferReplacementLeg(
                                        accountId = source.id,
                                        currencyCode = sourceCurrency,
                                        amount = sourceValue,
                                        side = TransferSide.Outgoing
                                    )
                                ) + destinationLegs.mapIndexed { index, leg ->
                                    TransferReplacementLeg(
                                        accountId = requireNotNull(leg.account?.id) { "請選擇轉入帳戶 ${index + 1}。" },
                                        currencyCode = leg.currency,
                                        amount = requireNotNull(parsePositive(leg.amount)) { "請輸入轉入帳戶 ${index + 1} 的有效金額。" },
                                        side = TransferSide.Incoming
                                    )
                                }
                            }
                            TransferEditMode.ManyToOne -> {
                                val destination = requireNotNull(destinationAccount) { "請選擇轉入帳戶。" }
                                val destinationValue = requireNotNull(parsePositive(destinationAmount)) { "請輸入有效轉入總額。" }
                                sourceLegs.mapIndexed { index, leg ->
                                    TransferReplacementLeg(
                                        accountId = requireNotNull(leg.account?.id) { "請選擇轉出帳戶 ${index + 1}。" },
                                        currencyCode = leg.currency,
                                        amount = requireNotNull(parsePositive(leg.amount)) { "請輸入轉出帳戶 ${index + 1} 的有效金額。" },
                                        side = TransferSide.Outgoing
                                    )
                                } + TransferReplacementLeg(
                                    accountId = destination.id,
                                    currencyCode = destinationCurrency,
                                    amount = destinationValue,
                                    side = TransferSide.Incoming
                                )
                            }
                        }
                        repository.replaceTransferGroup(
                            TransferGroupReplacementDraft(
                                groupId = id,
                                date = date,
                                note = note,
                                legs = legs
                            )
                        )
                    }.onSuccess {
                        onDone()
                    }.onFailure {
                        errorMessage = it.localizedMessage ?: "無法儲存轉帳。"
                    }
                }
            },
            enabled = isLoaded && isEditable
        ) {
            Text("儲存")
        }

        if (isEditable) {
            TextButton(onClick = { showDeleteConfirm = true }) {
                Text("刪除轉帳", color = MaterialTheme.colorScheme.error)
            }
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

    if (errorMessage != null) {
        AlertDialog(
            onDismissRequest = { errorMessage = null },
            title = { Text("無法編輯轉帳") },
            text = { Text(errorMessage.orEmpty()) },
            confirmButton = {
                TextButton(onClick = { errorMessage = null }) { Text("了解") }
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
    leg: TransferEditLegInput,
    accounts: List<AccountEntity>,
    currencyService: org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService,
    onUpdate: (TransferEditLegInput) -> Unit,
    onRemove: (() -> Unit)?
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        ParitySectionHeader(
            title = title,
            detail = "每個分錄都會用自己的幣別與金額計算。"
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
