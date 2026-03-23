package org.duckdns.lhfser.aiaccounting.ui.utils

import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val dateFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
private val dateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")

fun BigDecimal.asCurrencyText(currency: String): String {
    val amount = setScale(2, RoundingMode.HALF_UP).toPlainString()
    return "$currency $amount"
}

fun Instant.toDateText(): String =
    dateFormatter.format(atZone(ZoneId.systemDefault()).toLocalDate())

fun Instant.toDateTimeText(): String =
    dateTimeFormatter.format(atZone(ZoneId.systemDefault()).toLocalDateTime())
