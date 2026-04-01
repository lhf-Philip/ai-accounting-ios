package org.duckdns.lhfser.aiaccounting.core.ai

import android.util.Base64
import com.google.gson.Gson
import java.io.IOException
import java.math.BigDecimal
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class ReceiptInfo(
    val amount: BigDecimal,
    val currency: String,
    val date: String,
    val time: String?,
    val merchant: String,
    val categoryName: String,
    val note: String
)

class ReceiptScanService(
    private val settingsStore: GeminiSettingsStore
) {
    private val gson = Gson()
    private val modelName = "gemini-flash-latest"

    suspend fun analyzeReceipt(
        imageBytes: ByteArray,
        userNote: String,
        categoryCandidates: List<String>
    ): ReceiptInfo = withContext(Dispatchers.IO) {
        val apiKey = settingsStore.apiKey
        require(apiKey.isNotBlank()) { "未設定 Gemini API Key。" }

        val categoryList = if (categoryCandidates.isEmpty()) "無可用分類，請回傳「未分類」" else categoryCandidates.joinToString(", ")
        val prompt = """
            You are an AI assistant for a personal finance app.
            Analyze the attached receipt image and the user's specific instruction: \"$userNote\".
            Available user categories (must prioritize from this list): $categoryList

            Task:
            1. Identify the Merchant Name. Translate to Traditional Chinese when possible.
            2. Identify the Date (format YYYY-MM-DD). If year is missing, assume the current year.
            3. Identify the Time (format HH:mm, 24-hour). If missing, return null.
            4. Calculate the Total Amount relevant to the user.
               - If the user note mentions splitting, only sum the user-relevant part.
               - Otherwise use the receipt grand total.
            5. Suggest a Category.
               - Prefer a close match from the provided category list.
               - If none fits, return \"未分類\".
            6. Detect the currency code (HKD, USD, TWD, JPY, CNY, EUR, GBP). Default to HKD if unknown.
            7. Summarize the purchase in Traditional Chinese.

            Output strict JSON only, without markdown fences, with this structure:
            {
              "amount": 100.5,
              "currency": "HKD",
              "date": "2026-04-01",
              "time": "13:45",
              "merchant": "麥當勞",
              "categoryName": "餐飲",
              "note": "午餐"
            }
        """.trimIndent()

        val requestBody = gson.toJson(
            mapOf(
                "contents" to listOf(
                    mapOf(
                        "parts" to listOf(
                            mapOf("text" to prompt),
                            mapOf(
                                "inlineData" to mapOf(
                                    "mimeType" to "image/jpeg",
                                    "data" to Base64.encodeToString(imageBytes, Base64.NO_WRAP)
                                )
                            )
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
            throw IllegalStateException("AI 未回傳可讀取的單據資料。")
        }

        return@withContext gson.fromJson(rawText, ReceiptInfo::class.java)
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
}

private data class GenerateContentResponse(
    val candidates: List<GenerateContentCandidate>?
)

private data class GenerateContentCandidate(
    val content: GenerateContentContent?
)

private data class GenerateContentContent(
    val parts: List<GenerateContentPart>?
)

private data class GenerateContentPart(
    val text: String?
)
