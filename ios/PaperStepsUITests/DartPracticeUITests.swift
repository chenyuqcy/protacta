import XCTest
import UIKit

/// This exercises navigation and explicit user confirmation using a labeled,
/// simulator-only drawing. It is not evidence of camera tracking or accuracy.
final class DartPracticeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-learning-progress", "--paper-guide-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["openDartPractice"].waitForExistence(timeout: 15))
        app.buttons["openDartPractice"].tap()
        XCTAssertTrue(app.staticTexts["practiceFixtureLabel"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saveValidationSample"].exists, "Normal practice does not expose local photo recording")
    }
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    func testTenActionCourseChecksReferenceHelpAndUserCompletion() {
        checkCounter(1)
        tap("checkPracticeStep")
        XCTAssertTrue(checkResult.waitForExistence(timeout: 3))
        XCTAssertTrue(checkResult.label.contains("Cannot judge"))
        checkCounter(1)
        tap("confirmPracticeAction")
        checkCounter(2)
        tap("checkPracticeStep")
        XCTAssertTrue(checkResult.label.contains("outline"))
        checkCounter(2)
        tap("practice3DReference")
        XCTAssertTrue(app.staticTexts["stepCounter"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP 2 OF 10")
        app.buttons["openDartPractice"].tap()
        checkCounter(2)
        tap("confirmPracticeAction")
        checkCounter(3)
        tap("practiceHelp")
        XCTAssertTrue(app.navigationBars["Action 3 help"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        tap("losePracticeFixture")
        XCTAssertEqual(app.otherElements["practiceOverlay"].value as? String, "searching")
        tap("restorePracticeFixture")
        XCTAssertEqual(app.otherElements["practiceOverlay"].value as? String, "aligned")
        tap("checkPracticeStep")
        checkCounter(3)
        capture("Synthetic_full_course_action3")
        for action in 3...10 {
            checkCounter(action)
            tap("confirmPracticeAction")
        }
        XCTAssertTrue(app.staticTexts["practiceCompletion"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["practiceCompletion"].label.contains("confirmed by you"))
        capture("User_confirmed_full_course")
        tap("previousPracticeAction")
        checkCounter(10)
    }

    func testBackgroundHidesAlignmentUntilExplicitRecovery() {
        tap("confirmPracticeAction"); tap("confirmPracticeAction")
        checkCounter(3)
        XCTAssertEqual(app.otherElements["practiceOverlay"].value as? String, "aligned")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["practiceCameraStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["practiceCameraStatus"].label.contains("camera paused"))
        tap("reacquirePractice")
        XCTAssertEqual(app.otherElements["practiceOverlay"].value as? String, "aligned")
        checkCounter(3)
    }

    func testSetupUsesTheNewPaperRevisionAndLocalToolsDismissWithoutChangingAction() {
        tap("practiceSetup")
        XCTAssertTrue(app.staticTexts["One sheet, ten actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["practicePaperRevision"].label.contains("PTC2 revision 2"))
        app.buttons["Done"].tap()
        checkCounter(1)
        tap("confirmPracticeAction")
        tap("practiceHelp")
        XCTAssertTrue(app.navigationBars["Action 2 help"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        checkCounter(2)
        tap("checkPracticeStep")
        XCTAssertTrue(checkResult.waitForExistence(timeout: 5))
        checkCounter(2)
    }

    func testTabletLandscapeCanReachSetupCheckAndConfirmation() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Tablet layout check") }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.app.frame.width > self.app.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
        tap("practiceSetup")
        XCTAssertTrue(app.staticTexts["One sheet, ten actions"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        tap("confirmPracticeAction"); tap("confirmPracticeAction")
        tap("checkPracticeStep")
        checkCounter(3)
        capture("Synthetic_full_course_iPad_landscape")
    }

    private func checkCounter(_ action: Int) {
        XCTAssertEqual(app.staticTexts["practiceCounter"].label, "ACTION \(action) OF 10")
    }
    private var checkResult: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "practiceCheckResult").firstMatch
    }
    private func tap(_ identifier: String) {
        let button = app.buttons[identifier]
        for _ in 0..<5 where !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(button.isHittable, identifier)
        button.tap()
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
