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

    func testStepFocusEnlargesTheFoldedTowelAndRestoresStableMovementFraming() throws {
        launch()
        openCourse("towel")
        goToStudioAction(3, total: 3)
        scrub(to: 1)
        let slider = app.sliders["everydayProgressSlider"]
        let closedPose = try XCTUnwrap(slider.value as? String)
        let actionFrame = try focusSnapshot()
        XCTAssertEqual(actionFrame.mode, "action")
        capture("Focus_towel_last_action_before_detail")

        app.buttons["everydayFocusStep"].tap()
        let detailFrame = try focusSnapshot()
        XCTAssertEqual(detailFrame.mode, "detail")
        XCTAssertLessThan(detailFrame.radius, actionFrame.radius * 0.75,
                          "The closed towel should visibly enlarge when explicitly focused")
        XCTAssertEqual(slider.value as? String, closedPose)
        assertStudioAction(3, total: 3)
        capture("Focus_towel_closed_detail")

        app.buttons["everydayFocusStep"].tap()
        XCTAssertEqual(try focusSnapshot().raw, actionFrame.raw,
                       "The second tap returns to the complete current movement")
        XCTAssertEqual(slider.value as? String, closedPose)
        app.buttons["everydayFocusStep"].tap()
        scrub(to: 0.4)
        XCTAssertEqual(try focusSnapshot().raw, actionFrame.raw,
                       "Scrubbing exits detail once before restoring the fixed action frame")
        for progress in [CGFloat(0.1), 0.95, 0.4] {
            scrub(to: progress)
            XCTAssertEqual(try focusSnapshot().raw, actionFrame.raw,
                           "The camera must not track each slider movement")
            assertStudioAction(3, total: 3)
        }

        let paused = try XCTUnwrap(slider.value as? String)
        viewport.pinch(withScale: 0.7, velocity: -1)
        XCTAssertGreaterThan(try focusSnapshot().zoom, 1.05,
                             "Verify the manual zoom gesture actually reached the renderer")
        app.buttons["everydayFocusStep"].tap()
        XCTAssertEqual(try focusSnapshot().mode, "detail")
        XCTAssertEqual(try focusSnapshot().zoom, 1, accuracy: 0.00001)
        XCTAssertEqual(slider.value as? String, paused)
        assertRemains(slider, value: paused)

        scrub(to: 1)
        app.buttons["everydayConfirm"].tap()
        XCTAssertTrue(app.staticTexts["everydayCompletion"].waitForExistence(timeout: 5))
        let completedFrame = try focusSnapshot()
        XCTAssertEqual(completedFrame.mode, "complete")
        XCTAssertLessThan(completedFrame.radius, actionFrame.radius * 0.75)
        XCTAssertEqual(viewport.value as? String, "Action 3, movement 100 percent")
        capture("Focus_towel_completed")
    }

    func testLateBedsheetFramingAndPausedPoseSurviveARLayoutRoundTrip() throws {
        launch(extraArguments: ["--equipment-ar-layout-fixture"])
        openCourse("flat_bedsheet")
        scrub(to: 0.4)
        let firstFrame = try focusSnapshot()
        goToStudioAction(4, total: 4)
        scrub(to: 0.37)
        let lateFrame = try focusSnapshot()
        XCTAssertEqual(lateFrame.mode, "action")
        XCTAssertLessThan(lateFrame.radius, firstFrame.radius * 0.72,
                          "Later folds should use their smaller movement bounds, not the entire course")
        capture("Focus_bedsheet_last_action")

        enterAR()
        XCTAssertFalse(app.buttons["everydayFocusStep"].exists,
                       "Studio camera fitting must not rescale or recenter a placed AR object")
        let arSlider = app.sliders["everydayARProgressSlider"]
        arSlider.adjust(toNormalizedSliderPosition: 0.65)
        let arPose = try XCTUnwrap(arSlider.value as? String)
        app.buttons["everydayExitAR"].tap()
        assertStudioAction(4, total: 4)
        XCTAssertEqual(app.sliders["everydayProgressSlider"].value as? String, arPose)
        XCTAssertEqual(try focusSnapshot().raw, lateFrame.raw)
        capture("Focus_bedsheet_after_AR_layout")
    }

    func testTabletRotationPreservesTheFocusedStepAndPausedPose() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Tablet focused-camera check") }
        launch()
        openCourse("towel")
        goToStudioAction(3, total: 3)
        scrub(to: 1)
        app.buttons["everydayFocusStep"].tap()
        let focused = try focusSnapshot()
        XCTAssertEqual(focused.mode, "detail")
        let slider = app.sliders["everydayProgressSlider"]
        let pose = try XCTUnwrap(slider.value as? String)

        for landscape in [true, false] {
            XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                landscape ? self.app.frame.width > self.app.frame.height : self.app.frame.height > self.app.frame.width
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
            XCTAssertEqual(try focusSnapshot().raw, focused.raw)
            XCTAssertEqual(slider.value as? String, pose)
            XCTAssertTrue(slider.isHittable)
            XCTAssertTrue(app.buttons["everydayFocusStep"].isHittable)
            XCTAssertTrue(app.frame.contains(app.buttons["everydayFocusStep"].frame))
            assertStudioAction(3, total: 3)
            capture("Focus_iPad_\(landscape ? "landscape" : "portrait")")
        }
    }

    func testCompactInstructionsAndHomeResumeKeepTheSamePractice() throws {
        launch()
        capture("Refined_home")
        openCourse("towel")
        scrub(to: 0.42)
        let slider = app.sliders["everydayProgressSlider"]
        let paused = try XCTUnwrap(slider.value as? String)
        let disclosure = app.buttons["everydayInstructionDisclosure"]
        XCTAssertFalse(app.staticTexts["everydayInstruction"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "everydayPlay").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "everydayHelp").count, 1)
        XCTAssertEqual(app.buttons["everydayPlay"].frame.midY, slider.frame.midY, accuracy: 4,
                       "Playback and seeking should share one control row")
        capture("Refined_towel_compact")
        disclosure.tap()
        XCTAssertTrue(app.staticTexts["everydayInstruction"].waitForExistence(timeout: 3))
        XCTAssertEqual(slider.value as? String, paused)
        assertStudioAction(1, total: 3)
        assertRemains(slider, value: paused)
        XCTAssertLessThan(app.staticTexts["everydayInstruction"].frame.maxY, slider.frame.minY)
        XCTAssertLessThan(app.buttons["everydayConfirm"].frame.maxY, app.frame.maxY - 15)
        capture("Refined_towel_instructions")
        disclosure.tap()
        XCTAssertFalse(app.staticTexts["everydayInstruction"].exists)
        XCTAssertEqual(slider.value as? String, paused)
        scrub(to: 1)
        app.buttons["everydayConfirm"].tap()
        assertStudioAction(2, total: 3)
        scrub(to: 0.5)
        closeCourse()
        let tile = app.buttons["hubCourse_towel"]
        reveal(tile)
        XCTAssertTrue((tile.value as? String)?.contains("Continue at action 2 of 3") == true)
        XCTAssertTrue((tile.value as? String)?.contains("1 actions confirmed by you") == true)
        capture("Refined_everyday_resume")
        tile.tap()
        assertStudioAction(2, total: 3)
    }

    func testAccessibleTextKeepsInstructionsAndPlaybackReachable() throws {
        launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openCourse("four_in_hand")
        let disclosure = app.buttons["everydayInstructionDisclosure"]
        reveal(disclosure)
        XCTAssertGreaterThan(disclosure.frame.height, 60, "Verify that enlarged text is actually active")
        disclosure.tap()
        XCTAssertTrue(app.staticTexts["everydayInstruction"].waitForExistence(timeout: 3))
        reveal(app.staticTexts["everydayInstruction"])
        capture("Refined_accessible_instructions")
        let slider = app.sliders["everydayProgressSlider"]
        reveal(slider)
        slider.adjust(toNormalizedSliderPosition: 0.4)
        let paused = try XCTUnwrap(slider.value as? String)
        assertRemains(slider, value: paused)
        XCTAssertGreaterThan(viewport.frame.height, 150, "Large text must not remove the model")
        slider.adjust(toNormalizedSliderPosition: 1)
        let next = app.buttons["everydayConfirm"]
        reveal(next)
        capture("Refined_accessible_controls")
        next.tap()
        reveal(app.staticTexts["everydayCounter"])
        assertStudioAction(2, total: 7)
    }

    func testTabletLayoutKeepsThePausedModelWhileRotatingAndReading() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Tablet layout check") }
        launch()
        openCourse("towel")
        scrub(to: 0.42)
        let slider = app.sliders["everydayProgressSlider"]
        let paused = try XCTUnwrap(slider.value as? String)
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.app.frame.width > self.app.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        XCTAssertTrue(slider.isHittable)
        XCTAssertEqual(slider.value as? String, paused)
        XCTAssertLessThanOrEqual(viewport.frame.maxX, slider.frame.minX,
                                 "Landscape places controls alongside the model")
        app.buttons["everydayInstructionDisclosure"].tap()
        XCTAssertTrue(app.staticTexts["everydayInstruction"].exists)
        XCTAssertEqual(slider.value as? String, paused)
        assertRemains(slider, value: paused)
        XCTAssertLessThan(app.staticTexts["everydayInstruction"].frame.maxY, slider.frame.minY)
        let geometry = XCTAttachment(string: "App frame: \(app.frame); viewport: \(viewport.frame); slider: \(slider.frame); screen raster: \(XCUIScreen.main.screenshot().image.size). Simulator raster orientation can lag its accessibility layout.")
        geometry.name = "Refined_iPad_landscape_geometry"; geometry.lifetime = .keepAlways; add(geometry)
        capture("Refined_iPad_landscape")
        XCUIDevice.shared.orientation = .portrait
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.app.frame.height > self.app.frame.width }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 5), .completed)
        XCTAssertTrue(slider.isHittable)
        XCTAssertEqual(slider.value as? String, paused)
        assertStudioAction(1, total: 3)
        capture("Refined_iPad_portrait")
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
            XCTAssertTrue(app.buttons["everydayConfirm"].label.contains("Continue"))
            app.buttons["everydayConfirm"].tap()
            waitForLabel(app.buttons["everydayPlay"], containing: "Pause move")
            app.buttons["everydayPlay"].tap()
            assertStudioAction(1, total: course.count)

            scrub(to: 0.5)
            capture("Everyday_\(course.id)_3D_mid_move")
            scrub(to: 1)
            waitForLabel(app.buttons["everydayConfirm"], containing: "I've done it")
            capture("Everyday_\(course.id)_3D_target")
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

    func testRepeatedARDraggingKeepsTheSameUnconfirmedAction() throws {
        launch(extraArguments: ["--equipment-ar-layout-fixture"])
        openCourse("t_shirt")
        scrub(to: 0.38)
        let studio = app.sliders["everydayProgressSlider"]
        let studioPercent = try XCTUnwrap(Double(try XCTUnwrap(studio.value as? String).replacingOccurrences(of: "%", with: "")))
        XCTAssertEqual(studioPercent, 38, accuracy: 12)
        enterAR()
        let slider = app.sliders["everydayARProgressSlider"]
        let confirm = app.buttons["everydayConfirm"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        for target in [CGFloat(0.18), 0.82, 0.35, 0.68, 0.05, 0.95, 0.5] {
            let before = "target=\(target), slider=\(slider.frame), next=\(confirm.frame), value=\(slider.value ?? "nil"), counter=\(app.staticTexts["everydayARCounter"].label)"
            let note = XCTAttachment(string: before); note.name = "AR_drag_before_\(target)"; note.lifetime = .keepAlways; add(note)
            XCTAssertLessThanOrEqual(slider.frame.maxY, confirm.frame.minY, "The slider and confirmation hit targets must stay separate")
            slider.adjust(toNormalizedSliderPosition: target)
            capture("AR_repeated_drag_\(Int(target * 100))_NO_LIVE_CAMERA")
            XCTAssertEqual(app.staticTexts["everydayARCounter"].label, "1/6")
            let percent = try XCTUnwrap(Double(try XCTUnwrap(slider.value as? String).replacingOccurrences(of: "%", with: "")))
            XCTAssertEqual(percent, Double(target * 100), accuracy: 12)
            XCTAssertTrue(app.buttons["everydayPlay"].label.contains("Play move"))
        }
        let finalPose = try XCTUnwrap(slider.value as? String)
        app.buttons["everydayExitAR"].tap()
        assertStudioAction(1, total: 6)
        XCTAssertEqual(studio.value as? String, finalPose)
        XCTAssertFalse(app.staticTexts["everydayCompletion"].exists)
    }

    func testAllFiveCoursesCanScrubInLabeledARAndReturnWithTheExactPausedPose() throws {
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
            let arSlider = app.sliders["everydayARProgressSlider"]
            XCTAssertTrue(arSlider.waitForExistence(timeout: 5))
            XCTAssertTrue(arSlider.isHittable)
            XCTAssertEqual(arSlider.value as? String, paused)
            arSlider.adjust(toNormalizedSliderPosition: 0.65)
            let arPose = try XCTUnwrap(arSlider.value as? String)
            XCTAssertNotEqual(arPose, paused, "AR scrubbing must update the same movement shown in the studio")
            XCTAssertEqual(app.staticTexts["everydayARCounter"].label, "1/\(course.count)",
                           "Seeking a model pose cannot confirm the learner's physical action")
            waitForLabel(app.buttons["everydayPlay"], containing: "Play move")
            app.buttons["everydayMore"].tap()
            let alignment = app.buttons["everydayAlignObject"]
            if ["t_shirt", "towel", "flat_bedsheet"].contains(course.id) {
                XCTAssertTrue(alignment.waitForExistence(timeout: 3), "Flat cloth courses should offer manual alignment")
                alignment.tap()
                XCTAssertTrue(app.buttons["everydayCancelAlignment"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["everydayAlignmentInstructions"].exists)
                XCTAssertFalse(app.buttons["everydayCaptureAlignment"].isEnabled,
                               "The labeled layout fixture must never invent physical alignment samples")
                capture("Everyday_\(course.id)_manual_alignment_NO_LIVE_CAMERA")
                app.buttons["everydayCancelAlignment"].tap()
                XCTAssertFalse(app.buttons["everydayCancelAlignment"].exists)
                XCTAssertEqual(arSlider.value as? String, arPose)
            } else {
                XCTAssertFalse(alignment.exists, "Cloth registration must not be offered as knot or worn-tie tracking")
                // SwiftUI's Menu can expose the underlying More button with an
                // invalid hit point while open. Dismiss on the empty, left-side
                // viewport, away from the top-right menu and bottom controls.
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap()
            }
            XCTAssertEqual(arSlider.value as? String, arPose,
                           "Closing a menu or cancelling calibration must not change the paused movement")
            app.buttons["everydayHelp"].tap()
            XCTAssertTrue(app.buttons["everydayCloseHelp"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.sliders["everydayHelpProgressSlider"].value as? String, arPose)
            app.buttons["everydayCloseHelp"].tap()
            XCTAssertTrue(app.buttons["everydayExitAR"].waitForExistence(timeout: 5))
            capture("Everyday_\(course.id)_AR_layout_NO_LIVE_CAMERA")
            app.buttons["everydayExitAR"].tap()
            assertStudioAction(1, total: course.count)
            XCTAssertEqual(app.sliders["everydayProgressSlider"].value as? String, arPose)
            XCTAssertTrue(app.buttons["everydayConfirm"].label.contains("Continue"))
            closeCourse()
            assertNoPermissionAlerts()
        }
    }

    func testClothSurfacesRemainUsableAcrossEveryLayerAndAtTheFoldEndpoint() throws {
        launch()
        let filter = app.segmentedControls["hubFilter"]
        reveal(filter)
        filter.buttons["Everyday"].tap()
        reveal(app.buttons["hubCourse_towel"])
        capture("Surface_catalog_clothes")
        for course in courses where ["towel", "t_shirt", "flat_bedsheet"].contains(course.id) {
            openCourse(course.id)
            for action in 1...course.count {
                assertStudioAction(action, total: course.count)
                scrub(to: 0)
                XCTAssertTrue(app.buttons["everydayPlay"].isEnabled)
                if action == 1 { capture("Surface_\(course.id)_flat") }
                scrub(to: 0.5)
                capture("Surface_\(course.id)_action_\(action)_mid")
                scrub(to: 1)
                // Reversing a near-closed fold must stay paused, drawable and
                // on this same action; reaching the endpoint is not a completion.
                scrub(to: 0.97)
                XCTAssertTrue(app.buttons["everydayPlay"].isEnabled)
                assertStudioAction(action, total: course.count)
                scrub(to: 1)
                waitForLabel(app.buttons["everydayConfirm"], containing: "I've done it")
                capture("Surface_\(course.id)_action_\(action)_closed")
                app.buttons["everydayConfirm"].tap()
            }
            XCTAssertTrue(app.staticTexts["everydayCompletion"].waitForExistence(timeout: 5))
            XCTAssertEqual(viewport.value as? String, "Action \(course.count), movement 100 percent")
            closeCourse()
        }
    }

    /// Focused visual evidence for the four newly refined references. Sampling
    /// the penultimate action gives a bend/loop sequence plus the adjacent final
    /// action boundary without repeating the full-course screenshot suite.
    /// Screenshots require human geometry review; AX values do not prove that
    /// surfaces or strands are continuous, nor validate a real physical task.
    func testRefinedClothAndKnotQuarterPosesKeepExplicitActionProgress() throws {
        launch()
        for course in courses where course.id != "towel" {
            let sampledAction = course.count - 1
            openCourse(course.id)
            for action in 1..<sampledAction {
                assertStudioAction(action, total: course.count)
                try positionQuarterPose(at: 1)
                app.buttons["everydayConfirm"].tap()
            }
            assertStudioAction(sampledAction, total: course.count)
            let slider = app.sliders["everydayProgressSlider"]

            for progress in [CGFloat(0), 0.25, 0.5, 0.75, 1] {
                try positionQuarterPose(at: progress)
                assertStudioAction(sampledAction, total: course.count)
                XCTAssertFalse(app.staticTexts["everydayCompletion"].exists)
                let actual = try XCTUnwrap(Double(try XCTUnwrap(slider.value as? String)
                    .replacingOccurrences(of: "%", with: "")))
                XCTAssertEqual(actual, Double(progress * 100), accuracy: 6,
                               "The rendered sample must follow the requested slider position")
                capture("Refined_\(course.id)_action_\(sampledAction)_p\(Int(progress * 100))")
            }

            // A reverse drag changes only the animated pose. Returning home
            // checks the persisted confirmation count, not just a visible label.
            try positionQuarterPose(at: 0.25)
            let reversed = try XCTUnwrap(slider.value as? String)
            assertRemains(slider, value: reversed)
            assertStudioAction(sampledAction, total: course.count)
            XCTAssertTrue(app.buttons["everydayConfirm"].label.contains("Continue"))
            closeCourse()
            let tile = app.buttons["hubCourse_\(course.id)"]
            reveal(tile)
            XCTAssertTrue((tile.value as? String)?.contains("Continue at action \(sampledAction) of \(course.count)") == true)
            XCTAssertTrue((tile.value as? String)?.contains("\(sampledAction - 1) actions confirmed by you") == true)

            tile.tap()
            assertStudioAction(sampledAction, total: course.count)
            try positionQuarterPose(at: 1)
            waitForLabel(app.buttons["everydayConfirm"], containing: "I've done it")
            capture("Refined_\(course.id)_boundary_previous_end")
            app.buttons["everydayConfirm"].tap()
            assertStudioAction(course.count, total: course.count)
            try positionQuarterPose(at: 0)
            capture("Refined_\(course.id)_boundary_next_start")
            XCTAssertFalse(app.staticTexts["everydayCompletion"].exists)

            try positionQuarterPose(at: 1)
            waitForLabel(app.buttons["everydayConfirm"], containing: "Finish")
            assertRemains(slider, value: "100%")
            assertStudioAction(course.count, total: course.count)
            XCTAssertFalse(app.staticTexts["everydayCompletion"].exists,
                           "Viewing the final model must still wait for the learner's confirmation")
            capture("Refined_\(course.id)_final_unconfirmed")
            closeCourse()
            reveal(tile)
            XCTAssertTrue((tile.value as? String)?.contains("Continue at action \(course.count) of \(course.count)") == true)
            XCTAssertTrue((tile.value as? String)?.contains("\(course.count - 1) actions confirmed by you") == true)
        }
    }

    /// Native slider gestures can miss a requested normalized position because
    /// of thumb/hit geometry and drag direction. For interior samples, reset to
    /// the start before each of at most three correction attempts so the target
    /// is always approached forward. Start/interior samples retain the original
    /// six-percentage-point limit. If the end drag lands just short, use Play
    /// to finish the movement through the real controls, without confirming it.
    /// This helper is intentionally limited to the quarter-pose visual journey.
    private func positionQuarterPose(at target: CGFloat, file: StaticString = #filePath, line: UInt = #line) throws {
        let slider = app.sliders["everydayProgressSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(slider.isHittable, file: file, line: line)
        let actionBefore = app.staticTexts["everydayCounter"].label
        var requested = min(1, max(0, target))
        var observed: Double = 0
        var trace: [String] = []
        let interiorSample = target > 0 && target < 1
        for attempt in 1...3 {
            if interiorSample {
                slider.adjust(toNormalizedSliderPosition: 0)
                let baselineValue = try XCTUnwrap(slider.value as? String, file: file, line: line)
                let baseline = try XCTUnwrap(Double(baselineValue.replacingOccurrences(of: "%", with: "")), file: file, line: line)
                let reset = "attempt=\(attempt), target=\(Double(target) * 100)%, resetRequested=0%, baselineObserved=\(baseline)%"
                trace.append(reset)
                print("Quarter-pose sampling: \(reset)")
            }
            slider.adjust(toNormalizedSliderPosition: requested)
            let value = try XCTUnwrap(slider.value as? String, file: file, line: line)
            observed = try XCTUnwrap(Double(value.replacingOccurrences(of: "%", with: "")), file: file, line: line) / 100
            let entry = "attempt=\(attempt), target=\(Double(target) * 100)%, requested=\(Double(requested) * 100)%, observed=\(observed * 100)%"
            trace.append(entry)
            print("Quarter-pose sampling: \(entry)")
            if target == 1 && (observed < 1 || !app.buttons["everydayConfirm"].label.contains("done it")) {
                let label = app.buttons["everydayConfirm"].label
                if !label.contains("I've done it") && !label.contains("Finish") {
                    trace.append("End drag landed at \(observed * 100)%; played the remaining movement without confirmation")
                    app.buttons["everydayPlay"].tap()
                    let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format:
                        "label CONTAINS %@ OR label CONTAINS %@", "I've done it", "Finish"),
                        object: app.buttons["everydayConfirm"])
                    XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 10), .completed, file: file, line: line)
                    let finalValue = try XCTUnwrap(slider.value as? String, file: file, line: line)
                    observed = try XCTUnwrap(Double(finalValue.replacingOccurrences(of: "%", with: "")), file: file, line: line) / 100
                }
            }
            let tolerance = target == 1 ? 0 : 0.06
            let confirmLabel = app.buttons["everydayConfirm"].label
            let finishGateReady = target != 1 || confirmLabel.contains("I've done it") || confirmLabel.contains("Finish")
            if abs(observed - Double(target)) <= tolerance && finishGateReady { break }
            requested = interiorSample ? min(1, max(0, requested + target - CGFloat(observed))) : target
        }
        let evidence = XCTAttachment(string: trace.joined(separator: "\n"))
        evidence.name = "Quarter_pose_drag_feedback_\(actionBefore)_target_\(Int(target * 100))"
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTAssertEqual(observed * 100, Double(target * 100), accuracy: target == 1 ? 0 : 6,
                       "Bounded correction must reach the original sampling tolerance", file: file, line: line)
        if target == 1 {
            let label = app.buttons["everydayConfirm"].label
            XCTAssertTrue(label.contains("I've done it") || label.contains("Finish"),
                          "The exact endpoint must expose learner confirmation", file: file, line: line)
        }
        XCTAssertEqual(app.buttons["everydayPlay"].label, "Play move",
                       "Positioning must pause the animation", file: file, line: line)
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, actionBefore,
                       "Positioning must not advance or confirm an action", file: file, line: line)
        XCTAssertFalse(app.staticTexts["everydayCompletion"].exists, file: file, line: line)
    }

    func testRoundedTowelPreservesScrubbingAndTheARLayoutPose() throws {
        launch(extraArguments: ["--equipment-ar-layout-fixture"])
        openCourse("towel")
        for action in 1...3 {
            assertStudioAction(action, total: 3)
            scrub(to: 0.5)
            capture("Fabric_towel_\(action)_curved")
            XCTAssertTrue(app.buttons["everydayPlay"].isEnabled)
            if action == 3 {
                enterAR()
                let arSlider = app.sliders["everydayARProgressSlider"]
                arSlider.adjust(toNormalizedSliderPosition: 0.65)
                let arPose = try XCTUnwrap(arSlider.value as? String)
                capture("Fabric_towel_AR_fixture_NO_LIVE_CAMERA")
                app.buttons["everydayExitAR"].tap()
                XCTAssertEqual(app.sliders["everydayProgressSlider"].value as? String, arPose)
                assertStudioAction(3, total: 3)
            }
            scrub(to: 1)
            scrub(to: 0.25)
            scrub(to: 1)
            waitForLabel(app.buttons["everydayConfirm"], containing: "I've done it")
            capture("Fabric_towel_\(action)_closed")
            app.buttons["everydayConfirm"].tap()
        }
        XCTAssertTrue(app.staticTexts["everydayCompletion"].waitForExistence(timeout: 5))
        capture("Fabric_towel_completed")
    }

    func testCancellingClothAlignmentRetainsTheCurrentActionAndUnconfirmedPose() throws {
        launch(extraArguments: ["--equipment-ar-layout-fixture"])
        openCourse("towel")
        scrub(to: 1)
        waitForLabel(app.buttons["everydayConfirm"], containing: "I've done it")
        app.buttons["everydayConfirm"].tap()
        assertStudioAction(2, total: 3)
        scrub(to: 0.43)
        let paused = try XCTUnwrap(app.sliders["everydayProgressSlider"].value as? String)
        enterAR()
        XCTAssertEqual(app.staticTexts["everydayARCounter"].label, "2/3")
        app.buttons["everydayMore"].tap()
        app.buttons["everydayAlignObject"].tap()
        XCTAssertTrue(app.buttons["everydayCancelAlignment"].waitForExistence(timeout: 5))
        let calibrationPose = try XCTUnwrap(viewport.value as? String)
        assertRemains(viewport, value: calibrationPose)
        XCTAssertFalse(app.buttons["everydayCaptureAlignment"].isEnabled)
        assertNoPermissionAlerts()
        app.buttons["everydayCancelAlignment"].tap()
        XCTAssertEqual(app.staticTexts["everydayARCounter"].label, "2/3")
        XCTAssertEqual(app.sliders["everydayARProgressSlider"].value as? String, paused)
        XCTAssertFalse(app.staticTexts["everydayCompletion"].exists)
        app.buttons["everydayExitAR"].tap()
        assertStudioAction(2, total: 3)
        XCTAssertEqual(app.sliders["everydayProgressSlider"].value as? String, paused)
        XCTAssertTrue(app.buttons["everydayConfirm"].label.contains("Continue"))
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

    func testCompletedTowelKeepsFinalPoseUntilExplicitRestart() throws {
        launch(extraArguments: ["--equipment-ar-layout-fixture"])
        openCourse("towel")
        for action in 1...3 {
            assertStudioAction(action, total: 3)
            scrub(to: 1)
            waitForLabel(app.buttons["everydayConfirm"], containing: "I've done it")
            app.buttons["everydayConfirm"].tap()
        }
        XCTAssertTrue(app.staticTexts["everydayCompletion"].waitForExistence(timeout: 5))
        let finalPose = try XCTUnwrap(viewport.value as? String)
        XCTAssertEqual(finalPose, "Action 3, movement 100 percent")

        app.buttons["everydayMore"].tap()
        XCTAssertTrue(app.buttons["everydayShowStart"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["everydayShowStart"].isEnabled)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap()
        XCTAssertEqual(viewport.value as? String, finalPose)
        app.buttons["everydayHelp"].tap()
        XCTAssertTrue(app.buttons["everydayCloseHelp"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.sliders["everydayHelpProgressSlider"].exists,
                       "A completion summary cannot silently change the completed model pose")
        XCTAssertFalse(app.buttons["everydayHelpReplay"].isEnabled)
        app.buttons["everydayCloseHelp"].tap()
        XCTAssertTrue(app.buttons["everydayRestart"].waitForExistence(timeout: 5))
        XCTAssertEqual(viewport.value as? String, finalPose)

        enterAR()
        XCTAssertEqual(app.staticTexts["everydayARCounter"].label, "Complete")
        XCTAssertFalse(app.sliders["everydayARProgressSlider"].exists)
        app.buttons["everydayMore"].tap()
        XCTAssertTrue(app.buttons["everydayShowStart"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["everydayShowStart"].isEnabled)
        XCTAssertFalse(app.buttons["everydayAlignObject"].exists,
                       "Flat-start calibration requires explicitly starting a new practice")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap()
        app.buttons["everydayExitAR"].tap()
        XCTAssertTrue(app.staticTexts["everydayCompletion"].waitForExistence(timeout: 5))
        XCTAssertEqual(viewport.value as? String, finalPose)
        capture("Everyday_completed_towel_preserves_final_pose")

        app.buttons["everydayRestart"].tap()
        assertStudioAction(1, total: 3)
        scrub(to: 0.4)
        XCTAssertFalse(app.staticTexts["everydayCompletion"].exists)
        enterAR()
        XCTAssertTrue(app.sliders["everydayARProgressSlider"].isEnabled)
        app.buttons["everydayMore"].tap()
        XCTAssertTrue(app.buttons["everydayAlignObject"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["everydayAlignObject"].isEnabled)
        app.buttons["everydayAlignObject"].tap()
        XCTAssertTrue(app.buttons["everydayCancelAlignment"].waitForExistence(timeout: 5))
        app.buttons["everydayCancelAlignment"].tap()
        XCTAssertEqual(app.staticTexts["everydayARCounter"].label, "1/3")
        assertNoPermissionAlerts()
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
        XCTAssertTrue(app.buttons["everydayConfirm"].label.contains("Continue"))
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
            let slider = app.sliders["everydayARProgressSlider"]
            XCTAssertTrue(slider.isHittable)
            XCTAssertTrue(app.frame.contains(slider.frame))
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

    private func goToStudioAction(_ target: Int, total: Int) {
        for action in 1..<target {
            assertStudioAction(action, total: total)
            scrub(to: 1)
            waitForLabel(app.buttons["everydayConfirm"], containing: "I've done it")
            app.buttons["everydayConfirm"].tap()
        }
        assertStudioAction(target, total: total)
    }

    private struct FocusSnapshot {
        let raw: String
        let mode: String
        let radius: Double
        let zoom: Double
    }

    private func focusSnapshot(file: StaticString = #filePath, line: UInt = #line) throws -> FocusSnapshot {
        let button = app.buttons["everydayFocusStep"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), file: file, line: line)
        let raw = try XCTUnwrap(button.value as? String, file: file, line: line)
        let entries = Dictionary(uniqueKeysWithValues: raw.split(separator: ";").compactMap { entry -> (String, String)? in
            let pair = entry.split(separator: "=", maxSplits: 1)
            return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
        })
        let mode = try XCTUnwrap(entries["mode"], raw, file: file, line: line)
        let radius = try XCTUnwrap(entries["radius"].flatMap(Double.init), raw, file: file, line: line)
        let zoom = try XCTUnwrap(entries["zoom"].flatMap(Double.init), raw, file: file, line: line)
        let center = try XCTUnwrap(entries["center"], raw, file: file, line: line).split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(center.count, 3, raw, file: file, line: line)
        XCTAssertTrue(center.allSatisfy(\.isFinite) && radius.isFinite && radius > 0 && zoom.isFinite && zoom > 0,
                      raw, file: file, line: line)
        return FocusSnapshot(raw: raw, mode: mode, radius: radius, zoom: zoom)
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
            // Resume cards can push the category picker above the viewport.
            // A negative AX position still means the element is above us.
            if element.exists && element.frame.midY < scroll.frame.midY { scroll.swipeDown() }
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
