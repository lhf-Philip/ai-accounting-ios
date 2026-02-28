import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryMonthlyBudget.monthKey, order: .reverse) private var budgets: [CategoryMonthlyBudget]
    @Query(sort: \FinancialTransaction.date, order: .reverse) private var transactions: [FinancialTransaction]
    @StateObject private var currencyService = CurrencyService.shared
    @AppStorage("mainCurrency") private var mainCurrency: String = "HKD"
    @AppStorage("UserGeminiAPIKey") private var legacyApiKey: String = ""
    @AppStorage("enableAutoBackup") private var enableAutoBackup: Bool = false
    @AppStorage("lastBackupDate") private var lastBackupDate: Double = 0
    @AppStorage("backupRetentionDays") private var backupRetentionDays: Int = 30
    
    // 狀態變數
    @State private var isExportingJSON = false
    @State private var isImportingJSON = false
    @State private var isExportingCSV = false
    @State private var jsonDocument: JSONDocument?
    @State private var csvDocument: CSVDocument?
    
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingDeleteAlert = false
    @State private var showingImportRepairPrompt = false
    @State private var apiKey: String = ""
    
    let currencies = ["HKD", "TWD", "USD", "JPY", "CNY", "EUR", "GBP"]
    private let keychainServiceName = "org.duckdns.lhfser.AIMoney"
    private let keychainAccountName = "gemini_api_key"
    
    private var monthlyBudgetAlerts: [BudgetStatus] {
        let key = BudgetService.monthKey(from: Date())
        return BudgetService.statuses(for: key, budgets: budgets, transactions: transactions, currencyService: currencyService)
            .filter { $0.ratio >= 1 }
    }
    
    // MARK: - 精確倒數計時邏輯
    struct TimeLeftInfo {
        let text: String
        let percentage: Double
        let isCritical: Bool
    }
    
    private func calculateTimeLeft(currentDate: Date) -> TimeLeftInfo {
        let url = Bundle.main.executableURL ?? Bundle.main.bundleURL
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let creation = attributes?[.creationDate] as? Date ?? Date.distantPast
        let modification = attributes?[.modificationDate] as? Date ?? Date.distantPast
        let installDate = creation > modification ? creation : modification
        
        guard let expireDate = Calendar.current.date(byAdding: .day, value: 7, to: installDate) else {
            return TimeLeftInfo(text: "無法計算", percentage: 0, isCritical: false)
        }
        
        let interval = expireDate.timeIntervalSince(currentDate)
        if interval <= 0 {
            return TimeLeftInfo(text: "已過期", percentage: 0, isCritical: true)
        }
        
        let totalSeconds = Int(interval)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        let text = "\(days)天 \(hours)時 \(minutes)分 \(seconds)秒"
        let percentage = interval / (7 * 24 * 3600)
        let isCritical = days < 1
        
        return TimeLeftInfo(text: text, percentage: percentage, isCritical: isCritical)
    }
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - App 有效期
                Section("App 有效期") {
                    TimelineView(.periodic(from: .now, by: 1.0)) { context in
                        let info = calculateTimeLeft(currentDate: context.date)
                        
                        VStack(spacing: 8) {
                            HStack {
                                Text("剩餘時間")
                                Spacer()
                                Text(info.text)
                                    .font(.headline)
                                    .monospacedDigit()
                                    .foregroundStyle(info.isCritical ? .red : .green)
                            }
                            ProgressView(value: info.percentage, total: 1.0)
                                .tint(info.isCritical ? .red : .blue)
                        }
                    }
                    Text("重裝後時間自動更新 (需 Clean Build)。").font(.caption2).foregroundStyle(.secondary)
                }
                
                // MARK: - AI 設定
                Section("AI 設定") {
                    SecureField("Gemini API Key", text: $apiKey)
                        .textContentType(.password)
                        .onChange(of: apiKey, initial: false) { _, newValue in
                            saveAPIKey(newValue)
                        }
                        .onSubmit { hideKeyboard() }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
                
                // MARK: - 數據備份與還原
                Section("數據管理") {
                    // 自動備份設定
                    Button(action: {
                        BackupManager.shared.pickFolderAndSavePermission { success in
                            if success { alertMessage = "✅ 資料夾設定成功"; showingAlert = true }
                        }
                    }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("設定自動備份資料夾").foregroundStyle(.primary)
                                Text(enableAutoBackup ? "✅ 已開啟" : "⚠️ 未設定").font(.caption).foregroundStyle(enableAutoBackup ? .green : .red)
                            }
                            Spacer()
                            Image(systemName: "folder.badge.gear")
                        }
                    }
                    
                    Stepper("保留最近 \(backupRetentionDays) 天的備份", value: $backupRetentionDays, in: 7...365)
                    
                    // JSON 全機備份 (推薦)
                    Button {
                        let data = BackupManager.shared.createBackupData(modelContext: modelContext)
                        do {
                            let encoder = JSONEncoder()
                            encoder.outputFormatting = .prettyPrinted
                            encoder.dateEncodingStrategy = .iso8601
                            let encoded = try encoder.encode(data)
                            if let text = String(data: encoded, encoding: .utf8) {
                                jsonDocument = JSONDocument(text: text)
                                isExportingJSON = true
                            }
                        } catch {
                            print("JSON 備份失敗: \(error)")
                            alertMessage = "備份失敗: \(error.localizedDescription)"
                            showingAlert = true
                        }
                    } label: { Label("全機備份 (JSON)", systemImage: "arrow.up.doc") }
                    .fileExporter(isPresented: $isExportingJSON, document: jsonDocument, contentType: .json, defaultFilename: "Backup.json") { _ in }
                    
                    // JSON 全機還原
                    Button {
                        isImportingJSON = true
                    } label: { Label("全機還原 (JSON)", systemImage: "arrow.down.doc") }
                    .fileImporter(isPresented: $isImportingJSON, allowedContentTypes: [.json]) { res in handleImport(result: res) }
                    
                    // CSV 匯出 (Excel 用)
                    Button {
                        let csv = BackupManager.shared.generateCSV(modelContext: modelContext)
                        csvDocument = CSVDocument(text: csv)
                        isExportingCSV = true
                    } label: { Label("匯出報表 (CSV) - Excel 用", systemImage: "tablecells") }
                    .fileExporter(isPresented: $isExportingCSV, document: csvDocument, contentType: .commaSeparatedText, defaultFilename: "Report.csv") { _ in }
                }
                
                // MARK: - 其他設定
                Section("偏好設定") {
                    Button("更改語言 (系統設定)") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    Picker("主要貨幣", selection: $mainCurrency) {
                        ForEach(currencies, id: \.self) { code in Text(code).tag(code) }
                    }
                    .onChange(of: mainCurrency, initial: false) { _, _ in
                        Task { await CurrencyService.shared.fetchRates() }
                    }
                }
                
                Section("資料管理") {
                    NavigationLink(destination: CategoriesView()) { Label("分類管理", systemImage: "list.bullet") }
                    NavigationLink(destination: TagsView()) { Label("標籤管理", systemImage: "tag") }
                    NavigationLink(destination: AdvancesView()) {
                        Label("代墊追蹤", systemImage: "person.2.fill")
                    }
                    NavigationLink(destination: BudgetsView()) {
                        Label("預算與超支提醒", systemImage: "chart.bar.doc.horizontal")
                    }
                    NavigationLink(destination: DataHealthCheckView()) {
                        Label("資料健康檢查", systemImage: "stethoscope")
                    }
                }
                
                if !monthlyBudgetAlerts.isEmpty {
                    Section("本月超支提醒") {
                        ForEach(monthlyBudgetAlerts) { status in
                            HStack {
                                Text(status.budget.category?.name ?? "未分類")
                                Spacer()
                                Text("超支 \(abs(status.remaining).formatted(.currency(code: status.budget.currencyCode)))")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                        }
                    }
                }
                
                Section {
                    Button("清除所有資料", role: .destructive) { showingDeleteAlert = true }
                }
            }
            .navigationTitle("設定")
            
            .alert("提示", isPresented: $showingAlert) { Button("好") {} } message: { Text(alertMessage) }
            .alert("匯入完成", isPresented: $showingImportRepairPrompt) {
                Button("稍後") {
                    alertMessage = "匯入成功！可稍後到「資料健康檢查」執行修復工具。"
                    showingAlert = true
                }
                Button("立即修復") {
                    repairLegacyAdvanceLinksAfterImport()
                }
            } message: {
                Text("是否立即修復舊代墊資料連結？建議匯入舊版 JSON 後執行一次。")
            }
            .alert("確定清除？", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) {}
                Button("確定", role: .destructive) {
                    deleteAllData()
                    alertMessage = "資料已清除"
                    showingAlert = true
                }
            }
            .onAppear { loadAPIKey() }
        }
    }
    
    private func loadAPIKey() {
        if let keychainValue = KeychainService.shared.read(service: keychainServiceName, account: keychainAccountName),
           !keychainValue.isEmpty {
            apiKey = keychainValue
            return
        }
        
        let legacy = legacyApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !legacy.isEmpty else { return }
        
        if KeychainService.shared.save(service: keychainServiceName, account: keychainAccountName, value: legacy) {
            legacyApiKey = ""
        }
        apiKey = legacy
    }
    
    private func saveAPIKey(_ rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if value.isEmpty {
            _ = KeychainService.shared.delete(service: keychainServiceName, account: keychainAccountName)
        } else if !KeychainService.shared.save(service: keychainServiceName, account: keychainAccountName, value: value) {
            alertMessage = "無法儲存 API Key 至 Keychain"
            showingAlert = true
        }
        
        if !legacyApiKey.isEmpty {
            legacyApiKey = ""
        }
    }
    
    private func handleImport(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                alertMessage = "無法獲取檔案權限"
                showingAlert = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                try BackupManager.shared.restoreFromJSON(url: url, modelContext: modelContext)
                showingImportRepairPrompt = true
            } catch {
                alertMessage = "失敗：\(error.localizedDescription)"
                showingAlert = true
            }
        case .failure(let error):
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }
    
    private func repairLegacyAdvanceLinksAfterImport() {
        do {
            let result = try AdvanceService.repairLegacyLinks(modelContext: modelContext)
            alertMessage = """
            匯入成功並完成修復。
            已更新 \(result.totalUpdated) 筆連結。
            - 代墊主檔：修復 \(result.updatedCaseLinkCount) / 未修復 \(result.unresolvedCaseLinkCount)
            - 代墊對象：修復 \(result.updatedParticipantLinkCount) / 未修復 \(result.unresolvedParticipantLinkCount)
            """
        } catch {
            alertMessage = "匯入成功，但修復失敗：\(error.localizedDescription)"
        }
        showingAlert = true
    }
    
    private func deleteAllData() {
        do {
            try modelContext.delete(model: FinancialTransaction.self)
            try modelContext.delete(model: Account.self)
            try modelContext.delete(model: Category.self)
            try modelContext.delete(model: Tag.self)
            try modelContext.delete(model: Shortcut.self)
            try modelContext.delete(model: CategoryMonthlyBudget.self)
            try modelContext.delete(model: AdvanceRepayment.self)
            try modelContext.delete(model: AdvanceParticipant.self)
            try modelContext.delete(model: AdvanceCase.self)
            try modelContext.save()
        } catch {
            print("清除失敗: \(error)")
        }
    }
}

// ... Documents & Extension ...
struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents { text = String(decoding: data, as: UTF8.self) } else { text = "" }
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: text.data(using: .utf8)!)
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents { text = String(decoding: data, as: UTF8.self) } else { text = "" }
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: text.data(using: .utf8)!)
    }
}

#if canImport(UIKit)
extension View {
    func hideKeyboard() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
}
#endif
