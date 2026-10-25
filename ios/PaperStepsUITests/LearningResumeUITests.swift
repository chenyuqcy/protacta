import XCTest

/// A real process relaunch verifies the visible resume path and test-owned local
/// storage. It uses free lessons and makes no purchase or physical AR claim.
final class LearningResumeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["PROTACTA_PROGRESS_TEST_SUITE"] = "org.realitycore.protacta.prototype.uitests.\(UUID().uuidString)"
        app.launchArguments = ["--ui-testing", "--reset-learning-progress"]
        app.launch()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 15))
        app.buttons["lesson_dart"].tap()
        app.buttons["startLesson"].tap()
        XCTAssertTrue(app.staticTexts["stepCounter"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testRelaunchContinueLessonSwitchAndExplicitRestartKeepTheExpectedFold() throws {
        for step in 1...3 {
            waitUntilEnabled(app.buttons["nextStep"])
            app.buttons["nextStep"].tap()
            waitForLabel(app.staticTexts["stepCounter"], containing: "STEP \(step) OF 10")
            waitUntilEnabled(app.buttons["nextStep"])
        }
        app.sliders["foldProgress"].adjust(toNormalizedSliderPosition: 0.4)
        waitForLabel(app.buttons["nextStep"], containing: "Finish this fold")
        let savedProgress = try XCTUnwrap(app.sliders["foldProgress"].value as? String)
        let savedTitle = app.staticTexts["stepTitle"].label
        capture("Saved_Dart_step_3_partial_fold")

        // Launch the same app with the same suite, but without the reset flag.
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let continueButton = app.buttons["startLesson"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 15))
        XCTAssertTrue(continueButton.label.localizedCaseInsensitiveContains("continue"))
        XCTAssertTrue(app.buttons["startOverLesson"].exists)
        XCTAssertFalse(app.staticTexts["stepCounter"].exists, "Opening the app must not begin the lesson automatically")
        XCTAssertTrue(app.buttons["openAR"].exists)
        XCTAssertFalse(app.buttons["closeAR"].exists, "Relaunch must not restore a camera session")
        capture("Resume_card_after_process_relaunch")
        continueButton.tap()
        assertRestoredDart(title: savedTitle, sliderValue: savedProgress)

        app.buttons["chooseLesson"].tap()
        let fox = app.buttons["library_fox"]
        XCTAssertTrue(fox.waitForExistence(timeout: 5))
        reveal(fox)
        fox.tap()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 5))
        app.buttons["startLesson"].tap()
        XCTAssertTrue(app.staticTexts["stepCounter"].waitForExistence(timeout: 5))
        waitUntilEnabled(app.buttons["nextStep"])
        app.buttons["nextStep"].tap()
        waitUntilEnabled(app.buttons["nextStep"])
        app.sliders["foldProgress"].adjust(toNormalizedSliderPosition: 0.65)
        waitForLabel(app.buttons["nextStep"], containing: "Finish this fold")

        chooseDart()
        XCTAssertTrue(app.buttons["startLesson"].label.localizedCaseInsensitiveContains("continue"))
        app.buttons["startLesson"].tap()
        assertRestoredDart(title: savedTitle, sliderValue: savedProgress)
        capture("Dart_restored_after_switching_lessons")

        chooseDart()
        let startOver = app.buttons["startOverLesson"]
        XCTAssertTrue(startOver.waitForExistence(timeout: 5))
        reveal(startOver)
        startOver.tap()
        XCTAssertTrue(app.staticTexts["stepCounter"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "BEFORE YOU BEGIN")
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Start with a blank sheet")
        XCTAssertFalse(app.sliders["foldProgress"].exists)
        XCTAssertFalse(app.buttons["backStep"].isEnabled)
        capture("Explicit_restart_begins_with_blank_sheet")
    }

    private func chooseDart() {
        app.buttons["chooseLesson"].tap()
        let dart = app.buttons["library_dart"]
        XCTAssertTrue(dart.waitForExistence(timeout: 5))
        reveal(dart)
        dart.tap()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 5))
    }

    private func assertRestoredDart(title: String, sliderValue: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts["stepCounter"].waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP 3 OF 10", file: file, line: line)
        XCTAssertEqual(app.staticTexts["stepTitle"].label, title, file: file, line: line)
        XCTAssertEqual(app.sliders["foldProgress"].value as? String, sliderValue, file: file, line: line)
        XCTAssertEqual(app.buttons["playPause"].label, "Play fold", file: file, line: line)
        XCTAssertTrue(app.buttons["nextStep"].label.contains("Finish this fold"), file: file, line: line)
        XCTAssertTrue(app.buttons["openAR"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["closeAR"].exists, file: file, line: line)
    }

    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        if element.isHittable { return }
        let scroll = app.scrollViews.containing(.any, identifier: element.identifier).firstMatch
        XCTAssertTrue(scroll.exists, file: file, line: line)
        for _ in 0..<6 {
            if element.isHittable { return }
            if element.frame.midY < scroll.frame.midY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, "Expected a reachable control", file: file, line: line)
    }

    private func waitUntilEnabled(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, file: file, line: line)
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, file: file, line: line)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
