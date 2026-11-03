import XCTest
import UIKit

/// Native imported structure walkthroughs, not real repairs or camera tests.
final class EquipmentTutorialUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--tutorial-hub"]; app.launch()
        XCTAssertTrue(app.buttons["hubOrigami"].waitForExistence(timeout: 15))
    }
    override func tearDownWithError() throws {
        app?.terminate(); app = nil
        XCUIDevice.shared.orientation = .portrait
    }

    func testMotorFiveActionExteriorWalkthroughAndCredits() { run("gearmotor", count: 5, scope: "internal rotor") }
    func testTurbofanSixActionStructurePreviewAndCredits() { run("turbofan", count: 6, scope: "not manufacturer CAD") }

    func testModelFirstHomeAndPlayerKeepDetailsOptional() {
        capture("Simple_home")
        XCTAssertFalse(app.staticTexts["See the move.\nMake it yours."].exists)
        let filter = app.segmentedControls["hubFilter"]
        filter.buttons["Everyday"].tap()
        XCTAssertTrue(app.buttons["hubCourse_towel"].exists)
        XCTAssertFalse(app.buttons["hubEquipment_gearmotor"].exists)
        filter.buttons["Equipment"].tap()
        XCTAssertFalse(app.buttons["hubOrigami"].exists)
        XCTAssertFalse(app.buttons["hubCourse_towel"].exists)
        XCTAssertTrue(app.buttons["hubEquipment_gearmotor"].exists)
        XCTAssertTrue(app.buttons["hubEquipment_turbofan"].exists)
        capture("Simple_model_catalog")
        filter.buttons["All"].tap()
        let card = app.buttons["hubEquipment_gearmotor"]; reveal(card); card.tap()
        XCTAssertTrue(app.buttons["assemblyNext"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.sliders["assemblySlider"].exists, "The model starts with a compact control tray")
        let viewport = app.descendants(matching: .any).matching(identifier: "assemblyViewportRegion").firstMatch
        XCTAssertGreaterThan(viewport.frame.height, app.frame.height * 0.55)
        for id in ["assemblyNext", "assemblyPlay", "assemblyVoice", "assemblyReadStep", "assemblyToggleDetails"] {
            XCTAssertTrue(app.buttons[id].isHittable)
            XCTAssertGreaterThanOrEqual(app.buttons[id].frame.height, 44)
        }
        capture("Simple_motor_compact")
        app.buttons["assemblyToggleDetails"].tap()
        let slider = app.sliders["assemblySlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.45)
        let partial = slider.value as? String
        app.buttons["assemblyToggleDetails"].tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: slider)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        app.buttons["assemblyToggleDetails"].tap()
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        XCTAssertEqual(slider.value as? String, partial, "Opening details must preserve the partially played movement")
        app.buttons["assemblyToggleDetails"].tap()
        app.buttons["assemblyNext"].tap()
        XCTAssertTrue(app.staticTexts["assemblyCounter"].label.contains("2/5"))
        app.buttons["assemblyPrevious"].tap()
        app.buttons["assemblyToggleDetails"].tap()
        XCTAssertTrue(slider.exists)
        capture("Simple_motor_details")
    }

    func testCompactVoiceFailureExplainsTouchFallbackAndCanBeRetried() {
        let card = app.buttons["hubEquipment_gearmotor"]; reveal(card); card.tap()
        XCTAssertTrue(app.buttons["assemblyNext"].waitForExistence(timeout: 30))
        app.buttons["assemblyVoice"].tap()
        let status = app.staticTexts["assemblyVoiceStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 3), "Voice failure must stay visible with the instructions hidden")
        XCTAssertTrue(status.label.contains("Voice input is unavailable in automated tests"))
        XCTAssertTrue(status.label.contains("buttons"))
        XCTAssertTrue(app.frame.contains(status.frame))
        XCTAssertTrue(app.buttons["assemblyVoice"].isHittable)
        XCTAssertTrue(app.buttons["assemblyNext"].isEnabled)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        capture("equipment_compact_voice_unavailable_touch_fallback")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
                guard let frame = self?.app.frame else { return false }
                return frame.width > frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 8), .completed)
            XCTAssertTrue(app.frame.contains(status.frame))
            capture("equipment_landscape_compact_voice_unavailable_touch_fallback")
        }
        app.buttons["assemblyVoice"].tap()
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        app.buttons["assemblyNext"].tap()
        XCTAssertTrue(app.staticTexts["assemblyCounter"].label.contains("2/5"))
        app.buttons["assemblyToggleDetails"].tap()
        XCTAssertTrue(status.waitForExistence(timeout: 3), "The full panel must retain the same recovery message")
        XCTAssertTrue(status.label.contains("Voice input is unavailable in automated tests"))
        XCTAssertTrue(app.frame.contains(status.frame))
        XCTAssertTrue(app.buttons["assemblyNext"].isHittable)
        capture("equipment_expanded_voice_unavailable_touch_fallback")
        app.buttons["assemblyClose"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }

    func testIPadMotorRotationPreservesPartialMovementAndCompactControls() throws {
        try checkTabletRotation("gearmotor", count: 5)
    }

    func testIPadTurbofanRotationPreservesPartialMovementAndCompactControls() throws {
        try checkTabletRotation("turbofan", count: 6)
    }

    private func checkTabletRotation(_ id: String, count: Int) throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad viewport and rotation review") }
        let card = app.buttons["hubEquipment_\(id)"]; reveal(card); card.tap()
        XCTAssertTrue(app.buttons["assemblyNext"].waitForExistence(timeout: 30))
        app.buttons["assemblyToggleDetails"].tap()
        app.sliders["assemblySlider"].adjust(toNormalizedSliderPosition: 1)
        app.buttons["assemblyNext"].tap()
        let slider = app.sliders["assemblySlider"]
        slider.adjust(toNormalizedSliderPosition: 0.45)
        let partial = try XCTUnwrap(slider.value as? String)
        let selected = app.buttons["assemblyPartMenu"].label
        for landscape in [false, true, false] {
            XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
                guard let frame = self?.app.frame else { return false }
                return landscape ? frame.width > frame.height : frame.height > frame.width
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 8), .completed)
            XCTAssertTrue(app.staticTexts["assemblyCounter"].label.contains("2/\(count)"))
            XCTAssertEqual(slider.value as? String, partial, "Rotation must not finish or restart the movement")
            XCTAssertEqual(app.buttons["assemblyPartMenu"].label, selected)
            assertTabletBounds()
            capture("\(id)_iPad_\(landscape ? "landscape" : "portrait")_partial_movement")
            app.buttons["assemblyToggleDetails"].tap()
            XCTAssertFalse(slider.exists)
            assertTabletBounds()
            capture("\(id)_iPad_\(landscape ? "landscape" : "portrait")_compact")
            app.buttons["assemblyToggleDetails"].tap()
            XCTAssertEqual(slider.value as? String, partial)
        }
        app.buttons["assemblyClose"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }

    private func assertTabletBounds(file: StaticString = #filePath, line: UInt = #line) {
        let viewport = app.descendants(matching: .any).matching(identifier: "assemblyViewportRegion").firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertGreaterThan(viewport.frame.height, 160, file: file, line: line)
        XCTAssertGreaterThan(viewport.frame.width, 300, file: file, line: line)
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(viewport.frame), file: file, line: line)
        for id in ["assemblyClose", "assemblyPartMenu", "assemblyNext", "assemblyVoice", "assemblyToggleDetails"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.isHittable, id, file: file, line: line)
            XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(button.frame), id, file: file, line: line)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, id, file: file, line: line)
        }
        XCTAssertFalse(viewport.frame.intersects(app.buttons["assemblyNext"].frame), file: file, line: line)
        if app.frame.width > app.frame.height && app.sliders["assemblySlider"].exists {
            XCTAssertGreaterThan(viewport.frame.width, app.frame.width * 0.6, "Wide layouts should give the model most of the width", file: file, line: line)
            XCTAssertLessThanOrEqual(viewport.frame.maxX, app.buttons["assemblyPartMenu"].frame.minX, "The instructions belong beside the wide model", file: file, line: line)
        }
    }

    private func run(_ id: String, count: Int, scope: String) {
        let card = app.buttons["hubEquipment_\(id)"]; reveal(card); card.tap()
        XCTAssertTrue(app.buttons["assemblyNext"].waitForExistence(timeout: 30))
        capture("\(id)_initial_model")
        app.buttons["assemblyToggleDetails"].tap()
        app.buttons["assemblyPartMenu"].tap()
        app.buttons["Focus selected part"].tap()
        XCTAssertEqual(app.buttons["assemblyResetView"].value as? String, "Focused part")
        capture("\(id)_focused_first_part")
        app.buttons["assemblyResetView"].tap()
        app.buttons["assemblyMore"].tap(); app.buttons["assemblyCredits"].tap()
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
