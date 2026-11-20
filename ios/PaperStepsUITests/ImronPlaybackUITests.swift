import XCTest

/// Exercises the shipped controls, with an isolated progress domain. Simulator
/// animation runs at the test duration, so these tests do not measure 0.5x/2x
/// wall-clock speed or certify a physical fold. Attachments show selection style.
final class ImronPlaybackUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["PROTACTA_PROGRESS_TEST_SUITE"] = "org.realitycore.protacta.prototype.uitests.\(UUID().uuidString)"
        app.launchArguments = ["--ui-testing", "--tutorial-hub", "--reset-learning-progress", "--reset-everyday-progress"]
        app.launch()
        openDartFromHome()
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP 1 OF 10")
        XCTAssertEqual(app.foldProgressValue, "0%")
        XCTAssertEqual(app.buttons["autoPlayToggle"].value as? String, "Off")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testSpeedSelectionPersistsAndManualInteractionCancelsAutoPlay() throws {
        app.buttons["speed_half"].tap()
        XCTAssertTrue(app.staticTexts["½×"].waitForExistence(timeout: 5))
        capture("Imron_speed_half_selected_before_relaunch")
        relaunchAndResume()
        XCTAssertTrue(app.staticTexts["½×"].waitForExistence(timeout: 5))
        capture("Imron_speed_half_selected_after_relaunch")

        app.buttons["speed_two"].tap()
        waitForDoubleSpeedBadge()
        capture("Imron_speed_two_selected_before_relaunch")
        relaunchAndResume()
        waitForDoubleSpeedBadge()
        capture("Imron_speed_two_selected_after_relaunch")

        // Start at the paused first fold, then wait for an observed step change;
        // no tap needs to land inside the 0.35-second test animation.
        app.buttons["autoPlayToggle"].tap()
        waitForAutoPlay("On")
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let self else { return false }
            let label = self.app.staticTexts["stepCounter"].label
            return label.hasPrefix("STEP ") && label != "STEP 1 OF 10"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 12), .completed)
        app.buttons["autoPlayToggle"].tap()
        waitForAutoPlay("Off")
        try assertPoseRemainsPaused(attachment: "Imron_autoplay_off_keeps_current_pose")

        app.buttons["autoPlayToggle"].tap()
        waitForAutoPlay("On")
        app.sliders["foldTimeline"].adjust(toNormalizedSliderPosition: 0.42)
        waitForAutoPlay("Off")
        let progress = try XCTUnwrap(app.foldProgressValue)
        XCTAssertNotEqual(progress, "0%")
        XCTAssertNotEqual(progress, "100%")
        XCTAssertTrue(app.buttons["nextStep"].label.contains("Continue"))
        try assertPoseRemainsPaused(attachment: "Imron_scrub_cancels_autoplay_without_delayed_jump")
    }

    func testAutoPlayEndsAtFinalPoseAndRequiresExplicitFinish() throws {
        app.buttons["autoPlayToggle"].tap()
        waitForAutoPlay("On")
        let finish = app.buttons["nextStep"]
        let finalPose = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Finish"), object: finish)
        XCTAssertEqual(XCTWaiter.wait(for: [finalPose], timeout: 40), .completed)
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP 10 OF 10")
        XCTAssertEqual(app.foldProgressValue, "100%")
        waitForAutoPlay("Off")
        try assertPoseRemainsPaused(attachment: "Imron_final_animation_waits_for_manual_finish")
        XCTAssertEqual(finish.label, "Finish")

        finish.tap()
        let complete = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "LESSON COMPLETE"), object: app.staticTexts["stepCounter"])
        XCTAssertEqual(XCTWaiter.wait(for: [complete], timeout: 5), .completed)
        XCTAssertEqual(finish.label, "Start over")
        XCTAssertFalse(app.buttons["autoPlayToggle"].exists)
        capture("Imron_explicit_finish_confirms_lesson")
    }

    private func openDartFromHome() {
        let entry = app.buttons["hubClassicDart"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        app.revealLessonElement(entry)
        entry.tap()
        XCTAssertTrue(app.sliders["foldTimeline"].waitForExistence(timeout: 10))
    }

    private func relaunchAndResume() {
        app.buttons["returnTutorialHub"].tap()
        XCTAssertTrue(app.buttons["hubClassicDart"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing", "--tutorial-hub"]
        app.launch()
        openDartFromHome()
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP 1 OF 10")
        XCTAssertEqual(app.foldProgressValue, "0%")
    }

    private func waitForDoubleSpeedBadge() {
        // Find the current-rate badge above the instruction title, rather than
        // the always-present 2x button. Selected color still needs visual review.
        let badge = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let self else { return false }
            let title = self.app.staticTexts["stepTitle"]
            guard title.exists else { return false }
            return self.app.staticTexts.matching(NSPredicate(format: "label == %@", "2×"))
                .allElementsBoundByIndex.contains { $0.frame.maxY < title.frame.minY }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [badge], timeout: 5), .completed)
    }

    private func waitForAutoPlay(_ value: String) {
        let state = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: app.buttons["autoPlayToggle"])
        XCTAssertEqual(XCTWaiter.wait(for: [state], timeout: 5), .completed)
    }

    private func assertPoseRemainsPaused(attachment: String) throws {
        let step = app.staticTexts["stepCounter"].label
        let progress = try XCTUnwrap(app.foldProgressValue)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let self else { return false }
            return self.app.staticTexts["stepCounter"].label != step || self.app.foldProgressValue != progress
        }, object: nil)
        changed.isInverted = true
        // Longer than the 1.6-second auto-play dwell: catches stale deadlines.
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 2.5), .completed)
        XCTAssertEqual(app.buttons["autoPlayToggle"].value as? String, "Off")
        capture(attachment)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
