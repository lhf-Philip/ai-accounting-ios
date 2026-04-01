package org.duckdns.lhfser.aiaccounting.core.ai

import com.google.gson.Gson
import java.io.IOException
import java.math.BigDecimal
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.backup.FullBackupData
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryMonthlyBudgetEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionWithDetails

data class BudgetSuggestionItem(
    val categoryId: String,
    val suggestedAmount: BigDecimal,
    val currencyCode: String,
    val reason: String
)

data class BudgetSuggestionRequest(
    val startDate: LocalDate,
    val endInstant: Instant,
    val targetMonthDate: LocalDate,
    val includeIncomeContext: Boolean,
    val mainCurrency: String,
    val transactions: List<TransactionWithDetails>,
    val budgets: List<CategoryMonthlyBudgetEntity>,
    val targetCategories: List<CategoryEntity>,
    val backupData: FullBackupData?
)

class BudgetSuggestionService(
    private val settingsStore: GeminiSettingsStore,
    private val currencyService: CurrencyService
) {
    private val gson = Gson()
    private val modelName = "gemini-2.0-flash"

    suspend fun suggestBudgets(request: BudgetSuggestionRequest): List<BudgetSuggestionItem> = withContext(Dispatchers.IO) {
        val apiKey = settingsStore.apiKey
        require(apiKey.isNotBlank()) { "未設定 Gemini API Key。" }
        require(request.targetCategories.isNotEmpty()) { "目前沒有可建議的支出分類。" }

        val payload = buildPayload(request)
        if (!hasMeaningfulSignal(payload)) {
            throw IllegalStateException("資料不足，暫時無法產生預算建議。")
        }

        val prompt = buildPrompt(gson.toJson(payload))
        val requestBody = gson.toJson(
            mapOf(
                "contents" to listOf(
                    mapOf(
                        "parts" to listOf(
                            mapOf("text" to prompt)
                        )
                    )
                )
            )
        )

        val responseText = postGenerateContent(apiKey, requestBody)
        val response = gson.fromJson(responseText, GenerateContentResponse::class.java)
        val rawText = response.candidates
            ?.firstOrNull()
            ?.content
            ?.parts
            ?.joinToString(separator = "") { it.text.orEmpty() }
            ?.trim()
            .orEmpty()
            .removePrefix("```json")
            .removePrefix("```")
            .removeSuffix("```")
            .trim()

        if (rawText.isBlank()) {
            throw IllegalStateException("AI 未回傳可讀取的建議。")
        }

        val parsed = gson.fromJson(rawText, SuggestionEnvelope::class.java)
        val validIds = request.targetCategories.map { it.id.toString() }.toSet()
        parsed.suggestions.filter {
            it.categoryId in validIds && it.suggestedAmount >= BigDecimal.ZERO
        }
    }

    private fun postGenerateContent(apiKey: String, body: String): String {
        val endpoint = URL("https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey")
        val connection = endpoint.openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            connection.connectTimeout = 20_000
            connection.readTimeout = 60_000
            connection.doOutput = true
            connection.outputStream.use { output ->
                output.write(body.toByteArray(StandardCharsets.UTF_8))
            }

            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (code !in 200..299) {
                throw IOException("AI 服務失敗（$code）：$text")
            }
            text
        } finally {
            connection.disconnect()
        }
    }

    private fun buildPayload(request: BudgetSuggestionRequest): BudgetSuggestionPayload {
        val startInstant = request.startDate.atStartOfDay(ZoneId.systemDefault()).toInstant()
        val targetMonthKey = monthKeyFromDate(request.targetMonthDate)
        val expenseHistory = summarizeTransactions(
            request.transactions,
            startInstant,
            request.endInstant,
            TransactionType.Expense,
            request.mainCurrency
        )
        val expenseCurrentPeriod = summarizeCurrentPeriod(
            request.transactions,
            startInstant,
            request.endInstant,
            TransactionType.Expense,
            request.mainCurrency
        )
        val incomeHistory = if (request.includeIncomeContext) {
            summarizeTransactions(
                request.transactions,
                startInstant,
                request.endInstant,
                TransactionType.Income,
                request.mainCurrency
            )
        } else null
        val incomeCurrentPeriod = if (request.includeIncomeContext) {
            summarizeCurrentPeriod(
                request.transactions,
                startInstant,
                request.endInstant,
                TransactionType.Income,
                request.mainCurrency
            )
        } else null

        val existingBudgets = request.budgets
            .filter { it.monthKey == targetMonthKey }
            .mapNotNull { budget ->
                val category = request.targetCategories.firstOrNull { it.id == budget.categoryId } ?: return@mapNotNull null
                ExistingBudgetPayload(
                    categoryId = category.id.toString(),
                    categoryName = category.name,
                    amount = currencyService.convert(budget.amount, budget.currencyCode, request.mainCurrency),
                    currencyCode = request.mainCurrency
                )
            }

        val backupExpenseHistory = request.backupData?.let {
            summarizeBackupTransactions(
                backupData = it,
                startInstant = startInstant,
                endInstant = request.endInstant,
                transactionTypeRawValue = TransactionType.Expense.rawValue,
                targetCurrency = request.mainCurrency
            )
        }

        val backupIncomeHistory = if (request.includeIncomeContext) {
            request.backupData?.let {
                summarizeBackupTransactions(
                    backupData = it,
                    startInstant = startInstant,
                    endInstant = request.endInstant,
                    transactionTypeRawValue = TransactionType.Income.rawValue,
                    targetCurrency = request.mainCurrency
                )
            }
        } else null

        return BudgetSuggestionPayload(
            analysisStartDate = request.startDate.toString(),
            analysisEndDate = request.endInstant.toString(),
            targetMonthKey = targetMonthKey,
            mainCurrency = request.mainCurrency,
            targetCategories = request.targetCategories.map {
                TargetCategoryPayload(categoryId = it.id.toString(), name = it.name)
            },
            existingBudgets = existingBudgets,
            appExpenseHistory = expenseHistory,
            appExpenseCurrentPeriod = expenseCurrentPeriod,
            appIncomeHistory = incomeHistory,
            appIncomeCurrentPeriod = incomeCurrentPeriod,
            backupExpenseHistory = backupExpenseHistory,
            backupIncomeHistory = backupIncomeHistory
        )
    }

    private fun summarizeTransactions(
        transactions: List<TransactionWithDetails>,
        startInstant: Instant,
        endInstant: Instant,
        type: TransactionType,
        targetCurrency: String
    ): List<CategoryHistoryPayload> {
        val totals = linkedMapOf<String, BigDecimal>()
        val names = mutableMapOf<String, String>()
        val ids = mutableMapOf<String, String?>()

        transactions.filter { tx ->
            tx.transaction.type == type &&
                tx.transaction.date >= startInstant &&
                tx.transaction.date <= endInstant
        }.forEach { tx ->
            val monthKey = monthKeyFromInstant(tx.transaction.date)
            val categoryName = tx.category?.name ?: "未分類"
            val categoryId = tx.category?.id?.toString()
            val key = "$monthKey|${categoryId ?: categoryName}"
            val normalizedAmount = currencyService.convert(tx.transaction.amount.abs(), tx.transaction.currencyCode, targetCurrency)
            totals[key] = totals.getOrDefault(key, BigDecimal.ZERO).add(normalizedAmount)
            names[key] = categoryName
            ids[key] = categoryId
        }

        return totals.entries.map { (key, total) ->
            val monthKey = key.substringBefore("|")
            CategoryHistoryPayload(
                categoryId = ids[key],
                categoryName = names[key] ?: "未分類",
                monthKey = monthKey,
                total = total
            )
        }
    }

    private fun summarizeCurrentPeriod(
        transactions: List<TransactionWithDetails>,
        startInstant: Instant,
        endInstant: Instant,
        type: TransactionType,
        targetCurrency: String
    ): List<CategoryCurrentPayload> {
        val totals = linkedMapOf<String, BigDecimal>()
        val names = mutableMapOf<String, String>()
        val ids = mutableMapOf<String, String?>()

        transactions.filter { tx ->
            tx.transaction.type == type &&
                tx.transaction.date >= startInstant &&
                tx.transaction.date <= endInstant
        }.forEach { tx ->
            val categoryName = tx.category?.name ?: "未分類"
            val categoryId = tx.category?.id?.toString()
            val key = categoryId ?: categoryName
            val normalizedAmount = currencyService.convert(tx.transaction.amount.abs(), tx.transaction.currencyCode, targetCurrency)
            totals[key] = totals.getOrDefault(key, BigDecimal.ZERO).add(normalizedAmount)
            names[key] = categoryName
            ids[key] = categoryId
        }

        return totals.entries.map { (key, total) ->
            CategoryCurrentPayload(
                categoryId = ids[key],
                categoryName = names[key] ?: "未分類",
                total = total
            )
        }
    }

    private fun summarizeBackupTransactions(
        backupData: FullBackupData,
        startInstant: Instant,
        endInstant: Instant,
        transactionTypeRawValue: String,
        targetCurrency: String
    ): List<CategoryHistoryPayload> {
        val categoryNames = backupData.categories.associate { it.id to it.name }
        val totals = linkedMapOf<String, BigDecimal>()
        val names = mutableMapOf<String, String>()

        backupData.transactions.filter { tx ->
            tx.type == transactionTypeRawValue &&
                tx.date >= startInstant &&
                tx.date <= endInstant
        }.forEach { tx ->
            val categoryName = tx.categoryID?.let(categoryNames::get) ?: "未分類"
            val monthKey = monthKeyFromInstant(tx.date)
            val key = "$monthKey|$categoryName"
            val normalizedAmount = if (tx.currencyCode.equals(targetCurrency, ignoreCase = true)) {
                tx.amount.abs()
            } else {
                tx.amount.abs()
            }
            totals[key] = totals.getOrDefault(key, BigDecimal.ZERO).add(normalizedAmount)
            names[key] = categoryName
        }

        return totals.entries.map { (key, total) ->
            CategoryHistoryPayload(
                categoryId = null,
                categoryName = names[key] ?: "未分類",
                monthKey = key.substringBefore("|"),
                total = total
            )
        }
    }

    private fun hasMeaningfulSignal(payload: BudgetSuggestionPayload): Boolean {
        return payload.appExpenseHistory.isNotEmpty() ||
            payload.appExpenseCurrentPeriod.isNotEmpty() ||
            !payload.backupExpenseHistory.isNullOrEmpty()
    }

    private fun buildPrompt(payloadJson: String): String {
        return """
            You are an AI assistant for a personal finance app.
            Based on the summarized finance data below, suggest practical monthly budgets for the target month.

            Requirements:
            1. ONLY suggest budgets for the provided targetCategories.
            2. Income data, if present, is supporting context only. Do NOT return income categories.
            3. Use the provided mainCurrency for every suggestedAmount.
            4. Be conservative and realistic. Avoid abrupt increases unless the history clearly supports it.
            5. Keep each reason concise and in Traditional Chinese.
            6. Return strict JSON only, no Markdown.

            Output format:
            {
              "suggestions": [
                {
                  "categoryId": "UUID",
                  "suggestedAmount": 1234.56,
                  "currencyCode": "HKD",
                  "reason": "根據近月支出與本月進度的簡短原因"
                }
              ]
            }

            Finance summary:
            $payloadJson
        """.trimIndent()
    }

    private fun monthKeyFromInstant(instant: Instant): String {
        return monthKeyFromDate(instant.atZone(ZoneId.systemDefault()).toLocalDate())
    }

    private fun monthKeyFromDate(date: LocalDate): String {
        return "%04d-%02d".format(date.year, date.monthValue)
    }

    private data class TargetCategoryPayload(
        val categoryId: String,
        val name: String
    )

    private data class ExistingBudgetPayload(
        val categoryId: String,
        val categoryName: String,
        val amount: BigDecimal,
        val currencyCode: String
    )

    private data class CategoryHistoryPayload(
        val categoryId: String?,
        val categoryName: String,
        val monthKey: String,
        val total: BigDecimal
    )

    private data class CategoryCurrentPayload(
        val categoryId: String?,
        val categoryName: String,
        val total: BigDecimal
    )

    private data class BudgetSuggestionPayload(
        val analysisStartDate: String,
        val analysisEndDate: String,
        val targetMonthKey: String,
        val mainCurrency: String,
        val targetCategories: List<TargetCategoryPayload>,
        val existingBudgets: List<ExistingBudgetPayload>,
        val appExpenseHistory: List<CategoryHistoryPayload>,
        val appExpenseCurrentPeriod: List<CategoryCurrentPayload>,
        val appIncomeHistory: List<CategoryHistoryPayload>?,
        val appIncomeCurrentPeriod: List<CategoryCurrentPayload>?,
        val backupExpenseHistory: List<CategoryHistoryPayload>?,
        val backupIncomeHistory: List<CategoryHistoryPayload>?
    )

    private data class SuggestionEnvelope(
        val suggestions: List<BudgetSuggestionItem> = emptyList()
    )

    private data class GenerateContentResponse(
        val candidates: List<Candidate>?
    )

    private data class Candidate(
        val content: Content?
    )

    private data class Content(
        val parts: List<Part>?
    )

    private data class Part(
        val text: String?
    )
}
