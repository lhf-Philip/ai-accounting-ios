package org.duckdns.lhfser.aiaccounting.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.ui.Alignment
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf

@Composable
fun SectionHeader(
    title: String,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
        if (actionLabel != null && onAction != null) {
            TextButton(onClick = onAction) { Text(actionLabel) }
        }
    }
}

@Composable
fun SectionCard(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            content()
        }
    }
}

@Composable
fun CurrencyPicker(
    selected: String,
    onSelect: (String) -> Unit,
    buttonStyle: CurrencyButtonStyle = CurrencyButtonStyle.Tonal
) {
    val currencies = listOf("HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP")
    val expanded = remember { mutableStateOf(false) }
    val onClick = { expanded.value = true }
    when (buttonStyle) {
        CurrencyButtonStyle.Tonal -> {
            FilledTonalButton(onClick = onClick) {
                Text(selected)
            }
        }
        CurrencyButtonStyle.Text -> {
            TextButton(onClick = onClick) {
                Text(selected)
            }
        }
    }
    DropdownMenu(
        expanded = expanded.value,
        onDismissRequest = { expanded.value = false }
    ) {
        currencies.forEach { code ->
            DropdownMenuItem(
                text = { Text(code) },
                onClick = {
                    expanded.value = false
                    onSelect(code)
                }
            )
        }
    }
}

enum class CurrencyButtonStyle {
    Tonal,
    Text
}
