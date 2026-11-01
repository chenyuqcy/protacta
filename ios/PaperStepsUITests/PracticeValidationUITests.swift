import XCTest

final class PracticeValidationUITests: XCTestCase {
    func testSimulatorDrawingCannotBeSavedAsPhysicalEvidence() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--paper-guide-fixture", "--practice-validation"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["viewportOptions"].waitForExistence(timeout: 15))
        app.openPaperTool("openDartPractice")
        let save = app.buttons["saveValidationSample"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(app.staticTexts["validationAvailability"].label.contains("Simulator"))
        app.buttons["practiceSetup"].tap()
        let configure = app.buttons["openValidationSettings"]
        for _ in 0..<4 where !configure.isHittable { app.swipeUp() }
        XCTAssertTrue(configure.isHittable)
        configure.tap()
        XCTAssertTrue(app.navigationBars["Local validation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["validationOperatorID"].exists)
        XCTAssertTrue(app.textFields["validationSheetID"].exists)
        XCTAssertTrue(app.textFields["validationAttemptID"].exists)
        let availability = app.staticTexts["validationSetupAvailability"]
        for _ in 0..<4 where !availability.exists { app.swipeUp() }
        XCTAssertTrue(availability.label.contains("Simulator"))
    }
}
