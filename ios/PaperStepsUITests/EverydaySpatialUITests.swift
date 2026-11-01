import XCTest
import UIKit

/// Simulator navigation and rendered teaching references only. The labeled AR
/// fixture has no camera, tracking, object recognition or physical-task grader.
final class EverydaySpatialUITests: XCTestCase {
    private var app: XCUIApplication!
    private let courses: [(id: String, count: Int)] = [
        ("t_shirt", 6), ("towel", 3), ("flat_bedsheet", 4),
        ("square_knot", 5), ("four_in_hand", 7)
    ]

    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("These cases use explicit Simulator fixtures and audio fallbacks.")
        #endif
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        XCUIDevice.shared.orientation = .portrait
    }

    func testAllFiveCoursesUse3DAndExplicitNextAutoplaysWithoutConfirmingTheNewAction() {
        launch()
        for course in courses {
            openCourse(course.id)
            assertStudioAction(1, total: course.count)
            XCTAssertTrue(viewport.exists)
            XCTAssertFalse(app.segmentedControls["everydayViewMode"].exists)
            XCTAssertFalse(app.otherElements["everydayVisual"].exists)
            scrub(to: 0.42)
            XCTAssertTrue(app.buttons["everydayConfirm"].label.contains("Continue move"))
            app.buttons["everydayConfirm"].tap()
            waitForLabel(app.buttons["everydayPlay"], containing: "Pause move")
            app.buttons["everydayPlay"].tap()
            assertStudioAction(1, total: course.count)

            if ["t_shirt", "four_in_hand"].contains(course.id) {
                scrub(to: 0.5)
                capture("Everyday_\(course.id)_3D_mid_move")
            }
            scrub(to: 1)
            waitForLabel(app.buttons["everydayConfirm"], containing: "I've done it")
            if ["t_shirt", "four_in_hand"].contains(course.id) {
                capture("Everyday_\(course.id)_3D_target")
            }
            app.buttons["everydayConfirm"].tap()
            assertStudioAction(2, total: course.count)
            waitForLabel(app.buttons["everydayPlay"], containing: "Pause move")
            // Merely viewing action 2 must not record action 2 as completed.
            scrub(to: 1)
            XCTAssertFalse(app.staticTexts["everydayCompletion"].exists)
            assertStudioAction(2, total: course.count)
            closeCourse()
            assertNoPermissionAlerts()
        }
    }

    func testAllFiveCoursesCanEnterLabeledARAndReturnWithTheExactPausedPose() throws {
        launch(extraArguments: ["--equipment-ar-layout-fixture"])
        for course in courses {
            openCourse(course.id)
            scrub(to: 0.38)
            let paused = try XCTUnwrap(app.sliders["everydayProgressSlider"].value as? String)
            app.buttons["everydayEnterAR"].tap()
            XCTAssertTrue(app.buttons["everydayExitAR"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["everydayARCounter"].label, "1/\(course.count)")
            XCTAssertTrue(app.staticTexts["everydayARFixtureLabel"].label.contains("NO LIVE CAMERA"))
            XCTAssertFalse(app.sliders["everydayProgressSlider"].exists)
            XCTAssertTrue(viewport.exists)
            app.buttons["everydayHelp"].tap()
            XCTAssertTrue(app.buttons["everydayCloseHelp"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.sliders["everydayHelpProgressSlider"].value as? String, paused)
            app.buttons["everydayCloseHelp"].tap()
            XCTAssertTrue(app.buttons["everydayExitAR"].waitForExistence(timeout: 5))
            if ["t_shirt", "four_in_hand"].contains(course.id) {
                capture("Everyday_\(course.id)_AR_layout_NO_LIVE_CAMERA")
            }
            app.buttons["everydayExitAR"].tap()
            assertStudioAction(1, total: course.count)
            XCTAssertEqual(app.sliders["everydayProgressSlider"].value as? String, paused)
            XCTAssertTrue(app.buttons["everydayConfirm"].label.contains("Continue move"))
            closeCourse()
            assertNoPermissionAlerts()
        }
    }

    func testUnsupportedARLeavesTheSame3DLessonUsableWithoutPermissionAlerts() throws {
        launch()
        openCourse("t_shirt")
        scrub(to: 0.35)
        let paused = try XCTUnwrap(app.sliders["everydayProgressSlider"].value as? String)
        app.buttons["everydayEnterAR"].tap()
        waitForLabel(app.staticTexts["everydayARUnavailable"], containing: "supported iPhone or iPad")
        XCTAssertFalse(app.buttons["everydayExitAR"].exists)
        XCTAssertTrue(app.buttons["everydayEnterAR"].isHittable)
        XCTAssertEqual(app.sliders["everydayProgressSlider"].value as? String, paused)
        assertStudioAction(1, total: 6)
        app.buttons["everydayConfirm"].tap()
        waitForLabel(app.buttons["everydayPlay"], containing: "Pause move")
        assertStudioAction(1, total: 6)
        assertNoPermissionAlerts()
        capture("Everyday_unsupported_AR_keeps_3D_usable")
    }

    func testHelpAndBackgroundPauseWithoutAdvancingTheLearnersAction() throws {
        launch()
        openCourse("towel")
        scrub(to: 0.3)
        app.buttons["everydayConfirm"].tap()
        waitForLabel(app.buttons["everydayPlay"], containing: "Pause move")
        app.buttons["everydayHelp"].tap()
        XCTAssertTrue(app.buttons["everydayCloseHelp"].waitForExistence(timeout: 5))
        let slider = app.sliders["everydayHelpProgressSlider"]
        let helpPose = try XCTUnwrap(slider.value as? String)
        assertRemains(slider, value: helpPose)
        app.buttons["everydayCloseHelp"].tap()
        XCTAssertTrue(app.buttons["everydayConfirm"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.sliders["everydayProgressSlider"].value as? String, helpPose)
        assertStudioAction(1, total: 3)

        scrub(to: 0.24)
        let beforeBackground = try XCTUnwrap(app.sliders["everydayProgressSlider"].value as? String)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["everydayConfirm"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.sliders["everydayProgressSlider"].value as? String, beforeBackground)
        XCTAssertTrue(app.buttons["everydayConfirm"].label.contains("Continue move"))
        assertStudioAction(1, total: 3)
    }

    func testVoiceOnlyARFailureOffersRecoveryAndRestoresThePausedPose() throws {
        launch(extraArguments: ["--equipment-ar-layout-fixture"])
        openCourse("towel")
        scrub(to: 0.4)
        let paused = try XCTUnwrap(app.sliders["everydayProgressSlider"].value as? String)
        enterAR()
        app.buttons["everydayVoiceOnlyAR"].tap()
        XCTAssertTrue(app.buttons["exitVoiceOnlyAR"].waitForExistence(timeout: 5))
        waitForLabel(app.staticTexts["voiceOnlyRecoveryMessage"], containing: "Voice input is unavailable in automated tests")
        XCTAssertTrue(app.buttons["voiceOnlyRetry"].isHittable)
        XCTAssertTrue(app.buttons["voiceOnlyShowControls"].isHittable)
        XCTAssertFalse(app.buttons["everydayConfirm"].exists)
        XCTAssertFalse(app.buttons["everydayPrevious"].exists)
        XCTAssertFalse(app.buttons["everydayVoice"].exists)
        assertNoPermissionAlerts()
        app.buttons["voiceOnlyShowControls"].tap()
        XCTAssertTrue(app.buttons["everydayExitAR"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["everydayARCounter"].label, "1/3")
        app.buttons["everydayExitAR"].tap()
        XCTAssertEqual(app.sliders["everydayProgressSlider"].value as? String, paused)
        assertStudioAction(1, total: 3)
    }

    func testCleanVoiceOnlyARFixtureHasOnlyExitAndNeverStartsTheMicrophone() {
        launch(extraArguments: ["--equipment-ar-layout-fixture", "--voice-only-layout-fixture"])
        openCourse("t_shirt")
        scrub(to: 0.4)
        enterAR()
        app.buttons["everydayVoiceOnlyAR"].tap()
        XCTAssertTrue(app.buttons["exitVoiceOnlyAR"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["voiceOnlyFixtureLabel"].label.contains("MIC OFF"))
        XCTAssertTrue(app.staticTexts["everydayARFixtureLabel"].label.contains("NO LIVE CAMERA"))
        let hintGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["voiceOnlyHint"])
        XCTAssertEqual(XCTWaiter.wait(for: [hintGone], timeout: 8), .completed)
        for id in ["everydayConfirm", "everydayPrevious", "everydayHelp", "everydayExitAR", "everydayVoice", "voiceOnlyRetry", "voiceOnlyShowControls"] {
            XCTAssertFalse(app.buttons[id].exists, id)
        }
        XCTAssertTrue(app.buttons["exitVoiceOnlyAR"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["exitVoiceOnlyAR"].frame.height, 44)
        assertNoPermissionAlerts()
        capture("Everyday_clean_voice_only_AR_MIC_OFF_NO_LIVE_CAMERA")
        app.buttons["exitVoiceOnlyAR"].tap()
        XCTAssertTrue(app.buttons["everydayExitAR"].waitForExistence(timeout: 5))
    }

    func testIPadARControlsStayReachableAcrossRotation() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Tablet rotation check") }
        launch(extraArguments: ["--equipment-ar-layout-fixture"])
        openCourse("t_shirt")
        scrub(to: 0.4)
        enterAR()
        for landscape in [false, true, false] {
            XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let size = XCUIScreen.main.screenshot().image.size
                return landscape ? size.width > size.height : size.height > size.width
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
            for id in ["everydayExitAR", "everydayConfirm", "everydayHelp", "everydayVoiceOnlyAR"] {
                let button = app.buttons[id]
                XCTAssertTrue(button.isHittable, id)
                XCTAssertTrue(app.frame.contains(button.frame), id)
                XCTAssertGreaterThanOrEqual(button.frame.height, 44, id)
            }
            capture("Everyday_iPad_AR_\(landscape ? "landscape" : "portrait")_NO_LIVE_CAMERA")
        }
    }

    private func launch(extraArguments: [String] = []) {
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--tutorial-hub", "--reset-everyday-progress"] + extraArguments
        app.launch()
        XCTAssertTrue(app.segmentedControls["hubFilter"].waitForExistence(timeout: 15))
    }

    private var viewport: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "everydayViewport").firstMatch
    }

    private func openCourse(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let filter = app.segmentedControls["hubFilter"]
        if filter.exists && filter.buttons["Everyday"].exists {
            reveal(filter, file: file, line: line)
            filter.buttons["Everyday"].tap()
        }
        let tile = app.buttons["hubCourse_\(id)"]
        reveal(tile, file: file, line: line)
        tile.tap()
        XCTAssertTrue(app.buttons["everydayConfirm"].waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(viewport.waitForExistence(timeout: 5), file: file, line: line)
    }

    private func closeCourse() {
        app.buttons["everydayClose"].tap()
        XCTAssertTrue(app.segmentedControls["hubFilter"].waitForExistence(timeout: 5))
    }

    private func enterAR() {
        app.buttons["everydayEnterAR"].tap()
        XCTAssertTrue(app.buttons["everydayExitAR"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["everydayARFixtureLabel"].label.contains("NO LIVE CAMERA"))
    }

    private func scrub(to progress: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        let slider = app.sliders["everydayProgressSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(slider.isHittable, file: file, line: line)
        slider.adjust(toNormalizedSliderPosition: progress)
    }

    private func assertStudioAction(_ index: Int, total: Int, file: StaticString = #filePath, line: UInt = #line) {
        waitForLabel(app.staticTexts["everydayCounter"], containing: "ACTION \(index) OF \(total)", file: file, line: line)
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed, file: file, line: line)
    }

    private func assertRemains(_ element: XCUIElement, value: String, file: StaticString = #filePath, line: UInt = #line) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (element.value as? String) != value }, object: element)
        changed.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 1.2), .completed, file: file, line: line)
    }

    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            let scroll = app.scrollViews.firstMatch
            if element.exists && element.frame.midY > 0 && element.frame.midY < scroll.frame.midY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, element.identifier, file: file, line: line)
    }

    private func assertNoPermissionAlerts(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(app.alerts.firstMatch.exists, file: file, line: line)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists, file: file, line: line)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
