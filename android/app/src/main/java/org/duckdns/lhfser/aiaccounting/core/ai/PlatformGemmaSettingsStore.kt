package org.duckdns.lhfser.aiaccounting.core.ai

import android.content.Context
import org.duckdns.lhfser.aiaccounting.core.security.KeystoreStringCipher
import java.util.UUID

enum class ReceiptAiProvider(val label: String) {
    GeminiByok("自備 Gemini API Key"),
    PlatformGemma("受邀 Gemma")
}

class PlatformGemmaSettingsStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
    private val cipher = KeystoreStringCipher("ai_accounting_platform_gemma")

    var baseUrl: String
        get() = prefs.getString(KEY_BASE_URL, "")?.trim().orEmpty()
        set(value) { prefs.edit().putString(KEY_BASE_URL, value.trim()).apply() }

    var provider: ReceiptAiProvider
        get() = runCatching { ReceiptAiProvider.valueOf(prefs.getString(KEY_PROVIDER, "") ?: "") }
            .getOrDefault(ReceiptAiProvider.GeminiByok)
        set(value) { prefs.edit().putString(KEY_PROVIDER, value.name).apply() }

    val installationId: String
        get() = secret(KEY_INSTALLATION_ID) ?: UUID.randomUUID().toString().also { setSecret(KEY_INSTALLATION_ID, it) }

    val deviceId: String? get() = secret(KEY_DEVICE_ID)
    val credential: String? get() = secret(KEY_CREDENTIAL)
    val registeredBaseUrl: String? get() = secret(KEY_REGISTERED_BASE_URL)
    val isRegistered: Boolean get() = deviceId != null && credential != null && registeredBaseUrl != null

    fun saveRegistration(deviceId: String, credential: String) {
        setSecret(KEY_DEVICE_ID, deviceId)
        setSecret(KEY_CREDENTIAL, credential)
        setSecret(KEY_REGISTERED_BASE_URL, baseUrl)
    }

    private fun secret(key: String): String? {
        val encrypted = prefs.getString(key, null) ?: return null
        return cipher.decrypt(encrypted).trim().takeIf { it.isNotEmpty() }
    }

    private fun setSecret(key: String, value: String) {
        prefs.edit().putString(key, cipher.encrypt(value.trim())).apply()
    }

    companion object {
        private const val PREF_NAME = "platform_gemma_settings"
        private const val KEY_BASE_URL = "base_url"
        private const val KEY_PROVIDER = "receipt_provider"
        private const val KEY_INSTALLATION_ID = "installation_id"
        private const val KEY_DEVICE_ID = "device_id"
        private const val KEY_CREDENTIAL = "credential"
        private const val KEY_REGISTERED_BASE_URL = "registered_base_url"
    }
}
