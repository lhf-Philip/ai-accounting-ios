package org.duckdns.lhfser.aiaccounting.core.money

import java.math.BigDecimal
import java.math.RoundingMode

private const val MONEY_SCALE = 2

fun BigDecimal.asMoney(): BigDecimal = setScale(MONEY_SCALE, RoundingMode.HALF_UP)

fun decimal(value: String): BigDecimal = BigDecimal(value)
