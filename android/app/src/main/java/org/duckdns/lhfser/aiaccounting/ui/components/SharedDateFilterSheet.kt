package org.duckdns.lhfser.aiaccounting.ui.components

import android.app.DatePickerDialog
import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import org.duckdns.lhfser.aiaccounting.core.preferences.SharedDateFilterType
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SharedDateFilterSheet(
    title: String,
    description: String,
    filterType: SharedDateFilterType,
    selectedDate: LocalDate,
    customStartDate: LocalDate,
    customEndDate: LocalDate,
    onSelectFilterType: (SharedDateFilterType) -> Unit,
    onPickSelectedDate: () -> Unit,
    onPickCustomStart: () -> Unit,
    onPickCustomEnd: () -> Unit,
    onDismiss: () -> Unit,
    allSubtitle: String,
    yearSubtitle: String,
    monthSubtitle: String,
    daySubtitle: String,
    customSubtitle: String = "自訂開始與結束日期"
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.background,
        dragHandle = { ParitySheetHandle() }
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(
                description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            SharedDateFilterType.entries.forEach { type ->
                ParitySelectionSheetRow(
                    title = type.label,
                    subtitle = when (type) {
                        SharedDateFilterType.All -> allSubtitle
                        SharedDateFilterType.Year -> yearSubtitle
                        SharedDateFilterType.Month -> monthSubtitle
                        SharedDateFilterType.Day -> daySubtitle
                        SharedDateFilterType.Custom -> customSubtitle
                    },
                    selected = filterType == type,
                    onClick = { onSelectFilterType(type) }
                )
            }

            when (filterType) {
                SharedDateFilterType.Year,
                SharedDateFilterType.Month,
                SharedDateFilterType.Day -> {
                    DatePickerRow(
                        title = "基準日期",
                        value = selectedDateLabel(filterType, selectedDate),
                        action = "調整",
                        onClick = onPickSelectedDate
                    )
                }
                SharedDateFilterType.Custom -> {
                    DatePickerRow(
                        title = "開始日期",
                        value = customStartDate.format(DateTimeFormatter.ISO_DATE),
                        action = "選擇",
                        onClick = onPickCustomStart
                    )
                    DatePickerRow(
                        title = "結束日期",
                        value = customEndDate.format(DateTimeFormatter.ISO_DATE),
                        action = "選擇",
                        onClick = onPickCustomEnd
                    )
                }
                SharedDateFilterType.All -> Unit
            }

            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = onDismiss) { Text("完成") }
            }
            Spacer(modifier = Modifier.height(8.dp))
        }
    }
}

fun showSharedDatePicker(
    context: Context,
    initialDate: LocalDate,
    onDateSelected: (LocalDate) -> Unit
) {
    DatePickerDialog(
        context,
        { _, year, month, day ->
            onDateSelected(LocalDate.of(year, month + 1, day))
        },
        initialDate.year,
        initialDate.monthValue - 1,
        initialDate.dayOfMonth
    ).show()
}

@Composable
private fun DatePickerRow(
    title: String,
    value: String,
    action: String,
    onClick: () -> Unit
) {
    PressableCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick,
        containerColor = MaterialTheme.colorScheme.surfaceVariant,
        pressedContainerColor = MaterialTheme.colorScheme.surface
    ) {
        Row(
            modifier = Modifier.padding(horizontal = AppSpacing.card, vertical = 14.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Text(
                    value,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Text(action, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
        }
    }
}

private fun selectedDateLabel(type: SharedDateFilterType, date: LocalDate): String {
    return when (type) {
        SharedDateFilterType.Year -> "${date.year}年"
        SharedDateFilterType.Month -> date.format(DateTimeFormatter.ofPattern("yyyy年 M月"))
        SharedDateFilterType.Day -> date.format(DateTimeFormatter.ofPattern("yyyy年 M月d日"))
        SharedDateFilterType.All,
        SharedDateFilterType.Custom -> date.format(DateTimeFormatter.ISO_DATE)
    }
}
