import Foundation
import CryptoKit
import CommonCrypto

struct WebDAVCredentials {
    let baseURL: URL
    let username: String
    let password: String
    let passphrase: String

    var hasPassphrase: Bool {
        !passphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum RemoteBackupFormat: String, Hashable {
    case encrypted
    case plainJSON
    case unknown

    var displayName: String {
        switch self {
        case .encrypted:
            "已加密"
        case .plainJSON:
            "未加密"
        case .unknown:
            "未知格式"
        }
    }
}

struct RemoteBackupFile: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
    let size: Int?
    let modifiedAt: Date?
    let format: RemoteBackupFormat
}

struct RemoteBackupPreview {
    let title: String
    let detail: String
}

private struct EncryptedBackupEnvelope: Codable {
    let formatVersion: Int
    let algorithm: String
    let createdAt: Date
    let salt: String
    let iv: String
    let ciphertext: String
    let tagBits: Int
}

enum RemoteBackupError: LocalizedError {
    case invalidURL
    case invalidCredentials
    case missingPassphrase
    case invalidResponse
    case httpStatus(Int)
    case invalidEnvelope
    case unsupportedBackupFormat
    case decryptFailed
    case keyDerivationFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "WebDAV URL 無效。"
        case .invalidCredentials:
            "請先填寫 WebDAV URL、帳戶與密碼。"
        case .missingPassphrase:
            "此操作需要加密 passphrase。"
        case .invalidResponse:
            "WebDAV 回應無效。"
        case .httpStatus(let status):
            "WebDAV 回應錯誤：HTTP \(status)。"
        case .invalidEnvelope:
            "遠端備份格式無效。"
        case .unsupportedBackupFormat:
            "遠端備份格式不支援。"
        case .decryptFailed:
            "無法解密備份，請確認 passphrase 是否正確。"
        case .keyDerivationFailed:
            "無法建立備份加密金鑰。"
        }
    }
}

final class RemoteBackupService {
    static let shared = RemoteBackupService()

    private let backupExtension = "aibackup"
    private let plainBackupExtension = "json"
    private let keyDerivationIterations: UInt32 = 120_000
    private let gcmTagByteCount = 16

    private init() {}

    func testConnection(credentials: WebDAVCredentials) async throws {
        var request = try makeRequest(credentials: credentials, url: credentials.baseURL)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.httpBody = propfindBody()
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, accepted: [200, 207])
    }

    func listBackups(credentials: WebDAVCredentials) async throws -> [RemoteBackupFile] {
        var request = try makeRequest(credentials: credentials, url: credentials.baseURL)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.httpBody = propfindBody()
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, accepted: [200, 207])
        let xml = String(decoding: data, as: UTF8.self)
        return parseBackupFiles(from: xml, baseURL: credentials.baseURL)
    }

    func uploadBackup(jsonData: Data, credentials: WebDAVCredentials, encrypt shouldEncrypt: Bool) async throws -> RemoteBackupFile {
        if shouldEncrypt, !credentials.hasPassphrase {
            throw RemoteBackupError.missingPassphrase
        }

        let payload = shouldEncrypt ? try encrypt(jsonData, passphrase: credentials.passphrase) : jsonData
        let fileExtension = shouldEncrypt ? backupExtension : plainBackupExtension
        let filename = "AIAccounting_Backup_\(Self.filenameDateFormatter.string(from: Date())).\(fileExtension)"
        let targetURL = credentials.baseURL.appendingPathComponent(filename)
        var request = try makeRequest(credentials: credentials, url: targetURL)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, accepted: [200, 201, 204])
        return RemoteBackupFile(
            name: filename,
            url: targetURL,
            size: payload.count,
            modifiedAt: Date(),
            format: shouldEncrypt ? .encrypted : .plainJSON
        )
    }

    func downloadBackup(_ file: RemoteBackupFile, credentials: WebDAVCredentials) async throws -> Data {
        var request = try makeRequest(credentials: credentials, url: file.url)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, accepted: [200])
        switch detectedFormat(for: file, data: data) {
        case .encrypted:
            guard credentials.hasPassphrase else {
                throw RemoteBackupError.missingPassphrase
            }
            return try decrypt(data, passphrase: credentials.passphrase)
        case .plainJSON:
            return data
        case .unknown:
            throw RemoteBackupError.unsupportedBackupFormat
        }
    }

    func makePreview(from backup: FullBackupData) -> RemoteBackupPreview {
        let dates = backup.transactions.map(\.date)
        let rangeText: String
        if let first = dates.min(), let last = dates.max() {
            rangeText = "\(first.formatted(date: .abbreviated, time: .omitted)) - \(last.formatted(date: .abbreviated, time: .omitted))"
        } else {
            rangeText = "沒有交易日期"
        }

        let detail = """
        版本：\(backup.version)
        建立時間：\(backup.timestamp.formatted(date: .abbreviated, time: .shortened))
        帳戶：\(backup.accounts.count)
        交易：\(backup.transactions.count)
        分類：\(backup.categories.count)
        標籤：\(backup.tags.count)
        代墊案件：\(backup.advanceCases?.count ?? 0)
        預算：\(backup.budgets?.count ?? 0)
        日期範圍：\(rangeText)
        """
        return RemoteBackupPreview(title: "遠端備份預覽", detail: detail)
    }

    private func encrypt(_ data: Data, passphrase: String) throws -> Data {
        let salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        let key = try deriveKey(passphrase: passphrase, salt: salt)
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(data, using: key, nonce: nonce)
        let combinedCiphertext = sealed.ciphertext + sealed.tag
        let envelope = EncryptedBackupEnvelope(
            formatVersion: 1,
            algorithm: "AES.GCM.PBKDF2.HMACSHA256",
            createdAt: Date(),
            salt: salt.base64EncodedString(),
            iv: Data(nonce).base64EncodedString(),
            ciphertext: combinedCiphertext.base64EncodedString(),
            tagBits: gcmTagByteCount * 8
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    private func decrypt(_ envelopeData: Data, passphrase: String) throws -> Data {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(EncryptedBackupEnvelope.self, from: envelopeData)
        guard envelope.formatVersion == 1,
              envelope.algorithm == "AES.GCM.PBKDF2.HMACSHA256",
              let salt = Data(base64Encoded: envelope.salt),
              let nonceData = Data(base64Encoded: envelope.iv),
              let combinedCiphertext = Data(base64Encoded: envelope.ciphertext),
              envelope.tagBits == gcmTagByteCount * 8,
              combinedCiphertext.count > gcmTagByteCount else {
            throw RemoteBackupError.invalidEnvelope
        }
        let key = try deriveKey(passphrase: passphrase, salt: salt)
        do {
            let ciphertext = combinedCiphertext.dropLast(gcmTagByteCount)
            let tag = combinedCiphertext.suffix(gcmTagByteCount)
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: Data(ciphertext), tag: Data(tag))
            return try AES.GCM.open(sealed, using: key)
        } catch {
            throw RemoteBackupError.decryptFailed
        }
    }

    private func deriveKey(passphrase: String, salt: Data) throws -> SymmetricKey {
        let password = Data(passphrase.utf8)
        var derivedKey = Data(repeating: 0, count: kCCKeySizeAES256)

        let status = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        keyDerivationIterations,
                        derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                        kCCKeySizeAES256
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw RemoteBackupError.keyDerivationFailed
        }
        return SymmetricKey(data: derivedKey)
    }

    private func makeRequest(credentials: WebDAVCredentials, url: URL) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let auth = "\(credentials.username):\(credentials.password)"
        guard let authData = auth.data(using: .utf8) else {
            throw RemoteBackupError.invalidCredentials
        }
        request.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validate(response: URLResponse, accepted: Set<Int>) throws {
        guard let http = response as? HTTPURLResponse else {
            throw RemoteBackupError.invalidResponse
        }
        guard accepted.contains(http.statusCode) else {
            throw RemoteBackupError.httpStatus(http.statusCode)
        }
    }

    private func propfindBody() -> Data {
        Data("""
        <?xml version="1.0" encoding="utf-8" ?>
        <propfind xmlns="DAV:">
          <prop>
            <getlastmodified />
            <getcontentlength />
          </prop>
        </propfind>
        """.utf8)
    }

    private func parseBackupFiles(from xml: String, baseURL: URL) -> [RemoteBackupFile] {
        let hrefs = matches(pattern: #"<[^>]*href[^>]*>(.*?)</[^>]*href>"#, in: xml)
        return hrefs.compactMap { rawHref in
            let decoded = rawHref
                .replacingOccurrences(of: "&amp;", with: "&")
                .removingPercentEncoding ?? rawHref
            let name = (decoded as NSString).lastPathComponent
            let format = formatFromFilename(name)
            guard format != .unknown else { return nil }
            return RemoteBackupFile(name: name, url: baseURL.appendingPathComponent(name), size: nil, modifiedAt: nil, format: format)
        }
        .sorted { $0.name > $1.name }
    }

    private func detectedFormat(for file: RemoteBackupFile, data: Data) -> RemoteBackupFormat {
        let filenameFormat = formatFromFilename(file.name)
        if filenameFormat != .unknown {
            return filenameFormat
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if (try? decoder.decode(EncryptedBackupEnvelope.self, from: data)) != nil {
            return .encrypted
        }
        if (try? JSONSerialization.jsonObject(with: data)) != nil {
            return .plainJSON
        }
        return .unknown
    }

    private func formatFromFilename(_ name: String) -> RemoteBackupFormat {
        if name.hasSuffix(".\(backupExtension)") {
            return .encrypted
        }
        if name.hasPrefix("AIAccounting_Backup_"), name.hasSuffix(".\(plainBackupExtension)") {
            return .plainJSON
        }
        return .unknown
    }

    private func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[captureRange])
        }
    }

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()
}
