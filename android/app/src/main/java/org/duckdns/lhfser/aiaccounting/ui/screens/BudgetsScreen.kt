package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.CategoryMonthlyBudgetEntity
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.utils.asCurrencyText
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.UUID
import androidx.compose.foundation.BorderStroke

@Composable
fun BudgetsScreen() {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()
    val budgets by repository.budgets.collectAsState(initial = emptyList())
    val categories by repository.categories.collectAsState(initial = emptyList())

    var selectedCategory by remember { mutableStateOf<CategoryEntity?>(null) }
    var amount by remember { mutableStateOf("") }
    var currency by remember { mutableStateOf("HKD") }
    var monthKey by remember { mutableStateOf(currentMonthKey()) }

    LazyColumn(
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(bottom = 12.dp)
    ) {
        item {
            Text("預算與超支提醒", style = MaterialTheme.typography.titleMedium)
        }
        item {
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
                border = BorderStroke(0.6.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.5f)),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier.padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text("新增預算", style = MaterialTheme.typography.titleSmall)
                    CategoryPicker(categories = categories, selected = selectedCategory) { selectedCategory = it }
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        TextButton(onClick = { }) { Text(currency) }
                        OutlinedTextField(
                            value = amount,
                            onValueChange = { amount = sanitizeAmount(it) },
                            label = { Text("預算金額") },
                            modifier = Modifier.weight(1f)
                        )
                    }
                    OutlinedTextField(
                        value = monthKey,
                        onValueChange = { monthKey = it },
                        label = { Text("月份 (YYYY-MM)") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    Button(
                        onClick = {
                            scope.launch {
                                val category = selectedCategory ?: return@launch
                                val amountValue = amount.toBigDecimalOrNull() ?: return@launch
                                repository.upsertBudget(
                                    CategoryMonthlyBudgetEntity(
                                        id = UUID.randomUUID(),
                                        monthKey = monthKey,
                                        amount = amountValue,
                                        currencyCode = currency,
                                        isEnabled = true,
                                        createdAt = Instant.now(),
                                        updatedAt = Instant.now(),
                                        categoryId = category.id
                                    )
                                )
                                amount = ""
                            }
                        }
                    ) {
                        Text("儲存")
                    }
                }
            }
        }
        items(budgets) { budget ->
            BudgetRow(budget = budget, category = categories.firstOrNull { it.id == budget.categoryId })
        }
    }
}

@Composable
private fun BudgetRow(budget: CategoryMonthlyBudgetEntity, category: CategoryEntity?) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        border = BorderStroke(0.6.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.5f))
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(category?.name ?: "未分類", style = MaterialTheme.typography.bodyLarge)
            Text("月份：${budget.monthKey}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text("預算：${budget.amount.asCurrencyText(budget.currencyCode)}", style = MaterialTheme.typography.titleSmall)
        }
    }
}

@Composable
private fun CategoryPicker(
    categories: List<CategoryEntity>,
    selected: CategoryEntity?,
    onSelect: (CategoryEntity?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("分類", style = MaterialTheme.typography.titleSmall)
        TextButton(onClick = { expanded = true }) { Text(selected?.name ?: "選擇分類") }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            categories.forEach { category ->
                DropdownMenuItem(text = { Text(category.name) }, onClick = {
                    expanded = false
                    onSelect(category)
                })
            }
        }
    }
}

private fun sanitizeAmount(input: String): String {
    val allowed = input.filter { it.isDigit() || it == '.' }
    var hasDot = false
    val result = StringBuilder()
    for (char in allowed) {
        if (char == '.') {
            if (hasDot) continue
            hasDot = true
        }
        result.append(char)
    }
    return result.toString()
}

private fun currentMonthKey(): String {
    return DateTimeFormatter.ofPattern("yyyy-MM").format(LocalDate.now())
}
