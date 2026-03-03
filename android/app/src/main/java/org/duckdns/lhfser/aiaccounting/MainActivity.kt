package org.duckdns.lhfser.aiaccounting

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import org.duckdns.lhfser.aiaccounting.ui.theme.AIAccountingTheme

private enum class AppTab(val titleRes: Int, val glyph: String) {
    Overview(R.string.tab_overview, "O"),
    Transactions(R.string.tab_transactions, "T"),
    Reports(R.string.tab_reports, "R"),
    Settings(R.string.tab_settings, "S")
}

class MainActivity : ComponentActivity() {

    private val prefs by lazy {
        getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val isFirstLaunch = consumeIsFirstLaunch()

        setContent {
            AIAccountingTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    AIAccountingApp(
                        initialTab = if (isFirstLaunch) AppTab.Overview else AppTab.Transactions
                    )
                }
            }
        }
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
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AIAccountingApp(initialTab: AppTab) {
    var selectedTab by rememberSaveable { mutableStateOf(initialTab) }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text(text = stringResource(id = selectedTab.titleRes)) }
            )
        },
        bottomBar = {
            NavigationBar {
                AppTab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = selectedTab == tab,
                        onClick = { selectedTab = tab },
                        icon = { Text(text = tab.glyph) },
                        label = { Text(text = stringResource(id = tab.titleRes)) }
                    )
                }
            }
        }
    ) { contentPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(contentPadding)
        ) {
            when (selectedTab) {
                AppTab.Overview -> PlaceholderPanel(
                    title = stringResource(id = R.string.overview_placeholder_title),
                    body = stringResource(id = R.string.overview_placeholder_body)
                )

                AppTab.Transactions -> PlaceholderPanel(
                    title = stringResource(id = R.string.transactions_placeholder_title),
                    body = stringResource(id = R.string.transactions_placeholder_body),
                    contentPadding = PaddingValues(horizontal = 24.dp, vertical = 20.dp)
                )

                AppTab.Reports -> PlaceholderPanel(
                    title = stringResource(id = R.string.reports_placeholder_title),
                    body = stringResource(id = R.string.reports_placeholder_body)
                )

                AppTab.Settings -> PlaceholderPanel(
                    title = stringResource(id = R.string.settings_placeholder_title),
                    body = stringResource(id = R.string.settings_placeholder_body)
                )
            }
        }
    }
}

@Composable
private fun PlaceholderPanel(
    title: String,
    body: String,
    contentPadding: PaddingValues = PaddingValues(horizontal = 24.dp, vertical = 32.dp)
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(contentPadding),
        horizontalAlignment = Alignment.Start,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(text = title)
        Text(text = body, textAlign = TextAlign.Start)
    }
}
