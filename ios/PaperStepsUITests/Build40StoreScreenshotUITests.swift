import XCTest
import UIKit

/// Run serially in Release against the public identity on a portrait large
/// iPhone or 13-inch iPad Simulator. No StoreKit fixture, paywall, synthetic AR,
/// injected interface, image editing or real-camera claim is used here.
final class Build40StoreScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!
    private var captureRecords = [[String: Any]]()

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if DEBUG
        throw XCTSkip("App Store capture requires -configuration Release.")
        #endif
        #if !targetEnvironment(simulator)
        throw XCTSkip("This capture harness is only for Simulator.")
        #endif
        XCTAssertEqual(AppReleaseIdentity.productPrefix, "org.realitycore.foliafold",
                       "Capture the public App Store identity, not the prototype.")
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        let suite = "org.realitycore.protacta.prototype.uitests.store40.\(UUID().uuidString)"
        app.launchEnvironment["PROTACTA_PROGRESS_TEST_SUITE"] = suite
        // Learning reset is limited by the app to the unique suite above.
        // Everyday uses its fixed isolated UI-test domain whenever --ui-testing
        // is present. Its reset flag is DEBUG-only, so root must clear only that
        // disposable QA domain before a Release run if it has old progress.
        // This class never clears the ordinary user defaults or app install.
        app.launchArguments = ["--ui-testing", "--tutorial-hub",
                               "--reset-learning-progress", "--reset-everyday-progress"]
        app.launch()
        let skip = app.buttons["skipIntroduction"]
        if skip.waitForExistence(timeout: 5) { skip.tap() }
        ready(app.segmentedControls["hubFilter"], timeout: 20)
        XCTAssertFalse(app.buttons["skipIntroduction"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "hubResume_")).firstMatch.exists,
                       "Use a fresh disposable Everyday UI-test domain for clean Home captures; do not erase real user progress.")
    }

    override func tearDownWithError() throws {
        defer { app?.terminate(); app = nil }
        guard !captureRecords.isEmpty else { return }
        let metadata: [String: Any] = [
            "candidate": "Protacta public 1.1.1 (40)",
            "bundleIdentifier": "org.realitycore.foliafold",
            "configuration": "Release",
            "scope": "Actual full Simulator UI; 3D studio only; not physical AR evidence",
            "captureMethod": "XCUIScreen.main.screenshot; unmodified native pixels",
            "storeKitFixture": false,
            "paywallShown": false,
            "syntheticAR": false,
            "visualApproval": "Pending human/root visual inspection",
            "simulatorModel": ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unreported",
            "images": captureRecords
        ]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Build40_Store_Screenshot_Metadata.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCapturePublicStoreScreens() throws {
        let dart = app.buttons["hubClassicDart"]
        ready(dart)
        XCTAssertTrue(dart.label.contains("Try the first fold"))
        XCTAssertTrue(app.buttons["hubOrigami"].exists)
        XCTAssertTrue(app.staticTexts["hubTagline"].exists)
        try capture("01_Home", screen: "Home", pose: "Fresh tutorial catalogue")

        dart.tap()
        ready(app.sliders["foldTimeline"])
        waitLabel(app.staticTexts["stepCounter"], containing: "STEP 1 OF 10")
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Make the center crease")
        app.tapViewOption("angleView")
        let foldSlider = app.sliders["foldTimeline"]
        ready(foldSlider)
        foldSlider.adjust(toNormalizedSliderPosition: 0.5)
        let foldPercent = try percentValue(foldSlider)
        XCTAssertTrue((20...80).contains(foldPercent), "Capture an actual intermediate fold, not an endpoint.")
        XCTAssertFalse(app.buttons["nextStep"].label.contains("Pause"), "Capture paused playback.")
        XCTAssertFalse(app.buttons["startLesson"].exists)
        try capture("02_Classic_Dart", screen: "Classic Dart · Studio · Step 1",
                    pose: "Actual slider value \(foldPercent)%")
        ready(app.buttons["returnTutorialHub"])
        app.buttons["returnTutorialHub"].tap()
        ready(app.segmentedControls["hubFilter"])

        try captureEveryday("towel", name: "03_Towel")
        try captureEveryday("t_shirt", name: "04_Tshirt")
        XCTAssertEqual(captureRecords.count, 4)
    }

    private func captureEveryday(_ id: String, name: String) throws {
        let filter = app.segmentedControls["hubFilter"]
        reveal(filter)
        let everyday = filter.buttons["Everyday"]
        ready(everyday)
        if !everyday.isSelected { everyday.tap() }
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: everyday)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        let tile = app.buttons["hubCourse_\(id)"]
        reveal(tile)
        tile.tap()
        let viewport = app.descendants(matching: .any).matching(identifier: "everydayViewport").firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 15))
        waitLabel(app.staticTexts["everydayCounter"], containing: "ACTION 1 OF")
        let slider = app.sliders["everydayProgressSlider"]
        ready(slider)
        slider.adjust(toNormalizedSliderPosition: 0.30)
        let progress = try percentValue(slider)
        XCTAssertTrue((20...85).contains(progress), "The movement must be between its endpoints.")
        waitLabel(app.buttons["everydayPlay"], containing: "Play move")
        XCTAssertTrue(app.buttons["everydayEnterAR"].isHittable)
        XCTAssertFalse(app.buttons["everydayExitAR"].exists)
        XCTAssertFalse(app.staticTexts["everydayARFixtureLabel"].exists)
        XCTAssertFalse(app.staticTexts["everydayARUnavailable"].exists)
        XCTAssertFalse(app.staticTexts["everydayActionTitle"].label.isEmpty)
        XCTAssertTrue(app.frame.contains(viewport.frame))
        try capture(name, screen: "\(id) · Studio · Action 1",
                    pose: "Actual slider value \(progress)%; \(viewport.value as? String ?? "")")
        ready(app.buttons["everydayClose"])
        app.buttons["everydayClose"].tap()
        ready(app.segmentedControls["hubFilter"])
    }

    private func percentValue(_ slider: XCUIElement) throws -> Int {
        let raw = try XCTUnwrap(slider.value as? String)
        let digits = raw.filter { $0.isNumber }
        return try XCTUnwrap(Int(digits), "Missing percentage in slider value: \(raw)")
    }

    private func ready(_ element: XCUIElement, timeout: TimeInterval = 8,
                       file: StaticString = #filePath, line: UInt = #line) {
        let available = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: timeout), .completed,
                       "Unreachable: \(element.identifier)", file: file, line: line)
    }

    private func waitLabel(_ element: XCUIElement, containing value: String,
                           file: StaticString = #filePath, line: UInt = #line) {
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 8), .completed, file: file, line: line)
    }

    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            let scroll = app.scrollViews.firstMatch
            guard scroll.exists else { break }
            if element.exists && element.frame.midY < scroll.frame.midY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        ready(element, file: file, line: line)
    }

    private func capture(_ name: String, screen: String, pose: String) throws {
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        XCTAssertFalse(app.buttons["closeUnlock"].exists)
        XCTAssertFalse(app.buttons["closePlans"].exists)
        Thread.sleep(forTimeInterval: 0.5) // Let the actual paused native frame settle.
        let shot = XCUIScreen.main.screenshot()
        let pixels = try XCTUnwrap(shot.image.cgImage)
        XCTAssertGreaterThan(pixels.height, pixels.width, "Capture the complete portrait screen.")
        XCTAssertGreaterThanOrEqual(pixels.width, 1179, "Use a supported modern iPhone or iPad Simulator.")
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "Build40_Store_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        captureRecords.append(["name": attachment.name, "screen": screen, "pose": pose,
                               "pixelWidth": pixels.width, "pixelHeight": pixels.height,
                               "modified": false, "physicalAR": false])
    }
}
