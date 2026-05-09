package org.duckdns.lhfser.aiaccounting.core.backup

import android.content.Context
import android.util.Base64
import com.google.gson.annotations.SerializedName
import java.security.SecureRandom
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import javax.crypto.Cipher
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
import org.duckdns.lhfser.aiaccounting.core.security.KeystoreStringCipher
import org.duckdns.lhfser.aiaccounting.data.backup.BackupJsonAdapter
import org.duckdns.lhfser.aiaccounting.data.backup.FullBackupData

data class WebDavCredentials(
    val baseUrl: String,
    val username: String,
    val password: String,
    val passphrase: String
) {
    val isConnectionComplete: Boolean
        get() = baseUrl.isNotBlank() && username.isNotBlank() && password.isNotBlank()

    val hasPassphrase: Boolean
        get() = passphrase.isNotBlank()
}

enum class RemoteBackupFormat(val label: String) {
    ENCRYPTED("已加密"),
    PLAIN_JSON("未加密"),
    UNKNOWN("未知格式")
}

data class RemoteBackupFile(
    val name: String,
    val url: String,
    val format: RemoteBackupFormat
) {
    val isEncrypted: Boolean
        get() = format == RemoteBackupFormat.ENCRYPTED
}

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
    private val plainBackupExtension = "json"

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

    suspend fun uploadBackup(json: String, credentials: WebDavCredentials, encryptBackup: Boolean): RemoteBackupFile = withContext(Dispatchers.IO) {
        if (encryptBackup) {
            require(credentials.hasPassphrase) { "此操作需要加密 passphrase" }
        }
        val payload = if (encryptBackup) encrypt(json.toByteArray(Charsets.UTF_8), credentials.passphrase) else json.toByteArray(Charsets.UTF_8)
        val extension = if (encryptBackup) backupExtension else plainBackupExtension
        val name = "AIAccounting_Backup_${filenameFormatter.format(Instant.now())}.$extension"
        val target = credentials.baseUrl.trimEnd('/') + "/" + name
        val request = baseRequest(credentials, target)
            .put(payload.toRequestBody(jsonMediaType))
            .build()
        client.newCall(request).execute().use { response ->
            require(response.code in setOf(200, 201, 204)) { "WebDAV HTTP ${response.code}" }
        }
        RemoteBackupFile(
            name = name,
            url = target,
            format = if (encryptBackup) RemoteBackupFormat.ENCRYPTED else RemoteBackupFormat.PLAIN_JSON
        )
    }

    suspend fun downloadBackup(file: RemoteBackupFile, credentials: WebDavCredentials): String = withContext(Dispatchers.IO) {
        val request = baseRequest(credentials, file.url).get().build()
        client.newCall(request).execute().use { response ->
            require(response.code == 200) { "WebDAV HTTP ${response.code}" }
            val data = response.body?.bytes() ?: error("遠端備份內容為空")
            when (detectFormat(file, data)) {
                RemoteBackupFormat.ENCRYPTED -> {
                    require(credentials.hasPassphrase) { "此操作需要加密 passphrase" }
                    decrypt(data, credentials.passphrase).toString(Charsets.UTF_8)
                }
                RemoteBackupFormat.PLAIN_JSON -> data.toString(Charsets.UTF_8)
                RemoteBackupFormat.UNKNOWN -> error("遠端備份格式不支援")
            }
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
                val format = formatFromName(decodedName)
                if (format == RemoteBackupFormat.UNKNOWN) return@mapNotNull null
                RemoteBackupFile(
                    name = decodedName,
                    url = baseUrl.trimEnd('/') + "/" + decodedName,
                    format = format
                )
            }
            .distinctBy { it.name }
            .sortedByDescending { it.name }
            .toList()
    }

    private fun detectFormat(file: RemoteBackupFile, data: ByteArray): RemoteBackupFormat {
        if (file.format != RemoteBackupFormat.UNKNOWN) return file.format
        val text = data.toString(Charsets.UTF_8)
        return when {
            runCatching { BackupJsonAdapter.gson.fromJson(text, EncryptedBackupEnvelope::class.java) }.getOrNull()?.algorithm == "AES.GCM.PBKDF2.HMACSHA256" -> RemoteBackupFormat.ENCRYPTED
            runCatching { BackupJsonAdapter.gson.fromJson(text, FullBackupData::class.java) }.isSuccess -> RemoteBackupFormat.PLAIN_JSON
            else -> RemoteBackupFormat.UNKNOWN
        }
    }

    private fun formatFromName(name: String): RemoteBackupFormat {
        return when {
            name.endsWith(".$backupExtension") -> RemoteBackupFormat.ENCRYPTED
            name.startsWith("AIAccounting_Backup_") && name.endsWith(".$plainBackupExtension") -> RemoteBackupFormat.PLAIN_JSON
            else -> RemoteBackupFormat.UNKNOWN
        }
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
    private val cipher = KeystoreStringCipher("ai_accounting_webdav_settings")

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

    var encryptRemoteBackups: Boolean
        get() = prefs.getBoolean("encrypt_remote_backups", true)
        set(value) { prefs.edit().putBoolean("encrypt_remote_backups", value).apply() }

    var didConfirmPlainWebDavBackup: Boolean
        get() = prefs.getBoolean("did_confirm_plain_webdav_backup", false)
        set(value) { prefs.edit().putBoolean("did_confirm_plain_webdav_backup", value).apply() }

    fun credentials(): WebDavCredentials {
        return WebDavCredentials(baseUrl = baseUrl, username = username, password = password, passphrase = passphrase)
    }
}
