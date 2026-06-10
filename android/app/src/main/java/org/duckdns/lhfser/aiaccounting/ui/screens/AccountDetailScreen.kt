package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.core.transactions.TransactionSemantics
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.data.repository.LedgerDeletionResult
import org.duckdns.lhfser.aiaccounting.data.settlement.DebtSettlementBalanceCalculator
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.routing.TransactionEditDestination
import org.duckdns.lhfser.aiaccounting.ui.routing.resolveTransactionEditDestination
import org.duckdns.lhfser.aiaccounting.ui.components.ParityEmptyState
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySectionHeader
import org.duckdns.lhfser.aiaccounting.ui.components.ParityStatusPill
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySummaryCard
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTopSection
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTokens
import org.duckdns.lhfser.aiaccounting.ui.components.PressableCard
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateTimeText
import java.math.BigDecimal
import java.util.UUID

@Composable
fun AccountDetailScreen(
    accountId: String?,
    onEditAccount: (String) -> Unit,
    onEditTransaction: (String) -> Unit,
    onEditTransfer: (String) -> Unit,
    onEditDebt: (String) -> Unit,
    onOpenAdvanceCase: (String) -> Unit
) {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()
    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val transactions by repository.transactions.collectAsState(initial = emptyList())
    val advanceCases by repository.advanceCases.collectAsState(initial = emptyList())

    val resolvedId = remember(accountId) { accountId?.let(UUID::fromString) }
    val account = remember(accounts, resolvedId) { accounts.firstOrNull { it.id == resolvedId } }
    var transactionToDelete by remember { mutableStateOf<TransactionWithDetails?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    if (account == null) {
        Column(
            modifier = Modifier.padding(
                horizontal = AppSpacing.screenHorizontal,
                vertical = AppSpacing.screenVertical
            )
        ) {
            ParityTopSection(title = "帳戶明細", subtitle = "找不到這個帳戶")
            ParityEmptyState(
                title = "找不到帳戶",
                message = "這個帳戶可能已刪除、尚未同步，或目前沒有可顯示的資料。",
                icon = Icons.Default.AccountBalanceWallet
            )
        }
        return
    }

    val accountTransactions = remember(transactions, account.id) {
        transactions
            .filter { it.transaction.accountId == account.id }
            .sortedByDescending { it.transaction.date }
    }
    val balances = remember(account, transactions, advanceCases) { calculateBalances(account, transactions, advanceCases) }

    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(
            start = AppSpacing.screenHorizontal,
            end = AppSpacing.screenHorizontal,
            top = AppSpacing.screenVertical,
            bottom = AppSpacing.screenVertical + ParityTokens.FloatingContentBottomPadding
        ),
        verticalArrangement = Arrangement.spacedBy(AppSpacing.section)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.section)) {
                ParityTopSection(
                    title = account.name,
                    subtitle = "${account.type.rawValue} · ${account.currency}",
                    accessory = {
                        if (account.isArchived) {
                            ParityStatusPill(
                                text = "已歸檔",
                                tint = MaterialTheme.colorScheme.tertiary
                            )
                        }
                        TextButton(onClick = { onEditAccount(account.id.toString()) }) {
                            Text("編輯")
                        }
                    }
                )
                if (balances.isEmpty()) {
                    ParitySummaryCard(
                        title = "目前餘額",
                        value = BigDecimal.ZERO.asCurrencyText(account.currency),
                        supporting = "尚未有任何交易"
                    )
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)) {
                        balances.forEach { balance ->
                            ParitySummaryCard(
                                title = if (balances.size == 1) "目前餘額" else "${balance.currency} 餘額",
                                value = balance.amount.asCurrencyText(balance.currency),
                                supporting = "含初始餘額與所有已記錄交易",
                                accent = if (balance.amount.signum() >= 0) {
                                    MaterialTheme.colorScheme.primary
                                } else {
                                    MaterialTheme.colorScheme.error
                                }
                            )
                        }
                    }
                }
            }
        }

        item {
            ParitySectionHeader(
                title = "交易紀錄",
                detail = "${accountTransactions.size} 筆 · 點擊即可查看或編輯"
            )
        }

        if (accountTransactions.isEmpty()) {
            item {
                ParityEmptyState(
                    title = "還沒有交易",
                    message = "這個帳戶目前只有初始資料，還沒有新增任何收入、支出或轉帳。",
                    icon = Icons.Default.AccountBalanceWallet
                )
            }
        } else {
            items(accountTransactions, key = { it.transaction.id }) { item ->
                AccountTransactionRow(
                    item = item,
                    onClick = {
                        scope.launch {
                            runCatching {
                                resolveTransactionEditDestination(repository, item)
                            }.onSuccess { destination ->
                                when (destination) {
                                    is TransactionEditDestination.Ordinary -> onEditTransaction(destination.transactionId)
                                    is TransactionEditDestination.Transfer -> onEditTransfer(destination.groupId)
                                    is TransactionEditDestination.Debt -> onEditDebt(destination.transactionId)
                                    is TransactionEditDestination.Advance -> onOpenAdvanceCase(destination.caseId)
                                }
                            }.onFailure {
                                errorMessage = it.localizedMessage ?: "無法開啟編輯頁。"
                            }
                        }
                    },
                    onLongClick = { transactionToDelete = item }
                )
            }
        }
    }
    if (transactionToDelete != null) {
        val target = transactionToDelete ?: return
        val groupId = target.transaction.transferGroupId?.toString()
        val isTransfer = target.transaction.type == TransactionType.Transfer && groupId != null
        AlertDialog(
            onDismissRequest = { transactionToDelete = null },
            title = { Text(if (isTransfer) "刪除轉帳？" else "刪除交易？") },
            text = { Text(if (isTransfer) "將刪除此筆轉帳的所有分錄。" else "刪除後無法復原。") },
            confirmButton = {
                TextButton(onClick = {
                    transactionToDelete = null
                    scope.launch {
                        val result = repository.deleteLedgerTransactionById(target.transaction.id)
                        if (result == LedgerDeletionResult.AdvanceInitialRequiresCase) {
                            errorMessage = "這是代墊建立分錄，請進入代墊詳情刪除整個代墊案件。"
                        }
                    }
                }) { Text("刪除", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { transactionToDelete = null }) { Text("取消") }
            }
        )
    }

    if (errorMessage != null) {
        AlertDialog(
            onDismissRequest = { errorMessage = null },
            title = { Text("無法執行操作") },
            text = { Text(errorMessage ?: "") },
            confirmButton = { TextButton(onClick = { errorMessage = null }) { Text("了解") } }
        )
    }

}

@Composable
private fun AccountTransactionRow(
    item: TransactionWithDetails,
    onClick: () -> Unit,
    onLongClick: () -> Unit
) {
    val transaction = item.transaction
    val amountColor = when {
        transaction.amount.signum() > 0 -> MaterialTheme.colorScheme.primary
        transaction.amount.signum() < 0 -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.onSurface
    }
    val categoryText = item.category?.name ?: defaultTransactionTitle(transaction.type)
    val isDebtForgiveness = transaction.type == TransactionType.Transfer && TransactionSemantics.isDebtForgiveness(transaction.note)
    val displayTitle = if (isDebtForgiveness) {
        TransactionSemantics.debtForgivenessDisplayTitle(transaction.note)
    } else {
        transaction.note.ifBlank { categoryText }
    }
    val metaText = listOfNotNull(categoryText, item.account?.name)
        .distinct()
        .joinToString(" · ")
        .ifBlank { "未分類" }

    PressableCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick,
        onLongClick = onLongClick,
        containerColor = MaterialTheme.colorScheme.surface,
        pressedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
        borderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.35f),
        pressedBorderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.48f)
    ) {
        Column(
            modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(AppSpacing.tight)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            text = displayTitle,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold
                        )
                        if (isDebtForgiveness) {
                            ParityStatusPill(text = "免除債務", tint = MaterialTheme.colorScheme.tertiary)
                        }
                    }
                    Text(
                        text = metaText,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = transaction.date.toDateTimeText(),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Column(
                    horizontalAlignment = Alignment.End,
                    verticalArrangement = Arrangement.spacedBy(3.dp)
                ) {
                    Text(
                        text = transaction.amount.asCurrencyText(transaction.currencyCode),
                        style = MaterialTheme.typography.titleSmall,
                        color = amountColor,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = when {
                            isDebtForgiveness -> "編輯免除債務"
                            transaction.type == TransactionType.Transfer -> "編輯轉帳"
                            else -> "點擊編輯 · 長按刪除"
                        },
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
        }
    }
}

private data class AccountCurrencyBalance(
    val currency: String,
    val amount: BigDecimal
)

private fun calculateBalances(
    account: AccountEntity,
    transactions: List<TransactionWithDetails>,
    advanceCases: List<AdvanceCaseWithDetails>
): List<AccountCurrencyBalance> {
    return DebtSettlementBalanceCalculator.balancesFor(account, transactions, advanceCases)
        .map { AccountCurrencyBalance(it.currencyCode, it.amount) }
}

private fun defaultTransactionTitle(type: TransactionType): String = when (type) {
    TransactionType.Income -> "收入"
    TransactionType.Expense -> "支出"
    TransactionType.Transfer -> "轉帳"
}
