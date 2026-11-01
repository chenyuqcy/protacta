import XCTest
import UIKit

/// Drives the actual native UI for a host-side simctl screen recording.
/// Recorded studio/illustration pixels are prototype demonstrations, not
/// physical-camera, fold-correctness, speech or learner-acceptance evidence.
final class DemoCaptureUITests: XCTestCase {
    private var app: XCUIApplication!
    private let sessionID = UUID().uuidString
    private var captureRoot: URL!
    private var sessionDirectory: URL!
    private var activeClip: String?
    private var events: [[String: Any]] = []
    private var selectedClips: Set<String> = []
    private let knownClips: Set<String> = ["01_origami", "02_everyday", "03_aeris", "04_synthetic_paper"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("Demo capture is exclusively a Simulator recording harness.")
        #endif
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory,
                                                               in: .userDomainMask).first)
        captureRoot = documents.appendingPathComponent("ProtactaDemoCapture", isDirectory: true)
        let requestURL = captureRoot.appendingPathComponent("recording-request.json")
        guard let data = try? Data(contentsOf: requestURL),
              let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let createdAt = request["createdAt"] as? Double,
              let clips = request["clips"] as? [String] else {
            throw XCTSkip("Demo recording requires a fresh host-owned recording-request.json.")
        }
        let age = Date().timeIntervalSince1970 - createdAt
        let requested = Set(clips)
        guard age.isFinite, (0...900).contains(age), !requested.isEmpty,
              requested.count == clips.count, requested.isSubset(of: knownClips) else {
            throw XCTSkip("Demo recording request is stale, malformed or names unsupported clips.")
        }
        selectedClips = requested
        sessionDirectory = captureRoot.appendingPathComponent(sessionID, isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        // Consume the opt-in in one same-volume move. A later normal test run
        // must skip even if this capture's host recorder subsequently crashes.
        try FileManager.default.moveItem(at: requestURL,
                                         to: sessionDirectory.appendingPathComponent("recording-request.json"))
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        if let clip = activeClip {
            try? publish(phase: "failed", clip: clip)
        }
        if !events.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: events,
                                                  options: [.prettyPrinted, .sortedKeys]) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "Demo_capture_timing_and_scope.json"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app?.terminate()
        app = nil
    }

    func testRecordDemoSequence() throws {
        if selectedClips.contains("01_origami") { try recordOrigami() }
        if selectedClips.contains("02_everyday") { try recordEveryday() }
        if selectedClips.contains("03_aeris") { try recordAeris() }
        if selectedClips.contains("04_synthetic_paper") { try recordSyntheticPaperStates() }
    }

    private func recordOrigami() throws {
        launchHub()
        try begin("01_origami")
        try checkpoint("home")
        hold(3)
        tap("hubOrigami")
        ready(app.buttons["startLesson"])
        try checkpoint("dart_landing")
        hold(2)
        tap("startLesson")
        ready(app.buttons["nextStep"])
        try checkpoint("flat_sheet_3d")
        hold(1.5)
        advanceOrigami(to: 1)
        try checkpoint("center_crease_3d")
        hold(1.5)
        tap("replayStep")
        ready(app.buttons["nextStep"])
        hold(1)
        tap("topView")
        hold(1.5)
        tap("angleView")
        hold(1.5)
        advanceOrigami(to: 2)
        hold(1)
        advanceOrigami(to: 3)
        try checkpoint("corner_fold_3d")
        hold(1.5)
        tap("foldNotes")
        ready(app.buttons["closeNotes"])
        try checkpoint("written_fold_help")
        hold(2.5)
        tap("closeNotes")
        jumpOrigami(to: 10)
        try checkpoint("finished_dart_reference_not_physical_completion")
        hold(3)
        try end()
    }

    private func recordEveryday() throws {
        launchHub()
        tap("hubCourse_t_shirt")
        ready(app.staticTexts["everydayCounter"])
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 1 OF 6")
        try begin("02_everyday")
        try checkpoint("tshirt_start")
        hold(2)
        tap("everydayShowStart")
        tap("everydayPlay")
        reveal(app.staticTexts["everydayActionTitle"])
        hold(6)
        try checkpoint("tshirt_action1_target")
        tap("everydayShowStart")
        hold(1.5)
        tap("everydayShowTarget")
        hold(1.5)
        tap("everydayConfirm")
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 2 OF 6")
        tap("everydayPlay")
        reveal(app.staticTexts["everydayActionTitle"])
        hold(6)
        try checkpoint("tshirt_action2_target")
        tap("everydayHelp")
        ready(app.navigationBars["Help with this action"])
        try checkpoint("action_specific_written_help")
        hold(3)
        tap("everydayHelpReplay")
        reveal(app.staticTexts["everydayActionTitle"])
        hold(6)
        tap("everydayClose")
        tap("hubCourse_square_knot")
        ready(app.staticTexts["everydayCounter"])
        try checkpoint("square_knot_illustration")
        tap("everydayPlay")
        reveal(app.staticTexts["everydayActionTitle"])
        hold(6)
        tap("everydayClose")
        tap("hubCourse_four_in_hand")
        ready(app.staticTexts["everydayCounter"])
        try checkpoint("tie_illustration")
        tap("everydayPlay")
        reveal(app.staticTexts["everydayActionTitle"])
        hold(6)
        try end()
    }

    private func recordAeris() throws {
        launchHub()
        tap("hubProductManual")
        ready(app.buttons["nextStep"], timeout: 20)
        try begin("03_aeris")
        try checkpoint("virtual_product_controls")
        hold(2)
        tap("nextStep")
        ready(app.buttons["pressRelease"])
        XCTAssertTrue(app.staticTexts["stepTitle"].label.contains("release tab"))
        XCTAssertFalse(app.buttons["nextStep"].isEnabled)
        try checkpoint("release_interaction_gate")
        hold(2)
        let hotspot = app.buttons["pressReleaseHotspot"]
        if hotspot.exists && hotspot.isHittable && hotspot.isEnabled { hotspot.tap() }
        else { tap("pressRelease") }
        ready(app.buttons["nextStep"])
        try checkpoint("virtual_release_pressed")
        hold(1.5)
        tap("nextStep")
        ready(app.buttons["nextStep"])
        XCTAssertTrue(app.staticTexts["stepTitle"].label.contains("rear cover"))
        reveal(app.buttons["taskMenu"])
        try checkpoint("rear_cover_open")
        hold(3)
        tap("nextStep")
        ready(app.buttons["nextStep"])
        XCTAssertTrue(app.staticTexts["stepTitle"].label.contains("filter out"))
        reveal(app.buttons["taskMenu"])
        try checkpoint("filter_out")
        hold(3)
        try recordAerisExploreFrame("aeris_explore_before_ax_tap")
        tap("exploreParts")
        var explored = waitForAerisExplore(timeout: 2.5)
        try recordAerisExploreFrame("aeris_explore_after_ax_tap")
        if !explored {
            // A tiny overlay control can report a usable AX target while its
            // synthesized tap misses. Retry only its freshly observed center.
            let control = app.buttons["exploreParts"]
            if revealIfPossible(control), control.exists, control.isEnabled {
                try recordAerisExploreFrame("aeris_explore_before_coordinate_retry")
                control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                explored = waitForAerisExplore(timeout: 2.5)
                try recordAerisExploreFrame("aeris_explore_after_coordinate_retry")
            }
        }
        if explored && revealIfPossible(app.buttons["pose_exploded"]) {
            try checkpoint("exploded_product")
            hold(3)
            var posed = true
            for pose in ["assembled", "cover", "exploded"] {
                let control = app.buttons["pose_\(pose)"]
                guard revealIfPossible(control), control.exists, control.isEnabled else {
                    posed = false
                    break
                }
                control.tap()
                hold(pose == "exploded" ? 4 : 2)
            }
            if posed { try checkpoint("exploded_final") }
            else { try checkpoint("aeris_pose_controls_unavailable_guided_footage_only") }
        } else {
            XCTAssertEqual(app.state, .runningForeground)
            XCTAssertTrue(app.staticTexts["stepTitle"].exists)
            try checkpoint("aeris_explore_unavailable_guided_footage_only")
            hold(3)
        }
        try end()
    }

    private func recordSyntheticPaperStates() throws {
        launchHub(syntheticPaper: true)
        tap("hubOrigami")
        tap("openPaperGuide")
        ready(app.staticTexts["paperGuideFixtureLabel"])
        XCTAssertTrue(app.staticTexts["paperGuideFixtureLabel"].label.contains("NOT A LIVE CAMERA"))
        ready(app.buttons["confirmPaperDirection"])
        try begin("04_synthetic_paper")
        try checkpoint("synthetic_direction_needed")
        hold(2.5)
        tap("confirmPaperDirection")
        XCTAssertTrue(app.staticTexts["paperGuideStatus"].label.contains("left long edge"))
        try checkpoint("paper_aligned")
        hold(3)
        tap("losePaperFixture")
        XCTAssertFalse(app.buttons["confirmPaperDirection"].isEnabled)
        XCTAssertTrue(app.staticTexts["paperGuideStatus"].label.contains("no longer aligned"))
        try checkpoint("paper_hidden")
        hold(2.5)
        tap("restorePaperFixture")
        ready(app.buttons["confirmPaperDirection"])
        try checkpoint("paper_recovered_needs_direction")
        hold(2.5)
        tap("confirmPaperDirection")
        XCTAssertTrue(app.staticTexts["paperGuideStatus"].label.contains("left long edge"))
        try checkpoint("synthetic_reconfirmed")
        hold(3)

        tap("closeAR")
        tap("openDartPractice")
        ready(app.staticTexts["practiceFixtureLabel"])
        XCTAssertTrue(app.staticTexts["practiceFixtureLabel"].label.contains("NOT A LIVE CAMERA"))
        tap("confirmPracticeAction")
        tap("confirmPracticeAction")
        XCTAssertEqual(app.staticTexts["practiceCounter"].label, "ACTION 3 OF 10")
        tap("checkPracticeStep")
        let result = app.descendants(matching: .any).matching(identifier: "practiceCheckResult").firstMatch
        ready(result)
        try checkpoint("synthetic_checkpoint_result")
        hold(2)
        tap("reviewPracticeComparison")
        ready(app.navigationBars["Captured comparison"])
        ready(app.staticTexts["comparisonSyntheticLabel"])
        XCTAssertTrue(app.otherElements["comparisonSnapshotCanvas"].exists)
        try checkpoint("checkpoint_comparison")
        hold(4)
        let replay = app.buttons["comparisonReplay"]
        for _ in 0..<6 where !replay.isHittable { app.swipeUp() }
        XCTAssertTrue(replay.isHittable)
        replay.tap()
        waitLabel(app.staticTexts["stepCounter"], equals: "STEP 3 OF 10")
        try checkpoint("comparison_replay_same_action_3d")
        hold(3)
        try end()
    }

    private func launchHub(syntheticPaper: Bool = false) {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--tutorial-hub", "--reset-learning-progress", "--reset-everyday-progress"]
        if syntheticPaper { app.launchArguments.append("--paper-guide-fixture") }
        app.launch()
        ready(app.buttons["hubOrigami"], timeout: 20)
    }

    private func begin(_ clip: String) throws {
        activeClip = clip
        try publish(phase: "ready", clip: clip)
        try waitForMarker(clip + ".start")
        try checkpoint("host_recording_started")
        hold(2)
    }

    private func end() throws {
        let clip = try XCTUnwrap(activeClip)
        hold(2)
        try publish(phase: "done", clip: clip)
        try waitForMarker(clip + ".continue")
        activeClip = nil
        app.terminate()
    }

    private func checkpoint(_ name: String) throws {
        events.append(["clipID": activeClip ?? "none", "name": name,
                       "timestamp": Date().timeIntervalSince1970])
        try JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys])
            .write(to: sessionDirectory.appendingPathComponent("events.json"), options: .atomic)
    }

    private func publish(phase: String, clip: String) throws {
        let state: [String: Any] = [
            "sessionID": sessionID, "clipID": clip, "phase": phase,
            "timestamp": Date().timeIntervalSince1970,
            "sessionDirectory": sessionDirectory.path,
            "requestedClips": selectedClips.sorted(),
            "syntheticPaperFixture": clip == "04_synthetic_paper",
            "scope": "Actual iOS Simulator UI pixels; not physical acceptance"
        ]
        try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
            .write(to: captureRoot.appendingPathComponent("latest.json"), options: .atomic)
    }

    private func waitForMarker(_ filename: String) throws {
        let marker = sessionDirectory.appendingPathComponent(filename)
        let deadline = Date().addingTimeInterval(60)
        while !FileManager.default.fileExists(atPath: marker.path) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard FileManager.default.fileExists(atPath: marker.path) else {
            XCTFail("Host recording handshake timed out: \(marker.path)")
            throw NSError(domain: "ProtactaDemoCapture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Missing host marker \(filename)"])
        }
    }

    private func advanceOrigami(to step: Int) {
        tap("nextStep")
        waitLabel(app.staticTexts["stepCounter"], equals: "STEP \(step) OF 10")
        ready(app.buttons["nextStep"], timeout: 20)
    }

    private func jumpOrigami(to step: Int) {
        tap("stepList")
        ready(app.buttons["closeSteps"])
        let target = app.buttons["jumpStep_\(step)"]
        for _ in 0..<12 where !target.isHittable { app.swipeUp() }
        XCTAssertTrue(target.isHittable)
        target.tap()
        waitLabel(app.staticTexts["stepCounter"], equals: "STEP \(step) OF 10", timeout: 12)
        ready(app.buttons["nextStep"], timeout: 20)
    }

    private func tap(_ identifier: String) {
        switch identifier {
        case "replayStep", "foldNotes", "stepList": app.tapFoldTool(identifier); return
        case "openPaperGuide", "openDartPractice": app.openPaperTool(identifier); return
        case "chooseLesson", "topView", "angleView": app.tapViewOption(identifier); return
        default: break
        }
        let button = app.buttons[identifier]
        reveal(button)
        ready(button)
        button.tap()
    }

    private func ready(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                guard element.exists else { return false }
                return element.isEnabled && !(element.identifier == "nextStep" && element.label.contains("Pause fold"))
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "Control did not become ready: \(element.identifier)")
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<10 {
            if element.isHittable { return }
            let scroll = app.scrollViews.firstMatch
            if scroll.exists {
                if element.exists && element.frame.midY < app.frame.midY { scroll.swipeDown() }
                else { scroll.swipeUp() }
            } else {
                if element.exists && element.frame.midY < app.frame.midY { app.swipeDown() }
                else { app.swipeUp() }
            }
        }
        XCTAssertTrue(element.isHittable, "Could not reveal \(element.identifier)")
    }

    private func waitForAerisExplore(timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            if self.app.buttons["pose_exploded"].exists { return true }
            let control = self.app.buttons["exploreParts"]
            guard control.exists else { return false }
            return control.label.contains("Back to guide")
        }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func revealIfPossible(_ element: XCUIElement) -> Bool {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return true }
            let frame = element.exists ? element.frame : .zero
            let scroll = app.scrollViews.firstMatch
            let towardTop = !frame.isEmpty && frame.midY < app.frame.midY
            if scroll.exists {
                if towardTop { scroll.swipeDown() }
                else { scroll.swipeUp() }
            } else {
                if towardTop { app.swipeDown() }
                else { app.swipeUp() }
            }
        }
        return element.exists && element.isHittable
    }

    private func recordAerisExploreFrame(_ name: String) throws {
        let control = app.buttons["exploreParts"]
        var snapshot: [String: Any] = [:]
        if control.exists {
            let frame = control.frame
            snapshot = ["label": control.label, "enabled": control.isEnabled,
                        "hittable": control.isHittable,
                        "frame": ["x": frame.minX, "y": frame.minY,
                                  "width": frame.width, "height": frame.height]]
        }
        events.append(["clipID": activeClip ?? "none", "name": name,
                       "timestamp": Date().timeIntervalSince1970,
                       "exploreParts": snapshot,
                       "poseControlsExist": ["assembled", "cover", "exploded"].map {
                           ["id": "pose_\($0)", "exists": app.buttons["pose_\($0)"].exists] as [String: Any]
                       }])
        try JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys])
            .write(to: sessionDirectory.appendingPathComponent("events.json"), options: .atomic)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitLabel(_ element: XCUIElement, equals value: String,
                           timeout: TimeInterval = 10) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in element.exists && element.label == value }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "Expected \(value)")
    }

    private func hold(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }
}
