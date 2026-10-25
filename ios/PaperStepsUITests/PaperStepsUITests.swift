import XCTest

/// Exercises the user-visible lesson contract. Screenshots are retained for
/// reviewing each actual rendered fold; UI assertions do not prove AR tracking.
final class PaperStepsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 15))
        app.buttons["lesson_dart"].tap()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testEveryFoldCompletesInEnglishAndCanRestart() {
        capture("00_Welcome")
        assertEnglishScreen()
        startLesson()
        assertStep(0, title: "Start with a blank sheet")
        XCTAssertFalse(app.buttons["backStep"].isEnabled)
        XCTAssertFalse(app.buttons["replayStep"].isEnabled)
        capture("01_Blank_sheet_angle")
        app.buttons["topView"].tap()
        capture("02_Blank_sheet_top")
        app.buttons["angleView"].tap()

        let titles = [
            "Make the center crease",
            "Open the sheet",
            "Fold the left corner",
            "Fold the right corner",
            "Narrow the left side",
            "Narrow the right side",
            "Close the body",
            "Fold the first wing",
            "Fold the other wing",
            "Open your finished wings"
        ]
        for (offset, title) in titles.enumerated() {
            let step = offset + 1
            advanceAndWait()
            assertStep(step, title: title)
            assertEnglishScreen()
            capture(String(format: "%02d_Step_%02d", step + 2, step))

            if [3, 6, 8, 10].contains(step) {
                app.buttons["topView"].tap()
                capture(String(format: "%02d_Step_%02d_top", step + 2, step))
                app.buttons["angleView"].tap()
            }
            if step == 3 {
                app.buttons["foldNotes"].tap()
                XCTAssertTrue(app.buttons["closeNotes"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["A little understanding."].exists)
                XCTAssertTrue(app.staticTexts["Written fold notes"].exists)
                assertEnglishScreen()
                capture("05_Corner_explanation")
                app.buttons["closeNotes"].tap()
                assertStep(3, title: title)
            }
        }

        XCTAssertTrue(app.buttons["nextStep"].label.contains("Finish lesson"))
        advanceAndWait()
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "LESSON COMPLETE")
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Made by you.")
        XCTAssertTrue(app.buttons["nextStep"].label.contains("Fold again"))
        XCTAssertFalse(app.sliders["foldProgress"].exists)
        assertEnglishScreen()
        capture("13_Made_by_you")

        app.buttons["nextStep"].tap()
        assertStep(0, title: "Start with a blank sheet")
        XCTAssertFalse(app.buttons["backStep"].isEnabled)
        XCTAssertTrue(app.buttons["nextStep"].label.contains("Next fold"))
        capture("14_Restarted_blank_sheet")
    }

    func testScrubResumeReplayAndBackKeepTheCorrectFold() {
        startLesson()
        advanceAndWait()
        assertStep(1, title: "Make the center crease")

        let progress = app.sliders["foldProgress"]
        XCTAssertTrue(progress.exists)
        progress.adjust(toNormalizedSliderPosition: 0.40)
        waitForLabel(app.buttons["nextStep"], contains: "Finish this fold")
        XCTAssertEqual(app.buttons["playPause"].label, "Play fold")
        assertStep(1, title: "Make the center crease")
        capture("Partial_center_fold_paused")

        // Resuming a partial fold finishes this step, rather than skipping it.
        app.buttons["nextStep"].tap()
        waitForLabel(app.buttons["nextStep"], contains: "Next fold")
        waitUntilEnabled(app.buttons["nextStep"])
        assertStep(1, title: "Make the center crease")

        // The transport control can resume another deliberately paused pose.
        progress.adjust(toNormalizedSliderPosition: 0.65)
        waitForLabel(app.buttons["nextStep"], contains: "Finish this fold")
        XCTAssertEqual(app.buttons["playPause"].label, "Play fold")
        app.buttons["playPause"].tap()
        waitForLabel(app.buttons["nextStep"], contains: "Next fold")
        waitUntilEnabled(app.buttons["nextStep"])
        assertStep(1, title: "Make the center crease")

        app.buttons["replayStep"].tap()
        waitUntilEnabled(app.buttons["nextStep"])
        waitForLabel(app.buttons["nextStep"], contains: "Next fold")
        assertStep(1, title: "Make the center crease")
        capture("Center_fold_replayed")

        app.buttons["backStep"].tap()
        assertStep(0, title: "Start with a blank sheet")
        XCTAssertFalse(app.sliders["foldProgress"].exists)
        XCTAssertFalse(app.buttons["backStep"].isEnabled)
        assertEnglishScreen()
    }

    func testSimulatorARFallbackTwicePreservesLessonAndPartialFold() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This case checks the simulator fallback; physical tabletop AR requires device testing.")
        #endif
        startLesson()
        advanceAndWait()
        advanceAndWait()
        advanceAndWait()
        assertStep(3, title: "Fold the left corner")
        app.sliders["foldProgress"].adjust(toNormalizedSliderPosition: 0.45)
        waitForLabel(app.buttons["nextStep"], contains: "Finish this fold")

        for visit in 1...2 {
            app.buttons["openAR"].tap()
            XCTAssertTrue(app.buttons["returnTo3D"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts["Your table, your workspace."].exists)
            XCTAssertTrue(app.buttons["closeAR"].exists)
            assertEnglishScreen()
            capture("AR_simulator_fallback_\(visit)")
            app.buttons["returnTo3D"].tap()
            XCTAssertTrue(app.buttons["openAR"].waitForExistence(timeout: 5))
            assertStep(3, title: "Fold the left corner")
            XCTAssertTrue(app.buttons["nextStep"].label.contains("Finish this fold"))
            XCTAssertEqual(app.buttons["playPause"].label, "Play fold")
            capture("Preserved_partial_fold_after_AR_\(visit)")
        }
        app.buttons["nextStep"].tap()
        waitForLabel(app.buttons["nextStep"], contains: "Next fold")
        waitUntilEnabled(app.buttons["nextStep"])
        assertStep(3, title: "Fold the left corner")
    }

    private func startLesson(file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["startLesson"].tap()
        XCTAssertTrue(app.staticTexts["stepTitle"].waitForExistence(timeout: 5), file: file, line: line)
        waitUntilEnabled(app.buttons["nextStep"], file: file, line: line)
    }

    private func advanceAndWait(file: StaticString = #filePath, line: UInt = #line) {
        let next = app.buttons["nextStep"]
        waitUntilEnabled(next, file: file, line: line)
        next.tap()
        waitUntilEnabled(next, file: file, line: line)
    }

    private func assertStep(_ number: Int, title: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(app.staticTexts["stepTitle"].label, title, file: file, line: line)
        XCTAssertEqual(app.staticTexts["stepCounter"].label, number == 0 ? "BEFORE YOU BEGIN" : "STEP \(number) OF 10", file: file, line: line)
    }

    private func waitUntilEnabled(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, "Control did not become enabled: \(element.identifier)", file: file, line: line)
    }

    private func waitForLabel(_ element: XCUIElement, contains text: String, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, "Expected label containing '\(text)'", file: file, line: line)
    }

    private func assertEnglishScreen(file: StaticString = #filePath, line: UInt = #line) {
        for text in app.staticTexts.allElementsBoundByIndex {
            XCTAssertNil(text.label.range(of: "\\p{Han}", options: .regularExpression), "Non-English UI text: \(text.label)", file: file, line: line)
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
