import XCTest

final class ReviewFlowTests: XCTestCase {
    func testPreviewQueueAndEvidence() {
        let app = XCUIApplication(); app.launchArguments = ["--preview-data"]; app.launch()
        continueAfterFailure = false
        let first = app.descendants(matching: .any)["review-00000000-0000-4000-8000-000000000001"].firstMatch
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
        for _ in 0..<5 where !first.isHittable { app.swipeUp() }
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        capture("01-queue", app)
        first.tap()
        XCTAssertTrue(app.buttons["reviewDecision"].waitForExistence(timeout: 10))
        capture("02-review", app)
        let evidence = app.buttons["inspect-aadhaar_front"]
        for _ in 0..<5 where !evidence.isHittable { app.swipeUp() }
        XCTAssertTrue(evidence.waitForExistence(timeout: 5)); evidence.tap()
        XCTAssertTrue(app.buttons["closeEvidence"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Page 1 of 1"].waitForExistence(timeout: 10))
        capture("03-evidence", app)
        app.buttons["closeEvidence"].tap()
        app.buttons["reviewDecision"].tap()
        XCTAssertTrue(app.navigationBars["Review decision"].waitForExistence(timeout: 5))
        for _ in 0..<4 where !app.buttons["commitDecision"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["commitDecision"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["commitDecision"].isEnabled)
        capture("04-decision-validation", app)
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
