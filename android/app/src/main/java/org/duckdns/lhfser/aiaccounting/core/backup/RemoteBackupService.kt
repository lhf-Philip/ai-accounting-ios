package org.duckdns.lhfser.aiaccounting.core.backup

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.google.gson.annotations.SerializedName
import java.security.KeyStore
import java.security.SecureRandom
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Credentials
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.duckdns.lhfser.aiaccounting.data.backup.BackupJsonAdapter
import org.duckdns.lhfser.aiaccounting.data.backup.FullBackupData

data class WebDavCredentials(
    val baseUrl: String,
    val username: String,
    val password: String,
    val passphrase: String
) {
    val isComplete: Boolean
        get() = baseUrl.isNotBlank() && username.isNotBlank() && password.isNotBlank() && passphrase.isNotBlank()
}

data class RemoteBackupFile(
    val name: String,
    val url: String
)

data class RemoteBackupPreview(
    val title: String,
    val detail: String
)

private data class EncryptedBackupEnvelope(
    val formatVersion: Int,
    val algorithm: String,
    val createdAt: Instant,
    val salt: String,
    val iv: String,
    val ciphertext: String,
    @SerializedName("tagBits") val tagBits: Int = 128
)

class RemoteBackupService(
    private val client: OkHttpClient = OkHttpClient()
) {
    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()
    private val xmlMediaType = "application/xml; charset=utf-8".toMediaType()
    private val backupExtension = "aibackup"

    suspend fun testConnection(credentials: WebDavCredentials) = withContext(Dispatchers.IO) {
        val request = baseRequest(credentials, credentials.baseUrl)
            .method("PROPFIND", propfindBody().toRequestBody(xmlMediaType))
            .header("Depth", "0")
            .build()
        client.newCall(request).execute().use { response ->
            require(response.code in setOf(200, 207)) { "WebDAV HTTP ${response.code}" }
        }
    }

    suspend fun listBackups(credentials: WebDavCredentials): List<RemoteBackupFile> = withContext(Dispatchers.IO) {
        val request = baseRequest(credentials, credentials.baseUrl)
            .method("PROPFIND", propfindBody().toRequestBody(xmlMediaType))
            .header("Depth", "1")
            .build()
        client.newCall(request).execute().use { response ->
            require(response.code in setOf(200, 207)) { "WebDAV HTTP ${response.code}" }
            val body = response.body?.string().orEmpty()
            parseBackupFiles(body, credentials.baseUrl)
        }
    }

    suspend fun uploadBackup(json: String, credentials: WebDavCredentials): RemoteBackupFile = withContext(Dispatchers.IO) {
        val encrypted = encrypt(json.toByteArray(Charsets.UTF_8), credentials.passphrase)
        val name = "AIAccounting_Backup_${filenameFormatter.format(Instant.now())}.$backupExtension"
        val target = credentials.baseUrl.trimEnd('/') + "/" + name
        val request = baseRequest(credentials, target)
            .put(encrypted.toRequestBody(jsonMediaType))
            .build()
        client.newCall(request).execute().use { response ->
            require(response.code in setOf(200, 201, 204)) { "WebDAV HTTP ${response.code}" }
        }
        RemoteBackupFile(name = name, url = target)
    }

    suspend fun downloadBackup(file: RemoteBackupFile, credentials: WebDavCredentials): String = withContext(Dispatchers.IO) {
        val request = baseRequest(credentials, file.url).get().build()
        client.newCall(request).execute().use { response ->
            require(response.code == 200) { "WebDAV HTTP ${response.code}" }
            val encrypted = response.body?.bytes() ?: error("遠端備份內容為空")
            decrypt(encrypted, credentials.passphrase).toString(Charsets.UTF_8)
        }
    }

    fun makePreview(backup: FullBackupData): RemoteBackupPreview {
        val dates = backup.transactions.map { it.date }
        val range = if (dates.isEmpty()) {
            "沒有交易日期"
        } else {
            "${dateFormatter.format(dates.minOrNull()!!)} - ${dateFormatter.format(dates.maxOrNull()!!)}"
        }
        return RemoteBackupPreview(
            title = "遠端備份預覽",
            detail = """
                版本：${backup.version}
                建立時間：${dateTimeFormatter.format(backup.timestamp)}
                帳戶：${backup.accounts.size}
                交易：${backup.transactions.size}
                分類：${backup.categories.size}
                標籤：${backup.tags.size}
                代墊案件：${backup.advanceCases?.size ?: 0}
                預算：${backup.budgets?.size ?: 0}
                日期範圍：$range
            """.trimIndent()
        )
    }

    fun decodeBackup(json: String): FullBackupData {
        return BackupJsonAdapter.gson.fromJson(json, FullBackupData::class.java)
    }

    private fun baseRequest(credentials: WebDavCredentials, url: String): Request.Builder {
        return Request.Builder()
            .url(url)
            .header("Authorization", Credentials.basic(credentials.username, credentials.password))
    }

    private fun propfindBody(): String {
        return """
            <?xml version="1.0" encoding="utf-8" ?>
            <propfind xmlns="DAV:">
              <prop>
                <getlastmodified />
                <getcontentlength />
              </prop>
            </propfind>
        """.trimIndent()
    }

    private fun parseBackupFiles(xml: String, baseUrl: String): List<RemoteBackupFile> {
        val regex = Regex("<[^>]*href[^>]*>(.*?)</[^>]*href>", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
        return regex.findAll(xml)
            .mapNotNull { match ->
                val href = match.groupValues.getOrNull(1).orEmpty()
                    .replace("&amp;", "&")
                val name = href.substringAfterLast('/').ifBlank { return@mapNotNull null }
                val decodedName = java.net.URLDecoder.decode(name, Charsets.UTF_8.name())
                if (!decodedName.endsWith(".$backupExtension")) return@mapNotNull null
                RemoteBackupFile(
                    name = decodedName,
                    url = baseUrl.trimEnd('/') + "/" + decodedName
                )
            }
            .distinctBy { it.name }
            .sortedByDescending { it.name }
            .toList()
    }

    private fun encrypt(data: ByteArray, passphrase: String): ByteArray {
        val salt = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val iv = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val key = deriveKey(passphrase, salt)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, iv))
        val ciphertext = cipher.doFinal(data)
        val envelope = EncryptedBackupEnvelope(
            formatVersion = 1,
            algorithm = "AES.GCM.PBKDF2.HMACSHA256",
            createdAt = Instant.now(),
            salt = base64(salt),
            iv = base64(iv),
            ciphertext = base64(ciphertext)
        )
        return BackupJsonAdapter.gson.toJson(envelope).toByteArray(Charsets.UTF_8)
    }

    private fun decrypt(envelopeBytes: ByteArray, passphrase: String): ByteArray {
        val envelope = BackupJsonAdapter.gson.fromJson(
            envelopeBytes.toString(Charsets.UTF_8),
            EncryptedBackupEnvelope::class.java
        )
        require(envelope.formatVersion == 1) { "遠端備份格式版本不支援" }
        require(envelope.algorithm == "AES.GCM.PBKDF2.HMACSHA256") { "遠端備份加密格式不支援" }
        val key = deriveKey(passphrase, unbase64(envelope.salt))
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(envelope.tagBits, unbase64(envelope.iv)))
        return cipher.doFinal(unbase64(envelope.ciphertext))
    }

    private fun deriveKey(passphrase: String, salt: ByteArray): SecretKeySpec {
        val spec = PBEKeySpec(passphrase.toCharArray(), salt, 120_000, 256)
        val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        return SecretKeySpec(factory.generateSecret(spec).encoded, "AES")
    }

    private fun base64(bytes: ByteArray): String = Base64.encodeToString(bytes, Base64.NO_WRAP)
    private fun unbase64(value: String): ByteArray = Base64.decode(value, Base64.NO_WRAP)

    companion object {
        private val filenameFormatter = DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss").withZone(ZoneId.systemDefault())
        private val dateFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd").withZone(ZoneId.systemDefault())
        private val dateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm").withZone(ZoneId.systemDefault())
    }
}

class WebDavSettingsStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("webdav_backup_settings", Context.MODE_PRIVATE)
    private val cipher = KeystoreStringCipher()

    var baseUrl: String
        get() = prefs.getString("base_url", "").orEmpty()
        set(value) { prefs.edit().putString("base_url", value.trim()).apply() }

    var username: String
        get() = prefs.getString("username", "").orEmpty()
        set(value) { prefs.edit().putString("username", value.trim()).apply() }

    var password: String
        get() = prefs.getString("password", null)?.let(cipher::decrypt).orEmpty()
        set(value) { prefs.edit().putString("password", cipher.encrypt(value.trim())).apply() }

    var passphrase: String
        get() = prefs.getString("passphrase", null)?.let(cipher::decrypt).orEmpty()
        set(value) { prefs.edit().putString("passphrase", cipher.encrypt(value.trim())).apply() }

    fun credentials(): WebDavCredentials {
        return WebDavCredentials(baseUrl = baseUrl, username = username, password = password, passphrase = passphrase)
    }
}

private class KeystoreStringCipher {
    private val alias = "ai_accounting_webdav_settings"

    fun encrypt(value: String): String {
        if (value.isBlank()) return ""
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val ciphertext = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        return "${base64(cipher.iv)}:${base64(ciphertext)}"
    }

    fun decrypt(value: String): String {
        if (value.isBlank() || !value.contains(":")) return ""
        return runCatching {
            val parts = value.split(":", limit = 2)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, unbase64(parts[0])))
            cipher.doFinal(unbase64(parts[1])).toString(Charsets.UTF_8)
        }.getOrDefault("")
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(alias, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val spec = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }

    private fun base64(bytes: ByteArray): String = Base64.encodeToString(bytes, Base64.NO_WRAP)
    private fun unbase64(value: String): ByteArray = Base64.decode(value, Base64.NO_WRAP)
}
