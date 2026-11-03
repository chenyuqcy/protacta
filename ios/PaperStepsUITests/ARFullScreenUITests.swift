import XCTest
import UIKit

/// Simulator-only layout preview of the tabletop controls. The fixture keeps
/// the studio renderer and is visibly labeled; these tests do not establish
/// camera tracking, real-object occlusion, speech recognition or real folds.
final class ARFullScreenUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("The tabletop layout fixture is available only in the Simulator.")
        #endif
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        launchLesson()
    }

    private func launchLesson(extraArguments: [String] = []) {
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--tabletop-layout-fixture"] + extraArguments
        app.launch()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 15))
        app.selectOrigamiLesson("dart")
        app.buttons["startLesson"].tap()
        XCTAssertTrue(app.staticTexts["stepCounter"].waitForExistence(timeout: 5))
    }

    func testVoiceOnlyUnavailableOffersRecoveryWithoutNavigationButtonsOrPermissionAlert() throws {
        let partial = try openPartialFoldInTabletopPreview()
        app.buttons["enterARFullScreen"].tap()
        app.buttons["enterARVoiceOnly"].tap()
        XCTAssertTrue(app.buttons["exitVoiceOnlyAR"].waitForExistence(timeout: 5))
        assertFullViewport()
        waitForLabel(app.staticTexts["voiceOnlyRecoveryMessage"], containing: "Voice input is unavailable in automated tests")
        for id in ["compactARNext", "compactARVoice", "nextStep", "backStep", "toggleHandsFree"] {
            XCTAssertFalse(app.buttons[id].exists, id)
        }
        XCTAssertTrue(app.buttons["voiceOnlyRetry"].isHittable)
        assertNoPermissionAlert()
        capture("Voice_only_AR_recovery_no_navigation_buttons")
        app.buttons["voiceOnlyShowControls"].tap()
        XCTAssertTrue(app.buttons["enterARFullScreen"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.foldProgressValue, partial)
        XCTAssertFalse(app.buttons["exitVoiceOnlyAR"].exists)
    }

    func testVisibleAdjustAndDonePreserveAPausedPartialFoldAndStayOutOfFullScreen() throws {
        let partial = try openPartialFoldInTabletopPreview()
        let adjust = app.buttons["adjustReference"]
        XCTAssertTrue(adjust.isHittable)
        XCTAssertGreaterThanOrEqual(adjust.frame.height, 44)
        waitForLabel(adjust, containing: "Adjust")
        XCTAssertFalse(app.staticTexts["adjustReferenceHint"].exists)

        adjust.tap()
        waitForLabel(adjust, containing: "Done")
        XCTAssertTrue(app.staticTexts["adjustReferenceHint"].exists)
        XCTAssertEqual(app.foldProgressValue, partial)
        XCTAssertEqual(app.foldPlaybackLabel, "Play fold")

        adjust.tap()
        waitForLabel(adjust, containing: "Adjust")
        XCTAssertFalse(app.staticTexts["adjustReferenceHint"].exists)
        XCTAssertEqual(app.foldProgressValue, partial)
        XCTAssertEqual(app.foldPlaybackLabel, "Play fold")

        enterFullScreen()
        XCTAssertFalse(adjust.exists)
        XCTAssertFalse(app.staticTexts["adjustReferenceHint"].exists)
        app.buttons["exitARFullScreen"].tap()
        XCTAssertTrue(adjust.waitForExistence(timeout: 5))
        waitForLabel(adjust, containing: "Adjust")
        XCTAssertEqual(app.foldProgressValue, partial)
        assertNoPermissionAlert()
    }

    func testVoiceOnlyCleanLayoutHasOnlyExitAndRestoresPartialFold() throws {
        launchLesson(extraArguments: ["--voice-only-layout-fixture"])
        let partial = try openPartialFoldInTabletopPreview()
        app.buttons["enterARFullScreen"].tap(); app.buttons["enterARVoiceOnly"].tap()
        XCTAssertTrue(app.buttons["exitVoiceOnlyAR"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["voiceOnlyFixtureLabel"].exists)
        XCTAssertTrue(app.staticTexts["voiceOnlyFixtureLabel"].label.contains("MIC OFF"))
        let hintGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["voiceOnlyHint"])
        XCTAssertEqual(XCTWaiter.wait(for: [hintGone], timeout: 8), .completed)
        assertFullViewport(); assertFixtureLabel()
        for id in ["compactARNext", "compactARVoice", "nextStep", "backStep", "voiceOnlyRetry", "voiceOnlyShowControls"] {
            XCTAssertFalse(app.buttons[id].exists, id)
        }
        XCTAssertTrue(app.buttons["exitVoiceOnlyAR"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["exitVoiceOnlyAR"].frame.height, 44)
        capture("Voice_only_AR_clean_layout_MIC_OFF_NO_LIVE_CAMERA")
        app.buttons["exitVoiceOnlyAR"].tap()
        XCTAssertTrue(app.buttons["enterARFullScreen"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.foldProgressValue, partial)
    }

    override func tearDownWithError() throws {
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
        app = nil
    }

    func testFullScreenEnlargesViewportPreservesFoldAndKeepsVoiceRecoveryUsable() throws {
        let partialProgress = try openPartialFoldInTabletopPreview()
        let regularHeight = viewport.frame.height
        capture("Tabletop_layout_preview_regular")

        enterFullScreen()
        assertFullViewport(tallerThan: regularHeight)
        assertCompactControls()
        waitForLabel(app.staticTexts["compactARStep"], containing: "Step 1 of 10")
        waitForLabel(app.buttons["compactARNext"], containing: "Finish this fold")
        capture("Tabletop_layout_preview_full_screen_partial_fold")

        // Expanding and collapsing must not finish or restart the partial fold.
        app.buttons["exitARFullScreen"].tap()
        XCTAssertTrue(app.buttons["enterARFullScreen"].waitForExistence(timeout: 5))
        waitForLabel(app.staticTexts["stepCounter"], containing: "STEP 1 OF 10")
        XCTAssertEqual(app.foldProgressValue, partialProgress)
        XCTAssertEqual(app.foldPlaybackLabel, "Play fold")
        waitForLabel(app.buttons["nextStep"], containing: "Finish this fold")

        enterFullScreen()
        app.buttons["compactARVoice"].tap()
        waitForLabel(app.staticTexts["compactARVoiceStatus"], containing: "Voice input is unavailable in automated tests")
        XCTAssertTrue(app.buttons["compactARVoice"].isHittable, "The same microphone control must remain available to retry")
        assertNoPermissionAlert()
        XCTAssertTrue(app.buttons["compactARNext"].isEnabled, "An unavailable microphone must not block touch navigation")
        capture("Tabletop_layout_preview_full_screen_voice_recovery")

        // First finish the partial action, then move to the next action.
        app.buttons["compactARNext"].tap()
        waitUntilEnabled(app.buttons["compactARNext"])
        waitForLabel(app.staticTexts["compactARStep"], containing: "Step 1 of 10")
        waitForLabel(app.buttons["compactARNext"], containing: "Next fold")
        app.buttons["compactARNext"].tap()
        waitForLabel(app.staticTexts["compactARStep"], containing: "Step 2 of 10")
        waitUntilEnabled(app.buttons["compactARNext"])
        capture("Tabletop_layout_preview_full_screen_next_fold")

        app.buttons["exitARFullScreen"].tap()
        XCTAssertTrue(app.buttons["enterARFullScreen"].waitForExistence(timeout: 5))
        waitForLabel(app.staticTexts["stepCounter"], containing: "STEP 2 OF 10")
        XCTAssertEqual(app.foldPlaybackLabel, "Play fold")
        XCTAssertTrue(app.buttons["closeAR"].isHittable)
        capture("Tabletop_layout_preview_restored_lesson_controls")

        // Leaving AR clears the presentation preference for the next entry.
        app.buttons["closeAR"].tap()
        XCTAssertTrue(app.buttons["openAR"].waitForExistence(timeout: 5))
        app.buttons["openAR"].tap()
        XCTAssertTrue(app.buttons["enterARFullScreen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["exitARFullScreen"].exists)
        XCTAssertFalse(app.buttons["compactARNext"].exists)
        waitForLabel(app.staticTexts["stepCounter"], containing: "STEP 2 OF 10")
        assertFixtureLabel()
    }

    func testIPadFullScreenControlsStayReachableAcrossRotation() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Tablet rotation layout check") }
        let partial = try openPartialFoldInTabletopPreview()
        enterFullScreen()
        for landscape in [false, true, false] {
            orient(landscape)
            assertFullViewport()
            assertCompactControls()
            waitForLabel(app.staticTexts["compactARStep"], containing: "Step 1 of 10")
            waitForLabel(app.buttons["compactARNext"], containing: "Finish this fold")
            capture("iPad_\(landscape ? "landscape" : "portrait")_tabletop_full_screen_layout_preview")
        }
        app.buttons["exitARFullScreen"].tap()
        XCTAssertTrue(app.buttons["enterARFullScreen"].waitForExistence(timeout: 5))
        waitForLabel(app.staticTexts["stepCounter"], containing: "STEP 1 OF 10")
        XCTAssertTrue(app.progressIndicators["foldProgressValue"].exists)
        XCTAssertEqual(app.foldProgressValue, partial)
        app.openLessonHelp()
        XCTAssertTrue(app.sliders["foldProgress"].isHittable)
        app.closeLessonHelp()
    }

    private var viewport: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "paperViewport").firstMatch
    }

    private func openPartialFoldInTabletopPreview(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        waitUntilEnabled(app.buttons["nextStep"], file: file, line: line)
        app.buttons["nextStep"].tap()
        waitForLabel(app.staticTexts["stepCounter"], containing: "STEP 1 OF 10", file: file, line: line)
        waitUntilEnabled(app.buttons["nextStep"], file: file, line: line)
        app.scrubFold(to: 0.4)
        waitForLabel(app.buttons["nextStep"], containing: "Finish this fold", file: file, line: line)
        let progress = try XCTUnwrap(app.foldProgressValue, file: file, line: line)
        app.buttons["openAR"].tap()
        XCTAssertTrue(app.buttons["enterARFullScreen"].waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(viewport.waitForExistence(timeout: 5), file: file, line: line)
        assertFixtureLabel(file: file, line: line)
        assertNoPermissionAlert(file: file, line: line)
        return progress
    }

    private func enterFullScreen(file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["enterARFullScreen"].tap()
        app.buttons["enterARCompactFullScreen"].tap()
        XCTAssertTrue(app.buttons["exitARFullScreen"].waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertFalse(app.buttons["enterARFullScreen"].exists, file: file, line: line)
    }

    private func assertCompactControls(file: StaticString = #filePath, line: UInt = #line) {
        for identifier in ["exitARFullScreen", "compactARNext", "compactARVoice"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.isHittable, "Unreachable compact control: \(identifier)", file: file, line: line)
            XCTAssertTrue(app.frame.contains(button.frame), "Control outside the app bounds: \(identifier), \(button.frame)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, identifier, file: file, line: line)
        }
        for identifier in ["chooseLesson", "openARHelp", "togglePositionLock", "adjustReference", "placeAgain", "toggleHints", "nextStep", "playPause", "stepList"] {
            XCTAssertFalse(app.buttons[identifier].exists, "Expanded lesson controls must not cover the full-screen viewport: \(identifier)", file: file, line: line)
        }
        XCTAssertFalse(app.sliders["foldProgress"].exists, file: file, line: line)
        XCTAssertFalse(app.sliders["foldTimeline"].exists, file: file, line: line)
        assertFixtureLabel(file: file, line: line)
    }

    private func assertFullViewport(tallerThan regularHeight: CGFloat? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let self, self.viewport.exists else { return false }
            let frame = self.viewport.frame
            let appFrame = self.app.frame
            return frame.height >= appFrame.height * 0.95 && frame.width >= appFrame.width * 0.95
                && (regularHeight.map { frame.height > $0 } ?? true)
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed, "The original viewport should expand to fill the app", file: file, line: line)
    }

    private func assertFixtureLabel(file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["arLayoutFixtureLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(label.label.contains("AR LAYOUT PREVIEW"), file: file, line: line)
        XCTAssertTrue(label.label.contains("NO LIVE CAMERA"), file: file, line: line)
    }

    private func orient(_ landscape: Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let frame = self?.app.frame else { return false }
            return landscape ? frame.width > frame.height : frame.height > frame.width
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, file: file, line: line)
    }

    private func waitUntilEnabled(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true AND NOT (identifier == %@ AND label CONTAINS %@)", "nextStep", "Pause fold"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, file: file, line: line)
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, file: file, line: line)
    }

    private func assertNoPermissionAlert(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(app.alerts.firstMatch.exists, file: file, line: line)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists,
                       "The layout preview must not request camera, microphone or speech permissions", file: file, line: line)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
