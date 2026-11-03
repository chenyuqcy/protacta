import XCTest

/// Navigation and labelled AR layout checks, not physical tracking acceptance.
final class TeamUpgradeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--tutorial-hub", "--reset-everyday-progress",
                               "--equipment-ar-layout-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["hubPhoneSetup"].waitForExistence(timeout: 15))
    }
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    func testPhoneSetupDistinguishesTabletopFromPaperGuidanceAndReturnsToHome() {
        app.buttons["hubPhoneSetup"].tap()
        XCTAssertTrue(app.buttons["closePhoneSetup"].waitForExistence(timeout: 5))
        let modes = app.segmentedControls["phoneSetupMode"]
        XCTAssertTrue(modes.buttons["Tabletop AR"].isSelected)
        capture("Build26_Phone_stand_and_tabletop_setup")
        reveal(app.staticTexts["phoneSetupTabletopScope"])
        XCTAssertTrue(app.staticTexts["phoneSetupTabletopScope"].label.contains("does not automatically align"))
        reveal(modes)
        modes.buttons["Paper guide"].tap()
        reveal(app.staticTexts["phoneSetupPaperScope"])
        XCTAssertTrue(app.staticTexts["phoneSetupPaperScope"].label.contains("flat-A4 centre crease"))
        XCTAssertFalse(app.staticTexts["phoneSetupTabletopScope"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.buttons["closePhoneSetup"].tap()
        XCTAssertTrue(app.buttons["hubPhoneSetup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["hubOrigami"].isHittable)
    }

    func testGlobalHelpOpensSetupAndQuickTourWithoutStartingSensors() {
        app.buttons["hubAbout"].tap()
        XCTAssertTrue(app.buttons["openTutorialSupport"].waitForExistence(timeout: 5))
        app.buttons["openTutorialSupport"].tap()
        XCTAssertTrue(app.buttons["closeTutorialSupport"].waitForExistence(timeout: 5))
        capture("Build26_Global_help")
        app.buttons["supportPhoneSetup"].tap()
        XCTAssertTrue(app.buttons["closePhoneSetup"].waitForExistence(timeout: 5))
        app.buttons["closePhoneSetup"].tap()
        XCTAssertTrue(app.buttons["supportQuickTour"].waitForExistence(timeout: 5))
        app.buttons["supportQuickTour"].tap()
        XCTAssertTrue(app.buttons["skipIntroduction"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["closeTutorialSupport"].exists, "Help must dismiss before presenting the tour")
        app.buttons["skipIntroduction"].tap()
        XCTAssertTrue(app.buttons["hubOrigami"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testEquipmentAndEverydayReferencesCanBeAdjustedAndRelockedWithoutChangingPose() throws {
        app.segmentedControls["hubFilter"].buttons["Equipment"].tap()
        reveal(app.buttons["hubEquipment_gearmotor"]); app.buttons["hubEquipment_gearmotor"].tap()
        XCTAssertTrue(app.buttons["assemblyNext"].waitForExistence(timeout: 20))
        app.buttons["assemblyToggleDetails"].tap()
        app.sliders["assemblySlider"].adjust(toNormalizedSliderPosition: 0.45)
        let motorPose = try XCTUnwrap(app.sliders["assemblySlider"].value as? String)
        app.buttons["assemblyEnterAR"].tap()
        assertLockToggle("assemblyARAdjust")
        capture("Build26_Equipment_locked_AR_NO_LIVE_CAMERA")
        app.buttons["assemblyToggleDetails"].tap()
        XCTAssertEqual(app.sliders["assemblySlider"].value as? String, motorPose)
        XCTAssertTrue(app.staticTexts["assemblyARCounter"].label.contains("1"))
        app.buttons["assemblyExitAR"].tap(); app.buttons["assemblyClose"].tap()
        XCTAssertTrue(app.segmentedControls["hubFilter"].waitForExistence(timeout: 5))
        app.segmentedControls["hubFilter"].buttons["Everyday"].tap()
        reveal(app.buttons["hubCourse_towel"]); app.buttons["hubCourse_towel"].tap()
        XCTAssertTrue(app.buttons["everydayConfirm"].waitForExistence(timeout: 10))
        let slider = app.sliders["everydayProgressSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.4)
        let towelPose = try XCTUnwrap(slider.value as? String)
        app.buttons["everydayEnterAR"].tap()
        assertLockToggle("everydayARAdjust")
        XCTAssertEqual(app.staticTexts["everydayARCounter"].label, "1/3")
        capture("Build26_Towel_locked_AR_NO_LIVE_CAMERA")
        app.buttons["everydayExitAR"].tap()
        XCTAssertEqual(slider.value as? String, towelPose)
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 1 OF 3")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    private func assertLockToggle(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(button.label.contains("Adjust"), file: file, line: line)
        button.tap()
        XCTAssertTrue(button.label.contains("Done"), file: file, line: line)
        button.tap()
        XCTAssertTrue(button.label.contains("Adjust"), file: file, line: line)
    }

    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<10 {
            if element.isHittable { return }
            let scroll = app.scrollViews.firstMatch
            if element.exists && element.frame.minY < scroll.frame.midY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, element.identifier, file: file, line: line)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
