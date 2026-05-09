package org.duckdns.lhfser.aiaccounting.core.preferences

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

enum class SharedDateFilterType(val label: String) {
    All("全部"),
    Year("本年"),
    Month("本月"),
    Day("今日"),
    Custom("自訂區間")
}

data class SharedDateFilterState(
    val type: SharedDateFilterType = SharedDateFilterType.Month,
    val selectedDate: LocalDate = LocalDate.now(),
    val customStartDate: LocalDate = LocalDate.now(),
    val customEndDate: LocalDate = LocalDate.now()
)

fun sharedDateFilterLabel(
    type: SharedDateFilterType,
    selectedDate: LocalDate,
    customStartDate: LocalDate,
    customEndDate: LocalDate,
    allLabel: String = "全部"
): String {
    return when (type) {
        SharedDateFilterType.All -> allLabel
        SharedDateFilterType.Year -> "${selectedDate.year}年"
        SharedDateFilterType.Month -> selectedDate.format(DateTimeFormatter.ofPattern("yyyy年 M月"))
        SharedDateFilterType.Day -> selectedDate.format(DateTimeFormatter.ofPattern("M月d日"))
        SharedDateFilterType.Custom -> {
            val (start, end) = normalizedCustomDateRange(customStartDate, customEndDate)
            "${start.format(DateTimeFormatter.ISO_DATE)} ~ ${end.format(DateTimeFormatter.ISO_DATE)}"
        }
    }
}

fun resolveSharedDateRange(
    type: SharedDateFilterType,
    selectedDate: LocalDate,
    customStartDate: LocalDate,
    customEndDate: LocalDate
): Pair<Instant?, Instant?> {
    val zone = ZoneId.systemDefault()
    return when (type) {
        SharedDateFilterType.All -> null to null
        SharedDateFilterType.Year -> {
            val start = LocalDate.of(selectedDate.year, 1, 1).atStartOfDay(zone).toInstant()
            val end = LocalDate.of(selectedDate.year + 1, 1, 1).atStartOfDay(zone).toInstant()
            start to end
        }
        SharedDateFilterType.Month -> {
            val start = selectedDate.withDayOfMonth(1).atStartOfDay(zone).toInstant()
            val end = selectedDate.withDayOfMonth(1).plusMonths(1).atStartOfDay(zone).toInstant()
            start to end
        }
        SharedDateFilterType.Day -> {
            val start = selectedDate.atStartOfDay(zone).toInstant()
            val end = selectedDate.plusDays(1).atStartOfDay(zone).toInstant()
            start to end
        }
        SharedDateFilterType.Custom -> {
            val (startDate, endDate) = normalizedCustomDateRange(customStartDate, customEndDate)
            val start = startDate.atStartOfDay(zone).toInstant()
            val end = endDate.plusDays(1).atStartOfDay(zone).toInstant()
            start to end
        }
    }
}

fun normalizedCustomDateRange(start: LocalDate, end: LocalDate): Pair<LocalDate, LocalDate> {
    return if (end.isBefore(start)) end to start else start to end
}
