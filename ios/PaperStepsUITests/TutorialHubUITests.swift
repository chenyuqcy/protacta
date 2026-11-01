import XCTest
import UIKit

/// Normal hub navigation with authored diagrams. These checks do not verify
/// physical folds, knot topology on real cord, or camera registration.
final class TutorialHubUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--tutorial-hub", "--reset-everyday-progress"]
        app.launch()
        XCTAssertTrue(app.buttons["hubOrigami"].waitForExistence(timeout: 15))
    }
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    func testAllFiveEverydayCoursesHaveCompleteConfirmedFlows() {
        capture("Protacta_course_hub")
        for (id, count) in [("t_shirt", 6), ("towel", 3), ("flat_bedsheet", 4), ("square_knot", 5), ("four_in_hand", 7)] {
            tapHome("hubCourse_\(id)")
            XCTAssertTrue(app.staticTexts["everydayCounter"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 1 OF \(count)")
            XCTAssertFalse(app.buttons["checkPracticeStep"].exists, "An illustrated course has no paper camera grader")
            capture("\(id)_start")
            for action in 1...count {
                XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION \(action) OF \(count)")
                let slider = app.sliders["everydayProgressSlider"]
                reveal(slider); slider.adjust(toNormalizedSliderPosition: 1)
                let checkpoints: [String: [Int]] = ["t_shirt": [1, 2], "square_knot": [2, 4], "four_in_hand": [2, 4, 5]]
                if checkpoints[id]?.contains(action) == true { capture("\(id)_action\(action)_target") }
                if action == count { capture("\(id)_final_visual") }
                tapPlayer("everydayConfirm")
            }
            XCTAssertTrue(app.staticTexts["everydayCompletion"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["everydayCompletion"].label.contains("confirmed by you"))
            app.buttons["everydayClose"].tap()
            XCTAssertTrue(app.buttons["hubOrigami"].waitForExistence(timeout: 5))
            if id == "towel" {
                tapHome("hubCourse_towel")
                XCTAssertTrue(app.staticTexts["everydayCompletion"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "everydayViewport").firstMatch.value as? String == "Action 3, movement 100 percent", "A restored completion must show the final visual")
                app.buttons["everydayClose"].tap()
            }
        }
    }

    func testHelpReplayAndProgressSurviveReturnAndRelaunchIndependently() {
        tapHome("hubCourse_towel")
        tapPlayer("everydayConfirm")
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 2 OF 3")
        tapPlayer("everydayHelp")
        XCTAssertTrue(app.navigationBars["Help with this action"].waitForExistence(timeout: 5))
        let helpReplay = app.buttons["everydayHelpReplay"]
        reveal(helpReplay); helpReplay.tap()
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 2 OF 3")
        app.buttons["everydayClose"].tap()
        tapHome("hubCourse_t_shirt")
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 1 OF 6")
        app.buttons["everydayClose"].tap()
        app.terminate()
        app.launchArguments = ["--ui-testing", "--tutorial-hub"]
        app.launch()
        tapHome("hubCourse_towel")
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 2 OF 3")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 2 OF 3")
        tapPlayer("everydayPrevious")
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 1 OF 3")
    }

    func testOrigamiAndAerisAreReachableWithReleaseTabGate() {
        tapHome("hubOrigami")
        XCTAssertTrue(app.buttons["viewportOptions"].waitForExistence(timeout: 15))
        app.buttons["returnTutorialHub"].tap()
        tapHome("hubProductManual")
        let next = app.buttons["nextStep"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in next.exists && next.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        capture("Aeris_integrated_product_guide")
        reveal(next); next.tap()
        XCTAssertTrue(app.staticTexts["stepTitle"].label.contains("release tab"))
        XCTAssertFalse(next.isEnabled)
        let press = app.buttons["pressRelease"]
        reveal(press)
        let pressReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in press.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [pressReady], timeout: 5), .completed)
        press.tap()
        let released = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in next.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [released], timeout: 5), .completed)
        next.tap()
        XCTAssertTrue(app.staticTexts["stepTitle"].label.contains("rear cover"))
        let close = app.buttons["aerisClose"]; reveal(close); close.tap()
        XCTAssertTrue(app.buttons["hubOrigami"].waitForExistence(timeout: 5))
    }

    func testTieFrontBandFormsDuringItsActionAndRemainsForThreading() {
        capture("Protacta_hub_final_layout")
        tapHome("hubCourse_four_in_hand")
        tapPlayer("everydayConfirm"); tapPlayer("everydayConfirm")
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 3 OF 7")
        tapPlayer("everydayShowStart")
        capture("Tie_front_band_before")
        XCTAssertEqual(app.sliders["everydayProgressSlider"].value as? String, "0%")
        tapPlayer("everydayShowTarget")
        capture("Tie_front_band_target")
        XCTAssertEqual(app.sliders["everydayProgressSlider"].value as? String, "100%")
        tapPlayer("everydayConfirm")
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 4 OF 7")
        tapPlayer("everydayShowTarget")
        capture("Tie_neck_loop_after_band")
    }

    func testTabletLandscapeCanPlayAndConfirmAnEverydayAction() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Tablet layout check") }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.app.frame.width > self.app.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        tapHome("hubCourse_t_shirt")
        let courseLandscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.app.frame.width > self.app.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [courseLandscape], timeout: 5), .completed)
        tapPlayer("everydayPlay")
        tapPlayer("everydaySpeed")
        XCTAssertEqual(app.buttons["everydaySpeed"].value as? String, "Slow")
        let confirm = app.buttons["everydayConfirm"]
        reveal(confirm)
        XCTAssertLessThanOrEqual(confirm.frame.maxX, app.frame.maxX)
        XCTAssertLessThanOrEqual(confirm.frame.maxY, app.frame.maxY)
        tapPlayer("everydayConfirm")
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 2 OF 6")
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        // The iOS 26.5 Simulator can return a portrait raster even while its
        // accessibility window reports landscape. Record both; don't present
        // the raster as proof of physical-device landscape rendering.
        let screenShot = XCUIScreen.main.screenshot()
        let image = XCTAttachment(screenshot: screenShot)
        image.name = "Everyday_iPad_screen_capture"; image.lifetime = .keepAlways; add(image)
        let geometry = XCTAttachment(string: "App frame: \(app.frame); screenshot points: \(screenShot.image.size); image orientation: \(screenShot.image.imageOrientation.rawValue)")
        geometry.name = "Verified_iPad_geometry"; geometry.lifetime = .keepAlways; add(geometry)
        app.buttons["everydayClose"].tap()
    }

    private func tapHome(_ id: String) {
        let button = app.buttons[id]
        for _ in 0..<6 where !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
        for _ in 0..<6 where !button.isHittable { app.scrollViews.firstMatch.swipeDown() }
        XCTAssertTrue(button.isHittable, id); button.tap()
    }
    private func tapPlayer(_ id: String) {
        if id == "everydayConfirm" && !app.buttons[id].label.contains("I've done it") {
            let slider = app.sliders["everydayProgressSlider"]
            if slider.exists { slider.adjust(toNormalizedSliderPosition: 1) }
        }
        if ["everydayShowStart", "everydayShowTarget", "everydayReplay", "everydaySpeed"].contains(id) {
            let more = app.buttons["everydayMore"]; reveal(more); more.tap()
        }
        let b = app.buttons[id]; reveal(b); b.tap()
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
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
