package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.foundation.BorderStroke
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.duckdns.lhfser.aiaccounting.data.db.TagEntity
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.components.SectionHeader
import java.util.UUID

@Composable
fun TagsScreen(onEdit: (String) -> Unit) {
    val repository = LocalRepository.current
    val tags by repository.tags.collectAsState(initial = emptyList())

    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
        SectionHeader(
            title = "標籤",
            actionLabel = "新增標籤",
            onAction = { onEdit(UUID.randomUUID().toString()) }
        )
        LazyColumn(
            verticalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.padding(top = 12.dp)
        ) {
            items(tags) { tag ->
                TagRow(tag = tag, onClick = { onEdit(tag.id.toString()) })
            }
        }
    }
}

@Composable
private fun TagRow(tag: TagEntity, onClick: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        border = BorderStroke(0.6.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.5f))
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text("#", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
            Text(tag.name, style = MaterialTheme.typography.bodyLarge)
        }
    }
}
