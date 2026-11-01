import XCTest
import UIKit

/// Generated pixels exercise visual coaching and navigation. They are labeled
/// synthetic in the review itself and establish no physical-camera accuracy.
final class DartCheckComparisonUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--paper-guide-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["viewportOptions"].waitForExistence(timeout: 15))
        app.openPaperTool("openDartPractice")
    }
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    func testMismatchReviewShowsFrozenAreasAndReplaysTheSameAction() {
        openActionThreeComparison()
        XCTAssertTrue(app.staticTexts["comparisonSyntheticLabel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["comparisonSnapshotCanvas"].exists)
        XCTAssertTrue(app.staticTexts["comparisonScope"].label.contains("Visible outline only"))
        let comparisonValue = app.otherElements["comparisonSnapshotCanvas"].value as? String ?? ""
        XCTAssertTrue(comparisonValue.contains("highlighted comparison areas"))
        capture("Synthetic_frozen_mismatch_action3")
        revealComparisonButton("comparisonReplay")
        app.buttons["comparisonReplay"].tap()
        XCTAssertTrue(app.staticTexts["stepCounter"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP 3 OF 10")
        app.openPaperTool("openDartPractice")
        XCTAssertEqual(app.staticTexts["practiceCounter"].label, "ACTION 3 OF 10")
        XCTAssertFalse(app.buttons["reviewPracticeComparison"].exists)
        // A partly folded source is asymmetric: visual QA can detect an image
        // flip that a flat rectangle alone would conceal.
        tapRoot("confirmPracticeAction")
        tapRoot("checkPracticeStep"); tapRoot("reviewPracticeComparison")
        XCTAssertTrue(app.navigationBars["Captured comparison"].waitForExistence(timeout: 5))
        capture("Synthetic_frozen_mismatch_action4_asymmetric")
        app.buttons["comparisonClose"].tap()
        XCTAssertEqual(app.staticTexts["practiceCounter"].label, "ACTION 4 OF 10")
    }

    func testClosingAndBackgroundingRemoveTheOldImageWithoutAdvancing() {
        openActionThreeComparison()
        app.buttons["comparisonClose"].tap()
        XCTAssertTrue(app.staticTexts["practiceCounter"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["practiceCounter"].label, "ACTION 3 OF 10")
        XCTAssertFalse(app.buttons["reviewPracticeComparison"].exists)
        tapRoot("checkPracticeStep"); tapRoot("reviewPracticeComparison")
        XCTAssertTrue(app.staticTexts["comparisonSyntheticLabel"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !self.app.buttons["comparisonClose"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts["practiceCameraStatus"].label.contains("camera paused"))
        XCTAssertEqual(app.staticTexts["practiceCounter"].label, "ACTION 3 OF 10")
        XCTAssertFalse(app.buttons["reviewPracticeComparison"].exists)
    }

    func testReopenedOutlineKeepsCenterCreaseUnknown() {
        tapRoot("confirmPracticeAction")
        tapRoot("checkPracticeStep"); tapRoot("reviewPracticeComparison")
        XCTAssertTrue(app.staticTexts["comparisonCreaseUnknown"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["comparisonCreaseUnknown"].label.contains("crease"))
        let comparisonValue = app.otherElements["comparisonSnapshotCanvas"].value as? String ?? ""
        XCTAssertTrue(comparisonValue.contains("No highlighted outline differences"))
        app.buttons["comparisonClose"].tap()
        XCTAssertEqual(app.staticTexts["practiceCounter"].label, "ACTION 2 OF 10")
    }

    func testTabletLandscapeReviewKeepsItsFrozenGeometryAndControlsReachable() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Tablet layout check") }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.app.frame.width > self.app.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        openActionThreeComparison()
        XCTAssertTrue(app.otherElements["comparisonSnapshotCanvas"].waitForExistence(timeout: 5))
        capture("Synthetic_frozen_mismatch_iPad_landscape")
        revealComparisonButton("comparisonReturnToCamera")
        XCTAssertTrue(app.buttons["comparisonReturnToCamera"].isHittable)
        app.buttons["comparisonReturnToCamera"].tap()
        XCTAssertEqual(app.staticTexts["practiceCounter"].label, "ACTION 3 OF 10")
    }

    private func openActionThreeComparison() {
        tapRoot("confirmPracticeAction"); tapRoot("confirmPracticeAction")
        tapRoot("checkPracticeStep")
        let result = app.descendants(matching: .any).matching(identifier: "practiceCheckResult").firstMatch
        XCTAssertTrue(result.label.contains("Compare the outline"))
        tapRoot("reviewPracticeComparison")
        XCTAssertTrue(app.navigationBars["Captured comparison"].waitForExistence(timeout: 5))
    }
    private func tapRoot(_ id: String) {
        let button = app.buttons[id]
        for _ in 0..<6 where !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(button.isHittable, id)
        button.tap()
    }
    private func revealComparisonButton(_ id: String) {
        for _ in 0..<6 where !app.buttons[id].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons[id].isHittable)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
