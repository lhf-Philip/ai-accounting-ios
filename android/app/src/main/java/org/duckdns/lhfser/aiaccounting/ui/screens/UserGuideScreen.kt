package org.duckdns.lhfser.aiaccounting.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.Assessment
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import org.duckdns.lhfser.aiaccounting.ui.components.ParityTokens
import org.duckdns.lhfser.aiaccounting.ui.components.SectionCard
import org.duckdns.lhfser.aiaccounting.ui.theme.AppSpacing

@Composable
fun UserGuideScreen(
    onDone: () -> Unit,
    isFirstLaunch: Boolean = false
) {
    val scrollState = rememberScrollState()
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(scrollState)
            .imePadding()
            .padding(
                start = AppSpacing.screenHorizontal,
                end = AppSpacing.screenHorizontal,
                top = AppSpacing.screenVertical,
                bottom = AppSpacing.screenVertical + ParityTokens.FloatingContentBottomPadding
            ),
        verticalArrangement = Arrangement.spacedBy(AppSpacing.section)
    ) {
        HeroGuideCard()

        GuideSectionCard(
            title = "1. 先建立帳戶",
            icon = Icons.Default.AccountBalanceWallet,
            points = listOf(
                "在「帳戶」頁新增現金、銀行、信用卡或借貸帳戶。",
                "每個帳戶可設定基礎餘額與幣別，資產估算會自動換算。"
            )
        )

        GuideSectionCard(
            title = "2. 記錄日常收支",
            icon = Icons.Default.Description,
            points = listOf(
                "使用右下角「新增」按鈕建立收入、支出、轉帳、借貸或代墊。",
                "每筆交易可帶分類、標籤、備註與交易幣別。",
                "轉帳與代墊支援完整編輯，不需刪除重建。"
            )
        )

        GuideSectionCard(
            title = "3. 看懂報表",
            icon = Icons.Default.Assessment,
            points = listOf(
                "在「報表」切換收入/支出、分類/標籤檢視。",
                "點擊分類或標籤可查看對應交易明細。"
            )
        )

        GuideSectionCard(
            title = "4. 備份與資料安全",
            icon = Icons.Default.Settings,
            points = listOf(
                "在「設定 > 資料安全」匯入或匯出 JSON 備份。",
                "建議定期匯出完整備份；換機時可直接還原。",
                "Gemini API Key 只會保留在本機設定。"
            )
        )

        GuideSectionCard(
            title = "5. 進階功能",
            icon = Icons.Default.Settings,
            points = listOf(
                "代墊追蹤：管理多人分帳、還款進度與入帳帳戶。",
                "預算與超支提醒：按分類管理每月上限。",
                "資料健康檢查：快速找出連結或歷史資料異常。"
            )
        )

        Button(
            onClick = onDone,
            modifier = Modifier
                .fillMaxWidth()
                .height(50.dp),
            shape = RoundedCornerShape(18.dp),
            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
        ) {
            Text(if (isFirstLaunch) "開始使用" else "完成")
        }
    }
}

@Composable
private fun HeroGuideCard() {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.08f)
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                "一個畫面掌握收支、轉帳、借貸與代墊。",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface
            )
            Text(
                "建議流程：先建立帳戶，再開始記帳，最後到報表與設定確認資料。",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun GuideSectionCard(
    title: String,
    icon: ImageVector,
    points: List<String>
) {
    SectionCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Surface(
                modifier = Modifier
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.10f), RoundedCornerShape(14.dp)),
                shape = RoundedCornerShape(14.dp),
                color = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    modifier = Modifier.padding(10.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
            }
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface
            )
        }
        points.forEach { point ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.Top
            ) {
                Text(
                    text = "•",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(top = 1.dp)
                )
                Text(
                    text = point,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}
