package org.duckdns.lhfser.aiaccounting.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing

@Composable
fun SectionHeader(
    title: String,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = AppSpacing.tight),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
        if (actionLabel != null && onAction != null) {
            TextButton(onClick = onAction) { Text(actionLabel) }
        }
    }
}

@Composable
fun SectionCard(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        border = BorderStroke(0.6.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.35f)),
        modifier = modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(AppSpacing.card),
            verticalArrangement = Arrangement.spacedBy(AppSpacing.card)
        ) {
            content()
        }
    }
}

@Composable
@OptIn(ExperimentalFoundationApi::class)
fun PressableCard(
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null,
    enabled: Boolean = true,
    containerColor: Color = MaterialTheme.colorScheme.surface,
    pressedContainerColor: Color = MaterialTheme.colorScheme.surfaceVariant,
    borderColor: Color = MaterialTheme.colorScheme.outline.copy(alpha = 0.5f),
    pressedBorderColor: Color = MaterialTheme.colorScheme.outline.copy(alpha = 0.7f),
    contentPadding: PaddingValues = PaddingValues(0.dp),
    scaleOnPress: Float = 0.985f,
    elevation: Dp = 0.dp,
    pressedElevation: Dp = 1.dp,
    shape: Shape = MaterialTheme.shapes.medium,
    content: @Composable () -> Unit
) {
    var isPressed by remember { mutableStateOf(false) }
    val animatedScale by animateFloatAsState(
        targetValue = if (isPressed) scaleOnPress else 1f,
        animationSpec = spring(dampingRatio = 0.88f, stiffness = 720f),
        label = "pressScale"
    )
    val animatedElevation by animateDpAsState(
        targetValue = if (isPressed) pressedElevation else elevation,
        animationSpec = spring(dampingRatio = 0.92f, stiffness = 560f),
        label = "pressElevation"
    )
    val animatedContainer by animateColorAsState(
        targetValue = if (isPressed) pressedContainerColor else containerColor,
        animationSpec = tween(durationMillis = 140),
        label = "pressContainer"
    )
    val animatedBorder by animateColorAsState(
        targetValue = if (isPressed) pressedBorderColor else borderColor,
        animationSpec = tween(durationMillis = 140),
        label = "pressBorder"
    )

    val pressTrackingModifier = Modifier.pointerInput(enabled) {
        if (!enabled) return@pointerInput
        awaitPointerEventScope {
            while (true) {
                awaitFirstDown(requireUnconsumed = false)
                isPressed = true
                waitForUpOrCancellation()
                isPressed = false
            }
        }
    }

    val clickableModifier = if (onLongClick != null) {
        Modifier.combinedClickable(
            enabled = enabled,
            onClick = onClick,
            onLongClick = onLongClick
        )
    } else {
        Modifier.clickable(
            enabled = enabled,
            onClick = onClick
        )
    }

    Surface(
        modifier = modifier
            .graphicsLayer {
                scaleX = animatedScale
                scaleY = animatedScale
            }
            .then(pressTrackingModifier)
            .then(clickableModifier),
        shape = shape,
        color = animatedContainer,
        shadowElevation = animatedElevation,
        border = BorderStroke(0.6.dp, animatedBorder)
    ) {
        Box(modifier = Modifier.padding(contentPadding)) {
            content()
        }
    }
}

@Composable
fun CurrencyPicker(
    selected: String,
    onSelect: (String) -> Unit,
    buttonStyle: CurrencyButtonStyle = CurrencyButtonStyle.Tonal
) {
    val currencies = listOf("HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP")
    val expanded = remember { mutableStateOf(false) }
    val onClick = { expanded.value = true }
    when (buttonStyle) {
        CurrencyButtonStyle.Tonal -> {
            FilledTonalButton(onClick = onClick) {
                Text(selected)
            }
        }
        CurrencyButtonStyle.Text -> {
            TextButton(onClick = onClick) {
                Text(selected)
            }
        }
    }
    DropdownMenu(
        expanded = expanded.value,
        onDismissRequest = { expanded.value = false }
    ) {
        currencies.forEach { code ->
            DropdownMenuItem(
                text = { Text(code) },
                onClick = {
                    expanded.value = false
                    onSelect(code)
                }
            )
        }
    }
}

enum class CurrencyButtonStyle {
    Tonal,
    Text
}
