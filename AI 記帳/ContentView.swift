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

    @State private var selectedTab: RootTab = .ledger
    @State private var showingAddOptions = false
    @State private var showingAddTransaction = false
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
            Button("記一筆（收入/支出）") { showingAddTransaction = true }
            Button("掃描收據（AI）") { showingScanReceipt = true }
            Button("轉帳") { showingAddTransfer = true }
            Button("借貸（借入/還款）") { showingAddDebt = true }
            Button("新增代墊單（多人分帳）") { showingAddAdvanceCase = true }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showingAddTransaction) { AddTransactionView() }
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
            showingAddTransaction = false
            showingAddTransfer = false
            showingAddDebt = false
            showingAddAdvanceCase = false
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            switch newPhase {
            case .active:
                idleBackupTask?.cancel()
                idleBackupTask = nil
            case .inactive, .background:
                scheduleIdleAutoBackup()
            @unknown default:
                break
            }
        }
        .onAppear {
            guard !initialGuideChecked else { return }
            initialGuideChecked = true
            selectedTab = hasSeenUserGuide ? .ledger : .home
            if !hasSeenUserGuide {
                showingUserGuide = true
            }
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
    }

    private func floatingButtonBottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
        let tabBarClearance: CGFloat = safeAreaBottom > 0 ? 58 : 68
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
}
