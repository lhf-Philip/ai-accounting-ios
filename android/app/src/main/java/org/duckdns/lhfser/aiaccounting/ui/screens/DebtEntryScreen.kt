package org.duckdns.lhfser.aiaccounting.ui.screens

import android.app.DatePickerDialog
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.core.model.TransferSide
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionEntity
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyButtonStyle
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyPicker
import org.duckdns.lhfser.aiaccounting.ui.components.ParityEmptyState
import org.duckdns.lhfser.aiaccounting.ui.components.ParityMenuField
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySectionHeader
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySegmentedControl
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySummaryCard
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTopSection
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTokens
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateText
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

private enum class DebtMode(val label: String) {
    Borrow("借入 (我欠人)"),
    Repay("還款 (還給人)")
}

private enum class DebtEntryMode(val label: String) {
    Normal("一般"),
    Split("分拆 (1 -> 多)"),
    Merge("合併 (多 -> 1)")
}

private data class DebtSplitLeg(
    val id: UUID = UUID.randomUUID(),
    val account: AccountEntity? = null,
    val currency: String = "HKD",
    val amount: String = ""
)

private data class DebtMergeLeg(
    val id: UUID = UUID.randomUUID(),
    val currency: String = "HKD",
    val amount: String = ""
)

@Composable
fun DebtEntryScreen(onDone: () -> Unit) {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val scrollState = rememberScrollState()

    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val debtAccounts = remember(accounts) { accounts.filter { it.type == AccountType.Debt && !it.isArchived }.sortedBy { it.name } }
    val myAccounts = remember(accounts) { accounts.filter { it.type != AccountType.Debt && !it.isArchived }.sortedBy { it.sortOrder } }

    var mode by remember { mutableStateOf(DebtMode.Borrow) }
    var entryMode by remember { mutableStateOf(DebtEntryMode.Normal) }
    var selectedDebtAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var selectedMyAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var selectedCurrency by remember { mutableStateOf("HKD") }
    var amountInput by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var date by remember { mutableStateOf(Instant.now()) }
    var splitLegs by remember { mutableStateOf(listOf(DebtSplitLeg())) }
    var mergeLegs by remember { mutableStateOf(listOf(DebtMergeLeg())) }
    var validationMessage by remember { mutableStateOf<String?>(null) }

    if (selectedDebtAccount == null && debtAccounts.isNotEmpty()) {
        selectedDebtAccount = debtAccounts.first()
    }
    if (selectedMyAccount == null && myAccounts.isNotEmpty()) {
        selectedMyAccount = myAccounts.first()
        selectedCurrency = selectedMyAccount?.currency ?: selectedCurrency
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(scrollState)
            .padding(
                start = AppSpacing.screenHorizontal,
                end = AppSpacing.screenHorizontal,
                top = AppSpacing.screenVertical,
                bottom = AppSpacing.screenVertical + ParityTokens.FloatingContentBottomPadding
            ),
        verticalArrangement = Arrangement.spacedBy(AppSpacing.section)
    ) {
        ParityTopSection(
            title = "借貸管理",
            subtitle = "和 iOS 一樣，借貸會落成一組或多組轉帳分錄，方便之後繼續編輯與對帳。"
        )

        SectionCard {
            ParitySectionHeader(
                title = "借貸方式",
                detail = "先選操作，再決定一般 / 分拆 / 合併模式"
            )
            ParitySegmentedControl(
                options = DebtMode.values().toList(),
                selected = mode,
                label = { it.label },
                onSelect = { mode = it }
            )
            ParitySegmentedControl(
                options = DebtEntryMode.values().toList(),
                selected = entryMode,
                label = { it.label },
                onSelect = { entryMode = it }
            )
        }

        if (debtAccounts.isEmpty()) {
            ParityEmptyState(
                title = "還沒有借貸對象",
                message = "先到帳戶頁建立類型為借貸的帳戶，之後才能記錄借入與還款流程。"
            )
        } else {
            SectionCard {
                ParitySectionHeader(
                    title = "帳戶與對象",
                    detail = "選擇借貸對象與你的實際資金帳戶"
                )
                AccountMenuPicker(
                    label = if (mode == DebtMode.Borrow) "跟誰借" else "還給誰",
                    options = debtAccounts,
                    selected = selectedDebtAccount,
                    onSelect = { selectedDebtAccount = it }
                )
                if (entryMode != DebtEntryMode.Split) {
                    AccountMenuPicker(
                        label = if (mode == DebtMode.Borrow) "存入帳戶" else "付款帳戶",
                        options = myAccounts,
                        selected = selectedMyAccount,
                        onSelect = {
                            selectedMyAccount = it
                            if (it != null) {
                                selectedCurrency = it.currency
                            }
                        }
                    )
                }
            }
        }

        SectionCard {
            ParitySectionHeader(
                title = "金額與時間",
                detail = "這裡的資料會直接影響之後產生的轉帳分錄"
            )
            when (entryMode) {
                DebtEntryMode.Normal -> {
                    AmountCurrencyRow(
                        amount = amountInput,
                        onAmountChange = { amountInput = sanitizeAmount(it) },
                        currency = selectedCurrency,
                        onCurrencyChange = { selectedCurrency = it }
                    )
                }
                DebtEntryMode.Split -> {
                    splitLegs.forEachIndexed { index, leg ->
                        DebtSplitLegEditor(
                            index = index,
                            leg = leg,
                            accounts = myAccounts,
                            onUpdate = { updated ->
                                splitLegs = splitLegs.toMutableList().also { it[index] = updated }
                            },
                            onRemove = if (splitLegs.size > 1) {
                                { splitLegs = splitLegs.toMutableList().also { it.removeAt(index) } }
                            } else null
                        )
                    }
                    TextButton(onClick = { splitLegs = splitLegs + DebtSplitLeg(currency = selectedCurrency) }) {
                        Text("新增分拆帳戶")
                    }
                }
                DebtEntryMode.Merge -> {
                    mergeLegs.forEachIndexed { index, leg ->
                        DebtMergeLegEditor(
                            index = index,
                            leg = leg,
                            onUpdate = { updated ->
                                mergeLegs = mergeLegs.toMutableList().also { it[index] = updated }
                            },
                            onRemove = if (mergeLegs.size > 1) {
                                { mergeLegs = mergeLegs.toMutableList().also { it.removeAt(index) } }
                            } else null
                        )
                    }
                    TextButton(onClick = { mergeLegs = mergeLegs + DebtMergeLeg(currency = selectedCurrency) }) {
                        Text("新增合併金額項")
                    }
                }
            }

            TextButton(onClick = {
                val localDate = date.atZone(ZoneId.systemDefault()).toLocalDate()
                DatePickerDialog(
                    context,
                    { _, year, month, day ->
                        date = LocalDate.of(year, month + 1, day)
                            .atStartOfDay(ZoneId.systemDefault())
                            .toInstant()
                    },
                    localDate.year,
                    localDate.monthValue - 1,
                    localDate.dayOfMonth
                ).show()
            }) {
                Text("日期：${date.toDateText()}")
            }

            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("備註") }
            )
        }

        ParitySummaryCard(
            title = "交易預覽",
            value = totalAmountPreview(entryMode, amountInput, splitLegs, mergeLegs),
            supporting = when (mode) {
                DebtMode.Borrow -> "借入會讓借貸帳戶出帳、你的帳戶入帳"
                DebtMode.Repay -> "還款會讓你的帳戶出帳、借貸帳戶入帳"
            }
        )

        if (validationMessage != null) {
            Text(validationMessage.orEmpty(), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }

        Button(
            onClick = {
                val debtAccount = selectedDebtAccount
                if (debtAccount == null) {
                    validationMessage = "請先選擇借貸對象。"
                    return@Button
                }
                val transactions = buildDebtTransactions(
                    mode = mode,
                    entryMode = entryMode,
                    debtAccount = debtAccount,
                    myAccount = selectedMyAccount,
                    date = date,
                    note = note,
                    currency = selectedCurrency,
                    amountInput = amountInput,
                    splitLegs = splitLegs,
                    mergeLegs = mergeLegs
                )
                if (transactions == null) {
                    validationMessage = "請輸入完整金額並選擇需要的帳戶。"
                    return@Button
                }
                scope.launch {
                    repository.upsertTransactions(transactions)
                    onDone()
                }
            },
            modifier = Modifier
                .fillMaxWidth()
                .height(50.dp),
            shape = androidx.compose.foundation.shape.RoundedCornerShape(18.dp),
            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary),
            enabled = debtAccounts.isNotEmpty() && myAccounts.isNotEmpty()
        ) {
            Text("確認")
        }
    }
}

@Composable
private fun AccountMenuPicker(
    label: String,
    options: List<AccountEntity>,
    selected: AccountEntity?,
    onSelect: (AccountEntity?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        ParityMenuField(
            label = label,
            value = selected?.name.orEmpty(),
            onClick = { expanded = true }
        )
        androidx.compose.material3.DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { account ->
                androidx.compose.material3.DropdownMenuItem(
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
private fun AmountCurrencyRow(
    amount: String,
    onAmountChange: (String) -> Unit,
    currency: String,
    onCurrencyChange: (String) -> Unit
) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.weight(1f)) {
            OutlinedTextField(
                value = amount,
                onValueChange = onAmountChange,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("金額") }
            )
        }
        CurrencyPicker(selected = currency, onSelect = onCurrencyChange, buttonStyle = CurrencyButtonStyle.Text)
    }
}

@Composable
private fun DebtSplitLegEditor(
    index: Int,
    leg: DebtSplitLeg,
    accounts: List<AccountEntity>,
    onUpdate: (DebtSplitLeg) -> Unit,
    onRemove: (() -> Unit)?
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        AccountMenuPicker(
            label = "分拆帳戶 ${index + 1}",
            options = accounts,
            selected = leg.account,
            onSelect = {
                onUpdate(leg.copy(account = it, currency = it?.currency ?: leg.currency))
            }
        )
        AmountCurrencyRow(
            amount = leg.amount,
            onAmountChange = { onUpdate(leg.copy(amount = sanitizeAmount(it))) },
            currency = leg.currency,
            onCurrencyChange = { onUpdate(leg.copy(currency = it)) }
        )
        if (onRemove != null) {
            TextButton(onClick = onRemove) { Text("移除此帳戶") }
        }
    }
}

@Composable
private fun DebtMergeLegEditor(
    index: Int,
    leg: DebtMergeLeg,
    onUpdate: (DebtMergeLeg) -> Unit,
    onRemove: (() -> Unit)?
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("合併金額項 ${index + 1}", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
        AmountCurrencyRow(
            amount = leg.amount,
            onAmountChange = { onUpdate(leg.copy(amount = sanitizeAmount(it))) },
            currency = leg.currency,
            onCurrencyChange = { onUpdate(leg.copy(currency = it)) }
        )
        if (onRemove != null) {
            TextButton(onClick = onRemove) { Text("移除此金額項") }
        }
    }
}

private fun buildDebtTransactions(
    mode: DebtMode,
    entryMode: DebtEntryMode,
    debtAccount: AccountEntity,
    myAccount: AccountEntity?,
    date: Instant,
    note: String,
    currency: String,
    amountInput: String,
    splitLegs: List<DebtSplitLeg>,
    mergeLegs: List<DebtMergeLeg>
): List<TransactionEntity>? {
    return when (entryMode) {
        DebtEntryMode.Normal -> {
            val account = myAccount ?: return null
            val amount = amountInput.toBigDecimalOrNull()?.takeIf { it > BigDecimal.ZERO } ?: return null
            createDebtPair(mode, debtAccount, account, amount, currency, date, note)
        }
        DebtEntryMode.Split -> {
            val legs = splitLegs.map { leg ->
                val account = leg.account ?: return null
                val amount = leg.amount.toBigDecimalOrNull()?.takeIf { it > BigDecimal.ZERO } ?: return null
                Triple(account, amount, leg.currency)
            }
            legs.flatMapIndexed { index, (account, amount, legCurrency) ->
                createDebtPair(mode, debtAccount, account, amount, legCurrency, date, indexedMemo(note, entryMode, index, legs.size))
            }
        }
        DebtEntryMode.Merge -> {
            val account = myAccount ?: return null
            val items = mergeLegs.map { leg ->
                val amount = leg.amount.toBigDecimalOrNull()?.takeIf { it > BigDecimal.ZERO } ?: return null
                amount to leg.currency
            }
            items.flatMapIndexed { index, (amount, legCurrency) ->
                createDebtPair(mode, debtAccount, account, amount, legCurrency, date, indexedMemo(note, entryMode, index, items.size))
            }
        }
    }
}

private fun createDebtPair(
    mode: DebtMode,
    debtAccount: AccountEntity,
    myAccount: AccountEntity,
    amount: BigDecimal,
    currencyCode: String,
    date: Instant,
    memo: String
): List<TransactionEntity> {
    val finalMemo = memo.trim().ifBlank { mode.label }
    val groupId = UUID.randomUUID()
    val firstId = UUID.randomUUID()
    val secondId = UUID.randomUUID()
    return if (mode == DebtMode.Borrow) {
        listOf(
            TransactionEntity(
                id = firstId,
                amount = amount.abs().negate(),
                currencyCode = currencyCode,
                date = date,
                note = "$finalMemo (借入至 ${myAccount.name})",
                photoPath = null,
                type = TransactionType.Transfer,
                linkedTransactionId = secondId,
                transferGroupId = groupId,
                transferSide = TransferSide.Outgoing,
                createdAt = Instant.now(),
                updatedAt = Instant.now(),
                accountId = debtAccount.id,
                categoryId = null
            ),
            TransactionEntity(
                id = secondId,
                amount = amount.abs(),
                currencyCode = currencyCode,
                date = date,
                note = "$finalMemo (來自 ${debtAccount.name})",
                photoPath = null,
                type = TransactionType.Transfer,
                linkedTransactionId = firstId,
                transferGroupId = groupId,
                transferSide = TransferSide.Incoming,
                createdAt = Instant.now(),
                updatedAt = Instant.now(),
                accountId = myAccount.id,
                categoryId = null
            )
        )
    } else {
        listOf(
            TransactionEntity(
                id = firstId,
                amount = amount.abs().negate(),
                currencyCode = currencyCode,
                date = date,
                note = "$finalMemo (還款給 ${debtAccount.name})",
                photoPath = null,
                type = TransactionType.Transfer,
                linkedTransactionId = secondId,
                transferGroupId = groupId,
                transferSide = TransferSide.Outgoing,
                createdAt = Instant.now(),
                updatedAt = Instant.now(),
                accountId = myAccount.id,
                categoryId = null
            ),
            TransactionEntity(
                id = secondId,
                amount = amount.abs(),
                currencyCode = currencyCode,
                date = date,
                note = "$finalMemo (來自 ${myAccount.name})",
                photoPath = null,
                type = TransactionType.Transfer,
                linkedTransactionId = firstId,
                transferGroupId = groupId,
                transferSide = TransferSide.Incoming,
                createdAt = Instant.now(),
                updatedAt = Instant.now(),
                accountId = debtAccount.id,
                categoryId = null
            )
        )
    }
}

private fun totalAmountPreview(
    entryMode: DebtEntryMode,
    amountInput: String,
    splitLegs: List<DebtSplitLeg>,
    mergeLegs: List<DebtMergeLeg>
): String {
    val total = when (entryMode) {
        DebtEntryMode.Normal -> amountInput.toBigDecimalOrNull()
        DebtEntryMode.Split -> splitLegs.mapNotNull { it.amount.toBigDecimalOrNull() }.takeIf { it.size == splitLegs.size }?.fold(BigDecimal.ZERO, BigDecimal::add)
        DebtEntryMode.Merge -> mergeLegs.mapNotNull { it.amount.toBigDecimalOrNull() }.takeIf { it.size == mergeLegs.size }?.fold(BigDecimal.ZERO, BigDecimal::add)
    }
    return total?.toPlainString() ?: "尚未完成輸入"
}

private fun sanitizeAmount(input: String): String {
    var hasDot = false
    return buildString {
        input.forEach { char ->
            when {
                char.isDigit() -> append(char)
                char == '.' && !hasDot -> {
                    append(char)
                    hasDot = true
                }
            }
        }
    }.removePrefix(".")
}

private fun indexedMemo(base: String, mode: DebtEntryMode, index: Int, count: Int): String {
    val suffix = when (mode) {
        DebtEntryMode.Split -> "[分拆 ${index + 1}/$count]"
        DebtEntryMode.Merge -> "[合併 ${index + 1}/$count]"
        DebtEntryMode.Normal -> ""
    }
    val trimmed = base.trim()
    return listOf(trimmed, suffix).filter { it.isNotBlank() }.joinToString(" ")
}
