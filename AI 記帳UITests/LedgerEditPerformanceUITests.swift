import XCTest

final class LedgerEditPerformanceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = [
            "-UITestSeedLedgerPerformanceData",
            "-UITestDisableAnimations"
        ]
        app.launchEnvironment["AI_ACCOUNTING_UI_TESTS"] = "1"
        app.launch()
    }

    override func tearDownWithError() throws {
        if let failureCount = testRun?.failureCount, failureCount > 0 {
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "Failure Screenshot"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app = nil
    }

    func testLedgerEditFlowRunsWithoutManualOperation() throws {
        openLedger()
        openAndDismissDateFilter()
        editTransaction(named: "UITest 普通支出", noteFieldIdentifier: "transactionEditor.noteField", saveButtonIdentifier: "transactionEditor.saveButton")
        editTransaction(named: "UITest 轉帳", noteFieldIdentifier: "transferEditor.noteField", saveButtonIdentifier: "transferEditor.saveButton")
        editTransaction(named: "UITest 代墊還款", noteFieldIdentifier: "advanceTransferEditor.noteField", saveButtonIdentifier: "advanceTransferEditor.saveButton")
    }

    private func openLedger() {
        let ledgerTab = app.tabBars.buttons["帳目"]
        XCTAssertTrue(ledgerTab.waitForExistence(timeout: 15), "Ledger tab should be available")
        ledgerTab.tap()

        let ledgerList = app.collectionViews["ledger.list"]
        XCTAssertTrue(ledgerList.waitForExistence(timeout: 10), "Ledger list should be visible")
    }

    private func openAndDismissDateFilter() {
        let filterButton = app.buttons["ledger.dateFilter.button"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 10), "Date filter button should be visible")
        filterButton.tap()

        let doneButton = app.buttons["dateFilter.doneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 10), "Date filter done button should be visible")
        doneButton.tap()

        XCTAssertTrue(filterButton.waitForExistence(timeout: 10), "Ledger should be visible after closing date filter")
    }

    private func editTransaction(named rowText: String, noteFieldIdentifier: String, saveButtonIdentifier: String) {
        let rowLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", rowText)).firstMatch
        XCTAssertTrue(rowLabel.waitForExistence(timeout: 10), "Expected ledger row containing \(rowText)")
        rowLabel.tap()

        let noteField = app.textFields[noteFieldIdentifier]
        XCTAssertTrue(noteField.waitForExistence(timeout: 10), "Expected note field \(noteFieldIdentifier)")
        noteField.tap()
        noteField.typeText(" ui")

        let saveButton = app.buttons[saveButtonIdentifier]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10), "Expected save button \(saveButtonIdentifier)")
        saveButton.tap()

        let ledgerList = app.collectionViews["ledger.list"]
        XCTAssertTrue(ledgerList.waitForExistence(timeout: 10), "Ledger list should return after saving \(rowText)")
    }
}
