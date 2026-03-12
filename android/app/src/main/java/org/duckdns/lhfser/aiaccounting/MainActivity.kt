package org.duckdns.lhfser.aiaccounting

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.CompositionLocalProvider
import org.duckdns.lhfser.aiaccounting.ui.AIAccountingRoot
import org.duckdns.lhfser.aiaccounting.ui.LocalCurrencyService
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.theme.AIAccountingTheme
import org.duckdns.lhfser.aiaccounting.widget.SummaryWidgetProvider
import org.duckdns.lhfser.aiaccounting.widget.WidgetSummaryStore

class MainActivity : ComponentActivity() {

    private val prefs by lazy {
        getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val isFirstLaunch = consumeIsFirstLaunch()
        val hasSeenGuide = prefs.getBoolean(KEY_HAS_SEEN_GUIDE, false)
        syncWidgetPreviewContent(isFirstLaunch)
        val appContainer = (application as AIAccountingApp).container

        setContent {
            AIAccountingTheme {
                CompositionLocalProvider(
                    LocalRepository provides appContainer.repository,
                    LocalCurrencyService provides appContainer.currencyService
                ) {
                    AIAccountingRoot(
                        startOnOverview = isFirstLaunch,
                        showUserGuide = !hasSeenGuide,
                        onGuideSeen = {
                            prefs.edit().putBoolean(KEY_HAS_SEEN_GUIDE, true).apply()
                        }
                    )
                }
            }
        }
    }

    private fun syncWidgetPreviewContent(isFirstLaunch: Boolean) {
        val messageRes = if (isFirstLaunch) {
            R.string.widget_body_first_launch
        } else {
            R.string.widget_body_ready
        }
        WidgetSummaryStore.save(
            context = this,
            title = getString(R.string.widget_title),
            body = getString(messageRes)
        )
        SummaryWidgetProvider.refreshAll(this)
    }

    private fun consumeIsFirstLaunch(): Boolean {
        val isFirst = prefs.getBoolean(KEY_IS_FIRST_LAUNCH, true)
        if (isFirst) {
            prefs.edit().putBoolean(KEY_IS_FIRST_LAUNCH, false).apply()
        }
        return isFirst
    }

    private companion object {
        const val PREF_NAME = "ai_accounting_preferences"
        const val KEY_IS_FIRST_LAUNCH = "is_first_launch"
        const val KEY_HAS_SEEN_GUIDE = "has_seen_guide"
    }
}
