import XCTest

/// Uses the free Dart lesson and the automated-test audio fallback. Command
/// buttons exercise lesson actions; these tests do not verify live recognition,
/// spoken audio, camera tracking, or the correctness of a physical paper fold.
final class VoiceHelpUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 15))
        app.selectOrigamiLesson("dart")
        app.buttons["startLesson"].tap()
        XCTAssertTrue(app.staticTexts["stepCounter"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testHandsFreeStartsFromLessonAndKeepsUnavailableReasonVisible() {
        let handsFree = app.buttons["toggleHandsFree"]
        XCTAssertTrue(handsFree.waitForExistence(timeout: 5))
        handsFree.tap()
        waitForLabel(app.staticTexts["voiceRecoveryMessage"], containing: "Voice input is unavailable in automated tests")
        XCTAssertTrue(app.buttons["retryHandsFree"].isHittable)
        XCTAssertFalse(app.buttons["closeVoiceGuide"].exists, "Starting hands-free must not require opening a sheet")
        assertNoPermissionAlert()
        app.buttons["retryHandsFree"].tap()
        waitForLabel(app.staticTexts["voiceRecoveryMessage"], containing: "Voice input is unavailable in automated tests")
        XCTAssertTrue(app.buttons["nextStep"].isEnabled, "A microphone failure must leave the lesson usable")
        capture("HandsFreeRecovery")
    }

    func testRestartLessonReturnsToBlankSheetAndReplayStaysOnCurrentStep() {
        advanceToFirstFold()
        openVoiceGuide()
        XCTAssertTrue(app.staticTexts["handsFreeQuickStart"].exists || app.staticTexts["Restart lesson → return to a blank sheet"].exists)
        command("replay", feedback: "Replaying this fold.")
        closeVoiceGuide()
        assertStep(1, title: "Make the center crease")
        openVoiceGuide()
        command("restart", feedback: "Lesson restarted with a flat sheet.")
        closeVoiceGuide()
        assertStep(0, title: "Start with a blank sheet")
        XCTAssertFalse(app.buttons["backStep"].isEnabled)
        XCTAssertTrue(app.buttons["nextStep"].isEnabled)
    }

    func testVoiceCommandButtonsAndFoldHelpKeepTheLessonUsable() throws {
        openVoiceGuide()
        let startVoice = app.buttons["startVoiceControl"]
        reveal(startVoice)
        startVoice.tap()
        waitForLabel(app.staticTexts["voiceStatus"], containing: "Voice input is unavailable in automated tests")
        assertNoPermissionAlert()
        XCTAssertTrue(app.buttons["closeVoiceGuide"].isHittable)

        command("next", feedback: "Playing the next fold.")
        closeVoiceGuide()
        assertStep(1, title: "Make the center crease")
        waitUntilEnabled(app.buttons["nextStep"])

        // Start from a deliberately partial fold so replay has real work to do.
        app.scrubFold(to: 0.35)
        waitForLabel(app.buttons["nextStep"], containing: "Finish this fold")
        openVoiceGuide()
        command("replay", feedback: "Replaying this fold.")
        command("slower", feedback: "Playback set to half speed.")
        command("normalSpeed", feedback: "Playback set to normal speed.")
        command("why", feedback: "This crease is a guide for the nose and body.")
        waitForLabel(app.staticTexts["voiceStatus"], containing: "Read-aloud is unavailable in automated tests")
        reveal(app.staticTexts["voiceFeedback"])
        capture("VoiceHelpPanel")
        closeVoiceGuide()
        assertStep(1, title: "Make the center crease")
        XCTAssertEqual(app.foldPlaybackLabel, "Play fold", "Explaining the step should pause the fold")

        openVoiceGuide()
        command("back", feedback: "Previous step.")
        closeVoiceGuide()
        assertStep(0, title: "Start with a blank sheet")
        XCTAssertFalse(app.buttons["backStep"].isEnabled)

        advanceToFirstFold()
        let instruction = app.staticTexts["stepInstruction"].label
        app.buttons["foldHelp"].tap()
        XCTAssertTrue(app.buttons["closeFoldHelp"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Make the center crease"].exists)
        XCTAssertEqual(app.staticTexts["simplerInstruction"].label, instruction)
        for identifier in ["simplerInstruction", "foldCheckpoint", "foldMistake"] {
            let card = app.staticTexts[identifier]
            reveal(card)
            XCTAssertFalse(card.label.isEmpty)
        }
        capture("FoldHelpPanel")
        let readHelp = app.buttons["readFoldHelp"]
        reveal(readHelp)
        XCTAssertTrue(readHelp.isEnabled)
        readHelp.tap()
        assertNoPermissionAlert()
        XCTAssertTrue(app.buttons["closeFoldHelp"].isHittable)

        let replay = app.buttons["replayFromHelp"]
        reveal(replay)
        XCTAssertTrue(replay.isEnabled)
        replay.tap()
        waitUntilGone(app.buttons["closeFoldHelp"])
        assertStep(1, title: "Make the center crease")
        waitUntilEnabled(app.buttons["nextStep"])
        waitForLabel(app.buttons["nextStep"], containing: "Next fold")
        XCTAssertEqual(app.staticTexts["stepInstruction"].label, instruction)
        app.buttons["nextStep"].tap()
        assertStep(2, title: "Open the sheet")
        waitUntilEnabled(app.buttons["nextStep"])
    }

    func testSimulatorARFallbackPreservesPausedFoldAndBothHelpers() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This checks Simulator fallback; physical AR and microphone behavior require device testing.")
        #endif
        advanceToFirstFold()
        app.scrubFold(to: 0.4)
        waitForLabel(app.buttons["nextStep"], containing: "Finish this fold")
        let progress = try XCTUnwrap(app.foldProgressValue)

        app.buttons["openAR"].tap()
        XCTAssertTrue(app.buttons["returnTo3D"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Your table, your workspace."].exists)
        app.buttons["returnTo3D"].tap()
        XCTAssertTrue(app.buttons["openAR"].waitForExistence(timeout: 5))
        assertPausedFirstFold(progress: progress)

        openVoiceGuide()
        command("why", feedback: "This crease is a guide for the nose and body.")
        closeVoiceGuide()
        assertPausedFirstFold(progress: progress)

        app.buttons["foldHelp"].tap()
        XCTAssertTrue(app.buttons["closeFoldHelp"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["simplerInstruction"].exists)
        XCTAssertTrue(app.staticTexts["Make the center crease"].exists)
        app.buttons["closeFoldHelp"].tap()
        waitUntilGone(app.buttons["closeFoldHelp"])
        assertPausedFirstFold(progress: progress)
        XCTAssertTrue(app.buttons["foldHelp"].isHittable)
        XCTAssertTrue(app.buttons["openVoiceGuide"].isHittable)
    }

    private func openVoiceGuide(file: StaticString = #filePath, line: UInt = #line) {
        let open = app.buttons["openVoiceGuide"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), file: file, line: line)
        open.tap()
        XCTAssertTrue(app.buttons["closeVoiceGuide"].waitForExistence(timeout: 5), file: file, line: line)
    }

    private func closeVoiceGuide(file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["closeVoiceGuide"].tap()
        waitUntilGone(app.buttons["closeVoiceGuide"], file: file, line: line)
    }

    private func command(_ rawValue: String, feedback: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons["voiceCommand_\(rawValue)"]
        reveal(button, file: file, line: line)
        button.tap()
        waitForLabel(app.staticTexts["voiceFeedback"], containing: feedback, file: file, line: line)
    }

    private func advanceToFirstFold(file: StaticString = #filePath, line: UInt = #line) {
        waitUntilEnabled(app.buttons["nextStep"], file: file, line: line)
        app.buttons["nextStep"].tap()
        assertStep(1, title: "Make the center crease", file: file, line: line)
        waitUntilEnabled(app.buttons["nextStep"], file: file, line: line)
    }

    private func assertStep(_ number: Int, title: String, file: StaticString = #filePath, line: UInt = #line) {
        waitForLabel(app.staticTexts["stepCounter"], containing: number == 0 ? "BEFORE YOU BEGIN" : "STEP \(number) OF 10", file: file, line: line)
        XCTAssertEqual(app.staticTexts["stepTitle"].label, title, file: file, line: line)
    }

    private func assertPausedFirstFold(progress: String, file: StaticString = #filePath, line: UInt = #line) {
        assertStep(1, title: "Make the center crease", file: file, line: line)
        XCTAssertEqual(app.foldProgressValue, progress, file: file, line: line)
        XCTAssertEqual(app.foldPlaybackLabel, "Play fold", file: file, line: line)
        XCTAssertTrue(app.buttons["nextStep"].label.contains("Finish this fold"), file: file, line: line)
        XCTAssertTrue(app.buttons["openAR"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["closeAR"].exists, file: file, line: line)
    }

    private func assertNoPermissionAlert(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(app.alerts.firstMatch.exists, file: file, line: line)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists,
                       "Automated tests must not request speech or microphone permission", file: file, line: line)
    }

    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        if element.isHittable { return }
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5), file: file, line: line)
        for _ in 0..<6 {
            if element.isHittable { return }
            if element.exists && element.frame.midY > 0 && element.frame.midY < scroll.frame.midY {
                scroll.swipeDown()
            } else {
                scroll.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable, "Expected a reachable control: \(element.identifier)", file: file, line: line)
    }

    private func waitUntilEnabled(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true AND NOT (identifier == %@ AND label CONTAINS %@)", "nextStep", "Pause fold"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, file: file, line: line)
    }

    private func waitUntilGone(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, file: file, line: line)
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, file: file, line: line)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
