package org.duckdns.lhfser.aiaccounting.ui.screens

import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.duckdns.lhfser.aiaccounting.core.ai.GeminiSettingsStore
import org.duckdns.lhfser.aiaccounting.core.ai.ReceiptInfo
import org.duckdns.lhfser.aiaccounting.core.ai.ReceiptScanService
import org.duckdns.lhfser.aiaccounting.core.model.TransactionType
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.TransactionEntity
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyButtonStyle
import org.duckdns.lhfser.aiaccounting.ui.components.CurrencyPicker
import org.duckdns.lhfser.aiaccounting.ui.components.ParityMenuField
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySectionHeader
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySummaryCard
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTopSection
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTokens
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID

@Composable
fun ReceiptScanScreen(onDone: () -> Unit) {
    val context = LocalContext.current
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()
    val service = remember(context) { ReceiptScanService(GeminiSettingsStore(context)) }
    val scrollState = rememberScrollState()

    val accounts by repository.accounts.collectAsState(initial = emptyList())
    val categories by repository.categories.collectAsState(initial = emptyList())
    val activeAccounts = remember(accounts) { accounts.filter { !it.isArchived } }
    val expenseCategories = remember(categories) { categories.filter { it.kind.supports(TransactionType.Expense) } }

    var imageBytes by remember { mutableStateOf<ByteArray?>(null) }
    var userNote by remember { mutableStateOf("") }
    var isAnalyzing by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var scanResult by remember { mutableStateOf<ReceiptInfo?>(null) }

    var amountInput by remember { mutableStateOf("") }
    var currencyCode by remember { mutableStateOf("HKD") }
    var dateInput by remember { mutableStateOf(LocalDate.now().toString()) }
    var timeInput by remember { mutableStateOf("") }
    var noteInput by remember { mutableStateOf("") }
    var selectedAccount by remember { mutableStateOf<AccountEntity?>(null) }
    var selectedCategory by remember { mutableStateOf<CategoryEntity?>(null) }

    val imagePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            imageBytes = withContext(Dispatchers.IO) {
                context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            }
        }
    }

    LaunchedEffect(activeAccounts) {
        if (selectedAccount == null) {
            selectedAccount = activeAccounts.firstOrNull()
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
            title = "掃描單據",
            subtitle = "上傳單據圖片，先由 AI 識別，再由你確認後才寫入帳目。"
        )

        SectionCard {
            ParitySectionHeader(
                title = "上傳單據",
                detail = "你可以先挑圖片，再決定是否補充備註給 AI"
            )
            if (imageBytes == null) {
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(240.dp)
                        .clickable { imagePicker.launch("image/*") },
                    shape = RoundedCornerShape(18.dp),
                    color = MaterialTheme.colorScheme.surface,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.35f))
                ) {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        androidx.compose.material3.Icon(
                            imageVector = Icons.Default.CameraAlt,
                            contentDescription = null,
                            modifier = Modifier.size(42.dp),
                            tint = MaterialTheme.colorScheme.primary
                        )
                        Text("上傳或拍攝單據", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        Text("支援從相簿或檔案挑選圖片", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            } else {
                val bitmap = remember(imageBytes) {
                    imageBytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
                }
                if (bitmap != null) {
                    Image(
                        bitmap = bitmap.asImageBitmap(),
                        contentDescription = null,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(240.dp)
                    )
                }
                Button(
                    onClick = { imagePicker.launch("image/*") },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(50.dp),
                    shape = RoundedCornerShape(18.dp)
                ) {
                    Text("更換單據圖片")
                }
            }

            OutlinedTextField(
                value = userNote,
                onValueChange = { userNote = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("備註（可選）") },
                placeholder = { Text("例如：我和朋友 AA 制，只計我自己的餐費") }
            )

            Button(
                onClick = {
                    val bytes = imageBytes ?: return@Button
                    isAnalyzing = true
                    errorMessage = null
                    scope.launch {
                        runCatching {
                            service.analyzeReceipt(bytes, userNote, expenseCategories.map { it.name })
                        }.onSuccess { result ->
                            scanResult = result
                            amountInput = result.amount.toPlainString()
                            currencyCode = normalizedCurrencyCode(result.currency, selectedAccount?.currency ?: "HKD")
                            dateInput = result.date
                            timeInput = result.time.orEmpty()
                            noteInput = listOf(result.merchant, result.note)
                                .filter { it.isNotBlank() }
                                .joinToString(" - ")
                            selectedCategory = matchCategory(expenseCategories, result.categoryName)
                        }.onFailure {
                            errorMessage = it.localizedMessage ?: "AI 識別失敗"
                        }
                        isAnalyzing = false
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(50.dp),
                shape = RoundedCornerShape(18.dp),
                enabled = imageBytes != null && !isAnalyzing
            ) {
                Text(if (isAnalyzing) "AI 分析中..." else "開始智能識別")
            }

            if (errorMessage != null) {
                Text(
                    text = errorMessage.orEmpty(),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }
        }

        if (scanResult != null) {
            ParitySummaryCard(
                title = "AI 識別結果",
                value = "請確認後再入帳",
                supporting = "AI 只提供建議，你可以在儲存前修改所有欄位。"
            )

            SectionCard {
                ParitySectionHeader(
                    title = "確認與調整",
                    detail = "金額、帳戶、分類、日期時間都可以在儲存前修改"
                )
                OutlinedTextField(
                    value = amountInput,
                    onValueChange = { amountInput = sanitizeDecimal(it) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("金額") },
                    shape = RoundedCornerShape(18.dp)
                )
                CurrencyPicker(selected = currencyCode, onSelect = { currencyCode = it }, buttonStyle = CurrencyButtonStyle.Text)
                OutlinedTextField(
                    value = dateInput,
                    onValueChange = { dateInput = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("日期（YYYY-MM-DD）") },
                    shape = RoundedCornerShape(18.dp)
                )
                OutlinedTextField(
                    value = timeInput,
                    onValueChange = { timeInput = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("時間（HH:mm，可選）") },
                    shape = RoundedCornerShape(18.dp)
                )
                OutlinedTextField(
                    value = noteInput,
                    onValueChange = { noteInput = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("商戶 / 備註") },
                    shape = RoundedCornerShape(18.dp)
                )
                EntityPicker(
                    label = "帳戶",
                    options = activeAccounts,
                    selected = selectedAccount,
                    optionLabel = { it.name },
                    onSelect = { selectedAccount = it }
                )
                EntityPicker(
                    label = "分類",
                    options = expenseCategories,
                    selected = selectedCategory,
                    optionLabel = { it.name },
                    onSelect = { selectedCategory = it }
                )
                Button(
                    onClick = {
                        val account = selectedAccount ?: return@Button
                        val amount = amountInput.toBigDecimalOrNull() ?: return@Button
                        val transaction = TransactionEntity(
                            id = UUID.randomUUID(),
                            amount = amount.abs().negate(),
                            currencyCode = currencyCode,
                            date = parseDateTime(dateInput, timeInput),
                            note = noteInput,
                            photoPath = null,
                            type = TransactionType.Expense,
                            linkedTransactionId = null,
                            transferGroupId = null,
                            transferSide = null,
                            createdAt = Instant.now(),
                            updatedAt = Instant.now(),
                            accountId = account.id,
                            categoryId = selectedCategory?.id
                        )
                        scope.launch {
                            repository.upsertTransaction(transaction, emptyList())
                            onDone()
                        }
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(50.dp),
                    shape = RoundedCornerShape(18.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary),
                    enabled = selectedAccount != null && amountInput.toBigDecimalOrNull() != null
                ) {
                    Text("儲存為支出")
                }
            }
        }
    }
}

@Composable
private fun <T> EntityPicker(
    label: String,
    options: List<T>,
    selected: T?,
    optionLabel: (T) -> String,
    onSelect: (T) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        ParityMenuField(
            label = label,
            value = selected?.let(optionLabel).orEmpty(),
            onClick = { expanded = true }
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(optionLabel(option)) },
                    onClick = {
                        expanded = false
                        onSelect(option)
                    }
                )
            }
        }
    }
}

private fun parseDateTime(dateRaw: String, timeRaw: String): Instant {
    val date = runCatching { LocalDate.parse(dateRaw, DateTimeFormatter.ISO_LOCAL_DATE) }.getOrNull() ?: LocalDate.now()
    val time = if (timeRaw.isBlank()) {
        LocalTime.now().withSecond(0).withNano(0)
    } else {
        runCatching { LocalTime.parse(timeRaw, DateTimeFormatter.ofPattern("HH:mm")) }.getOrNull()
            ?: LocalTime.now().withSecond(0).withNano(0)
    }
    return LocalDateTime.of(date, time).atZone(ZoneId.systemDefault()).toInstant()
}

private fun matchCategory(categories: List<CategoryEntity>, name: String): CategoryEntity? {
    val normalized = name.trim()
    if (normalized.isBlank()) return null
    return categories.firstOrNull { it.name.equals(normalized, ignoreCase = true) }
        ?: categories.firstOrNull { it.name.contains(normalized, ignoreCase = true) || normalized.contains(it.name, ignoreCase = true) }
}

private fun normalizedCurrencyCode(raw: String, fallback: String): String {
    return when (raw.trim().uppercase()) {
        "HKD", "HK$", "H$" -> "HKD"
        "USD", "US$", "$" -> "USD"
        "TWD", "NT$", "NTD" -> "TWD"
        "JPY", "¥" -> "JPY"
        "CNY", "RMB", "CN¥" -> "CNY"
        "EUR", "€" -> "EUR"
        "GBP", "£" -> "GBP"
        else -> fallback.trim().uppercase()
    }
}

private fun sanitizeDecimal(input: String): String {
    var hasDot = false
    return buildString {
        input.forEach { char ->
            when {
                char.isDigit() -> append(char)
                char == '.' && !hasDot -> {
                    append(char)
                    hasDot = true
                }
            }
        }
    }.removePrefix(".")
}
