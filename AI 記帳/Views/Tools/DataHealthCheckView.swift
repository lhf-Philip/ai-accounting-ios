import SwiftUI
import SwiftData

struct DataHealthCheckView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var report: HealthReport?
    @State private var isRunning = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        List {
            Section("檢查摘要") {
                if let report {
                    summaryView(report)
                } else {
                    Text("尚未執行檢查")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("修復工具") {
                Button(isRunning ? "處理中..." : "修復代墊舊資料連結") {
                    repairAdvanceLegacyLinks()
                }
                .disabled(isRunning)
                
                Text("補齊舊資料缺少的連結欄位，讓整單連動刪除可更完整刪除相關交易。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if let report {
                issuesSection("錯誤", severity: .error, report: report)
                issuesSection("警告", severity: .warning, report: report)
                issuesSection("資訊", severity: .info, report: report)
            }
        }
        .navigationTitle("資料健康檢查")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isRunning ? "檢查中..." : "重新檢查") {
                    runCheck()
                }
                .disabled(isRunning)
            }
        }
        .onAppear {
            if report == nil {
                runCheck()
            }
        }
        .alert("處理結果", isPresented: $showingAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }
    
    @ViewBuilder
    private func summaryView(_ report: HealthReport) -> some View {
        let dateText: String = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter.string(from: report.generatedAt)
        }()
        
        VStack(alignment: .leading, spacing: 8) {
            Text("最後檢查：\(dateText)")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 12) {
                summaryBadge(title: "錯誤", count: report.errorCount, color: .red)
                summaryBadge(title: "警告", count: report.warningCount, color: .orange)
                summaryBadge(title: "資訊", count: report.infoCount, color: .blue)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func summaryBadge(title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.headline)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    @ViewBuilder
    private func issuesSection(_ title: String, severity: HealthSeverity, report: HealthReport) -> some View {
        let items = report.issues.filter { $0.severity == severity }
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.body)
                            .fontWeight(.semibold)
                        Text(item.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("建議：\(item.recommendation)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    private func runCheck() {
        isRunning = true
        report = DataHealthCheckService.run(modelContext: modelContext)
        isRunning = false
    }
    
    private func repairAdvanceLegacyLinks() {
        isRunning = true
        
        do {
            let result = try AdvanceService.repairLegacyLinks(modelContext: modelContext)
            report = DataHealthCheckService.run(modelContext: modelContext)
            
            alertMessage = """
            已更新 \(result.totalUpdated) 筆連結。
            - 代墊主檔：修復 \(result.updatedCaseLinkCount) / 未修復 \(result.unresolvedCaseLinkCount)
            - 代墊對象：修復 \(result.updatedParticipantLinkCount) / 未修復 \(result.unresolvedParticipantLinkCount)
            """
        } catch {
            alertMessage = "修復失敗：\(error.localizedDescription)"
        }
        
        isRunning = false
        showingAlert = true
    }
}
