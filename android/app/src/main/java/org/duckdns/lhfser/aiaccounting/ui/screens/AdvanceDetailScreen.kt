package org.duckdns.lhfser.aiaccounting.ui.screens

import android.app.DatePickerDialog
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
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
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceParticipantEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceRepaymentEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.TagEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceInitialMetadataEditDraft
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceRepaymentCreateDraft
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceRepaymentEditDraft
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceSelfExpenseEditDraft
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
import java.time.ZoneId
import java.util.UUID

private enum class RepaymentMode(val label: String) {
    Normal("一般"),
    Split("分拆 (1 -> 多)"),
    Merge("合併 (多 -> 1)")
}

private enum class RepaymentRecordKind(val label: String) {
    Ordinary("還款"),
    MutualDebtOffset("債務抵銷"),
    ManualDebtSettlement("跨幣種平賬")
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
    val context = LocalContext.current
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
    var repaymentDate by remember { mutableStateOf(Instant.now()) }
    var editingRepayment by remember { mutableStateOf<AdvanceRepaymentEntity?>(null) }
    var repaymentToRollback by remember { mutableStateOf<AdvanceRepaymentEntity?>(null) }
    var participantToEdit by remember { mutableStateOf<AdvanceParticipantEntity?>(null) }
    var editedParticipantAmount by remember { mutableStateOf("") }
    var selfExpense by remember { mutableStateOf<TransactionWithDetails?>(null) }
    var isEditingSelfExpense by remember { mutableStateOf(false) }
    var selfExpenseAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var selfExpenseAmount by remember { mutableStateOf("") }
    var selfExpenseCurrency by remember { mutableStateOf("HKD") }
    var selfExpenseNormalizedAmount by remember { mutableStateOf("") }
    var selfExpenseCategory by remember { mutableStateOf<CategoryEntity?>(null) }
    var selfExpenseTags by remember { mutableStateOf<List<TagEntity>>(emptyList()) }
    var selfExpenseDate by remember { mutableStateOf(Instant.now()) }
    var selfExpenseNote by remember { mutableStateOf("") }
    var isEditingInitialMetadata by remember { mutableStateOf(false) }
    var initialPayerAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var initialCategory by remember { mutableStateOf<CategoryEntity?>(null) }
    var initialTags by remember { mutableStateOf<List<TagEntity>>(emptyList()) }
    var initialDate by remember { mutableStateOf(Instant.now()) }
    var initialNote by remember { mutableStateOf("") }

    if (advanceCase == null) {
        Column(modifier = Modifier.padding(AppSpacing.screenHorizontal)) {
            Text("載入中...", style = MaterialTheme.typography.bodyLarge)
        }
        return
    }

    val caseData = advanceCase ?: return
    val caseCurrency = caseData.advanceCase.currencyCode
    val selfExpenseCategories = categories.filter { it.kind.supports(TransactionType.Expense) }
    val directionalCategories = if (isBorrowedByMe) {
        categories.filter { it.kind.supports(TransactionType.Expense) }
    } else {
        categories.filter { it.kind.supports(TransactionType.Income) }
    }
    val accountLabel = if (isBorrowedByMe) "付款帳戶" else "入帳帳戶"

    LaunchedEffect(caseData.advanceCase.id, receiveAccounts, categories) {
        if (!isEditingInitialMetadata) {
            initialPayerAccount = receiveAccounts.firstOrNull {
                it.id == caseData.advanceCase.payerAccountId
            }
            initialCategory = categories.firstOrNull {
                it.id == caseData.advanceCase.expenseCategoryId
            }
            initialDate = caseData.advanceCase.date
            initialNote = caseData.advanceCase.note
        }
    }

    LaunchedEffect(caseData.advanceCase.selfExpenseTransactionId) {
        val transactionId = caseData.advanceCase.selfExpenseTransactionId
        val transaction = transactionId?.let { repository.getTransaction(it) }
        selfExpense = transaction
        if (!isEditingSelfExpense && transaction != null) {
            selfExpenseAccount = transaction.account
            selfExpenseAmount = transaction.transaction.amount.abs().stripTrailingZeros().toPlainString()
            selfExpenseCurrency = transaction.transaction.currencyCode
            selfExpenseNormalizedAmount =
                caseData.advanceCase.myShareAmount.stripTrailingZeros().toPlainString()
            selfExpenseCategory = transaction.category
            selfExpenseTags = transaction.tags
            selfExpenseDate = transaction.transaction.date
            selfExpenseNote = transaction.transaction.note
        }
    }

    LaunchedEffect(caseData.participants) {
        val selectedParticipantId = selectedParticipant?.id
        selectedParticipant = caseData.participants.firstOrNull {
            it.id == selectedParticipantId
        } ?: caseData.participants.firstOrNull()
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
            if (!isEditingInitialMetadata) {
                initialTags = if (isBorrowedByMe) {
                    transfers.firstOrNull()?.tags.orEmpty()
                } else {
                    emptyList()
                }
            }
        } else {
            isBorrowedByMe = false
        }
    }

    LaunchedEffect(receiveAccounts) {
        if (selectedReceiveAccount == null) {
            val defaultAccount = receiveAccounts.firstOrNull()
            selectedReceiveAccount = defaultAccount
            if (defaultAccount != null) {
                selectedCurrency = defaultAccount.currency
            }
        }
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
    val editableRemaining = remaining + (editingRepayment?.normalizedAmount ?: BigDecimal.ZERO)
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
                    if (!isEditingInitialMetadata) {
                        TextButton(onClick = {
                            initialPayerAccount = receiveAccounts.firstOrNull {
                                it.id == caseData.advanceCase.payerAccountId
                            }
                            initialCategory = categories.firstOrNull {
                                it.id == caseData.advanceCase.expenseCategoryId
                            }
                            initialDate = caseData.advanceCase.date
                            initialNote = caseData.advanceCase.note
                            scope.launch {
                                val firstGroupId =
                                    caseData.participants.firstOrNull()?.initialTransferGroupId
                                initialTags = if (isBorrowedByMe && firstGroupId != null) {
                                    repository.getTransferGroup(firstGroupId).firstOrNull()?.tags.orEmpty()
                                } else {
                                    emptyList()
                                }
                            }
                            isEditingInitialMetadata = true
                        }) {
                            Text("編輯案件記帳資料")
                        }
                    } else {
                        if (isBorrowedByMe) {
                            CategoryPicker(
                                categories = selfExpenseCategories,
                                selected = initialCategory,
                                onSelect = { initialCategory = it }
                            )
                            TagPicker(
                                tags = tags,
                                selected = initialTags,
                                onChange = { initialTags = it }
                            )
                            Text(
                                "他人代墊我不會使用自己的付款帳戶。",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        } else {
                            AccountPicker(
                                label = "付款帳戶",
                                accounts = receiveAccounts,
                                selected = initialPayerAccount,
                                onSelect = { initialPayerAccount = it }
                            )
                        }
                        TextButton(onClick = {
                            showRepaymentDatePicker(context, initialDate) {
                                initialDate = it
                            }
                        }) {
                            Text("日期：${initialDate.toDateText()}")
                        }
                        OutlinedTextField(
                            value = initialNote,
                            onValueChange = { initialNote = it },
                            label = { Text("備註") },
                            modifier = Modifier.fillMaxWidth(),
                            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                                imeAction = androidx.compose.ui.text.input.ImeAction.Done
                            ),
                            keyboardActions =
                                org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions()
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(
                                onClick = {
                                    scope.launch {
                                        runCatching {
                                            repository.updateAdvanceInitialMetadata(
                                                AdvanceInitialMetadataEditDraft(
                                                    caseId = caseData.advanceCase.id,
                                                    payerAccountId =
                                                        if (isBorrowedByMe) null else initialPayerAccount?.id,
                                                    date = initialDate,
                                                    note = initialNote,
                                                    categoryId =
                                                        if (isBorrowedByMe) initialCategory?.id else null,
                                                    tagIds =
                                                        if (isBorrowedByMe) initialTags.map { it.id }
                                                        else emptyList()
                                                )
                                            )
                                        }.onSuccess {
                                            advanceCase = repository.getAdvanceCase(caseData.advanceCase.id)
                                            isEditingInitialMetadata = false
                                            errorMessage = null
                                        }.onFailure {
                                            errorMessage = it.localizedMessage ?: "無法更新案件資料。"
                                        }
                                    }
                                },
                                enabled = isBorrowedByMe || initialPayerAccount != null
                            ) {
                                Text("儲存")
                            }
                            TextButton(onClick = { isEditingInitialMetadata = false }) {
                                Text("取消")
                            }
                        }
                    }
                }
            }
        }

        selfExpense?.let { expense ->
            item {
                Text("自己的份額", style = MaterialTheme.typography.titleMedium)
                SectionCard {
                    if (!isEditingSelfExpense) {
                        Text(
                            expense.transaction.amount.abs()
                                .asCurrencyText(expense.transaction.currencyCode),
                            style = MaterialTheme.typography.titleLarge
                        )
                        Text(
                            "案件份額 ${caseData.advanceCase.myShareAmount.asCurrencyText(caseCurrency)}",
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Text(
                            expense.account?.name ?: "未指定帳戶",
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        TextButton(onClick = {
                            selfExpenseAccount = expense.account
                            selfExpenseAmount =
                                expense.transaction.amount.abs().stripTrailingZeros().toPlainString()
                            selfExpenseCurrency = expense.transaction.currencyCode
                            selfExpenseNormalizedAmount =
                                caseData.advanceCase.myShareAmount.stripTrailingZeros().toPlainString()
                            selfExpenseCategory = expense.category
                            selfExpenseTags = expense.tags
                            selfExpenseDate = expense.transaction.date
                            selfExpenseNote = expense.transaction.note
                            isEditingSelfExpense = true
                        }) {
                            Text("編輯自己的份額")
                        }
                    } else {
                        AccountPicker(
                            label = "支出帳戶",
                            accounts = receiveAccounts,
                            selected = selfExpenseAccount,
                            onSelect = { selfExpenseAccount = it }
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            CurrencyPicker(
                                selected = selfExpenseCurrency,
                                onSelect = { selfExpenseCurrency = it },
                                buttonStyle = CurrencyButtonStyle.Text
                            )
                            OutlinedTextField(
                                value = selfExpenseAmount,
                                onValueChange = { selfExpenseAmount = sanitizeAmount(it) },
                                label = { Text("實際扣款") },
                                modifier = Modifier.weight(1f)
                            )
                        }
                        OutlinedTextField(
                            value = selfExpenseNormalizedAmount,
                            onValueChange = { selfExpenseNormalizedAmount = sanitizeAmount(it) },
                            label = { Text("案件中的自己份額 ($caseCurrency)") },
                            modifier = Modifier.fillMaxWidth()
                        )
                        Text(
                            "實際扣款可用其他幣種；案件份額用於代墊摘要。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        CategoryPicker(
                            categories = selfExpenseCategories,
                            selected = selfExpenseCategory,
                            onSelect = { selfExpenseCategory = it }
                        )
                        TagPicker(
                            tags = tags,
                            selected = selfExpenseTags,
                            onChange = { selfExpenseTags = it }
                        )
                        TextButton(onClick = {
                            showRepaymentDatePicker(context, selfExpenseDate) {
                                selfExpenseDate = it
                            }
                        }) {
                            Text("日期：${selfExpenseDate.toDateText()}")
                        }
                        OutlinedTextField(
                            value = selfExpenseNote,
                            onValueChange = { selfExpenseNote = it },
                            label = { Text("備註") },
                            modifier = Modifier.fillMaxWidth(),
                            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                                imeAction = androidx.compose.ui.text.input.ImeAction.Done
                            ),
                            keyboardActions =
                                org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions()
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(
                                onClick = {
                                    val account = selfExpenseAccount ?: return@Button
                                    val actualAmount = parsePositive(selfExpenseAmount) ?: return@Button
                                    val normalizedAmount =
                                        parsePositive(selfExpenseNormalizedAmount) ?: return@Button
                                    scope.launch {
                                        runCatching {
                                            repository.updateAdvanceSelfExpense(
                                                AdvanceSelfExpenseEditDraft(
                                                    caseId = caseData.advanceCase.id,
                                                    accountId = account.id,
                                                    amount = actualAmount,
                                                    currencyCode = selfExpenseCurrency,
                                                    normalizedAmount = normalizedAmount,
                                                    date = selfExpenseDate,
                                                    note = selfExpenseNote,
                                                    categoryId = selfExpenseCategory?.id,
                                                    tagIds = selfExpenseTags.map { it.id }
                                                )
                                            )
                                        }.onSuccess {
                                            advanceCase = repository.getAdvanceCase(caseData.advanceCase.id)
                                            selfExpense = repository.getTransaction(expense.transaction.id)
                                            isEditingSelfExpense = false
                                            errorMessage = null
                                        }.onFailure {
                                            errorMessage = it.localizedMessage ?: "無法更新自己的份額。"
                                        }
                                    }
                                },
                                enabled = selfExpenseAccount != null &&
                                    parsePositive(selfExpenseAmount) != null &&
                                    parsePositive(selfExpenseNormalizedAmount) != null
                            ) {
                                Text("儲存")
                            }
                            TextButton(onClick = { isEditingSelfExpense = false }) {
                                Text("取消")
                            }
                        }
                    }
                }
            }
        }

        item {
            Text("代墊對象", style = MaterialTheme.typography.titleMedium)
            SectionCard {
                caseData.participants.forEach { participant ->
                    ParticipantRow(
                        participant = participant,
                        currency = caseCurrency,
                        onEdit = {
                            participantToEdit = participant
                            editedParticipantAmount = participant.owedAmount.stripTrailingZeros().toPlainString()
                        }
                    )
                }
            }
        }

        item {
            Text("還款紀錄", style = MaterialTheme.typography.titleMedium)
            SectionCard {
                if (caseData.repayments.isEmpty()) {
                    Text("尚未記錄還款", color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    caseData.repayments.sortedByDescending { it.date }.forEach { repayment ->
                        val recordKind = repaymentRecordKind(repayment.note)
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 6.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Text(
                                "${recordKind.label} · ${repayment.amount.asCurrencyText(repayment.currencyCode)} · 沖銷 ${repayment.normalizedAmount.asCurrencyText(caseCurrency)}",
                                style = MaterialTheme.typography.bodyLarge
                            )
                            Text(
                                repayment.date.toDateText(),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                if (recordKind == RepaymentRecordKind.Ordinary &&
                                    repayment.linkedTransferGroupId != null
                                ) {
                                    TextButton(onClick = {
                                        scope.launch {
                                            val participant = caseData.participants.firstOrNull {
                                                it.id == repayment.participantId
                                            } ?: return@launch
                                            val account = receiveAccounts.firstOrNull {
                                                it.id == repayment.receivedAccountId
                                            }
                                            val group = repository.getTransferGroup(repayment.linkedTransferGroupId)
                                            val ownLeg = group.firstOrNull {
                                                if (isBorrowedByMe) {
                                                    it.transaction.accountId == repayment.receivedAccountId &&
                                                        (it.transaction.transferSide == org.duckdns.lhfser.aiaccounting.core.model.TransferSide.Outgoing ||
                                                            it.transaction.amount < BigDecimal.ZERO)
                                                } else {
                                                    it.transaction.accountId == repayment.receivedAccountId &&
                                                        (it.transaction.transferSide == org.duckdns.lhfser.aiaccounting.core.model.TransferSide.Incoming ||
                                                            it.transaction.amount > BigDecimal.ZERO)
                                                }
                                            }
                                            editingRepayment = repayment
                                            selectedParticipant = participant
                                            selectedReceiveAccount = account
                                            amountInput = repayment.amount.stripTrailingZeros().toPlainString()
                                            selectedCurrency = repayment.currencyCode
                                            settlementAmountInput = repayment.normalizedAmount.stripTrailingZeros().toPlainString()
                                            settlementManuallyEdited = true
                                            repaymentDate = repayment.date
                                            note = repayment.note
                                            mode = RepaymentMode.Normal
                                            selectedCategory = categories.firstOrNull {
                                                it.id == ownLeg?.transaction?.categoryId
                                            }
                                            selectedTags = ownLeg?.tags.orEmpty()
                                        }
                                    }) {
                                        Text("編輯")
                                    }
                                }
                                TextButton(onClick = { repaymentToRollback = repayment }) {
                                    Text("撤銷", color = MaterialTheme.colorScheme.error)
                                }
                            }
                        }
                    }
                }
            }
        }

        item {
            Text(
                if (editingRepayment == null) "記錄還款" else "編輯還款",
                style = MaterialTheme.typography.titleMedium
            )
            SectionCard {
                ParticipantPicker(
                    participants = caseData.participants,
                    selected = selectedParticipant,
                    onSelect = { selectedParticipant = it }
                )

                if (editingRepayment == null) {
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
                }

                if (mode != RepaymentMode.Split) {
                    AccountPicker(
                        label = accountLabel,
                        accounts = receiveAccounts,
                        selected = selectedReceiveAccount,
                        onSelect = { selectedReceiveAccount = it }
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
                TextButton(onClick = {
                    showRepaymentDatePicker(context, repaymentDate) { repaymentDate = it }
                }) {
                    Text("日期：${repaymentDate.toDateText()}")
                }
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text("備註") },
                    modifier = Modifier.fillMaxWidth()
                ,
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                    keyboardActions = org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions())

                Button(
                    onClick = {
                        scope.launch {
                            val participant = selectedParticipant ?: return@launch
                            try {
                                when (mode) {
                                    RepaymentMode.Normal -> {
                                        val receiveAccount = selectedReceiveAccount ?: return@launch
                                        val amount = parsePositive(amountInput) ?: return@launch
                                        val normalizedAmount = parsedSettlementAmount ?: return@launch
                                        if (normalizedAmount - editableRemaining > BigDecimal("0.0001")) {
                                            errorMessage = "沖銷金額超過未還餘額。"
                                            return@launch
                                        }
                                        val existingRepayment = editingRepayment
                                        if (existingRepayment == null) {
                                            recordSingleRepayment(
                                                repository = repository,
                                                advanceCase = caseData,
                                                participant = participant,
                                                receiveAccount = receiveAccount,
                                                amount = amount,
                                                currency = selectedCurrency,
                                                normalizedAmount = normalizedAmount,
                                                date = repaymentDate,
                                                note = note,
                                                category = selectedCategory,
                                                tagIds = selectedTags.map { it.id }
                                            )
                                        } else {
                                            repository.updateAdvanceRepayment(
                                                AdvanceRepaymentEditDraft(
                                                    repaymentId = existingRepayment.id,
                                                    receiveAccountId = receiveAccount.id,
                                                    amount = amount,
                                                    currencyCode = selectedCurrency,
                                                    normalizedAmount = normalizedAmount,
                                                    date = repaymentDate,
                                                    note = note,
                                                    categoryId = selectedCategory?.id,
                                                    tagIds = selectedTags.map { it.id }
                                                )
                                            )
                                        }
                                    }
                                    RepaymentMode.Split -> {
                                        val legs = mutableListOf<Triple<AccountEntity, BigDecimal, String>>()
                                        splitLegs.forEach { leg ->
                                            val account = leg.account
                                            val amount = parsePositive(leg.amount)
                                            if (account == null || amount == null) {
                                                errorMessage = "分拆模式下，請為每一項選擇帳戶並填入金額。"
                                                return@launch
                                            }
                                            legs += Triple(account, amount, leg.currency)
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
                                        repository.recordAdvanceRepayments(
                                            advanceCaseId = caseData.advanceCase.id,
                                            participantId = participant.id,
                                            drafts = legs.mapIndexed { index, leg ->
                                                AdvanceRepaymentCreateDraft(
                                                    receiveAccountId = leg.first.id,
                                                    amount = leg.second,
                                                    normalizedAmount =
                                                        normalizedLegs[index] ?: return@launch,
                                                    currencyCode = leg.third,
                                                    date = repaymentDate,
                                                    note = indexedNote(note, "分拆", index, legs.size),
                                                    categoryId = selectedCategory?.id,
                                                    tagIds = selectedTags.map { it.id }
                                                )
                                            }
                                        )
                                    }
                                    RepaymentMode.Merge -> {
                                        val receiveAccount = selectedReceiveAccount ?: return@launch
                                        val legs = mutableListOf<Pair<BigDecimal, String>>()
                                        mergeLegs.forEach { leg ->
                                            val amount = parsePositive(leg.amount)
                                            if (amount == null) {
                                                errorMessage = "合併模式下，請為每一項填入金額。"
                                                return@launch
                                            }
                                            legs += amount to leg.currency
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
                                        repository.recordAdvanceRepayments(
                                            advanceCaseId = caseData.advanceCase.id,
                                            participantId = participant.id,
                                            drafts = legs.mapIndexed { index, item ->
                                                AdvanceRepaymentCreateDraft(
                                                    receiveAccountId = receiveAccount.id,
                                                    amount = item.first,
                                                    normalizedAmount =
                                                        normalizedLegs[index] ?: return@launch,
                                                    currencyCode = item.second,
                                                    date = repaymentDate,
                                                    note = indexedNote(note, "合併", index, legs.size),
                                                    categoryId = selectedCategory?.id,
                                                    tagIds = selectedTags.map { it.id }
                                                )
                                            }
                                        )
                                    }
                                }
                            } catch (error: Exception) {
                                errorMessage = error.localizedMessage ?: "無法儲存還款。"
                                return@launch
                            }
                            errorMessage = null
                            editingRepayment = null
                            amountInput = ""
                            settlementAmountInput = ""
                            settlementManuallyEdited = false
                            note = ""
                            selectedCategory = null
                            selectedTags = emptyList()
                            repaymentDate = Instant.now()
                            advanceCase = repository.getAdvanceCase(caseData.advanceCase.id)
                        }
                    },
                    enabled = canSubmit
                ) {
                    Text(if (editingRepayment == null) "儲存" else "更新還款")
                }

                if (editingRepayment != null) {
                    TextButton(onClick = {
                        editingRepayment = null
                        amountInput = ""
                        settlementAmountInput = ""
                        settlementManuallyEdited = false
                        note = ""
                        selectedCategory = null
                        selectedTags = emptyList()
                        repaymentDate = Instant.now()
                    }) {
                        Text("取消編輯")
                    }
                }

                if (errorMessage != null) {
                    Text(errorMessage ?: "", color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }

    repaymentToRollback?.let { repayment ->
        val recordKind = repaymentRecordKind(repayment.note)
        AlertDialog(
            onDismissRequest = { repaymentToRollback = null },
            title = { Text("確認撤銷${recordKind.label}？") },
            text = {
                Text(
                    when (recordKind) {
                        RepaymentRecordKind.Ordinary ->
                            "會刪除還款紀錄及其關聯轉帳，並回復未還金額。"
                        RepaymentRecordKind.MutualDebtOffset ->
                            "會整組撤銷這次債務抵銷，並回復所有受影響案件的未清金額。"
                        RepaymentRecordKind.ManualDebtSettlement ->
                            "會整組撤銷這次跨幣種平賬，並回復所有受影響案件的未清金額。"
                    }
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    scope.launch {
                        runCatching {
                            when (recordKind) {
                                RepaymentRecordKind.Ordinary ->
                                    repository.rollbackAdvanceRepayment(repayment.id)
                                RepaymentRecordKind.MutualDebtOffset -> {
                                    val offsetId = requireNotNull(
                                        org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository
                                            .mutualDebtOffsetId(repayment.note)
                                    )
                                    repository.rollbackMutualDebtOffset(offsetId)
                                }
                                RepaymentRecordKind.ManualDebtSettlement -> {
                                    val settlementId = requireNotNull(
                                        org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository
                                            .manualDebtSettlementId(repayment.note)
                                    )
                                    repository.rollbackManualDebtSettlement(settlementId)
                                }
                            }
                        }.onSuccess {
                            advanceCase = repository.getAdvanceCase(caseData.advanceCase.id)
                        }.onFailure {
                            errorMessage = it.localizedMessage ?: "無法沖銷還款。"
                        }
                        repaymentToRollback = null
                    }
                }) { Text("撤銷") }
            },
            dismissButton = {
                TextButton(onClick = { repaymentToRollback = null }) { Text("取消") }
            }
        )
    }

    participantToEdit?.let { participant ->
        AlertDialog(
            onDismissRequest = { participantToEdit = null },
            title = { Text("更正欠款") },
            text = {
                OutlinedTextField(
                    value = editedParticipantAmount,
                    onValueChange = { editedParticipantAmount = sanitizeAmount(it) },
                    label = { Text("欠款金額 ($caseCurrency)") }
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    val amount = parsePositive(editedParticipantAmount)
                    if (amount == null) {
                        errorMessage = "請輸入大於 0 的欠款金額。"
                    } else {
                        scope.launch {
                            runCatching {
                                repository.updateAdvanceParticipantOwedAmount(participant.id, amount)
                            }.onSuccess {
                                advanceCase = repository.getAdvanceCase(caseData.advanceCase.id)
                            }.onFailure {
                                errorMessage = it.localizedMessage ?: "無法更正欠款。"
                            }
                            participantToEdit = null
                        }
                    }
                }) { Text("儲存") }
            },
            dismissButton = {
                TextButton(onClick = { participantToEdit = null }) { Text("取消") }
            }
        )
    }
}

private fun repaymentRecordKind(note: String): RepaymentRecordKind {
    return when {
        org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository
            .isMutualDebtOffset(note) -> RepaymentRecordKind.MutualDebtOffset
        org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository
            .isManualDebtSettlement(note) -> RepaymentRecordKind.ManualDebtSettlement
        else -> RepaymentRecordKind.Ordinary
    }
}


@Composable
private fun ParticipantRow(
    participant: AdvanceParticipantEntity,
    currency: String,
    onEdit: () -> Unit
) {
    val remaining = (participant.owedAmount - participant.repaidAmount).max(BigDecimal.ZERO)
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(participant.name, style = MaterialTheme.typography.bodyLarge)
        Text("欠款：${participant.owedAmount.asCurrencyText(currency)}")
        Text("已還：${participant.repaidAmount.asCurrencyText(currency)}")
        Text("未還：${remaining.asCurrencyText(currency)}")
        TextButton(onClick = onEdit) { Text("更正欠款") }
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
            ,
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                keyboardActions = org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions())
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
            ,
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                keyboardActions = org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions())
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
    date: Instant,
    note: String,
    category: CategoryEntity?,
    tagIds: List<UUID>
) {
    repository.recordAdvanceRepayment(
        advanceCase = advanceCase.advanceCase,
        participant = participant,
        amount = amount.abs(),
        normalizedAmount = normalizedAmount.abs(),
        currencyCode = currency,
        date = date,
        note = note.trim(),
        receiveAccount = receiveAccount,
        category = category,
        tagIds = tagIds
    )
}

private fun showRepaymentDatePicker(
    context: android.content.Context,
    initial: Instant,
    onPicked: (Instant) -> Unit
) {
    val zone = ZoneId.systemDefault()
    val date = initial.atZone(zone).toLocalDate()
    DatePickerDialog(
        context,
        { _, year, month, day ->
            val originalTime = initial.atZone(zone).toLocalTime()
            onPicked(
                java.time.LocalDate.of(year, month + 1, day)
                    .atTime(originalTime)
                    .atZone(zone)
                    .toInstant()
            )
        },
        date.year,
        date.monthValue - 1,
        date.dayOfMonth
    ).show()
}

private fun indexedNote(base: String, mode: String, index: Int, count: Int): String {
    val suffix = "[$mode ${index + 1}/$count]"
    val trimmed = base.trim()
    return if (trimmed.isBlank()) suffix else "$trimmed $suffix"
}
