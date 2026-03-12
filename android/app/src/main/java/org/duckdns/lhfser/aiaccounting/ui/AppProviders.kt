package org.duckdns.lhfser.aiaccounting.ui

import androidx.compose.runtime.staticCompositionLocalOf
import org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository

val LocalRepository = staticCompositionLocalOf<AccountingRepository> {
    error("AccountingRepository not provided")
}
