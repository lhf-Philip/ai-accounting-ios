package org.duckdns.lhfser.aiaccounting.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.Assessment
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavType
import androidx.navigation.navArgument
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import org.duckdns.lhfser.aiaccounting.ui.components.ParityActionSheetRow
import org.duckdns.lhfser.aiaccounting.ui.components.ParityBottomBar
import org.duckdns.lhfser.aiaccounting.ui.components.ParityBottomBarItem
import org.duckdns.lhfser.aiaccounting.ui.components.ParityFloatingAddButton
import org.duckdns.lhfser.aiaccounting.ui.components.ParitySheetHandle
import org.duckdns.lhfser.aiaccounting.ui.screens.AccountDetailScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.AccountEditorScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.AccountsScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.AddAdvanceCaseScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.AddTransferScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.AdvanceDetailScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.AdvancesScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.BudgetsScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.CategoriesScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.CategoryEditorScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.DataHealthScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.DebtEntryScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.OverviewScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.ReceiptScanScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.ReportsScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.SettingsScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.ShortcutEditorScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.TagEditorScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.TagsScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.TransferEditorScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.TransactionEditorScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.TransactionsScreen
import org.duckdns.lhfser.aiaccounting.ui.screens.UserGuideScreen
import java.util.UUID

private sealed class AppDestination(
    val route: String,
    val label: String,
    val icon: androidx.compose.ui.graphics.vector.ImageVector? = null
) {
    data object Overview : AppDestination("overview", "總覽", Icons.Default.Home)
    data object Transactions : AppDestination("transactions", "帳目", Icons.AutoMirrored.Filled.List)
    data object Reports : AppDestination("reports", "報表", Icons.Default.Assessment)
    data object Accounts : AppDestination("accounts", "帳戶", Icons.Default.AccountBalanceWallet)
    data object Settings : AppDestination("settings", "設定", Icons.Default.Settings)

    data object TransactionAdd : AppDestination("transaction/add", "記一筆")
    data object TransactionEdit : AppDestination("transaction/edit/{transactionId}", "編輯記帳")
    data object TransferAdd : AppDestination("transfer/add", "轉帳")
    data object TransferEdit : AppDestination("transfer/edit/{groupId}", "編輯轉帳")
    data object AdvanceAdd : AppDestination("advance/add", "新增代墊")
    data object AdvanceDetail : AppDestination("advance/{caseId}", "代墊明細")
    data object ReceiptScan : AppDestination("receipt/scan", "掃描單據")
    data object DebtAdd : AppDestination("debt/add", "借貸管理")
    data object AccountDetail : AppDestination("accounts/{accountId}", "帳戶明細")
    data object Guide : AppDestination("guide", "使用教學")

    data object Categories : AppDestination("categories", "分類管理")
    data object CategoryEdit : AppDestination("categories/edit/{categoryId}", "編輯分類")
    data object Tags : AppDestination("tags", "標籤管理")
    data object TagEdit : AppDestination("tags/edit/{tagId}", "編輯標籤")
    data object Budgets : AppDestination("budgets", "預算與提醒")
    data object DataHealth : AppDestination("data-health", "資料健康檢查")
    data object AccountEdit : AppDestination("accounts/edit/{accountId}", "編輯帳戶")
    data object ShortcutEdit : AppDestination("shortcuts/edit/{shortcutId}", "捷徑")
}

private val topLevelDestinations = listOf(
    AppDestination.Overview,
    AppDestination.Transactions,
    AppDestination.Reports,
    AppDestination.Accounts,
    AppDestination.Settings
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AIAccountingRoot(
    startOnOverview: Boolean,
    showUserGuide: Boolean,
    onGuideSeen: () -> Unit
) {
    val navController = rememberNavController()
    val currencyService = LocalCurrencyService.current
    var showAddSheet by remember { mutableStateOf(false) }
    var showGuide by remember { mutableStateOf(showUserGuide) }
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route
    val topLevelRoutes = remember { topLevelDestinations.map { it.route }.toSet() }
    val showTopLevelChrome = currentRoute in topLevelRoutes
    val startDestination = if (startOnOverview) AppDestination.Overview.route else AppDestination.Transactions.route

    LaunchedEffect(currencyService.mainCurrency) {
        currencyService.fetchRates()
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            if (!showTopLevelChrome && currentRoute != null) {
                TopAppBar(
                    title = { Text(text = resolveTitle(backStackEntry), style = MaterialTheme.typography.titleLarge) },
                    navigationIcon = {
                        if (navController.previousBackStackEntry != null) {
                            IconButton(onClick = { navController.popBackStack() }) {
                                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                            }
                        }
                    },
                    actions = {
                        when {
                            currentRoute == AppDestination.Categories.route -> {
                                TextButton(onClick = { navController.navigate("categories/edit/${UUID.randomUUID()}") }) {
                                    Text("新增")
                                }
                            }
                            currentRoute == AppDestination.Tags.route -> {
                                TextButton(onClick = { navController.navigate("tags/edit/${UUID.randomUUID()}") }) {
                                    Text("新增")
                                }
                            }
                        }
                    },
                    windowInsets = TopAppBarDefaults.windowInsets,
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background)
                )
            }
        },
        bottomBar = {
            if (showTopLevelChrome) {
                ParityBottomBar {
                    topLevelDestinations.forEach { destination ->
                        ParityBottomBarItem(
                            modifier = Modifier.weight(1f),
                            selected = currentRoute == destination.route,
                            label = destination.label,
                            icon = destination.icon ?: return@forEach,
                            onClick = {
                                navController.navigate(destination.route) {
                                    launchSingleTop = true
                                    popUpTo(navController.graph.startDestinationId) { saveState = true }
                                    restoreState = true
                                }
                            }
                        )
                    }
                }
            }
        },
        floatingActionButton = {
            if (showTopLevelChrome) {
                ParityFloatingAddButton(onClick = { showAddSheet = true })
            }
        },
        contentWindowInsets = WindowInsets.safeDrawing
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = startDestination,
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            composable(AppDestination.Overview.route) {
                OverviewScreen(
                    onQuickAdd = { showAddSheet = true },
                    onOpenGuide = { showGuide = true },
                    onOpenLedger = {
                        navController.navigate(AppDestination.Transactions.route) {
                            launchSingleTop = true
                            popUpTo(navController.graph.startDestinationId) { saveState = true }
                            restoreState = true
                        }
                    },
                    onOpenReports = {
                        navController.navigate(AppDestination.Reports.route) {
                            launchSingleTop = true
                            popUpTo(navController.graph.startDestinationId) { saveState = true }
                            restoreState = true
                        }
                    },
                    onOpenAccounts = {
                        navController.navigate(AppDestination.Accounts.route) {
                            launchSingleTop = true
                            popUpTo(navController.graph.startDestinationId) { saveState = true }
                            restoreState = true
                        }
                    }
                )
            }
            composable(AppDestination.Transactions.route) {
                TransactionsScreen(
                    onEdit = { id -> navController.navigate("transaction/edit/$id") },
                    onEditTransfer = { groupId -> navController.navigate("transfer/edit/$groupId") },
                    onOpenAdvanceCase = { caseId -> navController.navigate("advance/$caseId") },
                    onAddShortcut = { navController.navigate("shortcuts/edit/${UUID.randomUUID()}") }
                )
            }
            composable(AppDestination.Reports.route) { ReportsScreen() }
            composable(AppDestination.Accounts.route) {
                AccountsScreen(
                    onOpenDetail = { id -> navController.navigate("accounts/$id") },
                    onAddAccount = { navController.navigate("accounts/edit/${UUID.randomUUID()}") }
                )
            }
            composable(AppDestination.Settings.route) {
                SettingsScreen(
                    onOpenGuide = { navController.navigate(AppDestination.Guide.route) },
                    onOpenCategories = { navController.navigate(AppDestination.Categories.route) },
                    onOpenTags = { navController.navigate(AppDestination.Tags.route) },
                    onOpenBudgets = { navController.navigate(AppDestination.Budgets.route) },
                    onOpenAdvances = { navController.navigate("advances") },
                    onOpenHealth = { navController.navigate(AppDestination.DataHealth.route) }
                )
            }

            composable(AppDestination.TransactionAdd.route) {
                TransactionEditorScreen(onDone = { navController.popBackStack() })
            }
            composable(
                AppDestination.TransactionEdit.route,
                arguments = listOf(navArgument("transactionId") { type = NavType.StringType })
            ) { entry ->
                TransactionEditorScreen(
                    transactionId = entry.arguments?.getString("transactionId"),
                    onDone = { navController.popBackStack() }
                )
            }
            composable(AppDestination.TransferAdd.route) {
                AddTransferScreen(onDone = { navController.popBackStack() })
            }
            composable(
                AppDestination.TransferEdit.route,
                arguments = listOf(navArgument("groupId") { type = NavType.StringType })
            ) { entry ->
                TransferEditorScreen(
                    groupId = entry.arguments?.getString("groupId"),
                    onDone = { navController.popBackStack() }
                )
            }
            composable(AppDestination.AdvanceAdd.route) {
                AddAdvanceCaseScreen(onDone = { navController.popBackStack() })
            }
            composable(AppDestination.ReceiptScan.route) {
                ReceiptScanScreen(onDone = { navController.popBackStack() })
            }
            composable(AppDestination.DebtAdd.route) {
                DebtEntryScreen(onDone = { navController.popBackStack() })
            }
            composable("advances") {
                AdvancesScreen(onOpenCase = { caseId -> navController.navigate("advance/$caseId") })
            }
            composable(
                AppDestination.AdvanceDetail.route,
                arguments = listOf(navArgument("caseId") { type = NavType.StringType })
            ) { entry ->
                AdvanceDetailScreen(caseId = entry.arguments?.getString("caseId"))
            }
            composable(AppDestination.Categories.route) {
                CategoriesScreen(onEdit = { id -> navController.navigate("categories/edit/$id") })
            }
            composable(
                AppDestination.CategoryEdit.route,
                arguments = listOf(navArgument("categoryId") { type = NavType.StringType })
            ) { entry ->
                CategoryEditorScreen(
                    categoryId = entry.arguments?.getString("categoryId"),
                    onDone = { navController.popBackStack() }
                )
            }
            composable(AppDestination.Tags.route) {
                TagsScreen(onEdit = { id -> navController.navigate("tags/edit/$id") })
            }
            composable(
                AppDestination.TagEdit.route,
                arguments = listOf(navArgument("tagId") { type = NavType.StringType })
            ) { entry ->
                TagEditorScreen(
                    tagId = entry.arguments?.getString("tagId"),
                    onDone = { navController.popBackStack() }
                )
            }
            composable(AppDestination.Budgets.route) { BudgetsScreen() }
            composable(AppDestination.DataHealth.route) { DataHealthScreen() }
            composable(
                AppDestination.AccountEdit.route,
                arguments = listOf(navArgument("accountId") { type = NavType.StringType })
            ) { entry ->
                AccountEditorScreen(
                    accountId = entry.arguments?.getString("accountId"),
                    onDone = { navController.popBackStack() }
                )
            }
            composable(
                AppDestination.AccountDetail.route,
                arguments = listOf(navArgument("accountId") { type = NavType.StringType })
            ) { entry ->
                AccountDetailScreen(
                    accountId = entry.arguments?.getString("accountId"),
                    onEditAccount = { id -> navController.navigate("accounts/edit/$id") },
                    onEditTransaction = { id -> navController.navigate("transaction/edit/$id") },
                    onEditTransfer = { groupId -> navController.navigate("transfer/edit/$groupId") }
                )
            }
            composable(
                AppDestination.ShortcutEdit.route,
                arguments = listOf(navArgument("shortcutId") { type = NavType.StringType })
            ) { entry ->
                ShortcutEditorScreen(
                    shortcutId = entry.arguments?.getString("shortcutId"),
                    onDone = { navController.popBackStack() }
                )
            }
            composable(AppDestination.Guide.route) {
                Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
                    UserGuideScreen(onDone = { navController.popBackStack() })
                    Spacer(modifier = Modifier.height(20.dp))
                }
            }
        }
    }

    if (showAddSheet) {
        AddActionSheet(
            onDismiss = { showAddSheet = false },
            onAction = { destination ->
                showAddSheet = false
                navController.navigate(destination)
            }
        )
    }

    if (showGuide) {
        val guideSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = {
                showGuide = false
                onGuideSeen()
            },
            sheetState = guideSheetState,
            containerColor = MaterialTheme.colorScheme.background,
            dragHandle = { ParitySheetHandle() }
        ) {
            Column(modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp)) {
                UserGuideScreen(
                    onDone = {
                        showGuide = false
                        onGuideSeen()
                    }
                )
                Spacer(modifier = Modifier.height(24.dp))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddActionSheet(
    onDismiss: () -> Unit,
    onAction: (String) -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.background,
        dragHandle = { ParitySheetHandle() }
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text("新增內容", style = MaterialTheme.typography.titleMedium, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold)
            Text("選擇現在想建立的記錄類型。", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(modifier = Modifier.height(4.dp))
            ParityActionSheetRow(
                title = "記一筆（收入/支出）",
                subtitle = "快速新增收入或支出交易",
                icon = Icons.Default.Description
            ) { onAction(AppDestination.TransactionAdd.route) }
            ParityActionSheetRow(
                title = "掃描收據（AI）",
                subtitle = "上傳照片後由 AI 分析帳單內容",
                icon = Icons.Default.QrCodeScanner
            ) { onAction(AppDestination.ReceiptScan.route) }
            ParityActionSheetRow(
                title = "轉帳",
                subtitle = "處理帳戶之間的資金移動",
                icon = Icons.Default.SwapHoriz
            ) { onAction(AppDestination.TransferAdd.route) }
            ParityActionSheetRow(
                title = "借貸（借入/還款）",
                subtitle = "建立借貸或記錄還款流向",
                icon = Icons.Default.AccountBalanceWallet
            ) { onAction(AppDestination.DebtAdd.route) }
            ParityActionSheetRow(
                title = "新增代墊單（多人分帳）",
                subtitle = "建立多人代墊並追蹤後續還款",
                icon = Icons.Default.Group
            ) { onAction(AppDestination.AdvanceAdd.route) }
            Spacer(modifier = Modifier.height(12.dp))
        }
    }
}

private fun resolveTitle(backStackEntry: NavBackStackEntry?): String {
    val route = backStackEntry?.destination?.route ?: return "AI 記帳"
    return when {
        route.startsWith("transaction/edit") -> "編輯記帳"
        route == AppDestination.TransactionAdd.route -> "記一筆"
        route == AppDestination.TransferAdd.route -> "轉帳"
        route == AppDestination.ReceiptScan.route -> "掃描單據"
        route == AppDestination.DebtAdd.route -> "借貸管理"
        route == AppDestination.AdvanceAdd.route -> "新增代墊"
        route.startsWith("advance/") -> "代墊明細"
        route == AppDestination.Categories.route -> "分類"
        route.startsWith("categories/edit") -> "編輯分類"
        route == AppDestination.Tags.route -> "標籤"
        route.startsWith("tags/edit") -> "編輯標籤"
        route == AppDestination.Budgets.route -> "預算與提醒"
        route == AppDestination.DataHealth.route -> "資料健康檢查"
        route.startsWith("accounts/edit") -> "編輯帳戶"
        route.startsWith("accounts/") -> "帳戶明細"
        route.startsWith("shortcuts/edit") -> "捷徑"
        route == AppDestination.Guide.route -> "使用教學"
        else -> "AI 記帳"
    }
}
