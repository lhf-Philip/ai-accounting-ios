package org.duckdns.lhfser.aiaccounting.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService
import org.duckdns.lhfser.aiaccounting.core.transactions.RateSourceState
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import java.math.BigDecimal
import java.math.RoundingMode

@Composable
fun CurrencyRateHint(
    currencyService: CurrencyService,
    amount: BigDecimal?,
    currencyCode: String,
    modifier: Modifier = Modifier
) {
    val preview = remember(amount, currencyCode, currencyService.mainCurrency, currencyService.rateSourceState, currencyService.rates) {
        amount?.let { currencyService.previewInMainCurrency(it, currencyCode) }
    }

    when {
        amount == null || amount <= BigDecimal.ZERO || currencyCode.equals(currencyService.mainCurrency, ignoreCase = true) -> Unit
        preview != null -> {
            Column(
                modifier = modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Text(
                    text = "約 ${preview.amount.asCurrencyText(currencyService.mainCurrency)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = preview.source.label,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary
                )
            }
        }
        else -> {
            Text(
                text = "暫時無法取得匯率",
                modifier = modifier.fillMaxWidth(),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error
            )
        }
    }
}

@Composable
fun TransferRateHint(
    currencyService: CurrencyService,
    outgoingAmount: BigDecimal?,
    outgoingCurrency: String,
    incomingAmount: BigDecimal?,
    incomingCurrency: String,
    modifier: Modifier = Modifier
) {
    val canCompare = outgoingAmount != null && incomingAmount != null && outgoingAmount > BigDecimal.ZERO && incomingAmount > BigDecimal.ZERO
    val impliedRate = remember(outgoingAmount, incomingAmount, outgoingCurrency, incomingCurrency) {
        if (!canCompare || outgoingCurrency.equals(incomingCurrency, ignoreCase = true)) {
            null
        } else {
            incomingAmount!!.divide(outgoingAmount, 6, RoundingMode.HALF_UP)
        }
    }
    val marketRate = remember(outgoingCurrency, incomingCurrency, currencyService.rateSourceState, currencyService.rates) {
        currencyService.getMarketRate(outgoingCurrency, incomingCurrency)
    }

    if (!canCompare || outgoingCurrency.equals(incomingCurrency, ignoreCase = true)) return

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 4.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        impliedRate?.let {
            Text(
                text = "輸入匯率 1 $outgoingCurrency = ${it.stripTrailingZeros().toPlainString()} $incomingCurrency",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.Medium
            )
        }
        marketRate?.let {
            Text(
                text = "參考匯率 1 $outgoingCurrency = ${BigDecimal.valueOf(it).setScale(4, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()} $incomingCurrency（${currencyService.resolvedRateSourceState.label}）",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.primary
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            CurrencyRateHint(
                currencyService = currencyService,
                amount = outgoingAmount,
                currencyCode = outgoingCurrency,
                modifier = Modifier.weight(1f)
            )
            CurrencyRateHint(
                currencyService = currencyService,
                amount = incomingAmount,
                currencyCode = incomingCurrency,
                modifier = Modifier.weight(1f)
            )
        }
    }
}
