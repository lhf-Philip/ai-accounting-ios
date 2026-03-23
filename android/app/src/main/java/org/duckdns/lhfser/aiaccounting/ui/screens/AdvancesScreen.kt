package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseWithDetails
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.PressableCard
import org.duckdns.lhfser.aiaccounting.ui.components.SectionHeader
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import org.duckdns.lhfser.aiaccounting.ui.utils.toDateText
import java.math.BigDecimal

@Composable
fun AdvancesScreen(onOpenCase: (String) -> Unit) {
    val repository = LocalRepository.current
    val cases by repository.advanceCases.collectAsState(initial = emptyList())

    LazyColumn(
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item { SectionHeader(title = "代墊追蹤") }
        items(cases) { advanceCase ->
            AdvanceCaseRow(advanceCase = advanceCase, onClick = { onOpenCase(advanceCase.advanceCase.id.toString()) })
        }
    }
}

@Composable
private fun AdvanceCaseRow(advanceCase: AdvanceCaseWithDetails, onClick: () -> Unit) {
    val outstanding = advanceCase.participants.fold(BigDecimal.ZERO) { acc, participant ->
        val remaining = (participant.owedAmount - participant.repaidAmount).max(BigDecimal.ZERO)
        acc + remaining
    }
    PressableCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(advanceCase.advanceCase.title, style = MaterialTheme.typography.bodyLarge)
                Text("日期：${advanceCase.advanceCase.date.toDateText()}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    "未還",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    outstanding.asCurrencyText(advanceCase.advanceCase.currencyCode),
                    style = MaterialTheme.typography.titleSmall
                )
            }
        }
    }
}
