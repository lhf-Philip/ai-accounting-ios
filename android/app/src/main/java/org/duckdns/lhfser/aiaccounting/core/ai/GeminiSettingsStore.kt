package org.duckdns.lhfser.aiaccounting.core.ai

import android.content.Context
import org.duckdns.lhfser.aiaccounting.core.security.KeystoreStringCipher

class GeminiSettingsStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
    private val cipher = KeystoreStringCipher("ai_accounting_gemini_settings")

    var apiKey: String
        get() {
            val encrypted = prefs.getString(KEY_API_KEY_ENCRYPTED, null)
            if (!encrypted.isNullOrBlank()) return cipher.decrypt(encrypted).trim()

            val legacyPlaintext = prefs.getString(KEY_API_KEY, "")?.trim().orEmpty()
            if (legacyPlaintext.isNotBlank()) {
                apiKey = legacyPlaintext
            }
            return legacyPlaintext
        }
        set(value) {
            val trimmed = value.trim()
            prefs.edit().apply {
                remove(KEY_API_KEY)
                if (trimmed.isBlank()) {
                    remove(KEY_API_KEY_ENCRYPTED)
                } else {
                    putString(KEY_API_KEY_ENCRYPTED, cipher.encrypt(trimmed))
                }
            }.apply()
        }

    companion object {
        private const val PREF_NAME = "gemini_settings"
        private const val KEY_API_KEY = "api_key"
        private const val KEY_API_KEY_ENCRYPTED = "api_key_encrypted"
    }
}
