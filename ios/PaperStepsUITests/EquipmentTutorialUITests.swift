import XCTest

/// Native imported structure walkthroughs, not real repairs or camera tests.
final class EquipmentTutorialUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--tutorial-hub"]; app.launch()
        XCTAssertTrue(app.buttons["hubOrigami"].waitForExistence(timeout: 15))
    }
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    func testMotorFiveActionExteriorWalkthroughAndCredits() { run("gearmotor", count: 5, scope: "internal rotor") }
    func testTurbofanSixActionStructurePreviewAndCredits() { run("turbofan", count: 6, scope: "not manufacturer CAD") }

    private func run(_ id: String, count: Int, scope: String) {
        let card = app.buttons["hubEquipment_\(id)"]; reveal(card); card.tap()
        XCTAssertTrue(app.buttons["assemblyNext"].waitForExistence(timeout: 30))
        capture("\(id)_initial_model")
        app.buttons["assemblyPartMenu"].tap()
        app.buttons["Focus selected part"].tap()
        XCTAssertEqual(app.buttons["assemblyResetView"].value as? String, "Focused part")
        capture("\(id)_focused_first_part")
        app.buttons["assemblyResetView"].tap()
        app.buttons["assemblyCredits"].tap()
        XCTAssertTrue(app.staticTexts["assemblyScope"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["assemblyScope"].label.contains(scope))
        app.buttons["assemblyCreditsDone"].tap()
        app.buttons["assemblyExplode"].tap()
        XCTAssertEqual(app.buttons["assemblyExplode"].value as? String, "Exploded")
        capture("\(id)_all_groups_exploded")
        app.buttons["assemblyExplode"].tap()
        for index in 1...count {
            XCTAssertTrue(app.staticTexts["assemblyCounter"].label.contains("\(index)/\(count)"))
            app.sliders["assemblySlider"].adjust(toNormalizedSliderPosition: 1)
            capture("\(id)_action_\(index)_target")
            if index != count { app.buttons["assemblyNext"].tap() }
        }
        app.buttons["assemblyToggleDetails"].tap()
        XCTAssertTrue(app.buttons["assemblyNext"].isHittable)
        XCTAssertTrue(app.buttons["assemblyVoice"].isHittable)
        capture("\(id)_compact_reassembled")
        app.buttons["assemblyClose"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<10 {
            if element.isHittable { return }
            if element.exists && element.frame.midY < app.frame.midY { app.scrollViews.firstMatch.swipeDown() }
            else { app.scrollViews.firstMatch.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
