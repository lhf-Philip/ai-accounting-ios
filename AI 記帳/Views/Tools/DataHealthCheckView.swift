import SwiftUI
import SwiftData

struct DataHealthCheckView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var report: HealthReport?
    @State private var isRunning = false
    
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
}
