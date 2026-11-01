import XCTest
import UIKit

/// User journeys for the simplified UI, not a learner study or live AR test.
final class TeamFeedbackUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["PROTACTA_PROGRESS_TEST_SUITE"] = "org.realitycore.protacta.prototype.uitests.\(UUID().uuidString)"
        app.launchArguments = ["--ui-testing", "--reset-learning-progress", "--tabletop-layout-fixture", "--voice-only-layout-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 15))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testEntryHasOnePrimaryActionAndLibraryIsASeparateDestination() {
        for id in ["chooseLesson", "lesson_dart", "lesson_fox", "openDartPractice", "openPaperGuide", "startOverLesson", "topView", "angleView"] {
            XCTAssertFalse(app.buttons[id].exists, "Secondary controls must be out of the welcome view: \(id)")
        }
        XCTAssertTrue(app.buttons["startLesson"].isHittable)
        capture("Build20_Clean_Dart_entry")
        app.selectOrigamiLesson("fox")
        XCTAssertTrue(app.staticTexts["The Little Fox"].exists)
        app.buttons["startLesson"].tap()
        XCTAssertTrue(app.staticTexts["stepCounter"].waitForExistence(timeout: 5))
    }

    func testPauseHelpScrubSlowAndReplayPreserveTheCurrentAction() throws {
        begin()
        app.buttons["nextStep"].tap()
        XCTAssertTrue(app.buttons["nextStep"].label.contains("Pause fold"))
        app.buttons["nextStep"].tap()
        XCTAssertTrue(app.buttons["nextStep"].label.contains("Finish this fold"))
        for id in ["replayStep", "foldNotes", "stepList", "playbackSpeed", "playPause", "openDartPractice", "openPaperGuide"] {
            XCTAssertFalse(app.buttons[id].exists, id)
        }
        for id in ["nextStep", "backStep", "foldHelp"] {
            XCTAssertTrue(app.buttons[id].isHittable, id)
            XCTAssertGreaterThanOrEqual(app.buttons[id].frame.height, 44)
        }
        capture("Build20_Three_main_actions")
        app.scrubFold(to: 0.4)
        let partial = try XCTUnwrap(app.foldProgressValue)
        app.openLessonHelp()
        app.buttons["playbackSpeed"].tap()
        XCTAssertEqual(app.buttons["playbackSpeed"].value as? String, "Half speed")
        capture("Build20_Secondary_tools_in_Help")
        app.closeLessonHelp()
        XCTAssertEqual(app.foldProgressValue, partial)
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP 1 OF 10")
        app.tapFoldTool("replayStep")
        waitReady()
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP 1 OF 10")
        XCTAssertEqual(app.foldProgressValue, "100%")
    }

    func testExplanationsAndStepListReturnToTheSameLesson() {
        begin(); advance()
        app.tapFoldTool("foldNotes")
        XCTAssertTrue(app.buttons["closeNotes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Written fold notes"].exists)
        app.buttons["closeNotes"].tap()
        app.tapFoldTool("stepList")
        XCTAssertTrue(app.buttons["closeSteps"].waitForExistence(timeout: 5))
        app.buttons["closeSteps"].tap()
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP 1 OF 10")
    }

    func testPhoneSetupDoesNotStartSensorsAndARRemainsAvailable() {
        app.tapViewOption("openPhoneSetup")
        XCTAssertTrue(app.buttons["closePhoneSetup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Make room for both hands."].exists)
        app.revealLessonElement(app.staticTexts["phoneSetupRecovery"])
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("Build20_Solo_phone_setup")
        app.buttons["closePhoneSetup"].tap()
        begin(); advance()
        app.buttons["openAR"].tap()
        XCTAssertTrue(app.buttons["enterARFullScreen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["arLayoutFixtureLabel"].label.contains("NO LIVE CAMERA"))
        capture("Build20_Quiet_AR_layout_NO_LIVE_CAMERA")
        app.buttons["enterARFullScreen"].tap(); app.buttons["enterARVoiceOnly"].tap()
        XCTAssertTrue(app.buttons["exitVoiceOnlyAR"].waitForExistence(timeout: 5))
        app.buttons["exitVoiceOnlyAR"].tap()
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP 1 OF 10")
    }

    func testHomeOpensTheCleanEntryAndReturnsToTheCatalog() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--tutorial-hub", "--reset-learning-progress"]
        app.launch()
        XCTAssertTrue(app.buttons["hubOrigami"].waitForExistence(timeout: 15))
        app.revealLessonElement(app.buttons["hubOrigami"])
        app.buttons["hubOrigami"].tap()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["returnTutorialHub"].isHittable)
        XCTAssertFalse(app.buttons["openDartPractice"].exists)
        XCTAssertFalse(app.buttons["openPaperGuide"].exists)
        capture("Build20_Entry_from_home")
        app.buttons["returnTutorialHub"].tap()
        XCTAssertTrue(app.buttons["hubOrigami"].waitForExistence(timeout: 5))
    }

    func testTabletKeepsPrimaryControlsReachableAcrossRotation() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Tablet layout check") }
        begin(); advance()
        for landscape in [false, true, false] {
            XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
            let oriented = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let screen = XCUIScreen.main.screenshot().image.size
                let windowReady = landscape ? self.app.frame.width > self.app.frame.height : self.app.frame.height > self.app.frame.width
                let screenReady = landscape ? screen.width > screen.height : screen.height > screen.width
                return windowReady && screenReady
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [oriented], timeout: 5), .completed)
            for id in ["nextStep", "backStep", "foldHelp", "viewportOptions"] {
                let button = app.buttons[id]
                XCTAssertTrue(button.isHittable, id)
                XCTAssertTrue(app.frame.contains(button.frame), id)
                XCTAssertGreaterThanOrEqual(button.frame.height, 44, id)
            }
            XCTAssertTrue(app.frame.contains(app.staticTexts["stepInstruction"].frame))
            capture("Build20_iPad_\(landscape ? "landscape" : "portrait")")
        }
    }

    private func begin() {
        app.buttons["startLesson"].tap()
        XCTAssertTrue(app.staticTexts["stepCounter"].waitForExistence(timeout: 5))
    }
    private func advance() { waitReady(); app.buttons["nextStep"].tap(); waitReady() }
    private func waitReady() {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true AND NOT label CONTAINS 'Pause fold'"), object: app.buttons["nextStep"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
