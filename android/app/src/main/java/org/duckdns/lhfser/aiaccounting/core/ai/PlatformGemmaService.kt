package org.duckdns.lhfser.aiaccounting.core.ai

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import com.google.gson.Gson
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class PlatformGemmaService(private val settings: PlatformGemmaSettingsStore) {
    private val gson = Gson()

    suspend fun register(invitationCode: String) = withContext(Dispatchers.IO) {
        val installationId = settings.installationId
        registerAgainstStableBaseUrl(
            rawBaseUrl = settings.baseUrl,
            register = { registeredBaseUrl ->
                post(
                    baseUrl = registeredBaseUrl,
                    path = "v1/devices/register",
                    body = mapOf(
                        "inviteCode" to invitationCode.trim(),
                        "installationId" to installationId,
                        "platform" to "android"
                    ),
                    authenticated = false,
                    responseType = RegistrationResponse::class.java
                )
            },
            saveRegistration = { response, registeredBaseUrl ->
                settings.saveRegistration(response.deviceId, response.credential, registeredBaseUrl)
            }
        )
    }

    suspend fun analyzeReceipt(
        imageBytes: ByteArray,
        userNote: String,
        categoryCandidates: List<String>
    ): ReceiptInfo = withContext(Dispatchers.IO) {
        val jpeg = receiptJpeg(imageBytes)
        val response = post(
            baseUrl = canonicalizePlatformGemmaBaseUrl(settings.registeredBaseUrl.orEmpty()),
            path = "v1/receipts/analyze",
            body = mapOf(
                "requestId" to UUID.randomUUID().toString(),
                "imageBase64" to Base64.encodeToString(jpeg, Base64.NO_WRAP),
                "mimeType" to "image/jpeg",
                "userNote" to userNote,
                "categories" to categoryCandidates
            ),
            authenticated = true,
            responseType = AnalyzeResponse::class.java
        )
        response.receipt
    }

    private fun <T> post(baseUrl: String, path: String, body: Any, authenticated: Boolean, responseType: Class<T>): T {
        val connection = URL("$baseUrl/$path").openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            connection.setRequestProperty("Cache-Control", "no-store")
            if (authenticated) {
                val deviceId = settings.deviceId ?: throw IllegalStateException("此設備尚未使用邀請碼登記。")
                val credential = settings.credential ?: throw IllegalStateException("此設備尚未使用邀請碼登記。")
                connection.setRequestProperty("Authorization", "Bearer $deviceId.$credential")
                connection.setRequestProperty("X-Installation-ID", settings.installationId)
            }
            connection.connectTimeout = 20_000
            connection.readTimeout = 75_000
            connection.useCaches = false
            connection.doOutput = true
            connection.outputStream.use { output ->
                output.write(gson.toJson(body).toByteArray(StandardCharsets.UTF_8))
            }
            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (code !in 200..299) {
                val message = runCatching { gson.fromJson(text, ErrorEnvelope::class.java).error.message }.getOrNull()
                throw IOException(message ?: "Gemma 服務失敗（$code）。")
            }
            gson.fromJson(text, responseType) ?: throw IOException("Gemma 服務回傳格式錯誤。")
        } finally {
            connection.disconnect()
        }
    }

    private fun receiptJpeg(bytes: ByteArray): ByteArray {
        val source = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            ?: throw IllegalArgumentException("無法讀取單據圖片。")
        val largest = maxOf(source.width, source.height)
        val resized = if (largest > 1024) {
            val scale = 1024f / largest
            Bitmap.createScaledBitmap(source, (source.width * scale).toInt(), (source.height * scale).toInt(), true)
        } else source
        return ByteArrayOutputStream().use { output ->
            check(resized.compress(Bitmap.CompressFormat.JPEG, 82, output)) { "無法壓縮單據圖片。" }
            if (resized !== source) resized.recycle()
            source.recycle()
            output.toByteArray()
        }
    }
}

private data class RegistrationResponse(val deviceId: String, val credential: String)
private data class AnalyzeResponse(val receipt: ReceiptInfo)
private data class ErrorEnvelope(val error: ServiceError)
private data class ServiceError(val code: String, val message: String)
