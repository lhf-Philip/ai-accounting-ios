package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.duckdns.lhfser.aiaccounting.core.health.DataHealthReport
import org.duckdns.lhfser.aiaccounting.core.health.HealthIssue
import org.duckdns.lhfser.aiaccounting.core.health.HealthSeverity
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing

@Composable
fun DataHealthScreen() {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()
    val scrollState = rememberScrollState()

    var report by remember { mutableStateOf<DataHealthReport?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var isRunning by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = AppSpacing.screenHorizontal, vertical = AppSpacing.screenVertical)
            .verticalScroll(scrollState),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Card(
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
            border = BorderStroke(0.6.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.5f)),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(
                modifier = Modifier.padding(AppSpacing.card),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(
                    text = "檢查交易、預算、代墊與轉帳連結是否一致，特別是代墊雙向與還款方向。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Button(
                    onClick = {
                        scope.launch {
                            isRunning = true
                            errorMessage = null
                            try {
                                report = repository.buildDataHealthReport()
                            } catch (error: Exception) {
                                errorMessage = error.message ?: "資料健康檢查失敗。"
                            } finally {
                                isRunning = false
                            }
                        }
                    }
                ) {
                    Text(if (isRunning) "檢查中..." else "開始檢查")
                }
                errorMessage?.let {
                    Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.error)
                }
            }
        }

        report?.let { current ->
            SummaryCard(current)
            IssueSection("錯誤", HealthSeverity.Error, current)
            IssueSection("警告", HealthSeverity.Warning, current)
            IssueSection("資訊", HealthSeverity.Info, current)
        }
    }
}

@Composable
private fun SummaryCard(report: DataHealthReport) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        border = BorderStroke(0.6.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.5f)),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(AppSpacing.card),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text("檢查摘要", style = MaterialTheme.typography.titleMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SummaryPill("錯誤 ${report.errorCount}", MaterialTheme.colorScheme.errorContainer)
                SummaryPill("警告 ${report.warningCount}", MaterialTheme.colorScheme.tertiaryContainer)
                SummaryPill("資訊 ${report.infoCount}", MaterialTheme.colorScheme.secondaryContainer)
            }
        }
    }
}

@Composable
private fun SummaryPill(label: String, containerColor: androidx.compose.ui.graphics.Color) {
    Card(
        colors = CardDefaults.cardColors(containerColor = containerColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp)
    ) {
        Text(
            text = label,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            style = MaterialTheme.typography.labelLarge
        )
    }
}

@Composable
private fun IssueSection(title: String, severity: HealthSeverity, report: DataHealthReport) {
    val items = report.issues.filter { it.severity == severity }
    if (items.isEmpty()) return

    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        border = BorderStroke(0.6.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.5f)),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(AppSpacing.card),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            items.forEach { issue ->
                IssueCard(issue)
            }
        }
    }
}

@Composable
private fun IssueCard(issue: HealthIssue) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.75f)),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(issue.title, style = MaterialTheme.typography.titleSmall)
            Text(issue.detail, style = MaterialTheme.typography.bodyMedium)
            Text(
                issue.recommendation,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
