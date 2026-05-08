package org.duckdns.lhfser.aiaccounting.ui

import androidx.compose.runtime.staticCompositionLocalOf
import org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService
import org.duckdns.lhfser.aiaccounting.core.preferences.UiPreferencesStore
import org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository

val LocalRepository = staticCompositionLocalOf<AccountingRepository> {
    error("AccountingRepository not provided")
}

val LocalCurrencyService = staticCompositionLocalOf<CurrencyService> {
    error("CurrencyService not provided")
}

val LocalUiPreferences = staticCompositionLocalOf<UiPreferencesStore> {
    error("UiPreferencesStore not provided")
}
