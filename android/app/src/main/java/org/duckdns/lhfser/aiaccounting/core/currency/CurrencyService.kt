package org.duckdns.lhfser.aiaccounting.core.currency

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.duckdns.lhfser.aiaccounting.core.transactions.RateSourceState
import java.math.BigDecimal
import java.math.RoundingMode
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant

data class ExchangeRateResponse(
    val base: String,
    val rates: Map<String, Double>
)

private data class ExchangeRateCache(
    val base: String,
    val rates: Map<String, Double>,
    val fetchedAt: Long
)

data class CurrencyPreview(
    val amount: BigDecimal,
    val source: RateSourceState
)

class CurrencyService(context: Context) {
    private val prefs = context.getSharedPreferences("currency_service", Context.MODE_PRIVATE)
    private val gson = Gson()
    private val cacheKey = "cachedExchangeRatesV2"
    private val legacyCacheKey = "cachedExchangeRates"
    private val cacheTtlMs = 7L * 24L * 60L * 60L * 1000L

    var rates by mutableStateOf<Map<String, Double>>(emptyMap())
        private set

    private var staleRates by mutableStateOf<Map<String, Double>>(emptyMap())

    var rateSourceState by mutableStateOf(RateSourceState.Unavailable)
        private set

    var mainCurrency: String
        get() = prefs.getString("mainCurrency", "HKD") ?: "HKD"
        set(value) {
            prefs.edit().putString("mainCurrency", value).apply()
            loadRatesFromLocal()
        }

    init {
        loadRatesFromLocal()
    }

    suspend fun fetchRates() {
        val requestedBase = mainCurrency.uppercase()
        val parsed = withContext(Dispatchers.IO) {
            val url = URL("https://api.exchangerate-api.com/v4/latest/$requestedBase")
            val connection = url.openConnection() as HttpURLConnection
            connection.connectTimeout = 8000
            connection.readTimeout = 8000
            connection.requestMethod = "GET"
            connection.doInput = true

            try {
                val response = connection.inputStream.bufferedReader().use { it.readText() }
                gson.fromJson(response, ExchangeRateResponse::class.java)
            } catch (_: Exception) {
                null
            } finally {
                connection.disconnect()
            }
        }

        if (parsed != null && parsed.base.equals(requestedBase, ignoreCase = true)) {
            rates = parsed.rates
            staleRates = parsed.rates
            rateSourceState = RateSourceState.Live
            saveRatesToLocal(base = requestedBase, rates = parsed.rates)
        } else {
            loadRatesFromLocal(preferStale = true)
        }
    }

    private fun saveRatesToLocal(base: String, rates: Map<String, Double>) {
        val cache = ExchangeRateCache(base = base, rates = rates, fetchedAt = Instant.now().toEpochMilli())
        prefs.edit().putString(cacheKey, gson.toJson(cache)).apply()
    }

    private fun loadRatesFromLocal(preferStale: Boolean = true) {
        val currentBase = mainCurrency.uppercase()
        rates = emptyMap()
        staleRates = emptyMap()
        rateSourceState = RateSourceState.Unavailable

        val cached = prefs.getString(cacheKey, null)
        if (cached != null) {
            val type = object : TypeToken<ExchangeRateCache>() {}.type
            val payload = gson.fromJson<ExchangeRateCache>(cached, type)
            if (payload.base.equals(currentBase, ignoreCase = true)) {
                val age = Instant.now().toEpochMilli() - payload.fetchedAt
                staleRates = payload.rates
                if (age <= cacheTtlMs) {
                    rates = payload.rates
                    rateSourceState = RateSourceState.Cached
                    return
                }
                if (preferStale && payload.rates.isNotEmpty()) {
                    rateSourceState = RateSourceState.Cached
                    return
                }
            }
        }

        if (prefs.contains(legacyCacheKey)) {
            prefs.edit().remove(legacyCacheKey).apply()
        }
    }

    fun convert(amount: BigDecimal, from: String): BigDecimal {
        if (from.equals(mainCurrency, ignoreCase = true)) return amount
        val rate = resolvedRates[from.uppercase()] ?: return amount
        if (rate <= 0.0) return amount
        return amount.divide(rate.toBigDecimal(), 6, RoundingMode.HALF_UP)
    }

    fun convert(amount: BigDecimal, from: String, to: String): BigDecimal {
        if (from.equals(to, ignoreCase = true)) return amount
        if (from.equals(mainCurrency, ignoreCase = true)) {
            val targetRate = resolvedRates[to.uppercase()] ?: return amount
            if (targetRate <= 0.0) return amount
            return amount.multiply(targetRate.toBigDecimal()).setScale(6, RoundingMode.HALF_UP)
        }
        if (to.equals(mainCurrency, ignoreCase = true)) {
            return convert(amount, from)
        }
        val targetRate = resolvedRates[to.uppercase()] ?: return amount
        if (targetRate <= 0.0) return amount
        val inMain = convert(amount, from)
        return inMain.multiply(targetRate.toBigDecimal()).setScale(6, RoundingMode.HALF_UP)
    }

    fun estimate(amount: BigDecimal, from: String, to: String): CurrencyPreview? {
        val sourceCode = from.uppercase()
        val targetCode = to.uppercase()
        if (sourceCode == targetCode) return CurrencyPreview(amount, resolvedRateSourceState)
        if (resolvedRates.isEmpty()) return null

        if (sourceCode == mainCurrency.uppercase()) {
            val targetRate = resolvedRates[targetCode] ?: return null
            if (targetRate <= 0.0) return null
            return CurrencyPreview(
                amount.multiply(targetRate.toBigDecimal()).setScale(6, RoundingMode.HALF_UP),
                resolvedRateSourceState
            )
        }

        if (targetCode == mainCurrency.uppercase()) {
            val sourceRate = resolvedRates[sourceCode] ?: return null
            if (sourceRate <= 0.0) return null
            return CurrencyPreview(
                amount.divide(sourceRate.toBigDecimal(), 6, RoundingMode.HALF_UP),
                resolvedRateSourceState
            )
        }

        val sourceRate = resolvedRates[sourceCode] ?: return null
        val targetRate = resolvedRates[targetCode] ?: return null
        if (sourceRate <= 0.0 || targetRate <= 0.0) return null
        val inMain = amount.divide(sourceRate.toBigDecimal(), 6, RoundingMode.HALF_UP)
        return CurrencyPreview(
            inMain.multiply(targetRate.toBigDecimal()).setScale(6, RoundingMode.HALF_UP),
            resolvedRateSourceState
        )
    }

    fun getMarketRate(from: String, to: String): Double? {
        if (from.equals(to, ignoreCase = true)) return 1.0
        val rateFrom = resolvedRates[from.uppercase()] ?: return null
        val rateTo = resolvedRates[to.uppercase()] ?: return null
        if (rateFrom <= 0.0 || rateTo <= 0.0) return null
        return (1.0 / rateFrom) * rateTo
    }

    fun previewInMainCurrency(amount: BigDecimal, from: String): CurrencyPreview? {
        if (from.equals(mainCurrency, ignoreCase = true)) return null
        return estimate(amount, from, mainCurrency)
    }

    val resolvedRateSourceState: RateSourceState
        get() = when {
            rates.isNotEmpty() -> rateSourceState
            staleRates.isNotEmpty() -> RateSourceState.Cached
            else -> RateSourceState.Unavailable
        }

    private val resolvedRates: Map<String, Double>
        get() = when {
            rates.isNotEmpty() -> rates
            staleRates.isNotEmpty() -> staleRates
            else -> emptyMap()
        }
}
