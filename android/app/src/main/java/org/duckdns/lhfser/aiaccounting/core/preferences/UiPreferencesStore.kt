package org.duckdns.lhfser.aiaccounting.core.preferences

import android.content.Context
import android.content.SharedPreferences
import java.time.LocalDate
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class UiPreferences(
    val pinOverviewControls: Boolean = true,
    val pinLedgerControls: Boolean = true,
    val pinReportsControls: Boolean = true,
    val dateFilter: SharedDateFilterState = SharedDateFilterState()
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

    fun setDateFilterType(value: SharedDateFilterType) {
        prefs.edit().putString(KEY_DATE_FILTER_TYPE, value.name).apply()
        _state.value = read()
    }

    fun setDateFilterSelectedDate(value: LocalDate) {
        prefs.edit().putString(KEY_DATE_FILTER_SELECTED_DATE, value.toString()).apply()
        _state.value = read()
    }

    fun setDateFilterCustomStartDate(value: LocalDate) {
        prefs.edit().putString(KEY_DATE_FILTER_CUSTOM_START_DATE, value.toString()).apply()
        _state.value = read()
    }

    fun setDateFilterCustomEndDate(value: LocalDate) {
        prefs.edit().putString(KEY_DATE_FILTER_CUSTOM_END_DATE, value.toString()).apply()
        _state.value = read()
    }

    private fun read(): UiPreferences {
        return UiPreferences(
            pinOverviewControls = prefs.getBoolean(KEY_PIN_OVERVIEW_CONTROLS, true),
            pinLedgerControls = prefs.getBoolean(KEY_PIN_LEDGER_CONTROLS, true),
            pinReportsControls = prefs.getBoolean(KEY_PIN_REPORTS_CONTROLS, true),
            dateFilter = SharedDateFilterState(
                type = readDateFilterType(),
                selectedDate = readDate(KEY_DATE_FILTER_SELECTED_DATE),
                customStartDate = readDate(KEY_DATE_FILTER_CUSTOM_START_DATE),
                customEndDate = readDate(KEY_DATE_FILTER_CUSTOM_END_DATE)
            )
        )
    }

    private fun readDateFilterType(): SharedDateFilterType {
        val raw = prefs.getString(KEY_DATE_FILTER_TYPE, SharedDateFilterType.Month.name)
        return SharedDateFilterType.entries.firstOrNull { it.name == raw } ?: SharedDateFilterType.Month
    }

    private fun readDate(key: String): LocalDate {
        val raw = prefs.getString(key, null) ?: return LocalDate.now()
        return runCatching { LocalDate.parse(raw) }.getOrDefault(LocalDate.now())
    }

    private companion object {
        const val PREF_NAME = "ui_preferences"
        const val KEY_PIN_OVERVIEW_CONTROLS = "pinOverviewControls"
        const val KEY_PIN_LEDGER_CONTROLS = "pinLedgerControls"
        const val KEY_PIN_REPORTS_CONTROLS = "pinReportsControls"
        const val KEY_DATE_FILTER_TYPE = "dateFilterType"
        const val KEY_DATE_FILTER_SELECTED_DATE = "dateFilterSelectedDate"
        const val KEY_DATE_FILTER_CUSTOM_START_DATE = "dateFilterCustomStartDate"
        const val KEY_DATE_FILTER_CUSTOM_END_DATE = "dateFilterCustomEndDate"
        val preferenceKeys = setOf(
            KEY_PIN_OVERVIEW_CONTROLS,
            KEY_PIN_LEDGER_CONTROLS,
            KEY_PIN_REPORTS_CONTROLS,
            KEY_DATE_FILTER_TYPE,
            KEY_DATE_FILTER_SELECTED_DATE,
            KEY_DATE_FILTER_CUSTOM_START_DATE,
            KEY_DATE_FILTER_CUSTOM_END_DATE
        )
    }
}
