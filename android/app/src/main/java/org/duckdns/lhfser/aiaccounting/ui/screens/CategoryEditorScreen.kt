package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.duckdns.lhfser.aiaccounting.core.model.CategoryKind
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import java.util.UUID

@Composable
fun CategoryEditorScreen(categoryId: String?, onDone: () -> Unit) {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()
    val categories by repository.categories.collectAsState(initial = emptyList())

    var name by remember { mutableStateOf("") }
    var icon by remember { mutableStateOf("square.grid.2x2") }
    var colorHex by remember { mutableStateOf("#90A4AE") }
    var kind by remember { mutableStateOf(CategoryKind.Both) }

    LaunchedEffect(categoryId, categories) {
        val id = categoryId?.let(UUID::fromString)
        val existing = categories.firstOrNull { it.id == id }
        if (existing != null) {
            name = existing.name
            icon = existing.icon
            colorHex = existing.colorHex
            kind = existing.kind
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        OutlinedTextField(
            value = name,
            onValueChange = { name = it },
            label = { Text("分類名稱") },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = icon,
            onValueChange = { icon = it },
            label = { Text("圖示（SF Symbol 名稱）") },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = colorHex,
            onValueChange = { colorHex = it },
            label = { Text("顏色 Hex") },
            modifier = Modifier.fillMaxWidth()
        )
        Button(
            onClick = {
                val existing = categories.map { it.colorHex }
                colorHex = autoPickDistinctColor(existing)
            }
        ) {
            Text("自動選擇不衝突顏色")
        }
        KindPicker(kind = kind, onChange = { kind = it })
        Button(
            onClick = {
                scope.launch {
                    val id = categoryId?.let(UUID::fromString) ?: UUID.randomUUID()
                    val category = CategoryEntity(
                        id = id,
                        name = name.ifBlank { "分類" },
                        icon = icon.ifBlank { "square.grid.2x2" },
                        colorHex = colorHex.ifBlank { "#90A4AE" },
                        kind = kind
                    )
                    repository.upsertCategory(category)
                    onDone()
                }
            },
            enabled = name.isNotBlank()
        ) {
            Text("儲存")
        }
    }
}

@Composable
private fun KindPicker(kind: CategoryKind, onChange: (CategoryKind) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("分類類型", style = MaterialTheme.typography.titleSmall)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CategoryKind.entries.forEach { item ->
                FilterChip(
                    selected = kind == item,
                    onClick = { onChange(item) },
                    label = { Text(item.rawValue) }
                )
            }
        }
    }
}

private fun autoPickDistinctColor(existing: List<String>): String {
    val palette = listOf(
        "#EF5350",
        "#EC407A",
        "#AB47BC",
        "#7E57C2",
        "#5C6BC0",
        "#42A5F5",
        "#26A69A",
        "#66BB6A",
        "#FFCA28",
        "#FFA726",
        "#8D6E63",
        "#78909C"
    )
    return palette.firstOrNull { color -> existing.none { it.equals(color, ignoreCase = true) } }
        ?: palette.random()
}
