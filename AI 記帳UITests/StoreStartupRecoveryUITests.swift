import XCTest

final class StoreStartupRecoveryUITests: XCTestCase {
    func testOpenFailureShowsRecoveryBeforeLedgerAndRetryOpensLedger() {
        verifyRecovery(extraArguments: [])
    }

    func testBackupFailureShowsRecoveryBeforeLedgerAndRetryOpensLedger() {
        verifyRecovery(extraArguments: ["-UITestBackupFailure"])
    }

    private func verifyRecovery(extraArguments: [String]) {
        let app = XCUIApplication()
        app.launchEnvironment["AI_ACCOUNTING_UI_TESTS"] = "1"
        app.launchArguments = ["-UITestStartupFailure", "-UITestDisableAnimations"] + extraArguments
        app.launch()
        let retry = app.buttons["storeRecovery.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["storeRecovery.diagnostics"].exists)
        XCTAssertFalse(app.tabBars.buttons["帳目"].exists)
        retry.tap()
        XCTAssertTrue(app.tabBars.buttons["帳目"].waitForExistence(timeout: 15))
        XCTAssertFalse(retry.exists)
        app.terminate()
    }
}
