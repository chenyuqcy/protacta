import XCTest
import UIKit

/// The fixture is explicit and simulator-only; this verifies UI/state wiring,
/// not Vision accuracy, a physical camera session, or real folding outcomes.
final class PaperGuideUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-learning-progress", "--paper-guide-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["openPaperGuide"].waitForExistence(timeout: 15))
        app.buttons["openPaperGuide"].tap()
        XCTAssertTrue(app.staticTexts["paperGuideFixtureLabel"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws { app?.terminate(); app = nil }

    func testDirectionLossRecoveryAndExplicitLearnerConfirmation() {
        let confirm = app.buttons["confirmPaperDirection"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["paperGuideStatus"].label.contains("left long edge"))
        capture("Synthetic_fixture_direction_confirmed")

        reveal(app.buttons["losePaperFixture"])
        app.buttons["losePaperFixture"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        XCTAssertFalse(confirm.isEnabled)
        XCTAssertTrue(app.staticTexts["paperGuideStatus"].label.contains("no longer aligned"))
        app.buttons["restorePaperFixture"].tap()
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        reveal(app.buttons["confirmFirstPaperFold"])
        app.buttons["confirmFirstPaperFold"].tap()
        XCTAssertTrue(app.staticTexts["stepCounter"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP 1 OF 10")
        XCTAssertFalse(app.staticTexts["paperGuideFixtureLabel"].exists)
        capture("Learner_confirmed_first_fold_returns_to_3D")
    }

    func testReferenceReturnsToTheExistingLessonPlayer() {
        reveal(app.buttons["paperGuideReference"])
        app.buttons["paperGuideReference"].tap()
        XCTAssertTrue(app.staticTexts["stepCounter"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Make the center crease")
        XCTAssertTrue(app.buttons["playPause"].exists)
    }

    func testBackgroundRequiresFreshDirectionAfterExplicitRecovery() {
        app.buttons["confirmPaperDirection"].tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["paperGuideStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["paperGuideStatus"].label.contains("session paused"))
        reveal(app.buttons["reacquirePaper"])
        app.buttons["reacquirePaper"].tap()
        let confirm = app.buttons["confirmPaperDirection"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(confirm.isEnabled)
        XCTAssertTrue(app.staticTexts["paperGuideStatus"].label.contains("TOP edge"))
    }

    func testGuideControlsRemainReachableOnTabletInLandscape() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Tablet layout check") }
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.frame.width > self.app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        defer { XCUIDevice.shared.orientation = .portrait }
        let confirm = app.buttons["confirmPaperDirection"]
        reveal(confirm)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["paperGuideStatus"].label.contains("left long edge"))
        reveal(app.buttons["rotatePaperDirection"])
        app.buttons["rotatePaperDirection"].tap()
        reveal(app.buttons["paperGuideReference"])
        let window = app.frame
        let reference = app.buttons["paperGuideReference"].frame
        XCTAssertGreaterThan(window.width, window.height)
        XCTAssertLessThanOrEqual(reference.maxX, window.maxX)
        XCTAssertLessThanOrEqual(reference.maxY, window.maxY)
        capture("Synthetic_fixture_iPad_landscape")
        app.buttons["paperGuideReference"].tap()
        XCTAssertTrue(app.staticTexts["stepCounter"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<4 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ name: String) {
        // Full-screen capture avoids XCUIApplication's rotated-window crop on
        // iPad Simulator. Keep its native orientation metadata in the receipt.
        let screenshot = XCUIScreen.main.screenshot()
        if name.contains("landscape") {
            let image = screenshot.image
            let info = XCTAttachment(string: "frame=\(app.frame) imageSize=\(image.size) imageOrientation=\(image.imageOrientation.rawValue)")
            info.name = "Landscape_geometry_metadata"
            info.lifetime = .keepAlways
            add(info)
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
