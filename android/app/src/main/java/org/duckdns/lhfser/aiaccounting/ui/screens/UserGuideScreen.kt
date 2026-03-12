package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun UserGuideScreen(onDone: () -> Unit) {
    val scrollState = rememberScrollState()
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .verticalScroll(scrollState),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text("歡迎使用 AI 記帳", style = MaterialTheme.typography.titleLarge)
        Text("1. 先新增帳戶與分類。")
        Text("2. 用「記一筆」新增收入/支出。")
        Text("3. 轉帳與代墊可從右下角新增。")
        Text("4. 報表可點擊分類查看明細。")
        Spacer(modifier = Modifier.height(8.dp))
        Button(onClick = onDone) { Text("開始使用") }
    }
}
