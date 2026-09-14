import XCTest
@testable import AI_記帳

@MainActor
final class RemoteBackupTransportTests: XCTestCase {
    func testHTTPRejectedBeforeTransportAtEveryEntryPoint() async throws {
        let recorder = Recorder()
        let service = RemoteBackupService(transport: recorder.send)
        let credentials = credentials("http://backup.example.test/dav/")
        for operation in ["test", "list", "upload", "download"] {
            do {
                switch operation {
                case "test": try await service.testConnection(credentials: credentials)
                case "list": _ = try await service.listBackups(credentials: credentials)
                case "upload": _ = try await service.uploadBackup(jsonData: Data("{}".utf8), credentials: credentials, encrypt: false)
                default: _ = try await service.downloadBackup(file(credentials.baseURL.appendingPathComponent("backup.json")), credentials: credentials)
                }
                XCTFail("\(operation) must reject HTTP before transport")
            } catch {
                XCTAssertTrue(error is RemoteBackupError)
            }
        }
        XCTAssertTrue(recorder.requests.isEmpty, "Invalid endpoints must never reach the transport")
    }

    func testHTTPSConnectionListingAndPlainRoundtrip() async throws {
        let recorder = Recorder()
        let service = RemoteBackupService(transport: recorder.send)
        let credentials = credentials("https://backup.example.test/dav/")
        let payload = Data("{\"version\":1,\"synthetic\":true}".utf8)
        try await service.testConnection(credentials: credentials)
        let files = try await service.listBackups(credentials: credentials)
        XCTAssertEqual(files.map(\.name), ["AIAccounting_Backup_fixture.json"])
        let uploaded = try await service.uploadBackup(jsonData: payload, credentials: credentials, encrypt: false)
        let downloaded = try await service.downloadBackup(uploaded, credentials: credentials)
        XCTAssertEqual(downloaded, payload)
        XCTAssertEqual(recorder.requests.map(\.httpMethod), ["PROPFIND", "PROPFIND", "PUT", "GET"])
        XCTAssertEqual(recorder.requests.prefix(2).map { $0.value(forHTTPHeaderField: "Depth") }, ["0", "1"])
        for request in recorder.requests {
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic " + Data("fixture-user:fixture-password".utf8).base64EncodedString())
        }
    }

    func testHTTPSEncryptedRoundtripKeepsPayloadEncryption() async throws {
        let recorder = Recorder()
        let service = RemoteBackupService(transport: recorder.send)
        let credentials = credentials("https://backup.example.test/dav/")
        let payload = Data("{\"synthetic\":true}".utf8)
        let uploaded = try await service.uploadBackup(jsonData: payload, credentials: credentials, encrypt: true)
        XCTAssertEqual(uploaded.format, .encrypted)
        XCTAssertNotEqual(recorder.uploaded, payload)
        let downloaded = try await service.downloadBackup(uploaded, credentials: credentials)
        XCTAssertEqual(downloaded, payload)
    }

    func testMalformedAndNonHTTPSURLsNeverReachTransport() async throws {
        let recorder = Recorder()
        let service = RemoteBackupService(transport: recorder.send)
        for url in ["ftp://backup.example.test/dav/", "file:///tmp/fixture", "/relative", "https:///", "https://user:password@backup.example.test/dav/"] {
            do {
                try await service.testConnection(credentials: credentials(url))
                XCTFail("Must reject invalid endpoint: \(url)")
            } catch { XCTAssertTrue(error is RemoteBackupError) }
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testDownloadRejectsInsecureAndForeignOrigins() async throws {
        let recorder = Recorder()
        let service = RemoteBackupService(transport: recorder.send)
        let credentials = credentials("https://backup.example.test/dav/")
        for target in ["http://backup.example.test/backup.json", "https://other.example.test/backup.json", "https://backup.example.test:8443/backup.json"] {
            do {
                _ = try await service.downloadBackup(file(URL(string: target)!), credentials: credentials)
                XCTFail("Must reject unsafe download destination")
            } catch { XCTAssertTrue(error is RemoteBackupError) }
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testHTTPSCustomPortAndEscapedPathRemainSupported() async throws {
        let recorder = Recorder()
        let service = RemoteBackupService(transport: recorder.send)
        let credentials = credentials("https://backup.example.test:8443/my%20backups/")
        _ = try await service.uploadBackup(jsonData: Data("{}".utf8), credentials: credentials, encrypt: false)
        XCTAssertEqual(recorder.requests.first?.url?.port, 8443)
        XCTAssertTrue(recorder.requests.first?.url?.absoluteString.contains("/my%20backups/AIAccounting_Backup_") == true)
    }

    func testRedirectDelegateOnlyAllowsSameHTTPSOrigin() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let source = URL(string: "https://backup.example.test/dav")!
        let task = session.dataTask(with: source)
        let response = HTTPURLResponse(url: source, statusCode: 307, httpVersion: "HTTP/1.1", headerFields: nil)!
        let delegate = WebDAVRedirectDelegate()
        for (target, allowed) in [
            ("https://backup.example.test/dav/", true),
            ("https://BACKUP.example.test:443/dav/", true),
            ("http://backup.example.test/dav/", false),
            ("https://other.example.test/dav/", false),
            ("https://backup.example.test:8443/dav/", false),
            ("https://user:password@backup.example.test/dav/", false)
        ] {
            let request = URLRequest(url: URL(string: target)!)
            let redirected: URLRequest? = await withCheckedContinuation { continuation in
                delegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) {
                    continuation.resume(returning: $0)
                }
            }
            XCTAssertEqual(redirected != nil, allowed, target)
        }
    }

    private func credentials(_ url: String) -> WebDAVCredentials {
        WebDAVCredentials(baseURL: URL(string: url)!, username: "fixture-user", password: "fixture-password", passphrase: "fixture-passphrase")
    }

    private func file(_ url: URL) -> RemoteBackupFile {
        RemoteBackupFile(name: "backup.json", url: url, size: nil, modifiedAt: nil, format: .plainJSON)
    }

    private final class Recorder {
        var requests: [URLRequest] = []
        var uploaded = Data("{}".utf8)

        func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            let body: Data
            let status: Int
            switch request.httpMethod {
            case "PROPFIND":
                status = 207
                body = Data("<d:multistatus xmlns:d=\"DAV:\"><d:response><d:href>/dav/AIAccounting_Backup_fixture.json</d:href></d:response></d:multistatus>".utf8)
            case "PUT":
                status = 201
                uploaded = request.httpBody ?? Data()
                body = Data()
            default:
                status = 200
                body = uploaded
            }
            return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
        }
    }
}
