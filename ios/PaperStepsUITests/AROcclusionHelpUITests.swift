import XCTest

/// Exercises help, mode selection and preservation of a paused fold. This uses
/// a free lesson and never opens a camera session or makes a StoreKit purchase.
final class AROcclusionHelpUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
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

    func testOcclusionHelpAndModeSelectionPreserveAPausedFold() throws {
        app.buttons["nextStep"].tap()
        waitForLabel(app.staticTexts["stepCounter"], containing: "STEP 1 OF 10")
        waitUntilEnabled(app.buttons["nextStep"])
        app.sliders["foldProgress"].adjust(toNormalizedSliderPosition: 0.4)
        waitForLabel(app.buttons["nextStep"], containing: "Finish this fold")
        let beforeProgress = try XCTUnwrap(app.sliders["foldProgress"].value as? String)
        let beforeTitle = app.staticTexts["stepTitle"].label
        let beforeCounter = app.staticTexts["stepCounter"].label

        app.buttons["aboutLesson"].tap()
        let openHelp = app.buttons["openARHelp"]
        XCTAssertTrue(openHelp.waitForExistence(timeout: 5))
        reveal(openHelp)
        openHelp.tap()
        XCTAssertTrue(app.buttons["closeARHelp"].waitForExistence(timeout: 5))

        #if targetEnvironment(simulator)
        let availability = app.staticTexts["occlusionAvailability"]
        XCTAssertTrue(availability.waitForExistence(timeout: 5))
        XCTAssertTrue(availability.label.localizedCaseInsensitiveContains("simulator"))
        XCTAssertTrue(availability.label.localizedCaseInsensitiveContains("unavailable"))
        #endif

        for identifier in ["modePeopleOnly", "modeAutomatic"] {
            let mode = app.buttons[identifier]
            XCTAssertTrue(mode.exists)
            reveal(mode)
            mode.tap()
            XCTAssertTrue(mode.isSelected, "The active mode should be exposed as selected")
        }

        let details = app.buttons["occlusionDetails"]
        XCTAssertTrue(details.exists)
        reveal(details)
        details.tap()
        capture("AR_occlusion_help_details")
        app.buttons["closeARHelp"].tap()

        XCTAssertTrue(app.staticTexts["stepCounter"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["stepCounter"].label, beforeCounter)
        XCTAssertEqual(app.staticTexts["stepTitle"].label, beforeTitle)
        XCTAssertEqual(app.sliders["foldProgress"].value as? String, beforeProgress)
        XCTAssertEqual(app.buttons["playPause"].label, "Play fold")
        XCTAssertTrue(app.buttons["nextStep"].label.contains("Finish this fold"))
        XCTAssertTrue(app.buttons["openAR"].exists, "Help must return to the existing 3D lesson without opening AR")
        capture("AR_help_keeps_paused_fold")
    }

    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
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
