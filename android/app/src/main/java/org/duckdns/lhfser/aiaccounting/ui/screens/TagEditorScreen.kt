package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
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
import org.duckdns.lhfser.aiaccounting.data.db.TagEntity
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard
import java.util.UUID

@Composable
fun TagEditorScreen(tagId: String?, onDone: () -> Unit) {
    val repository = LocalRepository.current
    val scope = rememberCoroutineScope()
    val tags by repository.tags.collectAsState(initial = emptyList())

    var name by remember { mutableStateOf("") }

    LaunchedEffect(tagId, tags) {
        val id = tagId?.let(UUID::fromString)
        val existing = tags.firstOrNull { it.id == id }
        if (existing != null) {
            name = existing.name
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("標籤資料", style = MaterialTheme.typography.titleMedium)
        SectionCard {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("標籤名稱") },
                modifier = Modifier.fillMaxWidth()
            )
        }
        Button(
            onClick = {
                scope.launch {
                    val id = tagId?.let(UUID::fromString) ?: UUID.randomUUID()
                    repository.upsertTag(TagEntity(id = id, name = name.ifBlank { "標籤" }))
                    onDone()
                }
            },
            enabled = name.isNotBlank()
        ) {
            Text("儲存")
        }
    }
}
