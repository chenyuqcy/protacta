import XCTest

/// Full-screen layout/state fixture only. It cannot create camera evidence.
final class EquipmentARUITests: XCTestCase {
    private var app: XCUIApplication!
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    func testMotorARLayoutKeepsPartialPoseAndReturnsToStudio() { runPreview("gearmotor", count: 5) }
    func testEngineARLayoutKeepsPartialPoseAndReturnsToStudio() { runPreview("turbofan", count: 6) }

    func testVoiceOnlyARHidesControlsAndRecoversWhenSpeechIsUnavailable() {
        launch(fixture: true); open("gearmotor")
        app.buttons["assemblyEnterAR"].tap()
        app.buttons["assemblyEnterVoiceOnlyAR"].tap()
        XCTAssertTrue(app.buttons["exitVoiceOnlyAR"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["voiceOnlyRecoveryMessage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["voiceOnlyRecoveryMessage"].label.contains("automated tests"))
        for id in ["assemblyNext", "assemblyPrevious", "assemblyVoice", "assemblyPartMenu", "assemblyExitAR"] {
            XCTAssertFalse(app.buttons[id].exists, id)
        }
        XCTAssertTrue(app.buttons["voiceOnlyRetry"].isHittable)
        capture("equipment_voice_only_recovery")
        app.buttons["voiceOnlyShowControls"].tap()
        XCTAssertTrue(app.buttons["assemblyNext"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["assemblyARCounter"].label.contains("1/5"))
    }

    func testVoiceOnlyLayoutKeepsEnginePartialPoseWithoutClaimingRealSpeech() {
        launch(fixture: true, voiceLayout: true); open("turbofan")
        app.buttons["assemblyToggleDetails"].tap()
        let slider = app.sliders["assemblySlider"]
        slider.adjust(toNormalizedSliderPosition: 0.45)
        let partial = slider.value as? String
        app.buttons["assemblyEnterAR"].tap(); app.buttons["assemblyEnterVoiceOnlyAR"].tap()
        XCTAssertTrue(app.buttons["exitVoiceOnlyAR"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["assemblyARFixtureLabel"].label.contains("NO LIVE CAMERA"))
        XCTAssertTrue(app.staticTexts["voiceOnlyFixtureLabel"].label.contains("MIC OFF"))
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["voiceOnlyHint"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 8), .completed)
        XCTAssertFalse(app.buttons["assemblyNext"].exists)
        XCTAssertFalse(app.buttons["assemblyVoice"].exists)
        XCTAssertTrue(app.buttons["exitVoiceOnlyAR"].isHittable)
        capture("equipment_voice_only_clean_layout_MIC_OFF_NO_LIVE_CAMERA")
        app.buttons["exitVoiceOnlyAR"].tap()
        XCTAssertTrue(app.buttons["assemblyNext"].waitForExistence(timeout: 5))
        app.buttons["assemblyToggleDetails"].tap()
        XCTAssertEqual(slider.value as? String, partial)
        app.buttons["assemblyExitAR"].tap()
        XCTAssertTrue(app.staticTexts["assemblyCounter"].label.contains("1/6"))
    }

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
        app.buttons["assemblyToggleDetails"].tap()
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
    private func launch(fixture: Bool, voiceLayout: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--tutorial-hub"]
        if fixture { app.launchArguments.append("--equipment-ar-layout-fixture") }
        if voiceLayout { app.launchArguments.append("--voice-only-layout-fixture") }
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
