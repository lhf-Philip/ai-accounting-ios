import SwiftUI
import SwiftData

private extension ProcessInfo {
    static var usesInMemoryStoreForTests: Bool {
        processInfo.environment["XCTestConfigurationFilePath"] != nil
            || processInfo.environment["AI_ACCOUNTING_UI_TESTS"] == "1"
            || processInfo.arguments.contains("-UITestSeedLedgerPerformanceData")
    }
}

@main
struct AI___App: App {
    @State private var startup = makeStartupController()

    private static func makeStartupController() -> StoreStartupController {
        var attempts = 0
        return StoreStartupController {
            attempts += 1
            if ProcessInfo.usesInMemoryStoreForTests {
                #if DEBUG
                if ProcessInfo.processInfo.environment["AI_ACCOUNTING_UI_TESTS"] == "1",
                   ProcessInfo.processInfo.arguments.contains("-UITestStartupFailure"), attempts == 1 {
                    let stage: StoreStartupStage = ProcessInfo.processInfo.arguments.contains("-UITestBackupFailure") ? .backup : .container
                    return .failure(StoreStartupFailure(stage: stage, error: NSError(domain: "UITestStartupFailure", code: 1)))
                }
                #endif
                do { return .success(try StoreStartupService.makeInMemoryContainer()) }
                catch { return .failure(StoreStartupFailure(stage: .container, error: error)) }
            }
            return StoreStartupService().load()
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch startup.state {
                case .idle, .opening:
                    ProgressView("正在開啟帳目資料…")
                case .ready(let container):
                    ContentView()
                        .modelContainer(container)
                case .failed(let failure):
                    StoreRecoveryView(failure: failure, retry: startup.retry)
                        .id(failure.backupURL)
                }
            }
            .task { await startup.startIfNeeded() }
        }
    }
}
