import XCTest

/// Full-screen layout/state fixture only. It cannot create camera evidence.
final class EquipmentARUITests: XCTestCase {
    private var app: XCUIApplication!
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    func testMotorARLayoutKeepsPartialPoseAndReturnsToStudio() { runPreview("gearmotor", count: 5) }
    func testEngineARLayoutKeepsPartialPoseAndReturnsToStudio() { runPreview("turbofan", count: 6) }

    func testUnsupportedSimulatorARKeepsWorkingStudio() {
        launch(fixture: false)
        open("gearmotor")
        app.buttons["assemblyEnterAR"].tap()
        XCTAssertTrue(app.staticTexts["assemblyARUnavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["assemblyNext"].isHittable)
        XCTAssertFalse(app.buttons["assemblyExitAR"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
    }

    private func runPreview(_ id: String, count: Int) {
        launch(fixture: true); open(id)
        let slider = app.sliders["assemblySlider"]
        slider.adjust(toNormalizedSliderPosition: 0.45)
        let partial = slider.value as? String
        let viewport = app.descendants(matching: .any).matching(identifier: "assemblyViewportRegion").firstMatch
        let studioHeight = viewport.frame.height
        app.buttons["assemblyEnterAR"].tap()
        XCTAssertTrue(app.buttons["assemblyExitAR"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["assemblyARFixtureLabel"].label.contains("NO LIVE CAMERA"))
        XCTAssertTrue(app.buttons["assemblyARHandEdges"].isHittable)
        XCTAssertTrue(app.staticTexts["assemblyARCounter"].label.contains("1"))
        XCTAssertGreaterThan(viewport.frame.height, studioHeight)
        XCTAssertGreaterThan(viewport.frame.height, app.frame.height * 0.9)
        for id in ["assemblyExitAR", "assemblyNext", "assemblyVoice", "assemblyToggleDetails"] {
            XCTAssertTrue(app.buttons[id].isHittable)
            XCTAssertTrue(app.frame.contains(app.buttons[id].frame))
        }
        capture("\(id)_AR_layout_preview_compact")
        app.buttons["assemblyVoice"].tap()
        XCTAssertTrue(app.staticTexts["assemblyVoiceStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["assemblyVoiceStatus"].isHittable)
        XCTAssertLessThanOrEqual(app.staticTexts["assemblyVoiceStatus"].frame.maxY,
                                app.buttons["assemblyPartMenu"].frame.minY)
        app.buttons["assemblyToggleDetails"].tap()
        XCTAssertEqual(slider.value as? String, partial)
        app.buttons["assemblyExitAR"].tap()
        XCTAssertTrue(app.buttons["assemblyEnterAR"].waitForExistence(timeout: 5))
        XCTAssertEqual(slider.value as? String, partial)
        XCTAssertTrue(app.staticTexts["assemblyCounter"].label.contains("1/\(count)"))
        app.buttons["assemblyNext"].tap()
        XCTAssertTrue(app.staticTexts["assemblyCounter"].label.contains("2/\(count)"))
        capture("\(id)_studio_after_AR_layout_preview")
    }
    private func launch(fixture: Bool) {
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--tutorial-hub"]
        if fixture { app.launchArguments.append("--equipment-ar-layout-fixture") }
        app.launch()
        XCTAssertTrue(app.buttons["hubOrigami"].waitForExistence(timeout: 15))
    }
    private func open(_ id: String) {
        let card = app.buttons["hubEquipment_\(id)"]
        for _ in 0..<10 {
            if card.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(card.isHittable); card.tap()
        XCTAssertTrue(app.buttons["assemblyNext"].waitForExistence(timeout: 30))
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
