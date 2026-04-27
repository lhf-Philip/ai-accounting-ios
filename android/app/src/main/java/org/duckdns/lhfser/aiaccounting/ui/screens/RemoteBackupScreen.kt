package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.duckdns.lhfser.aiaccounting.core.backup.RemoteBackupFile
import org.duckdns.lhfser.aiaccounting.core.backup.RemoteBackupPreview
import org.duckdns.lhfser.aiaccounting.core.backup.RemoteBackupService
import org.duckdns.lhfser.aiaccounting.core.backup.WebDavCredentials
import org.duckdns.lhfser.aiaccounting.core.backup.WebDavSettingsStore
import org.duckdns.lhfser.aiaccounting.data.backup.FullBackupData
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySectionHeader
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTokens
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTopSection
import org.duckdns.lhfser.aiaccounting.ui.components.PressableCard
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing

@Composable
fun RemoteBackupScreen() {
    val repository = LocalRepository.current
    val context = LocalContext.current
    val settingsStore = remember(context) { WebDavSettingsStore(context) }
    val service = remember { RemoteBackupService() }
    val scope = rememberCoroutineScope()
    val scrollState = rememberScrollState()

    var baseUrl by remember { mutableStateOf(settingsStore.baseUrl) }
    var username by remember { mutableStateOf(settingsStore.username) }
    var password by remember { mutableStateOf(settingsStore.password) }
    var passphrase by remember { mutableStateOf(settingsStore.passphrase) }
    var files by remember { mutableStateOf<List<RemoteBackupFile>>(emptyList()) }
    var preview by remember { mutableStateOf<RemoteBackupPreview?>(null) }
    var pendingRestore by remember { mutableStateOf<FullBackupData?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    var isBusy by remember { mutableStateOf(false) }
    var showRestoreConfirm by remember { mutableStateOf(false) }

    fun saveSettings() {
        settingsStore.baseUrl = baseUrl
        settingsStore.username = username
        settingsStore.password = password
        settingsStore.passphrase = passphrase
    }

    fun credentials(): WebDavCredentials {
        return WebDavCredentials(
            baseUrl = baseUrl.trim(),
            username = username.trim(),
            password = password.trim(),
            passphrase = passphrase.trim()
        )
    }

    fun runRemote(successMessage: String, block: suspend () -> Unit) {
        if (isBusy) return
        val creds = credentials()
        if (!creds.isComplete) {
            message = "請先填寫 WebDAV URL、帳戶、密碼和加密 passphrase。"
            return
        }
        saveSettings()
        isBusy = true
        message = "處理中..."
        scope.launch {
            runCatching { block() }
                .onSuccess { message = successMessage }
                .onFailure { message = "失敗：${it.localizedMessage ?: it.message ?: "未知錯誤"}" }
            isBusy = false
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(scrollState)
            .padding(
                start = AppSpacing.screenHorizontal,
                end = AppSpacing.screenHorizontal,
                top = AppSpacing.screenVertical,
                bottom = AppSpacing.screenVertical + ParityTokens.FloatingContentBottomPadding
            ),
        verticalArrangement = Arrangement.spacedBy(AppSpacing.section)
    ) {
        ParityTopSection(
            title = "WebDAV 遠端備份",
            subtitle = "手動加密上傳、下載預覽，再確認還原。"
        )

        ParitySectionHeader(title = "連線設定")
        SectionCard {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = baseUrl,
                    onValueChange = { baseUrl = it },
                    label = { Text("WebDAV URL") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
                OutlinedTextField(
                    value = username,
                    onValueChange = { username = it },
                    label = { Text("帳戶") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = { Text("WebDAV 密碼") },
                    modifier = Modifier.fillMaxWidth(),
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true
                )
                OutlinedTextField(
                    value = passphrase,
                    onValueChange = { passphrase = it },
                    label = { Text("備份加密 passphrase") },
                    modifier = Modifier.fillMaxWidth(),
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true
                )
                Button(
                    onClick = {
                        runRemote("連線測試成功。") {
                            service.testConnection(credentials())
                        }
                    },
                    modifier = Modifier.fillMaxWidth().height(50.dp)
                ) {
                    Text("測試連線")
                }
            }
        }

        ParitySectionHeader(title = "遠端備份")
        SectionCard {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Button(
                    onClick = {
                        runRemote("加密上傳完成。") {
                            service.uploadBackup(repository.exportBackupJson(), credentials())
                            files = service.listBackups(credentials())
                        }
                    },
                    modifier = Modifier.fillMaxWidth().height(50.dp)
                ) {
                    Text("加密並上傳目前備份")
                }
                Button(
                    onClick = {
                        runRemote("已載入遠端備份。") {
                            files = service.listBackups(credentials())
                        }
                    },
                    modifier = Modifier.fillMaxWidth().height(50.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.secondaryContainer)
                ) {
                    Text("重新載入遠端備份")
                }
                if (message != null) {
                    Text(message.orEmpty(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }

        ParitySectionHeader(title = "遠端檔案")
        if (files.isEmpty()) {
            SectionCard {
                Text(
                    "尚未載入遠端備份。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        } else {
            files.forEach { file ->
                PressableCard(
                    modifier = Modifier.fillMaxWidth(),
                    onClick = {
                        runRemote("已下載並解密備份。") {
                            val json = service.downloadBackup(file, credentials())
                            val backup = service.decodeBackup(json)
                            pendingRestore = backup
                            preview = service.makePreview(backup)
                        }
                    }
                ) {
                    Row(
                        modifier = Modifier.padding(AppSpacing.card).fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(AppSpacing.inline)
                    ) {
                        Text(file.name, modifier = Modifier.weight(1f), style = MaterialTheme.typography.titleSmall)
                        Text("預覽", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                    }
                }
            }
        }

        preview?.let { currentPreview ->
            ParitySectionHeader(title = currentPreview.title)
            SectionCard {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(currentPreview.detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Button(
                        onClick = { showRestoreConfirm = true },
                        enabled = pendingRestore != null && !isBusy,
                        modifier = Modifier.fillMaxWidth().height(50.dp)
                    ) {
                        Text("確認還原此備份")
                    }
                }
            }
        }
    }

    if (showRestoreConfirm) {
        AlertDialog(
            onDismissRequest = { showRestoreConfirm = false },
            title = { Text("還原遠端備份？") },
            text = { Text("這會以遠端備份覆蓋目前資料庫。建議先確認你已有本地備份。") },
            confirmButton = {
                TextButton(
                    onClick = {
                        val backup = pendingRestore ?: return@TextButton
                        showRestoreConfirm = false
                        scope.launch {
                            runCatching {
                                repository.importBackupJson(
                                    org.duckdns.lhfser.aiaccounting.data.backup.BackupJsonAdapter.gson.toJson(backup),
                                    replaceExisting = true
                                )
                            }.onSuccess {
                                message = "已完成遠端備份還原。"
                            }.onFailure {
                                message = "還原失敗：${it.localizedMessage ?: "未知錯誤"}"
                            }
                        }
                    }
                ) {
                    Text("還原", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showRestoreConfirm = false }) { Text("取消") }
            }
        )
    }
}
