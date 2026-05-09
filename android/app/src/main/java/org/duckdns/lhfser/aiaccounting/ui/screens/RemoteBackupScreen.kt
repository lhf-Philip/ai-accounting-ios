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
import androidx.compose.material3.Switch
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
    var encryptRemoteBackups by remember { mutableStateOf(settingsStore.encryptRemoteBackups) }
    var didConfirmPlainBackup by remember { mutableStateOf(settingsStore.didConfirmPlainWebDavBackup) }
    var files by remember { mutableStateOf<List<RemoteBackupFile>>(emptyList()) }
    var preview by remember { mutableStateOf<RemoteBackupPreview?>(null) }
    var pendingRestore by remember { mutableStateOf<FullBackupData?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    var isBusy by remember { mutableStateOf(false) }
    var showRestoreConfirm by remember { mutableStateOf(false) }
    var showPlainBackupConfirm by remember { mutableStateOf(false) }
    var showHttpRiskConfirm by remember { mutableStateOf(false) }
    var pendingHttpAction by remember { mutableStateOf<(() -> Unit)?>(null) }
    var pendingPlainBackupAction by remember { mutableStateOf<(() -> Unit)?>(null) }
    var httpWarningMentionsPlainBackup by remember { mutableStateOf(false) }

    fun saveSettings() {
        settingsStore.baseUrl = baseUrl
        settingsStore.username = username
        settingsStore.password = password
        settingsStore.passphrase = passphrase
        settingsStore.encryptRemoteBackups = encryptRemoteBackups
    }

    fun credentials(): WebDavCredentials {
        return WebDavCredentials(
            baseUrl = baseUrl.trim(),
            username = username.trim(),
            password = password.trim(),
            passphrase = passphrase.trim()
        )
    }

    fun isInsecureHttp(url: String): Boolean {
        return url.trim().startsWith("http://", ignoreCase = true)
    }

    fun runRemote(
        successMessage: String,
        requirePassphrase: Boolean = false,
        warnPlainBackup: Boolean = false,
        isPlainBackupUpload: Boolean = false,
        allowInsecureHttp: Boolean = false,
        block: suspend () -> Unit
    ) {
        if (isBusy) return
        val creds = credentials()
        if (!creds.isConnectionComplete) {
            message = "請先填寫 WebDAV URL、帳戶和密碼。"
            return
        }
        if (requirePassphrase && !creds.hasPassphrase) {
            message = "此操作需要加密 passphrase。"
            return
        }
        if (warnPlainBackup && !didConfirmPlainBackup) {
            pendingPlainBackupAction = {
                runRemote(
                    successMessage = successMessage,
                    requirePassphrase = requirePassphrase,
                    warnPlainBackup = false,
                    isPlainBackupUpload = isPlainBackupUpload,
                    allowInsecureHttp = allowInsecureHttp,
                    block = block
                )
            }
            showPlainBackupConfirm = true
            return
        }
        if (!allowInsecureHttp && isInsecureHttp(creds.baseUrl)) {
            httpWarningMentionsPlainBackup = isPlainBackupUpload
            pendingHttpAction = {
                runRemote(
                    successMessage = successMessage,
                    requirePassphrase = requirePassphrase,
                    warnPlainBackup = warnPlainBackup,
                    isPlainBackupUpload = isPlainBackupUpload,
                    allowInsecureHttp = true,
                    block = block
                )
            }
            showHttpRiskConfirm = true
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
                    label = { Text(if (encryptRemoteBackups) "備份加密 passphrase" else "加密 passphrase（還原加密備份時需要）") },
                    modifier = Modifier.fillMaxWidth(),
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(AppSpacing.inline)
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("加密遠端備份（建議）", style = MaterialTheme.typography.titleSmall)
                        Text(
                            if (encryptRemoteBackups) "上傳會使用 AES-GCM 加密，檔案副檔名為 .aibackup。"
                            else "未加密備份會以 .json 上傳，雲端可直接讀取你的財務資料。",
                            style = MaterialTheme.typography.bodySmall,
                            color = if (encryptRemoteBackups) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.error
                        )
                    }
                    Switch(
                        checked = encryptRemoteBackups,
                        onCheckedChange = {
                            encryptRemoteBackups = it
                            settingsStore.encryptRemoteBackups = it
                        }
                    )
                }
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
                        val shouldEncrypt = encryptRemoteBackups
                        runRemote(
                            successMessage = if (shouldEncrypt) "加密上傳完成。" else "未加密上傳完成。",
                            requirePassphrase = shouldEncrypt,
                            warnPlainBackup = !shouldEncrypt,
                            isPlainBackupUpload = !shouldEncrypt
                        ) {
                            service.uploadBackup(repository.exportBackupJson(), credentials(), encryptBackup = shouldEncrypt)
                            files = service.listBackups(credentials())
                        }
                    },
                    modifier = Modifier.fillMaxWidth().height(50.dp)
                ) {
                    Text(if (encryptRemoteBackups) "加密並上傳目前備份" else "未加密上傳目前備份")
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
                        runRemote("已下載並讀取備份。", requirePassphrase = file.isEncrypted) {
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
                        Column(modifier = Modifier.weight(1f)) {
                            Text(file.name, style = MaterialTheme.typography.titleSmall)
                            Text(
                                file.format.label,
                                style = MaterialTheme.typography.labelSmall,
                                color = if (file.isEncrypted) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.error
                            )
                        }
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

    if (showPlainBackupConfirm) {
        AlertDialog(
            onDismissRequest = {
                showPlainBackupConfirm = false
                pendingPlainBackupAction = null
            },
            title = { Text("上傳未加密備份？") },
            text = { Text("未加密 JSON 會包含帳戶、交易、備註、分類和標籤等資料。只有在你信任這個雲端儲存位置時才建議使用。") },
            confirmButton = {
                TextButton(
                    onClick = {
                        val action = pendingPlainBackupAction
                        didConfirmPlainBackup = true
                        settingsStore.didConfirmPlainWebDavBackup = true
                        showPlainBackupConfirm = false
                        pendingPlainBackupAction = null
                        action?.invoke()
                    }
                ) {
                    Text("未加密上傳", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        showPlainBackupConfirm = false
                        pendingPlainBackupAction = null
                    }
                ) {
                    Text("取消")
                }
            }
        )
    }

    if (showHttpRiskConfirm) {
        AlertDialog(
            onDismissRequest = {
                showHttpRiskConfirm = false
                pendingHttpAction = null
            },
            title = { Text("HTTP 連線不安全") },
            text = {
                Text(
                    if (httpWarningMentionsPlainBackup) {
                        "目前 WebDAV URL 使用 http://，而且你正在使用未加密備份；傳輸途中和雲端上都可能暴露財務資料。確定要繼續？"
                    } else {
                        "目前 WebDAV URL 使用 http://，傳輸途中可能被讀取或竄改。localhost / LAN 可以用作測試，但仍不建議放敏感備份。確定要繼續？"
                    }
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val action = pendingHttpAction
                        showHttpRiskConfirm = false
                        pendingHttpAction = null
                        action?.invoke()
                    }
                ) {
                    Text("仍然繼續", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        showHttpRiskConfirm = false
                        pendingHttpAction = null
                    }
                ) {
                    Text("取消")
                }
            }
        )
    }
}
