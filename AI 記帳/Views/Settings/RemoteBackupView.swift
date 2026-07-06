import SwiftUI
import SwiftData

struct RemoteBackupView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("webdavBackupURL") private var webdavURL: String = ""
    @AppStorage("webdavBackupUsername") private var webdavUsername: String = ""
    @AppStorage("encryptRemoteBackups") private var encryptRemoteBackups = true
    @AppStorage("didConfirmPlainWebDAVBackup") private var didConfirmPlainWebDAVBackup = false

    @State private var webdavPassword: String = ""
    @State private var backupPassphrase: String = ""
    @State private var files: [RemoteBackupFile] = []
    @State private var isBusy = false
    @State private var message: String?
    @State private var preview: RemoteBackupPreview?
    @State private var pendingRestoreBackup: FullBackupData?
    @State private var showingRestoreConfirm = false
    @State private var showingPlainBackupConfirm = false
    @State private var showingHTTPRiskConfirm = false
    @State private var pendingHTTPAction: RemoteAction?

    private let service = RemoteBackupService.shared
    private let keychainServiceName = "org.duckdns.lhfser.AIMoney.webdav"
    private let passwordAccountName = "webdav_password"
    private let passphraseAccountName = "backup_passphrase"

    private enum RemoteAction {
        case testConnection
        case uploadBackup
        case refreshList
        case loadPreview(RemoteBackupFile)
    }

    var body: some View {
        List {
            Section("WebDAV 連線") {
                TextField("WebDAV URL", text: $webdavURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                TextField("帳戶", text: $webdavUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                SecureField("WebDAV 密碼", text: $webdavPassword)
                Toggle("加密遠端備份（建議）", isOn: $encryptRemoteBackups)
                SecureField(
                    encryptRemoteBackups ? "備份加密 passphrase" : "加密 passphrase（還原加密備份時需要）",
                    text: $backupPassphrase
                )
                Text(encryptRemoteBackups ? "上傳會使用 AES-GCM 加密，檔案副檔名為 .aibackup。" : "未加密備份會以 .json 上傳，雲端可直接讀取你的財務資料。")
                    .font(.caption)
                    .foregroundStyle(encryptRemoteBackups ? Color.secondary : Color.orange)
                Button {
                    saveSecrets()
                    perform(.testConnection)
                } label: {
                    Label("測試連線", systemImage: "network")
                }
                .disabled(isBusy || !canConnect)
            }

            Section("遠端備份") {
                Button {
                    saveSecrets()
                    requestUploadBackup()
                } label: {
                    Label(encryptRemoteBackups ? "加密並上傳目前備份" : "未加密上傳目前備份", systemImage: "icloud.and.arrow.up")
                }
                .disabled(isBusy || !canUpload)

                Button {
                    saveSecrets()
                    perform(.refreshList)
                } label: {
                    Label("重新載入遠端備份", systemImage: "arrow.clockwise")
                }
                .disabled(isBusy || !canConnect)

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("遠端檔案") {
                if files.isEmpty {
                    Text("尚未載入遠端備份。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(files) { file in
                        Button {
                            loadPreview(file)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name)
                                        .foregroundStyle(.primary)
                                    Text(file.format.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(file.format == .plainJSON ? Color.orange : Color.secondary)
                                    if let size = file.size {
                                        Text("\(size) bytes")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isBusy)
                    }
                }
            }

            if let preview {
                Section(preview.title) {
                    Text(preview.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("確認還原此備份") {
                        showingRestoreConfirm = true
                    }
                    .disabled(pendingRestoreBackup == nil || isBusy)
                }
            }
        }
        .standardKeyboardBehavior()
        .navigationTitle("WebDAV 遠端備份")
        .onAppear(perform: loadSecrets)
        .alert("還原遠端備份？", isPresented: $showingRestoreConfirm) {
            Button("取消", role: .cancel) {}
            Button("還原", role: .destructive) {
                restorePendingBackup()
            }
        } message: {
            Text("這會以遠端備份覆蓋目前資料庫。建議先確認你已有本地備份。")
        }
        .alert("上傳未加密備份？", isPresented: $showingPlainBackupConfirm) {
            Button("取消", role: .cancel) {}
            Button("未加密上傳", role: .destructive) {
                didConfirmPlainWebDAVBackup = true
                perform(.uploadBackup)
            }
        } message: {
            Text("未加密 JSON 會包含帳戶、交易、備註、分類和標籤等資料。只有在你信任這個雲端儲存位置時才建議使用。")
        }
        .alert("HTTP 連線不安全", isPresented: $showingHTTPRiskConfirm) {
            Button("取消", role: .cancel) {
                pendingHTTPAction = nil
            }
            Button("仍然繼續", role: .destructive) {
                let action = pendingHTTPAction
                pendingHTTPAction = nil
                if let action {
                    perform(action, allowInsecureHTTP: true)
                }
            }
        } message: {
            Text(encryptRemoteBackups ? "目前 WebDAV URL 使用 http://，傳輸途中可能被讀取或竄改。確定要繼續？" : "目前 WebDAV URL 使用 http://，而且你正在使用未加密備份；傳輸途中和雲端上都可能暴露財務資料。確定要繼續？")
        }
    }

    private var canConnect: Bool {
        !webdavURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !webdavUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !webdavPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasPassphrase: Bool {
        !backupPassphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canUpload: Bool {
        canConnect && (!encryptRemoteBackups || hasPassphrase)
    }

    private func loadSecrets() {
        webdavPassword = KeychainService.shared.read(service: keychainServiceName, account: passwordAccountName) ?? ""
        backupPassphrase = KeychainService.shared.read(service: keychainServiceName, account: passphraseAccountName) ?? ""
    }

    private func saveSecrets() {
        _ = KeychainService.shared.save(service: keychainServiceName, account: passwordAccountName, value: webdavPassword)
        _ = KeychainService.shared.save(service: keychainServiceName, account: passphraseAccountName, value: backupPassphrase)
    }

    private func credentials(requirePassphrase: Bool = false) throws -> WebDAVCredentials {
        guard let url = URL(string: webdavURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw RemoteBackupError.invalidURL
        }
        guard canConnect else {
            throw RemoteBackupError.invalidCredentials
        }
        guard !requirePassphrase || hasPassphrase else {
            throw RemoteBackupError.missingPassphrase
        }
        return WebDAVCredentials(
            baseURL: url,
            username: webdavUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            password: webdavPassword.trimmingCharacters(in: .whitespacesAndNewlines),
            passphrase: backupPassphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func requestUploadBackup() {
        if !encryptRemoteBackups, !didConfirmPlainWebDAVBackup {
            showingPlainBackupConfirm = true
            return
        }
        perform(.uploadBackup)
    }

    private func perform(_ action: RemoteAction, allowInsecureHTTP: Bool = false) {
        guard canConnect else {
            message = RemoteBackupError.invalidCredentials.localizedDescription
            return
        }
        if !allowInsecureHTTP, isInsecureHTTP {
            pendingHTTPAction = action
            showingHTTPRiskConfirm = true
            return
        }

        switch action {
        case .testConnection:
            run("連線測試成功") {
                try await service.testConnection(credentials: credentials())
            }
        case .uploadBackup:
            uploadBackup()
        case .refreshList:
            refreshList()
        case .loadPreview(let file):
            loadPreview(file)
        }
    }

    private var isInsecureHTTP: Bool {
        webdavURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("http://")
    }

    private func uploadBackup() {
        let shouldEncrypt = encryptRemoteBackups
        run(shouldEncrypt ? "加密上傳完成" : "未加密上傳完成") {
            let backup = await MainActor.run {
                BackupManager.shared.createBackupData(modelContext: modelContext)
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(backup)
            _ = try await service.uploadBackup(jsonData: data, credentials: credentials(requirePassphrase: shouldEncrypt), encrypt: shouldEncrypt)
            let remoteFiles = try await service.listBackups(credentials: credentials())
            await MainActor.run {
                files = remoteFiles
            }
        }
    }

    private func refreshList() {
        run("已載入遠端備份") {
            let remoteFiles = try await service.listBackups(credentials: credentials())
            await MainActor.run {
                files = remoteFiles
            }
        }
    }

    private func loadPreview(_ file: RemoteBackupFile) {
        run("已下載並讀取備份") {
            let data = try await service.downloadBackup(file, credentials: credentials(requirePassphrase: file.format == .encrypted))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let backup = try decoder.decode(FullBackupData.self, from: data)
            let nextPreview = service.makePreview(from: backup)
            await MainActor.run {
                pendingRestoreBackup = backup
                preview = nextPreview
            }
        }
    }

    private func restorePendingBackup() {
        guard let pendingRestoreBackup else { return }
        do {
            let summary = try BackupManager.shared.restoreBackupData(pendingRestoreBackup, modelContext: modelContext, replaceExisting: true)
            message = """
            已完成遠端備份還原。
            \(summary.localizedSummary)
            """
        } catch {
            message = "還原失敗：\(error.localizedDescription)"
        }
    }

    private func run(_ successMessage: String, operation: @escaping () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        message = "處理中..."
        Task {
            do {
                try await operation()
                await MainActor.run {
                    message = successMessage
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    message = "失敗：\(error.localizedDescription)"
                    isBusy = false
                }
            }
        }
    }
}
