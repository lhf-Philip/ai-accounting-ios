package org.duckdns.lhfser.aiaccounting.core.ai

import android.content.Context

class GeminiSettingsStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)

    var apiKey: String
        get() = prefs.getString(KEY_API_KEY, "")?.trim().orEmpty()
        set(value) {
            prefs.edit().putString(KEY_API_KEY, value.trim()).apply()
        }

    companion object {
        private const val PREF_NAME = "gemini_settings"
        private const val KEY_API_KEY = "api_key"
    }
}
