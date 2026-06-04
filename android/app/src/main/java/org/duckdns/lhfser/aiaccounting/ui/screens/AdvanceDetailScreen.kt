package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
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
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceParticipantEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.TagEntity
import org.duckdns.lhfser.aiaccounting.ui.LocalCurrencyService
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyPicker
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyButtonStyle
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateText
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

private enum class RepaymentMode(val label: String) {
    Normal("一般"),
    Split("分拆 (1 -> 多)"),
    Merge("合併 (多 -> 1)")
}

private data class RepaymentSplitLeg(
    val id: String = UUID.randomUUID().toString(),
    var account: AccountEntity? = null,
    var currency: String = "HKD",
    var amount: String = ""
)

private data class RepaymentMergeLeg(
    val id: String = UUID.randomUUID().toString(),
    var currency: String = "HKD",
    var amount: String = ""
)

@Composable
fun AdvanceDetailScreen(caseId: String?) {
    val repository = LocalRepository.current
    val currencyService = LocalCurrencyService.current
    val scope = rememberCoroutineScope()
    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val categories by repository.categories.collectAsState(initial = emptyList())
    val tags by repository.tags.collectAsState(initial = emptyList())

    var advanceCase by remember { mutableStateOf<AdvanceCaseWithDetails?>(null) }

    LaunchedEffect(caseId) {
        val id = caseId?.let(UUID::fromString) ?: return@LaunchedEffect
        advanceCase = repository.getAdvanceCase(id)
    }

    val receiveAccounts = accounts.filter { it.type != AccountType.Debt && !it.isArchived }

    var selectedParticipant by remember { mutableStateOf<AdvanceParticipantEntity?>(null) }
    var selectedReceiveAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var selectedCategory by remember { mutableStateOf<CategoryEntity?>(null) }
    var selectedTags by remember { mutableStateOf<List<TagEntity>>(emptyList()) }
    var amountInput by remember { mutableStateOf("") }
    var settlementAmountInput by remember { mutableStateOf("") }
    var settlementManuallyEdited by remember { mutableStateOf(false) }
    var note by remember { mutableStateOf("") }
    var selectedCurrency by remember { mutableStateOf("HKD") }
    var mode by remember { mutableStateOf(RepaymentMode.Normal) }
    var isBorrowedByMe by remember { mutableStateOf(false) }
    var splitLegs by remember { mutableStateOf(listOf(RepaymentSplitLeg())) }
    var mergeLegs by remember { mutableStateOf(listOf(RepaymentMergeLeg())) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    if (advanceCase == null) {
        Column(modifier = Modifier.padding(AppSpacing.screenHorizontal)) {
            Text("載入中...", style = MaterialTheme.typography.bodyLarge)
        }
        return
    }

    val caseData = advanceCase ?: return
    val caseCurrency = caseData.advanceCase.currencyCode
    val directionalCategories = if (isBorrowedByMe) {
        categories.filter { it.kind.supports(TransactionType.Expense) }
    } else {
        categories.filter { it.kind.supports(TransactionType.Income) }
    }
    val accountLabel = if (isBorrowedByMe) "付款帳戶" else "入帳帳戶"

    LaunchedEffect(caseData.participants) {
        if (selectedParticipant == null) {
            selectedParticipant = caseData.participants.firstOrNull()
        }
        val firstParticipant = caseData.participants.firstOrNull()
        val groupId = firstParticipant?.initialTransferGroupId
        if (groupId != null) {
            val transfers = repository.getTransferGroup(groupId)
            val outgoing = transfers.firstOrNull {
                it.transaction.transferSide == org.duckdns.lhfser.aiaccounting.core.model.TransferSide.Outgoing ||
                    it.transaction.amount < BigDecimal.ZERO
            }?.transaction
            isBorrowedByMe = when {
                outgoing == null -> false
                outgoing.accountId != null && outgoing.accountId == firstParticipant.debtAccountId -> true
                outgoing.note.contains("(代墊給我") -> true
                else -> false
            }
        } else {
            isBorrowedByMe = false
        }
    }

    LaunchedEffect(receiveAccounts) {
        if (selectedReceiveAccount == null) {
            selectedReceiveAccount = receiveAccounts.firstOrNull()
        }
        selectedReceiveAccount?.let { selectedCurrency = it.currency }
        if (splitLegs.firstOrNull()?.account == null) {
            val defaultAccount = receiveAccounts.firstOrNull()
            if (defaultAccount != null) {
                    splitLegs = splitLegs.toMutableList().also {
                        it[0] = it[0].copy(account = defaultAccount, currency = defaultAccount.currency)
                    }
            }
        }
    }

    LaunchedEffect(directionalCategories) {
        if (selectedCategory != null && directionalCategories.none { it.id == selectedCategory?.id }) {
            selectedCategory = null
        }
    }

    val remaining = selectedParticipant?.let {
        (it.owedAmount - it.repaidAmount).max(BigDecimal.ZERO)
    } ?: BigDecimal.ZERO
    val parsedAmount = parsePositive(amountInput)
    val isCrossCurrencyRepayment = !selectedCurrency.equals(caseCurrency, ignoreCase = true)
    val settlementEstimate = parsedAmount?.let { currencyService.estimate(it, selectedCurrency, caseCurrency) }
    val parsedSettlementAmount = if (isCrossCurrencyRepayment) {
        parsePositive(settlementAmountInput)
    } else {
        parsedAmount
    }

    val canSubmit = when (mode) {
        RepaymentMode.Normal -> selectedParticipant != null &&
            selectedReceiveAccount != null &&
            parsedAmount != null &&
            parsedSettlementAmount != null
        RepaymentMode.Split -> selectedParticipant != null &&
            splitLegs.isNotEmpty() &&
            splitLegs.all { it.account != null && parsePositive(it.amount) != null }
        RepaymentMode.Merge -> selectedParticipant != null &&
            selectedReceiveAccount != null &&
            mergeLegs.isNotEmpty() &&
            mergeLegs.all { parsePositive(it.amount) != null }
    }

    LaunchedEffect(amountInput, selectedCurrency, caseCurrency, mode) {
        if (mode == RepaymentMode.Normal && !settlementManuallyEdited) {
            settlementAmountInput = if (isCrossCurrencyRepayment) {
                settlementEstimate?.amount?.stripTrailingZeros()?.toPlainString().orEmpty()
            } else {
                amountInput
            }
        }
    }

    LazyColumn(
        modifier = Modifier.padding(horizontal = AppSpacing.screenHorizontal, vertical = AppSpacing.screenVertical),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Text("案件資訊", style = MaterialTheme.typography.titleMedium)
            SectionCard {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(caseData.advanceCase.title, style = MaterialTheme.typography.titleLarge)
                    Text("日期：${caseData.advanceCase.date.toDateText()}")
                    Text("幣種：$caseCurrency")
                    Text("備註：${caseData.advanceCase.note.ifBlank { "-" }}")
                }
            }
        }

        item {
            Text("代墊對象", style = MaterialTheme.typography.titleMedium)
            SectionCard {
                caseData.participants.forEach { participant ->
                    ParticipantRow(participant = participant, currency = caseCurrency)
                }
            }
        }

        item {
            Text("記錄還款", style = MaterialTheme.typography.titleMedium)
            SectionCard {
                ParticipantPicker(
                    participants = caseData.participants,
                    selected = selectedParticipant,
                    onSelect = { selectedParticipant = it }
                )

                Text("模式", style = MaterialTheme.typography.titleSmall)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    RepaymentMode.values().forEach { item ->
                        FilterChip(
                            selected = mode == item,
                            onClick = { mode = item },
                            label = { Text(item.label) }
                        )
                    }
                }

                if (mode != RepaymentMode.Split) {
                    AccountPicker(
                        label = accountLabel,
                        accounts = receiveAccounts,
                        selected = selectedReceiveAccount,
                        onSelect = { acc ->
                            selectedReceiveAccount = acc
                            if (acc != null) selectedCurrency = acc.currency
                        }
                    )
                }

                when (mode) {
                    RepaymentMode.Normal -> {
                        AmountRow(
                            label = "還款金額",
                            amount = amountInput,
                            onAmountChange = { amountInput = sanitizeAmount(it) },
                            currency = selectedCurrency,
                            onCurrencyChange = { selectedCurrency = it }
                        )
                        if (isCrossCurrencyRepayment) {
                            SettlementAmountRow(
                                amount = settlementAmountInput,
                                onAmountChange = {
                                    settlementAmountInput = sanitizeAmount(it)
                                    settlementManuallyEdited = true
                                },
                                caseCurrency = caseCurrency,
                                estimateText = settlementEstimate?.let {
                                    "建議 ${it.amount.asCurrencyText(caseCurrency)}（${it.source.label}）"
                                } ?: "暫時無法取得匯率，請手動填入要沖銷的 $caseCurrency 金額。"
                            )
                        } else if (settlementEstimate != null) {
                            Text(
                                "沖銷 ${settlementEstimate.amount.asCurrencyText(caseCurrency)}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    RepaymentMode.Split -> {
                        splitLegs.forEach { leg ->
                            SplitLegEditor(
                                leg = leg,
                                accounts = receiveAccounts,
                                accountLabel = accountLabel,
                                onUpdate = { updated ->
                                    splitLegs = splitLegs.map { if (it.id == leg.id) updated else it }
                                },
                                onRemove = if (splitLegs.size > 1) {
                                    { splitLegs = splitLegs.filterNot { it.id == leg.id } }
                                } else null
                            )
                        }
                        TextButton(onClick = { splitLegs = splitLegs + RepaymentSplitLeg() }) {
                            Text(if (isBorrowedByMe) "新增分拆付款帳戶" else "新增分拆入帳帳戶")
                        }
                    }
                    RepaymentMode.Merge -> {
                        mergeLegs.forEach { leg ->
                            MergeLegEditor(
                                leg = leg,
                                onUpdate = { updated ->
                                    mergeLegs = mergeLegs.map { if (it.id == leg.id) updated else it }
                                },
                                onRemove = if (mergeLegs.size > 1) {
                                    { mergeLegs = mergeLegs.filterNot { it.id == leg.id } }
                                } else null
                            )
                        }
                        TextButton(onClick = { mergeLegs = mergeLegs + RepaymentMergeLeg(currency = selectedCurrency) }) {
                            Text("新增合併金額項")
                        }
                    }
                }

                CategoryPicker(categories = directionalCategories, selected = selectedCategory) {
                    selectedCategory = it
                }
                TagPicker(tags = tags, selected = selectedTags, onChange = { selectedTags = it })
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text("備註") },
                    modifier = Modifier.fillMaxWidth()
                )

                Button(
                    onClick = {
                        scope.launch {
                            val participant = selectedParticipant ?: return@launch
                            when (mode) {
	                                RepaymentMode.Normal -> {
	                                    val receiveAccount = selectedReceiveAccount ?: return@launch
	                                    val amount = parsePositive(amountInput) ?: return@launch
	                                    val normalizedAmount = parsedSettlementAmount ?: return@launch
	                                    if (normalizedAmount - remaining > BigDecimal("0.0001")) {
	                                        errorMessage = "沖銷金額超過未還餘額。"
	                                        return@launch
	                                    }
	                                    recordSingleRepayment(
	                                        repository = repository,
	                                        advanceCase = caseData,
	                                        participant = participant,
	                                        receiveAccount = receiveAccount,
	                                        amount = amount,
	                                        currency = selectedCurrency,
	                                        normalizedAmount = normalizedAmount,
	                                        note = note,
	                                        category = selectedCategory,
	                                        tagIds = selectedTags.map { it.id },
                                        isBorrowedByMe = isBorrowedByMe
                                    )
                                }
                                RepaymentMode.Split -> {
                                    val legs = splitLegs.mapNotNull { leg ->
                                        val account = leg.account ?: return@mapNotNull null
	                                        val amount = parsePositive(leg.amount) ?: return@mapNotNull null
	                                        Triple(account, amount, leg.currency)
	                                    }
	                                    val normalizedLegs = legs.map { leg ->
	                                        normalizedAmount(currencyService, leg.second, leg.third, caseCurrency)
	                                    }
	                                    if (normalizedLegs.any { it == null }) {
	                                        errorMessage = "暫時無法取得其中一項幣種的匯率，請改用一般模式並手動輸入沖銷金額。"
	                                        return@launch
	                                    }
	                                    if (!validateTotal(remaining, normalizedLegs.filterNotNull())) {
	                                        errorMessage = "分拆總金額超過未還餘額。"
	                                        return@launch
	                                    }
	                                    legs.forEachIndexed { index, leg ->
	                                        recordSingleRepayment(
	                                            repository = repository,
	                                            advanceCase = caseData,
	                                            participant = participant,
	                                            receiveAccount = leg.first,
	                                            amount = leg.second,
	                                            currency = leg.third,
	                                            normalizedAmount = normalizedLegs[index] ?: return@launch,
	                                            note = indexedNote(note, "分拆", index, legs.size),
	                                            category = selectedCategory,
	                                            tagIds = selectedTags.map { it.id },
                                            isBorrowedByMe = isBorrowedByMe
                                        )
                                    }
                                }
                                RepaymentMode.Merge -> {
                                    val receiveAccount = selectedReceiveAccount ?: return@launch
                                    val legs = mergeLegs.mapNotNull { leg ->
	                                        val amount = parsePositive(leg.amount) ?: return@mapNotNull null
	                                        amount to leg.currency
	                                    }
	                                    val normalizedLegs = legs.map { leg ->
	                                        normalizedAmount(currencyService, leg.first, leg.second, caseCurrency)
	                                    }
	                                    if (normalizedLegs.any { it == null }) {
	                                        errorMessage = "暫時無法取得其中一項幣種的匯率，請改用一般模式並手動輸入沖銷金額。"
	                                        return@launch
	                                    }
	                                    if (!validateTotal(remaining, normalizedLegs.filterNotNull())) {
	                                        errorMessage = "合併總金額超過未還餘額。"
	                                        return@launch
	                                    }
	                                    legs.forEachIndexed { index, item ->
	                                        recordSingleRepayment(
	                                            repository = repository,
	                                            advanceCase = caseData,
	                                            participant = participant,
	                                            receiveAccount = receiveAccount,
	                                            amount = item.first,
	                                            currency = item.second,
	                                            normalizedAmount = normalizedLegs[index] ?: return@launch,
	                                            note = indexedNote(note, "合併", index, legs.size),
	                                            category = selectedCategory,
                                            tagIds = selectedTags.map { it.id },
                                            isBorrowedByMe = isBorrowedByMe
                                        )
                                    }
                                }
                            }
                            errorMessage = null
                            amountInput = ""
                            note = ""
                            advanceCase = repository.getAdvanceCase(caseData.advanceCase.id)
                        }
                    },
                    enabled = canSubmit
                ) {
                    Text("儲存")
                }

                if (errorMessage != null) {
                    Text(errorMessage ?: "", color = MaterialTheme.colorScheme.error)
                }
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
private fun SettlementAmountRow(
    amount: String,
    onAmountChange: (String) -> Unit,
    caseCurrency: String,
    estimateText: String
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("沖銷代墊金額", style = MaterialTheme.typography.titleSmall)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedTextField(
                value = amount,
                onValueChange = onAmountChange,
                label = { Text("沖銷金額") },
                modifier = Modifier.weight(1f)
            )
            Text(
                caseCurrency,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 16.dp)
            )
        }
        Text(
            estimateText,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
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

@Composable
private fun SplitLegEditor(
    leg: RepaymentSplitLeg,
    accounts: List<AccountEntity>,
    accountLabel: String,
    onUpdate: (RepaymentSplitLeg) -> Unit,
    onRemove: (() -> Unit)?
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        AccountPicker(label = accountLabel, accounts = accounts, selected = leg.account) { acc ->
            onUpdate(leg.copy(account = acc, currency = acc?.currency ?: leg.currency))
        }
        AmountRow(
            label = "還款金額",
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

@Composable
private fun MergeLegEditor(
    leg: RepaymentMergeLeg,
    onUpdate: (RepaymentMergeLeg) -> Unit,
    onRemove: (() -> Unit)?
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        AmountRow(
            label = "還款金額",
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

private fun validateTotal(remaining: BigDecimal, normalizedAmounts: List<BigDecimal>): Boolean {
    val totalNormalized = normalizedAmounts.fold(BigDecimal.ZERO) { acc, item -> acc + item.abs() }
    val tolerance = BigDecimal("0.0001")
    return totalNormalized - remaining <= tolerance
}

private fun normalizedAmount(
    currencyService: org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService,
    amount: BigDecimal,
    currency: String,
    caseCurrency: String
): BigDecimal? {
    if (currency.equals(caseCurrency, ignoreCase = true)) return amount.abs()
    return currencyService.estimate(amount.abs(), currency, caseCurrency)?.amount
}

private suspend fun recordSingleRepayment(
    repository: org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository,
    advanceCase: AdvanceCaseWithDetails,
    participant: AdvanceParticipantEntity,
    receiveAccount: AccountEntity,
    amount: BigDecimal,
    currency: String,
    normalizedAmount: BigDecimal,
    note: String,
    category: CategoryEntity?,
    tagIds: List<UUID>,
    isBorrowedByMe: Boolean
) {
    repository.recordAdvanceRepayment(
        advanceCase = advanceCase.advanceCase,
        participant = participant,
        amount = amount.abs(),
        normalizedAmount = normalizedAmount.abs(),
        currencyCode = currency,
        date = Instant.now(),
        note = note.trim(),
        receiveAccount = receiveAccount,
        category = category,
        tagIds = tagIds,
        isBorrowedByMe = isBorrowedByMe
    )
}

private fun indexedNote(base: String, mode: String, index: Int, count: Int): String {
    val suffix = "[$mode ${index + 1}/$count]"
    val trimmed = base.trim()
    return if (trimmed.isBlank()) suffix else "$trimmed $suffix"
}
