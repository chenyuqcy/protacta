import XCTest

/// Checks a native schematic and manual course flow, not fabric simulation,
/// real-towel correctness or camera registration.
final class Towel3DUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--tutorial-hub", "--reset-everyday-progress"]
        app.launch()
        XCTAssertTrue(app.buttons["hubOrigami"].waitForExistence(timeout: 15))
        let towel = app.buttons["hubCourse_towel"]
        reveal(towel); towel.tap()
        XCTAssertTrue(app.staticTexts["everydayCounter"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws { app?.terminate(); app = nil }

    func test3DFoldsDiagramSwitchAndManualConfirmationsStayInSync() {
        XCTAssertFalse(app.segmentedControls["everydayViewMode"].exists)
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        capture("Towel_3D_start")

        for action in 1...3 {
            reveal(app.buttons["everydayMore"]); app.buttons["everydayMore"].tap()
            app.buttons["everydayShowStart"].tap()
            let slider = app.sliders["everydayProgressSlider"]
            slider.adjust(toNormalizedSliderPosition: 0.5)
            waitForLabel(app.staticTexts["everydayCounter"], containing: "ACTION \(action) OF 3")
            capture("Towel_3D_action_\(action)_half")
            app.buttons["everydayMore"].tap(); app.buttons["everydayShowTarget"].tap()
            XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION \(action) OF 3", "Playing/showing a target must not confirm the real action")
            capture("Towel_3D_action_\(action)_target")

            // The optional diagram lives in Help; the main renderer stays 3D.
            app.buttons["everydayHelp"].tap()
            XCTAssertTrue(app.buttons["everydayCloseHelp"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.sliders["everydayHelpProgressSlider"].value as? String, "100%")
            app.buttons["everydayCloseHelp"].tap()
            XCTAssertTrue(viewport.waitForExistence(timeout: 5))
            XCTAssertEqual(slider.value as? String, "100%")
            app.buttons["everydayMore"].tap(); app.buttons["everydayResetViewMenu"].tap()
            let confirm = app.buttons["everydayConfirm"]
            reveal(confirm); confirm.tap()
        }
        XCTAssertTrue(app.staticTexts["everydayCompletion"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["everydayCompletion"].label.contains("confirmed by you"))
        XCTAssertFalse(app.buttons["checkPracticeStep"].exists)
        app.buttons["everydayClose"].tap()
        XCTAssertTrue(app.buttons["hubOrigami"].waitForExistence(timeout: 5))
    }

    func testSceneReattachesAfterBackgroundAndSingleFingerScrollingStillWorks() {
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        let confirm = app.buttons["everydayConfirm"]
        reveal(confirm)
        XCTAssertTrue(confirm.isHittable, "Rotating the model must not block one-finger lesson scrolling")
        app.sliders["everydayProgressSlider"].adjust(toNormalizedSliderPosition: 1)
        confirm.tap()
        waitForLabel(app.staticTexts["everydayCounter"], containing: "ACTION 2 OF 3")
        XCTAssertTrue(viewport.exists)
        capture("Towel_3D_after_background_action_2")
    }

    private var viewport: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "everydayViewport").firstMatch
    }

    private func reveal(_ element: XCUIElement) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<10 {
            if element.isHittable { return }
            if element.exists && element.frame.midY < app.frame.midY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }

    private func waitForLabel(_ element: XCUIElement, containing value: String) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
    }

    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
