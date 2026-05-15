import SwiftUI
import SwiftData

struct DataHealthCheckView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FinancialTransaction.date, order: .reverse) private var transactions: [FinancialTransaction]
    @Query(sort: \Shortcut.name) private var shortcuts: [Shortcut]
    
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

                Button(isRunning ? "處理中..." : "修復他人代墊我舊帳務") {
                    repairLegacyBorrowedAdvanceAccountInflation()
                }
                .disabled(isRunning)
                
                Text("移除舊版他人代墊我誤寫入自己帳戶的入帳，改為借貸帳戶支出。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            legacyDebtIncomeSection
            
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
    private var legacyDebtIncomeSection: some View {
        let legacyTransactions = LegacyDebtIncomeRepairService.legacyDebtIncomeTransactions(from: transactions)
        let legacyShortcuts = LegacyDebtIncomeRepairService.legacyDebtIncomeShortcuts(from: shortcuts)

        if !legacyTransactions.isEmpty || !legacyShortcuts.isEmpty {
            Section("收入 / 借貸清理") {
                if !legacyTransactions.isEmpty {
                    Button(isRunning ? "處理中..." : "全部轉成免除債務 (\(legacyTransactions.count))") {
                        convertAllLegacyDebtIncomeTransactions(legacyTransactions)
                    }
                    .disabled(isRunning)

                    ForEach(legacyTransactions) { transaction in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(transaction.account?.name ?? "未指定借貸帳戶")
                                .font(.headline)
                            Text(transaction.amount.formatted(.currency(code: transaction.currencyCode)))
                                .font(.subheadline)
                            Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(transaction.note.isEmpty ? "沒有備註" : transaction.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("轉成免除債務") {
                                convertLegacyDebtIncomeTransaction(transaction)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRunning)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if !legacyShortcuts.isEmpty {
                    Button(isRunning ? "處理中..." : "清除收入捷徑的借貸帳戶綁定 (\(legacyShortcuts.count))") {
                        detachAllLegacyDebtIncomeShortcuts(legacyShortcuts)
                    }
                    .disabled(isRunning)

                    ForEach(legacyShortcuts) { shortcut in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(shortcut.icon) \(shortcut.name)")
                                .font(.headline)
                            Text("目前綁定：\(shortcut.account?.name ?? "未指定帳戶")")
                                .font(.subheadline)
                            Text("金額：\(shortcut.amount.formatted(.currency(code: shortcut.currencyCode)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("移除借貸帳戶綁定") {
                                detachLegacyDebtIncomeShortcut(shortcut)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning)
                        }
                        .padding(.vertical, 4)
                    }
                }
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

    private func repairLegacyBorrowedAdvanceAccountInflation() {
        isRunning = true

        do {
            let result = try AdvanceService.repairLegacyBorrowedAdvanceAccountInflation(modelContext: modelContext)
            report = DataHealthCheckService.run(modelContext: modelContext)
            alertMessage = """
            已修復 \(result.repairedParticipantCount) 位代墊對象。
            已移除 \(result.removedInflatedAccountTransactionCount) 筆誤寫入自己帳戶的入帳。
            """
        } catch {
            alertMessage = "修復失敗：\(error.localizedDescription)"
        }

        isRunning = false
        showingAlert = true
    }

    private func convertLegacyDebtIncomeTransaction(_ transaction: FinancialTransaction) {
        isRunning = true
        do {
            guard LegacyDebtIncomeRepairService.convertLegacyDebtIncomeTransaction(transaction, modelContext: modelContext) else {
                alertMessage = "這筆資料已經不是舊版收入 / 借貸異常紀錄。"
                showingAlert = true
                isRunning = false
                return
            }
            try modelContext.save()
            report = DataHealthCheckService.run(modelContext: modelContext)
            alertMessage = "已把這筆資料轉成免除債務。"
        } catch {
            alertMessage = "轉換失敗：\(error.localizedDescription)"
        }
        isRunning = false
        showingAlert = true
    }

    private func convertAllLegacyDebtIncomeTransactions(_ transactions: [FinancialTransaction]) {
        isRunning = true
        do {
            let converted = try LegacyDebtIncomeRepairService.convertLegacyDebtIncomeTransactions(
                transactions,
                modelContext: modelContext
            )
            report = DataHealthCheckService.run(modelContext: modelContext)
            alertMessage = "已把 \(converted) 筆舊版收入 / 借貸紀錄轉成免除債務。"
        } catch {
            alertMessage = "批量轉換失敗：\(error.localizedDescription)"
        }
        isRunning = false
        showingAlert = true
    }

    private func detachLegacyDebtIncomeShortcut(_ shortcut: Shortcut) {
        isRunning = true
        do {
            guard LegacyDebtIncomeRepairService.detachLegacyDebtIncomeShortcut(shortcut, modelContext: modelContext) else {
                alertMessage = "這個捷徑已經不是舊版收入 / 借貸異常綁定。"
                showingAlert = true
                isRunning = false
                return
            }
            try modelContext.save()
            report = DataHealthCheckService.run(modelContext: modelContext)
            alertMessage = "已移除這個收入捷徑的借貸帳戶綁定。"
        } catch {
            alertMessage = "清理失敗：\(error.localizedDescription)"
        }
        isRunning = false
        showingAlert = true
    }

    private func detachAllLegacyDebtIncomeShortcuts(_ shortcuts: [Shortcut]) {
        isRunning = true
        do {
            let detached = try LegacyDebtIncomeRepairService.detachLegacyDebtIncomeShortcuts(
                shortcuts,
                modelContext: modelContext
            )
            report = DataHealthCheckService.run(modelContext: modelContext)
            alertMessage = "已清除 \(detached) 個收入捷徑的借貸帳戶綁定。"
        } catch {
            alertMessage = "批量清理失敗：\(error.localizedDescription)"
        }
        isRunning = false
        showingAlert = true
    }
}
