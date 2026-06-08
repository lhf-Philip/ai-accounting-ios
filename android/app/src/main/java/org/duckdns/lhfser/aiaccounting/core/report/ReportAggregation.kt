package org.duckdns.lhfser.aiaccounting.core.report

import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.core.refund.RefundDestinationKind
import org.duckdns.lhfser.aiaccounting.core.refund.RefundSemanticInput
import org.duckdns.lhfser.aiaccounting.core.refund.RefundSemantics
import org.duckdns.lhfser.aiaccounting.core.transactions.RateSourceState

enum class ReportFlow(val transactionType: TransactionType) {
    Expense(TransactionType.Expense),
    Income(TransactionType.Income)
}

enum class ReportGroupingMode {
    Category,
    Tag
}

enum class ReportEstimateStatus(val label: String?) {
    Exact(null),
    Live("即時匯率"),
    Cached("上次匯率"),
    Partial("估算不完整"),
    Unavailable("估算不完整")
}

data class ReportConversion(
    val amount: BigDecimal,
    val status: ReportEstimateStatus
)

interface ReportCurrencyConverting {
    val mainCurrency: String
    fun estimateInMainCurrency(amount: BigDecimal, currencyCode: String): ReportConversion?
}

data class ReportTransactionSnapshot(
    val id: UUID,
    val amount: BigDecimal,
    val currencyCode: String,
    val date: Instant,
    val type: TransactionType,
    val categoryId: UUID?,
    val categoryName: String?,
    val categoryColorHex: String?,
    val tagNames: List<String>,
    val semantic: ReportTransactionSemantic = ReportTransactionSemantic.Regular
)

sealed interface ReportTransactionSemantic {
    data object Regular : ReportTransactionSemantic
    data class Refund(
        val destination: RefundDestinationKind,
        val originalExpenseRemaining: BigDecimal? = null
    ) : ReportTransactionSemantic
}

data class ReportCurrencyTotal(
    val currencyCode: String,
    val amount: BigDecimal
)

data class ReportSlice(
    val key: String,
    val name: String,
    val categoryColorHex: String?,
    val estimatedAmount: BigDecimal,
    val originalCurrencyTotals: List<ReportCurrencyTotal>,
    val grossEstimatedAmount: BigDecimal,
    val grossOriginalCurrencyTotals: List<ReportCurrencyTotal>,
    val refundReductionEstimatedAmount: BigDecimal,
    val refundReductionOriginalCurrencyTotals: List<ReportCurrencyTotal>,
    val refundSettlementOnlyEstimatedAmount: BigDecimal,
    val refundSettlementOnlyOriginalCurrencyTotals: List<ReportCurrencyTotal>,
    val estimateStatus: ReportEstimateStatus,
    val transactionIds: List<UUID>
) {
    val detailSummary: ReportDetailSummary
        get() = ReportDetailSummary(
            estimatedAmount = estimatedAmount,
            originalCurrencyTotals = originalCurrencyTotals,
            grossEstimatedAmount = grossEstimatedAmount,
            grossOriginalCurrencyTotals = grossOriginalCurrencyTotals,
            refundReductionEstimatedAmount = refundReductionEstimatedAmount,
            refundReductionOriginalCurrencyTotals = refundReductionOriginalCurrencyTotals,
            refundSettlementOnlyEstimatedAmount = refundSettlementOnlyEstimatedAmount,
            refundSettlementOnlyOriginalCurrencyTotals = refundSettlementOnlyOriginalCurrencyTotals,
            estimateStatus = estimateStatus,
            transactionIds = transactionIds
        )
}

data class ReportDetailSummary(
    val estimatedAmount: BigDecimal,
    val originalCurrencyTotals: List<ReportCurrencyTotal>,
    val grossEstimatedAmount: BigDecimal,
    val grossOriginalCurrencyTotals: List<ReportCurrencyTotal>,
    val refundReductionEstimatedAmount: BigDecimal,
    val refundReductionOriginalCurrencyTotals: List<ReportCurrencyTotal>,
    val refundSettlementOnlyEstimatedAmount: BigDecimal,
    val refundSettlementOnlyOriginalCurrencyTotals: List<ReportCurrencyTotal>,
    val estimateStatus: ReportEstimateStatus,
    val transactionIds: List<UUID>
) {
    val transactionCount: Int
        get() = transactionIds.size
}

data class ReportAggregationRequest(
    val transactions: List<ReportTransactionSnapshot>,
    val flow: ReportFlow,
    val grouping: ReportGroupingMode,
    val startDate: Instant? = null,
    val endDate: Instant? = null,
    val tagFilter: String? = null
)

data class ReportAggregationResult(
    val slices: List<ReportSlice>
) {
    val totalEstimatedAmount: BigDecimal
        get() = slices.fold(BigDecimal.ZERO) { total, slice -> total + slice.estimatedAmount }
}

object ReportAggregationService {
    fun aggregate(
        request: ReportAggregationRequest,
        currencyConverter: ReportCurrencyConverting
    ): ReportAggregationResult {
        val filtered = request.transactions.mapNotNull { transaction ->
            val contribution = contributionFor(transaction, request.flow) ?: return@mapNotNull null
            if (request.startDate != null && transaction.date < request.startDate) return@mapNotNull null
            if (request.endDate != null && transaction.date >= request.endDate) return@mapNotNull null
            if (!matchesTagFilter(transaction, request.tagFilter)) return@mapNotNull null
            ReportAggregationItem(transaction = transaction, contribution = contribution)
        }

        val grouped = when (request.grouping) {
            ReportGroupingMode.Category -> filtered.groupBy {
                it.transaction.categoryId?.toString() ?: "uncategorized"
            }
            ReportGroupingMode.Tag -> buildMap<String, MutableList<ReportAggregationItem>> {
                filtered.forEach { item ->
                    val tags = item.transaction.tagNames.ifEmpty { listOf("無標籤") }
                    tags.forEach { tagName ->
                        getOrPut(tagName) { mutableListOf() }.add(item)
                    }
                }
            }
        }

        return ReportAggregationResult(
            slices = grouped.map { (key, transactions) ->
                makeSlice(
                    key = key,
                    transactions = transactions,
                    grouping = request.grouping,
                    currencyConverter = currencyConverter
                )
            }.sortedWith(
                compareByDescending<ReportSlice> { it.estimatedAmount }
                    .thenBy { it.name.lowercase() }
            )
        )
    }

    private fun matchesTagFilter(
        transaction: ReportTransactionSnapshot,
        tagFilter: String?
    ): Boolean {
        if (tagFilter == null) return true
        return if (tagFilter == "無標籤") {
            transaction.tagNames.isEmpty()
        } else {
            tagFilter in transaction.tagNames
        }
    }

    private fun contributionFor(
        transaction: ReportTransactionSnapshot,
        flow: ReportFlow
    ): ReportContribution? {
        return when (val semantic = transaction.semantic) {
            ReportTransactionSemantic.Regular -> {
                if (transaction.type != flow.transactionType) null else {
                    ReportContribution.Regular(transaction.amount.abs())
                }
            }
            is ReportTransactionSemantic.Refund -> {
                if (flow != ReportFlow.Expense) return null
                val effect = runCatching {
                    RefundSemantics.effect(
                        RefundSemanticInput(
                            amount = transaction.amount.abs(),
                            destination = semantic.destination,
                            originalExpenseRemaining = semantic.originalExpenseRemaining
                        )
                    )
                }.getOrNull() ?: return null
                ReportContribution.Refund(
                    reductionAmount = effect.expenseReduction,
                    settlementOnlyAmount = effect.settlementOnlyAmount
                )
            }
        }
    }

    private fun makeSlice(
        key: String,
        transactions: List<ReportAggregationItem>,
        grouping: ReportGroupingMode,
        currencyConverter: ReportCurrencyConverting
    ): ReportSlice {
        val gross = ReportAmountAccumulator()
        val refundReduction = ReportAmountAccumulator()
        val refundSettlementOnly = ReportAmountAccumulator()
        val netOriginalTotals = mutableMapOf<String, BigDecimal>()
        val statuses = mutableListOf<ReportEstimateStatus>()
        var unavailableCount = 0
        var conversionAttemptCount = 0

        transactions.forEach { item ->
            val currencyCode = item.transaction.currencyCode.uppercase()
            when (val contribution = item.contribution) {
                is ReportContribution.Regular -> {
                    netOriginalTotals[currencyCode] = (netOriginalTotals[currencyCode] ?: BigDecimal.ZERO) + contribution.amount
                    add(
                        amount = contribution.amount,
                        currencyCode = currencyCode,
                        accumulator = gross,
                        currencyConverter = currencyConverter,
                        statuses = statuses,
                        unavailableCount = { unavailableCount += 1 },
                        conversionAttemptCount = { conversionAttemptCount += 1 }
                    )
                }
                is ReportContribution.Refund -> {
                    netOriginalTotals[currencyCode] = (netOriginalTotals[currencyCode] ?: BigDecimal.ZERO) - contribution.reductionAmount
                    add(
                        amount = contribution.reductionAmount,
                        currencyCode = currencyCode,
                        accumulator = refundReduction,
                        currencyConverter = currencyConverter,
                        statuses = statuses,
                        unavailableCount = { unavailableCount += 1 },
                        conversionAttemptCount = { conversionAttemptCount += 1 }
                    )
                    add(
                        amount = contribution.settlementOnlyAmount,
                        currencyCode = currencyCode,
                        accumulator = refundSettlementOnly,
                        currencyConverter = currencyConverter,
                        statuses = statuses,
                        unavailableCount = { unavailableCount += 1 },
                        conversionAttemptCount = { conversionAttemptCount += 1 }
                    )
                }
            }
        }
        val estimatedAmount = gross.estimatedAmount - refundReduction.estimatedAmount

        val status = when {
            conversionAttemptCount == 0 -> ReportEstimateStatus.Exact
            unavailableCount == conversionAttemptCount -> ReportEstimateStatus.Unavailable
            unavailableCount > 0 -> ReportEstimateStatus.Partial
            ReportEstimateStatus.Cached in statuses -> ReportEstimateStatus.Cached
            ReportEstimateStatus.Live in statuses -> ReportEstimateStatus.Live
            else -> ReportEstimateStatus.Exact
        }
        val first = transactions.firstOrNull()?.transaction

        return ReportSlice(
            key = key,
            name = when (grouping) {
                ReportGroupingMode.Category -> first?.categoryName ?: "未分類"
                ReportGroupingMode.Tag -> key
            },
            categoryColorHex = when (grouping) {
                ReportGroupingMode.Category -> first?.categoryColorHex
                ReportGroupingMode.Tag -> null
            },
            estimatedAmount = estimatedAmount,
            originalCurrencyTotals = netOriginalTotals.toCurrencyTotals(),
            grossEstimatedAmount = gross.estimatedAmount,
            grossOriginalCurrencyTotals = gross.originalCurrencyTotals,
            refundReductionEstimatedAmount = refundReduction.estimatedAmount,
            refundReductionOriginalCurrencyTotals = refundReduction.originalCurrencyTotals,
            refundSettlementOnlyEstimatedAmount = refundSettlementOnly.estimatedAmount,
            refundSettlementOnlyOriginalCurrencyTotals = refundSettlementOnly.originalCurrencyTotals,
            estimateStatus = status,
            transactionIds = transactions
                .sortedByDescending { it.transaction.date }
                .map { it.transaction.id }
        )
    }

    private fun add(
        amount: BigDecimal,
        currencyCode: String,
        accumulator: ReportAmountAccumulator,
        currencyConverter: ReportCurrencyConverting,
        statuses: MutableList<ReportEstimateStatus>,
        unavailableCount: () -> Unit,
        conversionAttemptCount: () -> Unit
    ) {
        if (amount.compareTo(BigDecimal.ZERO) == 0) return
        accumulator.originalTotals[currencyCode] = (accumulator.originalTotals[currencyCode] ?: BigDecimal.ZERO) + amount
        conversionAttemptCount()
        val conversion = currencyConverter.estimateInMainCurrency(amount, currencyCode)
        if (conversion == null) {
            unavailableCount()
        } else {
            accumulator.estimatedAmount += conversion.amount
            statuses += conversion.status
        }
    }
}

private data class ReportAggregationItem(
    val transaction: ReportTransactionSnapshot,
    val contribution: ReportContribution
)

private sealed interface ReportContribution {
    data class Regular(val amount: BigDecimal) : ReportContribution
    data class Refund(
        val reductionAmount: BigDecimal,
        val settlementOnlyAmount: BigDecimal
    ) : ReportContribution
}

private data class ReportAmountAccumulator(
    var estimatedAmount: BigDecimal = BigDecimal.ZERO,
    val originalTotals: MutableMap<String, BigDecimal> = mutableMapOf()
) {
    val originalCurrencyTotals: List<ReportCurrencyTotal>
        get() = originalTotals.toCurrencyTotals()
}

private fun Map<String, BigDecimal>.toCurrencyTotals(): List<ReportCurrencyTotal> {
    return entries
        .filter { it.value.compareTo(BigDecimal.ZERO) != 0 }
        .sortedBy { it.key }
        .map { ReportCurrencyTotal(currencyCode = it.key, amount = it.value) }
}

class CurrencyServiceReportConverter(
    private val currencyService: CurrencyService
) : ReportCurrencyConverting {
    override val mainCurrency: String
        get() = currencyService.mainCurrency

    override fun estimateInMainCurrency(
        amount: BigDecimal,
        currencyCode: String
    ): ReportConversion? {
        if (currencyCode.equals(mainCurrency, ignoreCase = true)) {
            return ReportConversion(amount = amount, status = ReportEstimateStatus.Exact)
        }
        val estimate = currencyService.estimate(amount, currencyCode, mainCurrency) ?: return null
        val status = when (estimate.source) {
            RateSourceState.Live -> ReportEstimateStatus.Live
            RateSourceState.Cached -> ReportEstimateStatus.Cached
            RateSourceState.Unavailable -> return null
        }
        return ReportConversion(amount = estimate.amount, status = status)
    }
}
