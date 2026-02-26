import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    
    // UI 狀態
    @State private var selectedTab = 0
    @State private var showingAddOptions = false
    @State private var showingAddTransaction = false
    @State private var showingAddTransfer = false
    @State private var showingScanReceipt = false
    @State private var showingAddDebt = false
    @State private var showingAdvanceTracker = false
    
    // 備份相關狀態
    @AppStorage("lastBackupDate") private var lastBackupDate: Double = 0
    @AppStorage("enableAutoBackup") private var enableAutoBackup: Bool = true
    @State private var isExporting = false
    @State private var exportDocument: CSVDocument?
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                TransactionsListView().tabItem { Label("帳目", systemImage: "list.bullet") }.tag(0)
                ChartsView().tabItem { Label("報表", systemImage: "chart.pie") }.tag(1)
                Text("").tabItem { Image(systemName: "circle.fill").environment(\.symbolVariants, .none) }.tag(2).disabled(true)
                AccountsView().tabItem { Label("帳戶", systemImage: "creditcard") }.tag(3)
                SettingsView().tabItem { Label("設定", systemImage: "gearshape") }.tag(4)
            }
            .onChange(of: selectedTab) { oldValue, newValue in
                if newValue == 2 {
                    selectedTab = oldValue
                    showingAddOptions = true
                }
            }
            
            Button(action: { showingAddOptions = true }) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.blue, Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 60, height: 60)
                        .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                    Image(systemName: "plus")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .offset(y: -5)
            .confirmationDialog("選擇操作", isPresented: $showingAddOptions, titleVisibility: .visible) {
                Button("記一筆 (收入/支出)") { showingAddTransaction = true }
                Button("掃描單據 (AI)") { showingScanReceipt = true }
                Button("轉帳") { showingAddTransfer = true }
                Button("借貸 (借入/還款)") { showingAddDebt = true }
                Button("代墊追蹤 (多人分帳/還款)") { showingAdvanceTracker = true }
                Button("取消", role: .cancel) { }
            }
        }
        .sheet(isPresented: $showingAddTransaction) { AddTransactionView() }
        .sheet(isPresented: $showingAddTransfer) { AddTransferView() }
        .sheet(isPresented: $showingScanReceipt) { ScanReceiptView() }
        .sheet(isPresented: $showingAddDebt) { AddDebtView() } // 這裡現在應該正常了
        .sheet(isPresented: $showingAdvanceTracker) {
            NavigationStack { AdvancesView() }
        }
        
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloseAddFlow"))) { _ in
            showingScanReceipt = false
            showingAddTransaction = false
            showingAddTransfer = false
            showingAddDebt = false
            showingAdvanceTracker = false
        }
        
        .task {
            BackupManager.shared.performAutoBackup(modelContext: modelContext)
        }
    }
}
