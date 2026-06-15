import XCTest

final class AdvanceStructuralEditingUITests: XCTestCase {
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
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "Advance Structural Editing Failure"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app = nil
    }

    func testDirectionConversionAppliesAfterImpactPreview() {
        openStructuralEditor()

        let otherAdvancedMe = app.buttons["他人代墊我"]
        XCTAssertTrue(otherAdvancedMe.waitForExistence(timeout: 10))
        otherAdvancedMe.tap()

        previewAndApply()
        reopenStructuralEditor()
        XCTAssertTrue(
            app.buttons["他人代墊我"].isSelected,
            "Reopened editor should show the converted direction"
        )
    }

    func testCurrencyChangeRequiresExplicitConfirmationAndApplies() {
        openStructuralEditor()

        let currencyPicker = app.buttons["advance.structural.currency"]
        XCTAssertTrue(currencyPicker.waitForExistence(timeout: 10))
        currencyPicker.tap()
        app.buttons["USD"].tap()

        let confirmation = scrollToElement(
            app.switches["advance.structural.confirmCurrency"]
        )
        XCTAssertTrue(confirmation.exists)
        confirmation.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(confirmation.value as? String, "1")

        previewAndApply()
        reopenStructuralEditor()
        let reopenedCurrency = app.buttons["advance.structural.currency"]
        XCTAssertTrue(
            reopenedCurrency.label.contains("USD")
                || (reopenedCurrency.value as? String)?.contains("USD") == true
        )

        let preview = app.buttons["advance.structural.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        preview.tap()
        XCTAssertTrue(
            app.alerts["確認套用結構性變更？"].waitForExistence(timeout: 10),
            "Reopening a non-HKD case without changing its currency must not require confirmation again"
        )
        XCTAssertFalse(app.alerts["無法編輯"].exists)
    }

    func testSplitLegParticipantEditingAndKeyboardDismissal() {
        openStructuralEditor()

        let title = app.textFields["advance.structural.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText(" UI")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.buttons["完成"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        let paymentLegs = app.descendants(matching: .any)
            .matching(identifier: "advance.structural.paymentLeg")
        let initialLegNodeCount = paymentLegs.count
        let addLeg = scrollToElement(app.buttons["advance.structural.addPaymentLeg"])
        addLeg.tap()
        XCTAssertGreaterThan(paymentLegs.count, initialLegNodeCount)

        let participantNames = app.descendants(matching: .any)
            .matching(identifier: "advance.structural.participantName")
        let initialParticipantCount = participantNames.count
        let removeParticipantButtons = app.buttons.matching(
            identifier: "advance.structural.removeParticipant"
        )
        XCTAssertEqual(removeParticipantButtons.count, 0)
        let addParticipant = scrollToHittable(app.buttons["advance.structural.addParticipant"])
        XCTAssertTrue(addParticipant.isHittable)
        addParticipant.tap()
        XCTAssertGreaterThan(participantNames.count, initialParticipantCount)
        let removeParticipant = scrollToHittable(removeParticipantButtons.firstMatch)
        XCTAssertTrue(removeParticipant.isHittable)
        removeParticipant.tap()
        XCTAssertEqual(participantNames.count, initialParticipantCount)
    }

    func testCancellingImpactPreviewLeavesCaseUnchanged() {
        openStructuralEditor()
        app.buttons["他人代墊我"].tap()

        let preview = app.buttons["advance.structural.preview"]
        preview.tap()
        let alert = app.alerts["確認套用結構性變更？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons.matching(identifier: "取消").firstMatch.tap()
        app.navigationBars["完整編輯代墊"].buttons["取消"].tap()

        reopenStructuralEditor()
        XCTAssertTrue(
            app.buttons["我代墊他人"].isSelected,
            "Cancelling the preview must not persist the draft"
        )
    }

    private func openStructuralEditor() {
        let settings = app.tabBars.buttons["設定"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()

        let advances = scrollToElement(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", "代墊追蹤")
            ).firstMatch
        )
        XCTAssertTrue(advances.exists)
        advances.tap()

        let seededCase = app.staticTexts["UITest 代墊晚餐"]
        XCTAssertTrue(seededCase.waitForExistence(timeout: 10))
        seededCase.tap()

        let edit = app.navigationBars["UITest 代墊晚餐"].buttons["編輯"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()

        XCTAssertTrue(
            app.textFields["advance.structural.title"].waitForExistence(timeout: 10)
        )
    }

    private func previewAndApply() {
        let preview = app.buttons["advance.structural.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        preview.tap()

        let apply = app.alerts["確認套用結構性變更？"]
            .buttons
            .matching(identifier: "advance.structural.apply")
            .firstMatch
        XCTAssertTrue(apply.waitForExistence(timeout: 10))
        apply.tap()

        XCTAssertFalse(
            app.textFields["advance.structural.title"].waitForExistence(timeout: 10)
        )
    }

    private func reopenStructuralEditor() {
        let edit = app.navigationBars["UITest 代墊晚餐"].buttons["編輯"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        XCTAssertTrue(
            app.textFields["advance.structural.title"].waitForExistence(timeout: 10)
        )
    }

    @discardableResult
    private func scrollToElement(_ element: XCUIElement) -> XCUIElement {
        for _ in 0..<8 where !element.exists {
            app.swipeUp()
        }
        return element
    }

    @discardableResult
    private func scrollToHittable(_ element: XCUIElement) -> XCUIElement {
        for _ in 0..<10 where !element.isHittable {
            app.swipeUp()
        }
        return element
    }

}
