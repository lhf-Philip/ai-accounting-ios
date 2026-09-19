import Foundation
import UIKit

enum ReceiptAIProvider: String, CaseIterable, Identifiable {
    case geminiBYOK
    case platformGemma

    var id: String { rawValue }

    var title: String {
        switch self {
        case .geminiBYOK: "自備 Gemini API Key"
        case .platformGemma: "受邀 Gemma"
        }
    }
}

struct PlatformGemmaUsage: Decodable {
    struct Device: Decodable {
        let requests: Int
        let requestLimit: Int
        let estimatedNeurons: Int
    }

    struct Platform: Decodable {
        let estimatedNeurons: Int
        let estimatedNeuronLimit: Int
    }

    let day: String
    let resetsAt: String
    let device: Device
    let platform: Platform
}

enum PlatformGemmaError: LocalizedError {
    case missingEndpoint
    case notRegistered
    case invalidResponse
    case service(String)

    var errorDescription: String? {
        switch self {
        case .missingEndpoint: "請先在設定輸入有效的 HTTPS Gemma 服務網址。"
        case .notRegistered: "此設備尚未使用邀請碼登記。"
        case .invalidResponse: "Gemma 服務回傳格式錯誤。"
        case .service(let message): message
        }
    }
}

final class PlatformGemmaService {
    static let shared = PlatformGemmaService()

    private let keychainService = "org.duckdns.lhfser.AIMoney.platform-gemma"
    private let installationAccount = "installation_id"
    private let deviceAccount = "device_id"
    private let credentialAccount = "device_credential"
    private let registeredEndpointAccount = "registered_endpoint"
    private let endpointKey = "PlatformGemmaBaseURL"

    private init() {}

    var isRegistered: Bool {
        stored(deviceAccount) != nil && stored(credentialAccount) != nil && stored(registeredEndpointAccount) != nil
    }

    func register(baseURL: String, invitationCode: String) async throws {
        let endpoint = try validatedBaseURL(baseURL)
        let persistedInstallationId = try installationId()
        let body = RegistrationRequest(
            inviteCode: invitationCode.trimmingCharacters(in: .whitespacesAndNewlines),
            installationId: persistedInstallationId,
            platform: "ios"
        )
        var request = URLRequest(url: endpoint.appending(path: "v1/devices/register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let response: RegistrationResponse = try await send(request)
        guard KeychainService.shared.save(service: keychainService, account: deviceAccount, value: response.deviceId),
              KeychainService.shared.save(service: keychainService, account: credentialAccount, value: response.credential),
              KeychainService.shared.save(service: keychainService, account: registeredEndpointAccount, value: endpoint.absoluteString) else {
            clearRegistration()
            throw PlatformGemmaError.service("無法安全儲存設備憑證。")
        }
        UserDefaults.standard.set(endpoint.absoluteString, forKey: endpointKey)
    }

    func analyzeReceipt(image: UIImage, userNote: String, categoryCandidates: [String]) async throws -> ReceiptInfo {
        let endpoint = try configuredEndpoint()
        guard let deviceId = stored(deviceAccount), let credential = stored(credentialAccount) else {
            throw PlatformGemmaError.notRegistered
        }
        guard let resized = image.resized(to: 1024), let imageData = resized.jpegData(compressionQuality: 0.82) else {
            throw PlatformGemmaError.service("無法處理單據圖片。")
        }
        let body = AnalyzeRequest(
            requestId: UUID().uuidString,
            imageBase64: imageData.base64EncodedString(),
            mimeType: "image/jpeg",
            userNote: userNote,
            categories: categoryCandidates
        )
        var request = URLRequest(url: endpoint.appending(path: "v1/receipts/analyze"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(deviceId).\(credential)", forHTTPHeaderField: "Authorization")
        request.setValue(try installationId(), forHTTPHeaderField: "X-Installation-ID")
        request.httpBody = try JSONEncoder().encode(body)
        let response: AnalyzeResponse = try await send(request)
        return response.receipt
    }

    private func configuredEndpoint() throws -> URL {
        guard let registeredEndpoint = stored(registeredEndpointAccount) else { throw PlatformGemmaError.notRegistered }
        return try validatedBaseURL(registeredEndpoint)
    }

    private func validatedBaseURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), components.scheme == "https", components.host != nil,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            throw PlatformGemmaError.missingEndpoint
        }
        components.path = ""
        guard let url = components.url else { throw PlatformGemmaError.missingEndpoint }
        return url
    }

    private func installationId() throws -> String {
        do {
            return try PlatformGemmaInstallationIdentifier.loadOrCreate(
                existing: stored(installationAccount),
                persist: { value in
                    KeychainService.shared.save(service: keychainService, account: installationAccount, value: value)
                }
            )
        } catch {
            throw PlatformGemmaError.service("無法安全儲存設備識別碼。")
        }
    }

    private func stored(_ account: String) -> String? {
        let value = KeychainService.shared.read(service: keychainService, account: account)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private func clearRegistration() {
        for account in [deviceAccount, credentialAccount, registeredEndpointAccount] {
            _ = KeychainService.shared.delete(service: keychainService, account: account)
        }
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        var request = request
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 75
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let (data, urlResponse) = try await URLSession(configuration: configuration).data(for: request)
        guard let http = urlResponse as? HTTPURLResponse else { throw PlatformGemmaError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw PlatformGemmaError.service(envelope?.error.message ?? "Gemma 服務失敗（\(http.statusCode)）。")
        }
        do { return try JSONDecoder().decode(Response.self, from: data) }
        catch { throw PlatformGemmaError.invalidResponse }
    }
}

private struct RegistrationRequest: Encodable {
    let inviteCode: String
    let installationId: String
    let platform: String
}

private struct RegistrationResponse: Decodable {
    let deviceId: String
    let credential: String
}

private struct AnalyzeRequest: Encodable {
    let requestId: String
    let imageBase64: String
    let mimeType: String
    let userNote: String
    let categories: [String]
}

private struct AnalyzeResponse: Decodable {
    let receipt: ReceiptInfo
    let usage: PlatformGemmaUsage
}

private struct ErrorEnvelope: Decodable {
    struct ServiceError: Decodable { let code: String; let message: String }
    let error: ServiceError
}
