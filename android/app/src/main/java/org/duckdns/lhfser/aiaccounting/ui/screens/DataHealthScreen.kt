package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import androidx.compose.foundation.BorderStroke

@Composable
fun DataHealthScreen() {
    val repository = LocalRepository.current
    val transactions by repository.transactions.collectAsState(initial = emptyList())
    val categories by repository.categories.collectAsState(initial = emptyList())
    val scrollState = rememberScrollState()

    var report by remember { mutableStateOf<String?>(null) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .verticalScroll(scrollState),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("資料健康檢查", style = MaterialTheme.typography.titleMedium)
        Card(
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
            border = BorderStroke(0.6.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.5f)),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("可快速檢查缺失資料與未使用分類", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Button(onClick = {
                    val missingAccount = transactions.count { it.transaction.accountId == null }
                    val missingCategory = transactions.count { it.transaction.categoryId == null }
                    val orphanCategory = categories.count { cat -> transactions.none { it.category?.id == cat.id } }
                    report = buildString {
                        appendLine("缺少帳戶交易：$missingAccount")
                        appendLine("缺少分類交易：$missingCategory")
                        appendLine("未被使用的分類：$orphanCategory")
                    }
                }) {
                    Text("開始檢查")
                }
                if (report != null) {
                    Text(report ?: "", style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }
}
