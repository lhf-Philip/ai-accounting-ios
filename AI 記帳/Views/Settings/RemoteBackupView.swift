import SwiftUI
import SwiftData

struct RemoteBackupView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("webdavBackupURL") private var webdavURL: String = ""
    @AppStorage("webdavBackupUsername") private var webdavUsername: String = ""

    @State private var webdavPassword: String = ""
    @State private var backupPassphrase: String = ""
    @State private var files: [RemoteBackupFile] = []
    @State private var isBusy = false
    @State private var message: String?
    @State private var preview: RemoteBackupPreview?
    @State private var pendingRestoreBackup: FullBackupData?
    @State private var showingRestoreConfirm = false

    private let service = RemoteBackupService.shared
    private let keychainServiceName = "org.duckdns.lhfser.AIMoney.webdav"
    private let passwordAccountName = "webdav_password"
    private let passphraseAccountName = "backup_passphrase"

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
                SecureField("備份加密 passphrase", text: $backupPassphrase)
                Button {
                    saveSecrets()
                    run("連線測試成功") {
                        try await service.testConnection(credentials: credentials())
                    }
                } label: {
                    Label("測試連線", systemImage: "network")
                }
                .disabled(isBusy || !canUseRemoteBackup)
            }

            Section("遠端備份") {
                Button {
                    saveSecrets()
                    uploadBackup()
                } label: {
                    Label("加密並上傳目前備份", systemImage: "icloud.and.arrow.up")
                }
                .disabled(isBusy || !canUseRemoteBackup)

                Button {
                    saveSecrets()
                    refreshList()
                } label: {
                    Label("重新載入遠端備份", systemImage: "arrow.clockwise")
                }
                .disabled(isBusy || !canUseRemoteBackup)

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
    }

    private var canUseRemoteBackup: Bool {
        !webdavURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !webdavUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !webdavPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !backupPassphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadSecrets() {
        webdavPassword = KeychainService.shared.read(service: keychainServiceName, account: passwordAccountName) ?? ""
        backupPassphrase = KeychainService.shared.read(service: keychainServiceName, account: passphraseAccountName) ?? ""
    }

    private func saveSecrets() {
        _ = KeychainService.shared.save(service: keychainServiceName, account: passwordAccountName, value: webdavPassword)
        _ = KeychainService.shared.save(service: keychainServiceName, account: passphraseAccountName, value: backupPassphrase)
    }

    private func credentials() throws -> WebDAVCredentials {
        guard let url = URL(string: webdavURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw RemoteBackupError.invalidURL
        }
        guard canUseRemoteBackup else {
            throw RemoteBackupError.invalidCredentials
        }
        return WebDAVCredentials(
            baseURL: url,
            username: webdavUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            password: webdavPassword.trimmingCharacters(in: .whitespacesAndNewlines),
            passphrase: backupPassphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func uploadBackup() {
        run("上傳完成") {
            let backup = await MainActor.run {
                BackupManager.shared.createBackupData(modelContext: modelContext)
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(backup)
            _ = try await service.uploadBackup(jsonData: data, credentials: credentials())
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
        run("已下載並解密備份") {
            let data = try await service.downloadBackup(file, credentials: credentials())
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
            try BackupManager.shared.restoreBackupData(pendingRestoreBackup, modelContext: modelContext, replaceExisting: true)
            message = "已完成遠端備份還原。"
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
