import SwiftUI

struct StoreRecoveryView: View {
    let failure: StoreStartupFailure
    let retry: () async -> Void
    @State private var exportedSnapshot: URL?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(failure.stage.title, systemImage: "externaldrive.badge.exclamationmark")
                        .font(.headline)
                    Text("帳目資料尚未開啟。你可以重試，或匯出診斷與已有的備份以便排查。")
                    Button("重試開啟") { Task { await retry() } }
                        .accessibilityIdentifier("storeRecovery.retry")
                }
                Section("診斷資料") {
                    Text(failure.diagnosticText).font(.caption).textSelection(.enabled)
                    ShareLink(item: failure.diagnosticText) { Label("匯出診斷", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("storeRecovery.diagnostics")
                }
                if let backup = failure.backupURL {
                    Section("遷移前備份") {
                        Text(backup.lastPathComponent).font(.caption)
                        Text("這是資料庫快照，須經檢查後才能還原。")
                        if let exportedSnapshot {
                            ShareLink(item: exportedSnapshot) { Label("分享備份檔", systemImage: "square.and.arrow.up") }
                        } else {
                            Button("準備匯出備份") {
                                do { exportedSnapshot = try StoreSnapshotExporter.export(backup) }
                                catch { exportError = error.localizedDescription }
                            }
                        }
                    }
                }
            }
            .navigationTitle("資料復原")
            .accessibilityIdentifier("storeRecovery.screen")
            .alert("匯出失敗", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("好", role: .cancel) { exportError = nil }
            } message: { Text(exportError ?? "") }
        }
    }
}
