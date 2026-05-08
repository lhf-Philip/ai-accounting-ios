package org.duckdns.lhfser.aiaccounting.core.preferences

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class UiPreferences(
    val pinOverviewControls: Boolean = true,
    val pinLedgerControls: Boolean = true,
    val pinReportsControls: Boolean = true
)

class UiPreferencesStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
    private val _state = MutableStateFlow(read())
    val state: StateFlow<UiPreferences> = _state.asStateFlow()

    private val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key != null && key in preferenceKeys) {
            _state.value = read()
        }
    }

    init {
        prefs.registerOnSharedPreferenceChangeListener(listener)
    }

    fun setPinOverviewControls(value: Boolean) {
        prefs.edit().putBoolean(KEY_PIN_OVERVIEW_CONTROLS, value).apply()
        _state.value = read()
    }

    fun setPinLedgerControls(value: Boolean) {
        prefs.edit().putBoolean(KEY_PIN_LEDGER_CONTROLS, value).apply()
        _state.value = read()
    }

    fun setPinReportsControls(value: Boolean) {
        prefs.edit().putBoolean(KEY_PIN_REPORTS_CONTROLS, value).apply()
        _state.value = read()
    }

    private fun read(): UiPreferences {
        return UiPreferences(
            pinOverviewControls = prefs.getBoolean(KEY_PIN_OVERVIEW_CONTROLS, true),
            pinLedgerControls = prefs.getBoolean(KEY_PIN_LEDGER_CONTROLS, true),
            pinReportsControls = prefs.getBoolean(KEY_PIN_REPORTS_CONTROLS, true)
        )
    }

    private companion object {
        const val PREF_NAME = "ui_preferences"
        const val KEY_PIN_OVERVIEW_CONTROLS = "pinOverviewControls"
        const val KEY_PIN_LEDGER_CONTROLS = "pinLedgerControls"
        const val KEY_PIN_REPORTS_CONTROLS = "pinReportsControls"
        val preferenceKeys = setOf(
            KEY_PIN_OVERVIEW_CONTROLS,
            KEY_PIN_LEDGER_CONTROLS,
            KEY_PIN_REPORTS_CONTROLS
        )
    }
}
