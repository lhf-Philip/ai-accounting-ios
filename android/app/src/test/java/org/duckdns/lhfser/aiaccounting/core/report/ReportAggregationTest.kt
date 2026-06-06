package org.duckdns.lhfser.aiaccounting.core.report

import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.junit.Assert.assertEquals
import org.junit.Test

class ReportAggregationTest {
    @Test
    fun categoryAggregation_preservesOriginalCurrencyAndEstimatesMainCurrency() {
        val categoryId = UUID.randomUUID()
        val transactionId = UUID.randomUUID()
        val result = ReportAggregationService.aggregate(
            request = ReportAggregationRequest(
                transactions = listOf(
                    ReportTransactionSnapshot(
                        id = transactionId,
                        amount = BigDecimal("-50"),
                        currencyCode = "USD",
                        date = Instant.parse("2026-02-01T12:00:00Z"),
                        type = TransactionType.Expense,
                        categoryId = categoryId,
                        categoryName = "餐飲",
                        categoryColorHex = "#FF0000",
                        tagNames = listOf("旅行")
                    )
                ),
                flow = ReportFlow.Expense,
                grouping = ReportGroupingMode.Category
            ),
            currencyConverter = FixedReportCurrencyConverter(
                mainCurrency = "HKD",
                ratesToMain = mapOf("USD" to BigDecimal("7.8")),
                source = ReportEstimateStatus.Live
            )
        )

        assertEquals(1, result.slices.size)
        val slice = result.slices.single()
        assertEquals("餐飲", slice.name)
        assertMoneyEquals("390", slice.estimatedAmount)
        assertEquals(
            listOf(ReportCurrencyTotal(currencyCode = "USD", amount = BigDecimal("50"))),
            slice.originalCurrencyTotals
        )
        assertEquals(ReportEstimateStatus.Live, slice.estimateStatus)
        assertEquals(listOf(transactionId), slice.transactionIds)
        assertEquals(1, slice.detailSummary.transactionCount)
    }

    @Test
    fun tagAggregation_filtersFlowAndDateAndSupportsCategoryDrillDown() {
        val start = Instant.parse("2026-02-01T00:00:00Z")
        val end = Instant.parse("2026-02-02T00:00:00Z")
        val categoryId = UUID.randomUUID()
        val expenseId = UUID.randomUUID()
        val transactions = listOf(
            snapshot(
                id = expenseId,
                amount = "-80",
                date = start.plusSeconds(60),
                type = TransactionType.Expense,
                categoryId = categoryId,
                tags = listOf("旅行", "朋友")
            ),
            snapshot(
                amount = "500",
                date = start.plusSeconds(120),
                type = TransactionType.Income,
                categoryId = null,
                tags = listOf("旅行")
            ),
            snapshot(
                amount = "-30",
                date = end,
                type = TransactionType.Expense,
                categoryId = categoryId,
                tags = listOf("旅行")
            )
        )
        val converter = FixedReportCurrencyConverter(mainCurrency = "HKD")

        val tags = ReportAggregationService.aggregate(
            request = ReportAggregationRequest(
                transactions = transactions,
                flow = ReportFlow.Expense,
                grouping = ReportGroupingMode.Tag,
                startDate = start,
                endDate = end
            ),
            currencyConverter = converter
        )
        assertEquals(listOf(expenseId), tags.slices.first { it.name == "旅行" }.transactionIds)
        assertEquals(listOf(expenseId), tags.slices.first { it.name == "朋友" }.transactionIds)

        val drillDown = ReportAggregationService.aggregate(
            request = ReportAggregationRequest(
                transactions = transactions,
                flow = ReportFlow.Expense,
                grouping = ReportGroupingMode.Category,
                startDate = start,
                endDate = end,
                tagFilter = "旅行"
            ),
            currencyConverter = converter
        )

        assertEquals("餐飲", drillDown.slices.single().name)
        assertEquals(listOf(expenseId), drillDown.slices.single().transactionIds)
    }

    @Test
    fun estimateStatus_distinguishesCachedPartialAndUnavailable() {
        val date = Instant.parse("2026-02-01T12:00:00Z")
        val transactions = listOf(
            snapshot(amount = "-100", currency = "HKD", date = date, categoryId = null),
            snapshot(amount = "-10", currency = "USD", date = date, categoryId = null),
            snapshot(amount = "-1000", currency = "JPY", date = date, categoryId = null)
        )
        val converter = FixedReportCurrencyConverter(
            mainCurrency = "HKD",
            ratesToMain = mapOf("USD" to BigDecimal("7.8")),
            source = ReportEstimateStatus.Cached
        )

        val partial = aggregate(transactions, converter)
        assertMoneyEquals("178", partial.slices.single().estimatedAmount)
        assertEquals(ReportEstimateStatus.Partial, partial.slices.single().estimateStatus)

        val unavailable = aggregate(
            listOf(snapshot(amount = "-1000", currency = "JPY", date = date, categoryId = null)),
            converter
        )
        assertEquals(ReportEstimateStatus.Unavailable, unavailable.slices.single().estimateStatus)

        val cached = aggregate(
            listOf(snapshot(amount = "-10", currency = "USD", date = date, categoryId = null)),
            converter
        )
        assertEquals(ReportEstimateStatus.Cached, cached.slices.single().estimateStatus)
    }

    private fun aggregate(
        transactions: List<ReportTransactionSnapshot>,
        converter: ReportCurrencyConverting
    ): ReportAggregationResult {
        return ReportAggregationService.aggregate(
            request = ReportAggregationRequest(
                transactions = transactions,
                flow = ReportFlow.Expense,
                grouping = ReportGroupingMode.Category
            ),
            currencyConverter = converter
        )
    }

    private fun snapshot(
        id: UUID = UUID.randomUUID(),
        amount: String,
        currency: String = "HKD",
        date: Instant,
        type: TransactionType = TransactionType.Expense,
        categoryId: UUID? = UUID.randomUUID(),
        tags: List<String> = emptyList()
    ): ReportTransactionSnapshot {
        return ReportTransactionSnapshot(
            id = id,
            amount = BigDecimal(amount),
            currencyCode = currency,
            date = date,
            type = type,
            categoryId = categoryId,
            categoryName = categoryId?.let { "餐飲" },
            categoryColorHex = categoryId?.let { "#FF0000" },
            tagNames = tags
        )
    }

    private fun assertMoneyEquals(expected: String, actual: BigDecimal) {
        assertEquals(0, BigDecimal(expected).compareTo(actual))
    }
}

private data class FixedReportCurrencyConverter(
    override val mainCurrency: String,
    val ratesToMain: Map<String, BigDecimal> = emptyMap(),
    val source: ReportEstimateStatus = ReportEstimateStatus.Live
) : ReportCurrencyConverting {
    override fun estimateInMainCurrency(amount: BigDecimal, currencyCode: String): ReportConversion? {
        if (currencyCode.equals(mainCurrency, ignoreCase = true)) {
            return ReportConversion(amount = amount, status = ReportEstimateStatus.Exact)
        }
        val rate = ratesToMain[currencyCode.uppercase()] ?: return null
        return ReportConversion(amount = amount * rate, status = source)
    }
}
