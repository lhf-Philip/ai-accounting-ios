package org.duckdns.lhfser.aiaccounting.ui.screens

import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.duckdns.lhfser.aiaccounting.core.ai.GeminiSettingsStore
import org.duckdns.lhfser.aiaccounting.ui.LocalCurrencyService
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySettingRow
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTopSection
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing

@Composable
fun SettingsScreen(
    onOpenGuide: () -> Unit,
    onOpenCategories: () -> Unit,
    onOpenTags: () -> Unit,
    onOpenBudgets: () -> Unit,
    onOpenAdvances: () -> Unit,
    onOpenHealth: () -> Unit
) {
    val repository = LocalRepository.current
    val currencyService = LocalCurrencyService.current
    val context = LocalContext.current
    val geminiSettingsStore = remember(context) { GeminiSettingsStore(context) }
    val scope = rememberCoroutineScope()
    val scrollState = rememberScrollState()

    var replaceExisting by remember { mutableStateOf(true) }
    var message by remember { mutableStateOf<String?>(null) }
    var mainCurrency by remember { mutableStateOf(currencyService.mainCurrency) }
    var currencyMenuExpanded by remember { mutableStateOf(false) }
    var apiKey by remember { mutableStateOf(geminiSettingsStore.apiKey) }

    val exportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val json = repository.exportBackupJson()
            val result = withContext(Dispatchers.IO) {
                context.contentResolver.openOutputStream(uri)?.use { output ->
                    output.write(json.toByteArray())
                }
            }
            message = if (result == null) "匯出失敗，請再試一次。" else "匯出完成。"
        }
    }

    val importLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        scope.launch {
            val text = withContext(Dispatchers.IO) {
                context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
            }
            if (text.isNullOrBlank()) {
                message = "匯入失敗：檔案內容為空。"
                return@launch
            }
            repository.importBackupJson(text, replaceExisting = replaceExisting)
            message = "匯入完成。"
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(scrollState)
            .padding(horizontal = AppSpacing.screenHorizontal, vertical = AppSpacing.screenVertical),
        verticalArrangement = Arrangement.spacedBy(AppSpacing.section)
    ) {
        ParityTopSection(
            title = "設定",
            subtitle = "管理語言、主幣別、備份、AI 功能和資料工具。"
        )

        Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)) {
            Text("新手與支援", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            SectionCard {
                ParitySettingRow(
                    title = "使用教學",
                    subtitle = "查看 app 的主要流程與功能說明",
                    onClick = onOpenGuide
                )
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)) {
            Text("偏好設定", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            SectionCard {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("主要貨幣", style = MaterialTheme.typography.titleSmall)
                        Text("總覽與報表會優先以此幣別顯示", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Button(onClick = { currencyMenuExpanded = true }, modifier = Modifier.height(42.dp)) {
                        Text(mainCurrency)
                    }
                    DropdownMenu(expanded = currencyMenuExpanded, onDismissRequest = { currencyMenuExpanded = false }) {
                        listOf("HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP").forEach { code ->
                            DropdownMenuItem(
                                text = { Text(code) },
                                onClick = {
                                    currencyMenuExpanded = false
                                    mainCurrency = code
                                    currencyService.mainCurrency = code
                                    scope.launch { currencyService.fetchRates() }
                                }
                            )
                        }
                    }
                }
                OutlinedTextField(
                    value = apiKey,
                    onValueChange = {
                        apiKey = it
                        geminiSettingsStore.apiKey = it
                    },
                    label = { Text("Gemini API Key（可選）") },
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)) {
            Text("資料與工具", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            SectionCard {
                ParitySettingRow("分類管理", "支援收入 / 支出 / 兩者", onClick = onOpenCategories)
                ParitySettingRow("標籤管理", "用於快速篩選與統計", onClick = onOpenTags)
                ParitySettingRow("代墊追蹤", "查看待還款與還款紀錄", onClick = onOpenAdvances)
                ParitySettingRow("預算與超支提醒", "設定每月分類預算與 AI 建議", onClick = onOpenBudgets)
                ParitySettingRow("資料健康檢查", "檢查缺失分類、帳戶與歷史異常", onClick = onOpenHealth)
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.inline)) {
            Text("資料安全", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            SectionCard {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("匯入時覆蓋現有資料", style = MaterialTheme.typography.titleSmall)
                        Text("開啟後會以匯入檔案為準", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Switch(checked = replaceExisting, onCheckedChange = { replaceExisting = it })
                }
                Button(
                    onClick = { exportLauncher.launch("Backup.json") },
                    modifier = Modifier.fillMaxWidth().height(48.dp)
                ) {
                    Text("匯出 JSON 備份")
                }
                Button(
                    onClick = { importLauncher.launch(arrayOf("application/json")) },
                    modifier = Modifier.fillMaxWidth().height(48.dp)
                ) {
                    Text("匯入 JSON 備份")
                }
                if (message != null) {
                    Text(message.orEmpty(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}
