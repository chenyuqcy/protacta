import XCTest

/// Uses only the introduction's local previews; no live camera or microphone.
final class FirstRunIntroductionUITests: XCTestCase {
    private var app: XCUIApplication!
    private var suite = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        suite = "org.realitycore.protacta.prototype.uitests.introduction.\(UUID().uuidString)"
        app = XCUIApplication()
        app.launchEnvironment["PROTACTA_INTRODUCTION_TEST_SUITE"] = suite
        app.launchEnvironment["PROTACTA_PROGRESS_TEST_SUITE"] = suite + ".progress"
        app.launchArguments = ["--ui-testing", "--tutorial-hub", "--enable-introduction"]
        app.launch()
        XCTAssertTrue(app.buttons["skipIntroduction"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testSkipPersistsAcrossLaunchAndQuickTourCanBeReplayed() {
        XCTAssertEqual(app.staticTexts["introductionCounter"].label, "1 OF 3")
        capture("Build25_Introduction_choose_a_lesson")
        app.buttons["skipIntroduction"].tap()
        assertHome()
        capture("Build25_Branded_home")
        app.terminate(); app.launch()
        assertHome()
        XCTAssertFalse(app.buttons["skipIntroduction"].exists)

        app.buttons["hubAbout"].tap()
        XCTAssertTrue(app.buttons["replayIntroduction"].waitForExistence(timeout: 5))
        app.buttons["replayIntroduction"].tap()
        XCTAssertTrue(app.buttons["skipIntroduction"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["introductionCounter"].label, "1 OF 3")
        app.buttons["skipIntroduction"].tap()
        assertHome()
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testTourPreviewCanBeDraggedAndCompletionPersistsWithoutPermissions() {
        app.buttons["introductionNext"].tap()
        XCTAssertEqual(app.staticTexts["introductionCounter"].label, "2 OF 3")
        let slider = app.sliders["introductionProgress"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        let before = slider.value as? String
        slider.adjust(toNormalizedSliderPosition: 0.8)
        XCTAssertNotEqual(slider.value as? String, before)
        capture("Build25_Introduction_drag_the_timeline")
        app.buttons["introductionBack"].tap()
        XCTAssertEqual(app.staticTexts["introductionCounter"].label, "1 OF 3")
        app.buttons["introductionNext"].tap()
        XCTAssertNotEqual(app.sliders["introductionProgress"].value as? String, before)
        app.buttons["introductionNext"].tap()
        XCTAssertEqual(app.staticTexts["introductionCounter"].label, "3 OF 3")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Get started"),
                                               object: app.buttons["introductionNext"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed)
        capture("Build25_Introduction_AR_and_voice")
        XCTAssertEqual(app.buttons["introductionNext"].label, "Get started")
        app.buttons["introductionNext"].tap()
        assertHome()
        app.terminate(); app.launch()
        assertHome()
        XCTAssertFalse(app.buttons["skipIntroduction"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    private func assertHome(file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"),
                                               object: app.buttons["hubOrigami"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, file: file, line: line)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
