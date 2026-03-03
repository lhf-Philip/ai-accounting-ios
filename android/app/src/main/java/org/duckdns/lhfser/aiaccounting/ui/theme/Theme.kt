package org.duckdns.lhfser.aiaccounting.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = Color(0xFF006C4C),
    secondary = Color(0xFF3E6472),
    tertiary = Color(0xFF56643B)
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF6BDDAF),
    secondary = Color(0xFFA5CDDD),
    tertiary = Color(0xFFBBCD90)
)

@Composable
fun AIAccountingTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = LightColors,
        typography = MaterialTheme.typography,
        content = content
    )
}
