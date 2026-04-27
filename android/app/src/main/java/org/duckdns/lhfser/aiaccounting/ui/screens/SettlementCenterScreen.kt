package org.duckdns.lhfser.aiaccounting.ui.screens

import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Timeline
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.core.transactions.TransactionSemantics
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails
import org.duckdns.lhfser.aiaccounting.ui.LocalCurrencyService
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.ParityEmptyState
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySegmentedControl
import org.duckdns.lhfser.aiaccounting.ui.components.ParityStatusPill
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySummaryCard
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTopSection
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTokens
import org.duckdns.lhfser.aiaccounting.ui.components.PressableCard
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateText
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

private enum class SettlementMode(val label: String) {
    People("按對象"),
    Cases("按案件"),
    Timeline("時間線")
}

private data class SettlementPersonSummary(
    val account: AccountEntity,
    val balances: List<SettlementCurrencyBalance>,
    val netInMainCurrency: BigDecimal,
    val advanceCaseCount: Int,
    val repaymentCount: Int,
    val forgivenessCount: Int
)

private data class SettlementCurrencyBalance(
    val currency: String,
    val amount: BigDecimal
)

private data class TimelineItem(
    val id: String,
    val date: Instant,
    val title: String,
    val subtitle: String,
    val amount: BigDecimal?,
    val currencyCode: String,
    val tint: Color
)

@Composable
fun SettlementCenterScreen(
    onOpenAdvanceCase: (String) -> Unit,
    onOpenDebt: () -> Unit
) {
    val repository = LocalRepository.current
    val currencyService = LocalCurrencyService.current
    val context = LocalContext.current

    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val transactions by repository.transactions.collectAsState(initial = emptyList())
    val advanceCases by repository.advanceCases.collectAsState(initial = emptyList())
    val mainCurrency = currencyService.mainCurrency
    val rateSnapshot = currencyService.rates
    var mode by rememberSaveable { mutableStateOf(SettlementMode.People) }

    val personSummaries = remember(accounts, transactions, advanceCases, mainCurrency, rateSnapshot) {
        buildPersonSummaries(accounts, transactions, advanceCases, currencyService, mainCurrency)
    }
    val totalNet = remember(personSummaries) {
        personSummaries.fold(BigDecimal.ZERO) { acc, summary -> acc + summary.netInMainCurrency }
    }
    val caseSummaries = remember(advanceCases) {
        advanceCases.sortedWith(
            compareByDescending<AdvanceCaseWithDetails> { outstandingAmount(it) }
                .thenByDescending { it.advanceCase.date }
        )
    }
    val timelineItems = remember(transactions, advanceCases) {
        buildTimelineItems(transactions, advanceCases)
    }
    val shareText = remember(personSummaries, totalNet, mainCurrency) {
        buildShareText(personSummaries, totalNet, mainCurrency)
    }

    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(
            start = AppSpacing.screenHorizontal,
            end = AppSpacing.screenHorizontal,
            top = AppSpacing.screenVertical,
            bottom = AppSpacing.screenVertical + ParityTokens.FloatingContentBottomPadding
        ),
        verticalArrangement = Arrangement.spacedBy(AppSpacing.section)
    ) {
        item {
            ParityTopSection(
                title = "結算中心",
                subtitle = "集中查看代墊、借貸、還款與免除債務。",
                accessory = {
                    TextButton(onClick = {
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, shareText)
                        }
                        context.startActivity(Intent.createChooser(intent, "分享結算摘要"))
                    }) {
                        Text("分享")
                    }
                }
            )
        }

        item {
            ParitySummaryCard(
                title = "整體淨額 ($mainCurrency)",
                value = totalNet.asCurrencyText(mainCurrency),
                supporting = "正數代表你待收；負數代表你待還。"
            )
        }

        item {
            ParitySegmentedControl(
                options = SettlementMode.values().toList(),
                selected = mode,
                label = { it.label },
                onSelect = { mode = it }
            )
        }

        when (mode) {
            SettlementMode.People -> {
                if (personSummaries.isEmpty()) {
                    item {
                        ParityEmptyState(
                            title = "沒有待結算對象",
                            message = "代墊、借貸、還款和免除債務都清空後，這裡會保持空白。",
                            icon = Icons.Default.CheckCircle
                        )
                    }
                } else {
                    items(personSummaries, key = { it.account.id }) { summary ->
                        PersonSummaryCard(summary = summary, mainCurrency = mainCurrency)
                    }
                }
            }
            SettlementMode.Cases -> {
                if (caseSummaries.isEmpty()) {
                    item {
                        ParityEmptyState(
                            title = "沒有代墊案件",
                            message = "新增代墊後，案件級結算會出現在這裡。",
                            icon = Icons.Default.Groups
                        )
                    }
                } else {
                    items(caseSummaries, key = { it.advanceCase.id }) { advanceCase ->
                        CaseSummaryCard(
                            advanceCase = advanceCase,
                            onClick = { onOpenAdvanceCase(advanceCase.advanceCase.id.toString()) }
                        )
                    }
                }
            }
            SettlementMode.Timeline -> {
                if (timelineItems.isEmpty()) {
                    item {
                        ParityEmptyState(
                            title = "沒有結算時間線",
                            message = "代墊、還款、借貸與免除債務紀錄會按時間排列。",
                            icon = Icons.Default.Timeline
                        )
                    }
                } else {
                    items(timelineItems, key = { it.id }) { item ->
                        TimelineCard(item = item)
                    }
                }
            }
        }

        item {
            PressableCard(modifier = Modifier.fillMaxWidth(), onClick = onOpenDebt) {
                Row(
                    modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("新增借貸 / 還款 / 免除債務", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        Text("快速跳轉到債務管理流程。", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

@Composable
private fun PersonSummaryCard(summary: SettlementPersonSummary, mainCurrency: String) {
    val primaryBalance = summary.balances.firstOrNull()
    PressableCard(modifier = Modifier.fillMaxWidth(), onClick = {}) {
        Column(
            modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 15.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(summary.account.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    Text(directionText(summary.netInMainCurrency), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    if (primaryBalance != null) {
                        Text(
                            primaryBalance.amount.asCurrencyText(primaryBalance.currency),
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            color = amountColor(primaryBalance.amount)
                        )
                    }
                    Text(
                        summary.netInMainCurrency.asCurrencyText(mainCurrency),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ParityStatusPill("代墊 ${summary.advanceCaseCount}", tint = MaterialTheme.colorScheme.tertiary)
                ParityStatusPill("還款 ${summary.repaymentCount}", tint = MaterialTheme.colorScheme.primary)
                ParityStatusPill("免除 ${summary.forgivenessCount}", tint = MaterialTheme.colorScheme.secondary)
            }
            summary.balances.drop(1).forEach { balance ->
                Text(
                    "${balance.currency}: ${balance.amount.asCurrencyText(balance.currency)}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun CaseSummaryCard(advanceCase: AdvanceCaseWithDetails, onClick: () -> Unit) {
    val outstanding = outstandingAmount(advanceCase)
    val total = totalAdvanced(advanceCase)
    PressableCard(modifier = Modifier.fillMaxWidth(), onClick = onClick) {
        Column(
            modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 15.dp),
            verticalArrangement = Arrangement.spacedBy(7.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(advanceCase.advanceCase.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    Text("${advanceCase.participants.size} 位對象 · ${advanceCase.advanceCase.date.toDateText()}", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text("未清", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(outstanding.asCurrencyText(advanceCase.advanceCase.currencyCode), style = MaterialTheme.typography.titleSmall, color = amountColor(outstanding))
                }
            }
            Text("總額 ${total.asCurrencyText(advanceCase.advanceCase.currencyCode)}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun TimelineCard(item: TimelineItem) {
    PressableCard(modifier = Modifier.fillMaxWidth(), onClick = {}) {
        Row(
            modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 14.dp),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text("●", color = item.tint, style = MaterialTheme.typography.titleMedium)
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(item.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Text(item.subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(item.date.toDateText(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (item.amount != null) {
                Text(
                    item.amount.asCurrencyText(item.currencyCode),
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = amountColor(item.amount)
                )
            }
        }
    }
}

private fun buildPersonSummaries(
    accounts: List<AccountEntity>,
    transactions: List<TransactionWithDetails>,
    advanceCases: List<AdvanceCaseWithDetails>,
    currencyService: org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService,
    mainCurrency: String
): List<SettlementPersonSummary> {
    val debtAccounts = accounts.filter { it.type == AccountType.Debt && !it.isArchived }
    val balancesByAccount = calculateDebtBalances(debtAccounts, transactions)
    val forgivenessByAccount = transactions
        .filter { it.account?.type == AccountType.Debt && TransactionSemantics.isDebtForgiveness(it.transaction.note) }
        .groupingBy { it.account?.id }
        .eachCount()
    val participantsByAccount = advanceCases
        .flatMap { advanceCase -> advanceCase.participants.map { participant -> advanceCase to participant } }
        .groupBy { it.second.debtAccountId }
    val repaymentsByAccount = advanceCases
        .flatMap { advanceCase -> advanceCase.repayments.mapNotNull { repayment ->
            val participant = advanceCase.participants.firstOrNull { it.id == repayment.participantId }
            val debtAccountId = participant?.debtAccountId ?: return@mapNotNull null
            debtAccountId to repayment
        } }
        .groupBy { it.first }

    return debtAccounts.map { account ->
        val balances = balancesByAccount[account.id].orEmpty()
        val netInMain = balances.fold(BigDecimal.ZERO) { acc, balance ->
            acc + currencyService.convert(balance.amount, balance.currency, mainCurrency)
        }
        val caseCount = participantsByAccount[account.id].orEmpty().map { it.first.advanceCase.id }.toSet().size
        val repaymentCount = repaymentsByAccount[account.id].orEmpty().size
        SettlementPersonSummary(
            account = account,
            balances = balances,
            netInMainCurrency = netInMain,
            advanceCaseCount = caseCount,
            repaymentCount = repaymentCount,
            forgivenessCount = forgivenessByAccount[account.id] ?: 0
        )
    }
        .filter { it.netInMainCurrency != BigDecimal.ZERO || it.advanceCaseCount > 0 || it.repaymentCount > 0 || it.forgivenessCount > 0 }
        .sortedByDescending { it.netInMainCurrency.abs() }
}

private fun calculateDebtBalances(
    accounts: List<AccountEntity>,
    transactions: List<TransactionWithDetails>
): Map<UUID, List<SettlementCurrencyBalance>> {
    val grouped = transactions.groupBy { it.transaction.accountId }
    return accounts.associate { account ->
        val totals = linkedMapOf<String, BigDecimal>()
        if (account.baseBalance != BigDecimal.ZERO) {
            totals[account.currency] = account.baseBalance
        }
        grouped[account.id].orEmpty().forEach { tx ->
            val currency = tx.transaction.currencyCode
            totals[currency] = totals.getOrDefault(currency, BigDecimal.ZERO) + tx.transaction.amount
        }
        account.id to totals.entries
            .filter { it.value != BigDecimal.ZERO }
            .sortedBy { it.key }
            .map { SettlementCurrencyBalance(it.key, it.value) }
    }
}

private fun buildTimelineItems(
    transactions: List<TransactionWithDetails>,
    advanceCases: List<AdvanceCaseWithDetails>
): List<TimelineItem> {
    val advanceGroupIds = advanceCases
        .flatMap { advanceCase ->
            advanceCase.participants.mapNotNull { it.initialTransferGroupId } +
                advanceCase.repayments.mapNotNull { it.linkedTransferGroupId }
        }
        .toSet()

    val items = mutableListOf<TimelineItem>()
    advanceCases.forEach { advanceCase ->
        items += TimelineItem(
            id = "case-${advanceCase.advanceCase.id}",
            date = advanceCase.advanceCase.date,
            title = "建立代墊：${advanceCase.advanceCase.title}",
            subtitle = "${advanceCase.participants.size} 位對象，未清 ${outstandingAmount(advanceCase).asCurrencyText(advanceCase.advanceCase.currencyCode)}",
            amount = totalAdvanced(advanceCase),
            currencyCode = advanceCase.advanceCase.currencyCode,
            tint = Color(0xFFFF9800)
        )
        advanceCase.repayments.forEach { repayment ->
            val participant = advanceCase.participants.firstOrNull { it.id == repayment.participantId }
            items += TimelineItem(
                id = "repayment-${repayment.id}",
                date = repayment.date,
                title = "代墊還款：${participant?.name ?: "未命名對象"}",
                subtitle = advanceCase.advanceCase.title,
                amount = repayment.amount,
                currencyCode = repayment.currencyCode,
                tint = Color(0xFF2E7D32)
            )
        }
    }

    transactions.forEach { tx ->
        val transaction = tx.transaction
        if (tx.account?.type != AccountType.Debt || transaction.type != TransactionType.Transfer) return@forEach
        val isForgiveness = TransactionSemantics.isDebtForgiveness(transaction.note)
        if (!isForgiveness && transaction.transferGroupId != null && transaction.transferGroupId in advanceGroupIds) return@forEach
        items += TimelineItem(
            id = "debt-${transaction.id}",
            date = transaction.date,
            title = when {
                isForgiveness -> TransactionSemantics.debtForgivenessDisplayTitle(transaction.note)
                transaction.amount.signum() < 0 -> "債務增加"
                else -> "債務減少"
            },
            subtitle = tx.account.name,
            amount = transaction.amount,
            currencyCode = transaction.currencyCode,
            tint = when {
                isForgiveness -> Color(0xFF8E24AA)
                transaction.amount.signum() < 0 -> Color(0xFFD32F2F)
                else -> Color(0xFF1976D2)
            }
        )
    }

    return items.sortedByDescending { it.date }
}

private fun outstandingAmount(advanceCase: AdvanceCaseWithDetails): BigDecimal {
    return advanceCase.participants.fold(BigDecimal.ZERO) { acc, participant ->
        acc + (participant.owedAmount - participant.repaidAmount).max(BigDecimal.ZERO)
    }
}

private fun totalAdvanced(advanceCase: AdvanceCaseWithDetails): BigDecimal {
    return advanceCase.advanceCase.myShareAmount + advanceCase.participants.fold(BigDecimal.ZERO) { acc, participant ->
        acc + participant.owedAmount
    }
}

private fun buildShareText(
    summaries: List<SettlementPersonSummary>,
    totalNet: BigDecimal,
    mainCurrency: String
): String {
    return buildString {
        appendLine("結算中心摘要")
        appendLine("淨額：${totalNet.asCurrencyText(mainCurrency)}")
        appendLine()
        summaries.forEach { summary ->
            val firstBalance = summary.balances.firstOrNull()
            appendLine(
                "${summary.account.name}, ${directionText(summary.netInMainCurrency)}, " +
                    "${firstBalance?.amount?.asCurrencyText(firstBalance.currency) ?: BigDecimal.ZERO.asCurrencyText(summary.account.currency)}, " +
                    "代墊 ${summary.advanceCaseCount}, 還款 ${summary.repaymentCount}, 免除 ${summary.forgivenessCount}"
            )
        }
    }
}

private fun directionText(amount: BigDecimal): String {
    return when {
        amount.signum() > 0 -> "對方欠你"
        amount.signum() < 0 -> "你欠對方"
        else -> "已結清"
    }
}

@Composable
private fun amountColor(amount: BigDecimal): Color {
    return when {
        amount.signum() > 0 -> Color(0xFF2E7D32)
        amount.signum() < 0 -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
}
