package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import kotlinx.coroutines.launch
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.TagEntity
import org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceCaseStructuralEditDraft
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceCaseStructuralImpact
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceParticipantStructuralDraft
import org.duckdns.lhfser.aiaccounting.data.repository.AdvancePaymentLegStructuralDraft
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceRepaymentStructuralDraft
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceSettlementDirection
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceShareStructuralDraft
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyButtonStyle
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyPicker
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard
import java.math.BigDecimal
import java.util.UUID

private data class StructuralPaymentLegUi(
    val id: UUID = UUID.randomUUID(),
    val transactionId: UUID? = null,
    val accountId: UUID? = null,
    val amount: String = "",
    val currencyCode: String = "HKD"
)

private data class StructuralParticipantUi(
    val id: UUID,
    val participantId: UUID? = null,
    val name: String = "",
    val debtAccountId: UUID? = null,
    val owedAmount: String = "",
    val paymentLegs: List<StructuralPaymentLegUi> = emptyList()
)

private data class StructuralRepaymentUi(
    val id: UUID,
    val participantId: UUID,
    val receiveAccountId: UUID?,
    val amount: String,
    val currencyCode: String,
    val normalizedAmount: String,
    val date: java.time.Instant,
    val note: String,
    val categoryId: UUID?,
    val tagIds: List<UUID>
)

private data class StructuralShareUi(
    val transactionId: UUID?,
    val accountId: UUID?,
    val amount: String,
    val currencyCode: String,
    val normalizedAmount: String
)

@Composable
fun AdvanceStructuralEditorDialog(
    advanceCase: AdvanceCaseWithDetails,
    accounts: List<AccountEntity>,
    categories: List<CategoryEntity>,
    tags: List<TagEntity>,
    onDismiss: () -> Unit,
    onApplied: suspend () -> Unit
) {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()
    val ownAccounts = accounts.filter { it.type != AccountType.Debt && !it.isArchived }
    val debtAccounts = accounts.filter { it.type == AccountType.Debt && !it.isArchived }
    val expenseCategories = categories.filter { it.kind.supports(TransactionType.Expense) }

    var title by remember { mutableStateOf(advanceCase.advanceCase.title) }
    var direction by remember {
        mutableStateOf(
            runCatching {
                AdvanceSettlementDirection.valueOf(
                    advanceCase.advanceCase.direction ?: ""
                )
            }.getOrDefault(
                if (advanceCase.advanceCase.payerAccountId == null) {
                    AdvanceSettlementDirection.OthersAdvancedMe
                } else {
                    AdvanceSettlementDirection.IAdvancedOthers
                }
            )
        )
    }
    var currencyCode by remember { mutableStateOf(advanceCase.advanceCase.currencyCode) }
    var note by remember { mutableStateOf(advanceCase.advanceCase.note) }
    var categoryId by remember { mutableStateOf(advanceCase.advanceCase.expenseCategoryId) }
    var selectedTagIds by remember { mutableStateOf(emptyList<UUID>()) }
    var includesShare by remember {
        mutableStateOf(advanceCase.advanceCase.selfExpenseTransactionId != null)
    }
    var share by remember {
        mutableStateOf(
            StructuralShareUi(
                transactionId = advanceCase.advanceCase.selfExpenseTransactionId,
                accountId = null,
                amount = "",
                currencyCode = advanceCase.advanceCase.currencyCode,
                normalizedAmount = advanceCase.advanceCase.myShareAmount.toPlainString()
            )
        )
    }
    var participants by remember { mutableStateOf(emptyList<StructuralParticipantUi>()) }
    var repayments by remember { mutableStateOf(emptyList<StructuralRepaymentUi>()) }
    var confirmsCurrencyAmounts by remember { mutableStateOf(true) }
    var loaded by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var pendingDraft by remember { mutableStateOf<AdvanceCaseStructuralEditDraft?>(null) }
    var pendingImpact by remember { mutableStateOf<AdvanceCaseStructuralImpact?>(null) }

    val hasSpecialRepayments = advanceCase.repayments.any {
        AccountingRepository.isMutualDebtOffset(it.note) ||
            AccountingRepository.isManualDebtSettlement(it.note)
    }

    LaunchedEffect(advanceCase.advanceCase.id) {
        selectedTagIds = repository.exportBackup().advanceCases
            .orEmpty()
            .firstOrNull { it.id == advanceCase.advanceCase.id }
            ?.tagIDs
            .orEmpty()
        share = advanceCase.advanceCase.selfExpenseTransactionId?.let { transactionId ->
            repository.getTransaction(transactionId)?.let { transaction ->
                StructuralShareUi(
                    transactionId = transactionId,
                    accountId = transaction.transaction.accountId,
                    amount = transaction.transaction.amount.abs().toPlainString(),
                    currencyCode = transaction.transaction.currencyCode,
                    normalizedAmount = advanceCase.advanceCase.myShareAmount.toPlainString()
                )
            }
        } ?: share.copy(accountId = ownAccounts.firstOrNull()?.id)

        participants = advanceCase.participants.map { participant ->
            val group = participant.initialTransferGroupId
                ?.let { repository.getTransferGroup(it) }
                .orEmpty()
            val legs = group
                .filter { it.transaction.advanceEntryRole == "InitialAsset" }
                .map { item ->
                    StructuralPaymentLegUi(
                        transactionId = item.transaction.id,
                        accountId = item.transaction.accountId,
                        amount = item.transaction.amount.abs().toPlainString(),
                        currencyCode = item.transaction.currencyCode
                    )
                }
            StructuralParticipantUi(
                id = participant.id,
                participantId = participant.id,
                name = participant.name,
                debtAccountId = participant.debtAccountId,
                owedAmount = participant.owedAmount.toPlainString(),
                paymentLegs = if (direction == AdvanceSettlementDirection.IAdvancedOthers) {
                    legs.ifEmpty {
                        listOf(
                            StructuralPaymentLegUi(
                                accountId = ownAccounts.firstOrNull()?.id,
                                currencyCode = ownAccounts.firstOrNull()?.currency ?: currencyCode
                            )
                        )
                    }
                } else {
                    emptyList()
                }
            )
        }
        repayments = advanceCase.repayments
            .filter {
                !AccountingRepository.isMutualDebtOffset(it.note) &&
                    !AccountingRepository.isManualDebtSettlement(it.note)
            }
            .mapNotNull { repayment ->
                val participantId = repayment.participantId ?: return@mapNotNull null
                val group = repayment.linkedTransferGroupId
                    ?.let { repository.getTransferGroup(it) }
                    .orEmpty()
                val ownLeg = group.firstOrNull {
                    it.transaction.advanceEntryRole == "RepaymentAsset"
                }
                StructuralRepaymentUi(
                    id = repayment.id,
                    participantId = participantId,
                    receiveAccountId = repayment.receivedAccountId,
                    amount = repayment.amount.toPlainString(),
                    currencyCode = repayment.currencyCode,
                    normalizedAmount = repayment.normalizedAmount.toPlainString(),
                    date = repayment.date,
                    note = repayment.note,
                    categoryId = ownLeg?.transaction?.categoryId,
                    tagIds = ownLeg?.tags?.map { it.id }.orEmpty()
                )
            }
        loaded = true
    }

    Dialog(onDismissRequest = onDismiss) {
        Surface(
            shape = MaterialTheme.shapes.large,
            tonalElevation = 6.dp,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 760.dp)
                .imePadding()
                .testTag("advance.structural.editor")
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text("完整編輯代墊", style = MaterialTheme.typography.titleLarge)
                if (!loaded) {
                    Text("載入中...")
                } else {
                    LazyColumn(
                        modifier = Modifier
                            .weight(1f, fill = false)
                            .testTag("advance.structural.list"),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        item {
                            SectionCard {
                                Text("方向", style = MaterialTheme.typography.titleSmall)
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    AdvanceSettlementDirection.values().forEach { item ->
                                        FilterChip(
                                            modifier = Modifier.testTag(
                                                "advance.structural.direction.${item.name}"
                                            ),
                                            selected = direction == item,
                                            onClick = {
                                                direction = item
                                                if (item == AdvanceSettlementDirection.OthersAdvancedMe) {
                                                    includesShare = false
                                                    participants = participants.map {
                                                        it.copy(paymentLegs = emptyList())
                                                    }
                                                } else {
                                                    participants = participants.map { participant ->
                                                        if (participant.paymentLegs.isEmpty()) {
                                                            participant.copy(
                                                                paymentLegs = listOf(
                                                                    StructuralPaymentLegUi(
                                                                        accountId = ownAccounts.firstOrNull()?.id,
                                                                        currencyCode = ownAccounts.firstOrNull()?.currency
                                                                            ?: currencyCode
                                                                    )
                                                                )
                                                            )
                                                        } else {
                                                            participant
                                                        }
                                                    }
                                                }
                                            },
                                            label = {
                                                Text(
                                                    if (item == AdvanceSettlementDirection.IAdvancedOthers) {
                                                        "我代墊他人"
                                                    } else {
                                                        "他人代墊我"
                                                    }
                                                )
                                            }
                                        )
                                    }
                                }
                                OutlinedTextField(
                                    value = title,
                                    onValueChange = { title = it },
                                    label = { Text("案件名稱") },
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .testTag("advance.structural.title"),
                                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                                        imeAction = ImeAction.Done
                                    ),
                                    keyboardActions =
                                        org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions()
                                )
                                Text("案件幣種", style = MaterialTheme.typography.titleSmall)
                                CurrencyPicker(
                                    selected = currencyCode,
                                    onSelect = {
                                        if (!it.equals(currencyCode, ignoreCase = true)) {
                                            confirmsCurrencyAmounts = false
                                        }
                                        currencyCode = it
                                    },
                                    buttonStyle = CurrencyButtonStyle.Tonal,
                                    modifier = Modifier.testTag("advance.structural.currency")
                                )
                                StructuralPicker(
                                    label = "支出分類",
                                    value = expenseCategories.firstOrNull { it.id == categoryId },
                                    options = expenseCategories,
                                    optionLabel = { it.name },
                                    onSelect = { categoryId = it?.id }
                                )
                                StructuralTagPicker(
                                    tags = tags,
                                    selectedIds = selectedTagIds,
                                    onChange = { selectedTagIds = it }
                                )
                                OutlinedTextField(
                                    value = note,
                                    onValueChange = { note = it },
                                    label = { Text("備註") },
                                    modifier = Modifier.fillMaxWidth(),
                                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                                        imeAction = ImeAction.Done
                                    ),
                                    keyboardActions =
                                        org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions()
                                )
                            }
                        }

                        if (direction == AdvanceSettlementDirection.IAdvancedOthers) {
                            item {
                                SectionCard {
                                    FilterChip(
                                        selected = includesShare,
                                        onClick = { includesShare = !includesShare },
                                        label = { Text("包含自己的份額") }
                                    )
                                    if (includesShare) {
                                        StructuralPicker(
                                            label = "自己份額付款帳戶",
                                            value = ownAccounts.firstOrNull { it.id == share.accountId },
                                            options = ownAccounts,
                                            optionLabel = { it.name },
                                            onSelect = { share = share.copy(accountId = it?.id) }
                                        )
                                        StructuralAmountRow(
                                            label = "實際付款",
                                            amount = share.amount,
                                            currency = share.currencyCode,
                                            onAmountChange = { share = share.copy(amount = sanitizeStructuralAmount(it)) },
                                            onCurrencyChange = { share = share.copy(currencyCode = it) }
                                        )
                                        StructuralNumberField(
                                            label = "$currencyCode 案件份額",
                                            value = share.normalizedAmount,
                                            onChange = {
                                                share = share.copy(
                                                    normalizedAmount = sanitizeStructuralAmount(it)
                                                )
                                            }
                                        )
                                    }
                                }
                            }
                        }

                        participants.forEach { participant ->
                            item(key = participant.id) {
                                StructuralParticipantEditor(
                                    participant = participant,
                                    direction = direction,
                                    caseCurrency = currencyCode,
                                    ownAccounts = ownAccounts,
                                    debtAccounts = debtAccounts,
                                    onChange = { updated ->
                                        participants = participants.map {
                                            if (it.id == participant.id) updated else it
                                        }
                                    },
                                    onRemove = if (participants.size > 1) {
                                        {
                                            participants = participants.filterNot {
                                                it.id == participant.id
                                            }
                                            participant.participantId?.let { participantId ->
                                                repayments = repayments.filterNot {
                                                    it.participantId == participantId
                                                }
                                            }
                                        }
                                    } else {
                                        null
                                    }
                                )
                            }
                        }

                        item {
                            TextButton(
                                modifier = Modifier.testTag("advance.structural.addParticipant"),
                                onClick = {
                                    participants = participants + StructuralParticipantUi(
                                        id = UUID.randomUUID(),
                                        paymentLegs =
                                            if (direction == AdvanceSettlementDirection.IAdvancedOthers) {
                                                listOf(
                                                    StructuralPaymentLegUi(
                                                        accountId = ownAccounts.firstOrNull()?.id,
                                                        currencyCode = ownAccounts.firstOrNull()?.currency
                                                            ?: currencyCode
                                                    )
                                                )
                                            } else {
                                                emptyList()
                                            }
                                    )
                                }
                            ) {
                                Text("新增參與人")
                            }
                        }

                        repayments.forEach { repayment ->
                            item(key = repayment.id) {
                                StructuralRepaymentEditor(
                                    repayment = repayment,
                                    participantName = participants.firstOrNull {
                                        it.participantId == repayment.participantId
                                    }?.name ?: "已移除對象",
                                    accounts = ownAccounts,
                                    categories = categories,
                                    direction = direction,
                                    caseCurrency = currencyCode,
                                    onChange = { updated ->
                                        repayments = repayments.map {
                                            if (it.id == repayment.id) updated else it
                                        }
                                    }
                                )
                            }
                        }

                        item {
                            SectionCard {
                                if (hasSpecialRepayments) {
                                    Text(
                                        "此案件含債務抵銷或手動結清。請先返回詳情整組撤銷。",
                                        color = MaterialTheme.colorScheme.error
                                    )
                                }
                                if (!currencyCode.equals(
                                        advanceCase.advanceCase.currencyCode,
                                        ignoreCase = true
                                    )
                                ) {
                                    FilterChip(
                                        modifier = Modifier.testTag(
                                            "advance.structural.confirmCurrency"
                                        ),
                                        selected = confirmsCurrencyAmounts,
                                        onClick = {
                                            confirmsCurrencyAmounts = !confirmsCurrencyAmounts
                                        },
                                        label = {
                                            Text("我已重新確認所有 $currencyCode 金額與沖銷額")
                                        }
                                    )
                                }
                                Text(
                                    "儲存前會先顯示影響預覽；確認後才原子重建。",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }

                    errorMessage?.let {
                        Text(it, color = MaterialTheme.colorScheme.error)
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End
                    ) {
                        TextButton(onClick = onDismiss) { Text("取消") }
                        Button(
                            modifier = Modifier.testTag("advance.structural.preview"),
                            onClick = {
                                scope.launch {
                                    runCatching {
                                        require(confirmsCurrencyAmounts) {
                                            "請先重新確認新案件幣種下的所有金額。"
                                        }
                                        val draft = buildStructuralDraft(
                                            advanceCase = advanceCase,
                                            title = title,
                                            direction = direction,
                                            currencyCode = currencyCode,
                                            note = note,
                                            categoryId = categoryId,
                                            tagIds = selectedTagIds,
                                            includesShare = includesShare,
                                            share = share,
                                            participants = participants,
                                            repayments = repayments
                                        )
                                        val impact = repository.previewAdvanceCaseStructuralEdit(draft)
                                        draft to impact
                                    }.onSuccess { (draft, impact) ->
                                        pendingDraft = draft
                                        pendingImpact = impact
                                        errorMessage = null
                                    }.onFailure {
                                        errorMessage = it.localizedMessage ?: "無法預覽變更。"
                                    }
                                }
                            },
                            enabled = !hasSpecialRepayments
                        ) {
                            Text("預覽影響")
                        }
                    }
                }
            }
        }
    }

    pendingImpact?.let { impact ->
        AlertDialog(
            onDismissRequest = {
                pendingImpact = null
                pendingDraft = null
            },
            title = { Text("確認套用結構性變更？") },
            text = {
                Text(
                    buildList {
                        addAll(impact.warnings)
                        add("將重建或更新 ${impact.affectedTransactionCount} 筆底層分錄。")
                        if (impact.removedParticipantCount > 0) {
                            add("將刪除 ${impact.removedParticipantCount} 位參與人。")
                        }
                        if (impact.removedRepaymentCount > 0) {
                            add("將刪除 ${impact.removedRepaymentCount} 筆還款。")
                        }
                    }.joinToString("\n")
                )
            },
            confirmButton = {
                TextButton(
                    modifier = Modifier.testTag("advance.structural.apply"),
                    onClick = {
                        val draft = pendingDraft ?: return@TextButton
                        scope.launch {
                            runCatching {
                                repository.applyAdvanceCaseStructuralEdit(draft)
                                onApplied()
                            }.onSuccess {
                                pendingDraft = null
                                pendingImpact = null
                                onDismiss()
                            }.onFailure {
                                errorMessage = it.localizedMessage ?: "無法套用變更。"
                                pendingDraft = null
                                pendingImpact = null
                            }
                        }
                    }
                ) {
                    Text("確認重建")
                }
            },
            dismissButton = {
                TextButton(
                    modifier = Modifier.testTag("advance.structural.cancelPreview"),
                    onClick = {
                        pendingImpact = null
                        pendingDraft = null
                    }
                ) {
                    Text("取消")
                }
            }
        )
    }
}

private fun buildStructuralDraft(
    advanceCase: AdvanceCaseWithDetails,
    title: String,
    direction: AdvanceSettlementDirection,
    currencyCode: String,
    note: String,
    categoryId: UUID?,
    tagIds: List<UUID>,
    includesShare: Boolean,
    share: StructuralShareUi,
    participants: List<StructuralParticipantUi>,
    repayments: List<StructuralRepaymentUi>
): AdvanceCaseStructuralEditDraft {
    val participantDrafts = participants.map { participant ->
        val debtAccountId = requireNotNull(participant.debtAccountId) {
            "請為每位參與人選擇債務帳戶。"
        }
        val owedAmount = requireNotNull(parseStructuralPositive(participant.owedAmount)) {
            "請輸入大於 0 的欠款金額。"
        }
        AdvanceParticipantStructuralDraft(
            participantId = participant.participantId,
            name = participant.name,
            debtAccountId = debtAccountId,
            owedAmount = owedAmount,
            paymentLegs =
                if (direction == AdvanceSettlementDirection.IAdvancedOthers) {
                    participant.paymentLegs.map { leg ->
                        AdvancePaymentLegStructuralDraft(
                            transactionId = leg.transactionId,
                            accountId = requireNotNull(leg.accountId) {
                                "請選擇付款帳戶。"
                            },
                            amount = requireNotNull(parseStructuralPositive(leg.amount)) {
                                "請輸入大於 0 的付款金額。"
                            },
                            currencyCode = leg.currencyCode
                        )
                    }
                } else {
                    emptyList()
                }
        )
    }
    val retainedParticipantIds = participantDrafts.mapNotNull { it.participantId }.toSet()
    val repaymentDrafts = repayments.map { repayment ->
        require(repayment.participantId in retainedParticipantIds) {
            "還款對象已被移除。"
        }
        AdvanceRepaymentStructuralDraft(
            repaymentId = repayment.id,
            receiveAccountId = requireNotNull(repayment.receiveAccountId) {
                "請選擇還款帳戶。"
            },
            amount = requireNotNull(parseStructuralPositive(repayment.amount)) {
                "請輸入大於 0 的還款金額。"
            },
            currencyCode = repayment.currencyCode,
            normalizedAmount = requireNotNull(
                parseStructuralPositive(repayment.normalizedAmount)
            ) {
                "請輸入大於 0 的沖銷額。"
            },
            date = repayment.date,
            note = repayment.note,
            categoryId = repayment.categoryId,
            tagIds = repayment.tagIds
        )
    }
    val shareDraft = if (
        direction == AdvanceSettlementDirection.IAdvancedOthers && includesShare
    ) {
        AdvanceShareStructuralDraft(
            transactionId = share.transactionId,
            accountId = requireNotNull(share.accountId) { "請選擇自己份額付款帳戶。" },
            amount = requireNotNull(parseStructuralPositive(share.amount)) {
                "請輸入自己份額的實際付款。"
            },
            normalizedAmount = requireNotNull(
                parseStructuralPositive(share.normalizedAmount)
            ) {
                "請輸入案件中的自己份額。"
            },
            currencyCode = share.currencyCode
        )
    } else {
        null
    }
    return AdvanceCaseStructuralEditDraft(
        caseId = advanceCase.advanceCase.id,
        title = title,
        date = advanceCase.advanceCase.date,
        direction = direction,
        currencyCode = currencyCode,
        note = note,
        categoryId = categoryId,
        tagIds = tagIds,
        share = shareDraft,
        participants = participantDrafts,
        repayments = repaymentDrafts
    )
}

@Composable
private fun StructuralParticipantEditor(
    participant: StructuralParticipantUi,
    direction: AdvanceSettlementDirection,
    caseCurrency: String,
    ownAccounts: List<AccountEntity>,
    debtAccounts: List<AccountEntity>,
    onChange: (StructuralParticipantUi) -> Unit,
    onRemove: (() -> Unit)?
) {
    SectionCard(modifier = Modifier.testTag("advance.structural.participant")) {
        OutlinedTextField(
            value = participant.name,
            onValueChange = { onChange(participant.copy(name = it)) },
            label = { Text("姓名") },
            modifier = Modifier.fillMaxWidth(),
            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                imeAction = ImeAction.Done
            ),
            keyboardActions =
                org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions()
        )
        StructuralPicker(
            label = "債務帳戶",
            value = debtAccounts.firstOrNull { it.id == participant.debtAccountId },
            options = debtAccounts,
            optionLabel = { it.name },
            onSelect = { onChange(participant.copy(debtAccountId = it?.id)) }
        )
        StructuralNumberField(
            label = "$caseCurrency 欠款金額",
            value = participant.owedAmount,
            onChange = {
                onChange(participant.copy(owedAmount = sanitizeStructuralAmount(it)))
            }
        )
        if (direction == AdvanceSettlementDirection.IAdvancedOthers) {
            participant.paymentLegs.forEach { leg ->
                Column(
                    modifier = Modifier
                        .padding(start = 12.dp)
                        .testTag("advance.structural.paymentLeg"),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    StructuralPicker(
                        label = "付款帳戶",
                        value = ownAccounts.firstOrNull { it.id == leg.accountId },
                        options = ownAccounts,
                        optionLabel = { it.name },
                        onSelect = { selected ->
                            onChange(
                                participant.copy(
                                    paymentLegs = participant.paymentLegs.map {
                                        if (it.id == leg.id) {
                                            it.copy(
                                                accountId = selected?.id,
                                                currencyCode = selected?.currency ?: it.currencyCode
                                            )
                                        } else {
                                            it
                                        }
                                    }
                                )
                            )
                        }
                    )
                    StructuralAmountRow(
                        label = "實際付款",
                        amount = leg.amount,
                        currency = leg.currencyCode,
                        onAmountChange = { amount ->
                            onChange(
                                participant.copy(
                                    paymentLegs = participant.paymentLegs.map {
                                        if (it.id == leg.id) {
                                            it.copy(amount = sanitizeStructuralAmount(amount))
                                        } else {
                                            it
                                        }
                                    }
                                )
                            )
                        },
                        onCurrencyChange = { currency ->
                            onChange(
                                participant.copy(
                                    paymentLegs = participant.paymentLegs.map {
                                        if (it.id == leg.id) it.copy(currencyCode = currency) else it
                                    }
                                )
                            )
                        }
                    )
                    if (participant.paymentLegs.size > 1) {
                        TextButton(onClick = {
                            onChange(
                                participant.copy(
                                    paymentLegs = participant.paymentLegs.filterNot {
                                        it.id == leg.id
                                    }
                                )
                            )
                        }) {
                            Text("刪除此付款來源")
                        }
                    }
                }
            }
            TextButton(
                modifier = Modifier.testTag("advance.structural.addPaymentLeg"),
                onClick = {
                    onChange(
                        participant.copy(
                            paymentLegs = participant.paymentLegs + StructuralPaymentLegUi(
                                accountId = ownAccounts.firstOrNull()?.id,
                                currencyCode = ownAccounts.firstOrNull()?.currency ?: caseCurrency
                            )
                        )
                    )
                }
            ) {
                Text("新增付款來源")
            }
        }
        onRemove?.let {
            TextButton(onClick = it) {
                Text("刪除此參與人", color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

@Composable
private fun StructuralRepaymentEditor(
    repayment: StructuralRepaymentUi,
    participantName: String,
    accounts: List<AccountEntity>,
    categories: List<CategoryEntity>,
    direction: AdvanceSettlementDirection,
    caseCurrency: String,
    onChange: (StructuralRepaymentUi) -> Unit
) {
    val expectedType = if (direction == AdvanceSettlementDirection.IAdvancedOthers) {
        TransactionType.Income
    } else {
        TransactionType.Expense
    }
    val compatibleCategories = categories.filter { it.kind.supports(expectedType) }

    SectionCard {
        Text("$participantName 的普通還款", style = MaterialTheme.typography.titleSmall)
        StructuralPicker(
            label = "帳戶",
            value = accounts.firstOrNull { it.id == repayment.receiveAccountId },
            options = accounts,
            optionLabel = { it.name },
            onSelect = { onChange(repayment.copy(receiveAccountId = it?.id)) }
        )
        StructuralPicker(
            label = "還款分類",
            value = compatibleCategories.firstOrNull { it.id == repayment.categoryId },
            options = compatibleCategories,
            optionLabel = { it.name },
            onSelect = { onChange(repayment.copy(categoryId = it?.id)) },
            testTagPrefix = "advance.structural.repaymentCategory"
        )
        StructuralAmountRow(
            label = "實際還款",
            amount = repayment.amount,
            currency = repayment.currencyCode,
            onAmountChange = {
                onChange(repayment.copy(amount = sanitizeStructuralAmount(it)))
            },
            onCurrencyChange = { onChange(repayment.copy(currencyCode = it)) }
        )
        StructuralNumberField(
            label = "$caseCurrency 沖銷額",
            value = repayment.normalizedAmount,
            onChange = {
                onChange(repayment.copy(normalizedAmount = sanitizeStructuralAmount(it)))
            }
        )
    }
}

@Composable
private fun StructuralAmountRow(
    label: String,
    amount: String,
    currency: String,
    onAmountChange: (String) -> Unit,
    onCurrencyChange: (String) -> Unit
) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        CurrencyPicker(
            selected = currency,
            onSelect = onCurrencyChange,
            buttonStyle = CurrencyButtonStyle.Text
        )
        OutlinedTextField(
            value = amount,
            onValueChange = onAmountChange,
            label = { Text(label) },
            modifier = Modifier.weight(1f),
            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                keyboardType = KeyboardType.Decimal,
                imeAction = ImeAction.Done
            ),
            keyboardActions =
                org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions()
        )
    }
}

@Composable
private fun StructuralNumberField(
    label: String,
    value: String,
    onChange: (String) -> Unit
) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(label) },
        modifier = Modifier.fillMaxWidth(),
        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
            keyboardType = KeyboardType.Decimal,
            imeAction = ImeAction.Done
        ),
        keyboardActions =
            org.duckdns.lhfser.aiaccounting.ui.components.keyboardDoneActions()
    )
}

@Composable
private fun <T> StructuralPicker(
    label: String,
    value: T?,
    options: List<T>,
    optionLabel: (T) -> String,
    onSelect: (T?) -> Unit,
    testTagPrefix: String? = null
) {
    var expanded by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(label, style = MaterialTheme.typography.titleSmall)
        TextButton(
            modifier = testTagPrefix?.let { Modifier.testTag(it) } ?: Modifier,
            onClick = { expanded = true }
        ) {
            Text(value?.let(optionLabel) ?: "請選擇")
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(
                text = { Text("不設定") },
                onClick = {
                    expanded = false
                    onSelect(null)
                }
            )
            options.forEach { option ->
                DropdownMenuItem(
                    modifier = testTagPrefix?.let {
                        Modifier.testTag("$it.option.${optionLabel(option)}")
                    } ?: Modifier,
                    text = { Text(optionLabel(option)) },
                    onClick = {
                        expanded = false
                        onSelect(option)
                    }
                )
            }
        }
    }
}

@Composable
private fun StructuralTagPicker(
    tags: List<TagEntity>,
    selectedIds: List<UUID>,
    onChange: (List<UUID>) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("標籤", style = MaterialTheme.typography.titleSmall)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            tags.forEach { tag ->
                FilterChip(
                    selected = tag.id in selectedIds,
                    onClick = {
                        onChange(
                            if (tag.id in selectedIds) {
                                selectedIds - tag.id
                            } else {
                                selectedIds + tag.id
                            }
                        )
                    },
                    label = { Text(tag.name) }
                )
            }
        }
    }
}

private fun sanitizeStructuralAmount(value: String): String {
    val allowed = value.filter { it.isDigit() || it == '.' }
    var hasDot = false
    return buildString {
        allowed.forEach { character ->
            if (character == '.') {
                if (hasDot) return@forEach
                hasDot = true
            }
            append(character)
        }
    }.let { if (it == ".") "" else it }
}

private fun parseStructuralPositive(value: String): BigDecimal? {
    return value.toBigDecimalOrNull()?.takeIf { it > BigDecimal.ZERO }
}
