package org.duckdns.lhfser.aiaccounting.ui.screens

import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.duckdns.lhfser.aiaccounting.ui.LocalCurrencyService
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard

@Composable
fun SettingsScreen(
    onOpenCategories: () -> Unit,
    onOpenTags: () -> Unit,
    onOpenBudgets: () -> Unit,
    onOpenAdvances: () -> Unit,
    onOpenHealth: () -> Unit
) {
    val repository = LocalRepository.current
    val currencyService = LocalCurrencyService.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var replaceExisting by remember { mutableStateOf(true) }
    var message by remember { mutableStateOf<String?>(null) }
    var mainCurrency by remember { mutableStateOf(currencyService.mainCurrency) }
    var currencyMenuExpanded by remember { mutableStateOf(false) }

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
        context.contentResolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION
        )
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
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("偏好設定", style = MaterialTheme.typography.titleMedium)
        SectionCard {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("主要貨幣", style = MaterialTheme.typography.titleSmall)
                    Text("報表與總覽以此幣別顯示", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Button(onClick = { currencyMenuExpanded = true }) {
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
        }

        Text("資料與工具", style = MaterialTheme.typography.titleMedium)
        SectionCard {
            SettingRow(title = "分類管理", subtitle = "支援收入/支出/兩者", onClick = onOpenCategories)
            SettingRow(title = "標籤管理", subtitle = "用於快速篩選與統計", onClick = onOpenTags)
            SettingRow(title = "代墊追蹤", subtitle = "查看待還款與還款紀錄", onClick = onOpenAdvances)
            SettingRow(title = "預算與超支提醒", subtitle = "設定每月分類預算", onClick = onOpenBudgets)
            SettingRow(title = "資料健康檢查", subtitle = "檢查缺失分類/帳戶", onClick = onOpenHealth)
        }

        Text("備份與匯入", style = MaterialTheme.typography.titleMedium)
        SectionCard {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("匯入時覆蓋現有資料", style = MaterialTheme.typography.titleSmall)
                    Text("開啟後會以匯入檔案為準", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Switch(checked = replaceExisting, onCheckedChange = { replaceExisting = it })
            }
            Spacer(modifier = Modifier.padding(top = 4.dp))
            Button(onClick = { exportLauncher.launch("Backup.json") }, modifier = Modifier.fillMaxWidth()) {
                Text("匯出 JSON 備份")
            }
            Button(onClick = { importLauncher.launch(arrayOf("application/json")) }, modifier = Modifier.fillMaxWidth()) {
                Text("匯入 JSON 備份")
            }
            if (message != null) {
                Text(message ?: "", style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}


@Composable
private fun SettingRow(title: String, subtitle: String, onClick: () -> Unit) {
    Surface(
        tonalElevation = 0.dp,
        color = MaterialTheme.colorScheme.surface,
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.bodyLarge)
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
        }
    }
}
