import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum RootTab: Hashable {
    case home
    case ledger
    case reports
    case accounts
    case settings
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \RecurringRule.updatedAt, order: .reverse) private var recurringRules: [RecurringRule]
    @Query(sort: \RecurringOccurrence.updatedAt, order: .reverse) private var recurringOccurrences: [RecurringOccurrence]

    @State private var selectedTab: RootTab = .ledger
    @State private var showingAddOptions = false
    @State private var showingAddExpense = false
    @State private var showingAddIncome = false
    @State private var showingAddTransfer = false
    @State private var showingScanReceipt = false
    @State private var showingAddDebt = false
    @State private var showingAddAdvanceCase = false

    @AppStorage("lastBackupDate") private var lastBackupDate: Double = 0
    @AppStorage("enableAutoBackup") private var enableAutoBackup: Bool = true
    @AppStorage("hasSeenUserGuide") private var hasSeenUserGuide: Bool = false

    @State private var idleBackupTask: Task<Void, Never>?
    @State private var showingUserGuide = false
    @State private var initialGuideChecked = false
#if DEBUG
    @State private var uiTestSeeded = false
#endif

    private var recurringSyncToken: Int {
        var hasher = Hasher()
        for rule in recurringRules {
            hasher.combine(rule.id)
            hasher.combine(rule.nextDueDate.timeIntervalSince1970)
            hasher.combine(rule.isPaused)
            hasher.combine(rule.updatedAt.timeIntervalSince1970)
        }
        for occurrence in recurringOccurrences {
            hasher.combine(occurrence.id)
            hasher.combine(occurrence.statusRaw)
            hasher.combine(occurrence.updatedAt.timeIntervalSince1970)
        }
        return hasher.finalize()
    }

    private var isRunningXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["AI_ACCOUNTING_UI_TESTS"] == "1"
            || ProcessInfo.processInfo.arguments.contains("-UITestSeedLedgerPerformanceData")
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                TabView(selection: $selectedTab) {
                    HomeDashboardView(
                        onQuickAdd: {
                            showingAddOptions = true
                        },
                        onOpenGuide: {
                            showingUserGuide = true
                        },
                        onOpenLedger: {
                            selectedTab = .ledger
                        },
                        onOpenReports: {
                            selectedTab = .reports
                        },
                        onOpenAccounts: {
                            selectedTab = .accounts
                        }
                    )
                    .tabItem {
                        Label("總覽", systemImage: "house")
                    }
                    .tag(RootTab.home)

                    TransactionsListView()
                        .tabItem {
                            Label("帳目", systemImage: "list.bullet")
                        }
                        .tag(RootTab.ledger)

                    ChartsView()
                        .tabItem {
                            Label("報表", systemImage: "chart.pie")
                        }
                        .tag(RootTab.reports)

                    AccountsView()
                        .tabItem {
                            Label("帳戶", systemImage: "creditcard")
                        }
                        .tag(RootTab.accounts)

                    SettingsView()
                        .tabItem {
                            Label("設定", systemImage: "gearshape")
                        }
                        .tag(RootTab.settings)
                }
                
                floatingAddButton
                    .padding(.trailing, 18)
                    .padding(.bottom, floatingButtonBottomPadding(safeAreaBottom: proxy.safeAreaInsets.bottom))
            }
        }
        .confirmationDialog("新增內容", isPresented: $showingAddOptions, titleVisibility: .visible) {
            Button("支出") { showingAddExpense = true }
            Button("收入") { showingAddIncome = true }
            Button("掃描收據（AI）") { showingScanReceipt = true }
            Button("轉帳") { showingAddTransfer = true }
            Button("債務管理（借入 / 還款 / 免除債務）") { showingAddDebt = true }
            Button("新增代墊單（多人分帳）") { showingAddAdvanceCase = true }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showingAddExpense) {
            AddTransactionView(initialType: .expense, locksTransactionType: true)
        }
        .sheet(isPresented: $showingAddIncome) {
            AddTransactionView(initialType: .income, locksTransactionType: true)
        }
        .sheet(isPresented: $showingAddTransfer) { AddTransferView() }
        .sheet(isPresented: $showingScanReceipt) { ScanReceiptView() }
        .sheet(isPresented: $showingAddDebt) { AddDebtView() }
        .sheet(isPresented: $showingAddAdvanceCase) { AddAdvanceCaseView() }
        .sheet(isPresented: $showingUserGuide) {
            UserGuideView(isFirstLaunch: !hasSeenUserGuide) {
                hasSeenUserGuide = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloseAddFlow"))) { _ in
            showingScanReceipt = false
            showingAddExpense = false
            showingAddIncome = false
            showingAddTransfer = false
            showingAddDebt = false
            showingAddAdvanceCase = false
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            guard !isRunningXCTest else { return }
            switch newPhase {
            case .active:
                idleBackupTask?.cancel()
                idleBackupTask = nil
                syncRecurringOccurrences()
            case .inactive, .background:
                scheduleIdleAutoBackup()
            @unknown default:
                break
            }
        }
        .onAppear {
            guard !isRunningXCTest else { return }
            guard !initialGuideChecked else { return }
            initialGuideChecked = true
            selectedTab = hasSeenUserGuide ? .ledger : .home
            if !hasSeenUserGuide {
                showingUserGuide = true
            }
        }
#if DEBUG
        .task {
            seedUITestDataIfNeeded()
        }
#endif
        .task(id: recurringSyncToken) {
            guard !isRunningXCTest else { return }
            syncRecurringOccurrences()
        }
    }

    private var floatingAddButton: some View {
        Button(action: { showingAddOptions = true }) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .shadow(color: .blue.opacity(0.25), radius: 10, x: 0, y: 5)

                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel("新增記錄")
        .accessibilityIdentifier("global.addButton")
    }

    private func floatingButtonBottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
        let tabBarClearance: CGFloat = safeAreaBottom > 0 ? 52 : 60
        return safeAreaBottom + tabBarClearance
    }

    private func scheduleIdleAutoBackup() {
        idleBackupTask?.cancel()
        idleBackupTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled, scenePhase != .active else { return }
            BackupManager.shared.performAutoBackup(modelContext: modelContext)
            idleBackupTask = nil
        }
    }

    private func syncRecurringOccurrences() {
        do {
            try RecurringTransactionService.syncDueOccurrences(
                rules: recurringRules,
                occurrences: recurringOccurrences,
                modelContext: modelContext
            )
        } catch {
            print("⚠️ 定期記帳同步失敗: \(error)")
        }
    }

#if DEBUG
    @MainActor
    private func seedUITestDataIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-UITestSeedLedgerPerformanceData") else { return }
        guard !uiTestSeeded else { return }
        uiTestSeeded = true
        selectedTab = .ledger
        UITestSeedService.seedLedgerPerformanceData(in: modelContext)
    }
#endif
}
