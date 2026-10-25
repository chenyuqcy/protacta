import XCTest
import StoreKitTest

/// Layout evidence on a dedicated iPad simulator. Purchases use the real local
/// StoreKit session and the production paywall; no entitlement injection.
final class TabletLayoutUITests: XCTestCase {
    private var app: XCUIApplication!
    private var storeSession: SKTestSession!
    private let productID = "org.realitycore.foliafold.complete"

    override func setUp() async throws {
        continueAfterFailure = false
        storeSession = try SKTestSession(configurationFileNamed: "FoliafoldTesting")
        storeSession.resetToDefaultState()
        storeSession.clearTransactions()
        storeSession.disableDialogs = true
        await MainActor.run { XCUIDevice.shared.orientation = .portrait }
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 15))
        let locked = NSPredicate(format: "label CONTAINS %@", "Unlock this lesson")
        await fulfillment(of: [expectation(for: locked, evaluatedWith: app.buttons["startLesson"])], timeout: 15)
    }

    override func tearDownWithError() throws {
        app?.terminate()
        storeSession?.clearTransactions()
        storeSession?.resetToDefaultState()
        XCUIDevice.shared.orientation = .portrait
        app = nil; storeSession = nil
    }

    func testTabletPortraitLandscapeLibraryPurchaseAndLongLessons() {
        XCTAssertGreaterThan(app.frame.width, 700, "Run this layout suite on an iPad")
        for landscape in [false, true] {
            orient(landscape)
            capture("iPad_\(direction)_Welcome")
            assertVisible(["chooseLesson", "openAR", "startLesson"])
            app.buttons["chooseLesson"].tap()
            XCTAssertTrue(app.buttons["closeLibrary"].waitForExistence(timeout: 5))
            let lessons = ["crane", "star", "frog", "turtle", "fullRabbit", "sittingDog", "fullFox", "elephant", "butterfly", "dart", "fox", "rabbit"]
            for lesson in lessons { XCTAssertTrue(app.buttons["library_\(lesson)"].exists) }
            capture("iPad_\(direction)_Library_top")
            reveal(app.buttons["library_rabbit"])
            capture("iPad_\(direction)_Library_bottom")
            assertVisible(["closeLibrary", "library_rabbit"])
            app.buttons["closeLibrary"].tap()
        }

        orient(false)
        app.buttons["startLesson"].tap()
        XCTAssertTrue(app.buttons["purchaseLibrary"].waitForExistence(timeout: 15))
        let lifetime = app.buttons["purchasePlan_lifetime"]
        reveal(lifetime)
        lifetime.tap()
        for landscape in [false, true] {
            orient(landscape)
            reveal(app.staticTexts["Small folds.\nMore possibilities."], towardsTop: true)
            capture("iPad_\(direction)_Paywall_top")
            reveal(app.buttons["keepExploring"])
            capture("iPad_\(direction)_Paywall_controls")
            assertVisible(["closeUnlock", "restorePurchases", "keepExploring"])
        }
        let buy = app.buttons["purchaseLibrary"]
        reveal(buy, towardsTop: true)
        XCTAssertFalse(buy.label.contains("Please wait"))
        buy.tap()
        let unlocked = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", "Start folding"),
            object: app.buttons["startLesson"])
        XCTAssertEqual(XCTWaiter.wait(for: [unlocked], timeout: 20), .completed)
        XCTAssertTrue(storeSession.allTransactions().contains { $0.productIdentifier == productID })
        capture("iPad_Landscape_Verified_purchase")

        for (lesson, step, total) in [("crane",22,28),("frog",22,22),("elephant",33,40),("fullFox",24,24)] {
            orient(false)
            if lesson != "crane" {
                app.buttons["chooseLesson"].tap()
                XCTAssertTrue(app.buttons["library_\(lesson)"].waitForExistence(timeout: 5))
                reveal(app.buttons["library_\(lesson)"])
                app.buttons["library_\(lesson)"].tap()
                XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 5))
            }
            app.buttons["startLesson"].tap()
            jump(to: step)
            XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP \(step) OF \(total)")
            app.sliders["foldProgress"].adjust(toNormalizedSliderPosition: lesson == "crane" ? 0.45 : 0.25)
            XCTAssertTrue(app.buttons["nextStep"].label.contains("Finish this fold"))
            capture("iPad_Portrait_\(lesson)_Long_instruction_controls")
            assertLessonControls()

            app.buttons["foldNotes"].tap()
            XCTAssertTrue(app.buttons["closeNotes"].waitForExistence(timeout: 5))
            capture("iPad_Portrait_\(lesson)_Notes")
            assertVisible(["closeNotes"])
            orient(true)
            capture("iPad_Landscape_\(lesson)_Notes")
            assertVisible(["closeNotes"])
            app.buttons["closeNotes"].tap()
            capture("iPad_Landscape_\(lesson)_Long_instruction_controls")
            assertLessonControls()
            app.buttons["topView"].tap()
            capture("iPad_Landscape_\(lesson)_Top_view")
            app.buttons["angleView"].tap()
            app.buttons["nextStep"].tap()
            ready(app.buttons["nextStep"])
            XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP \(step) OF \(total)",
                           "Finishing the scrubbed action must not skip to another step")
        }
    }

    private var direction: String { app.frame.width > app.frame.height ? "Landscape" : "Portrait" }

    func testTabletStepRowCenterSelectsFreeLessonStep() {
        // A free lesson isolates hit testing from store-server availability.
        app.buttons["chooseLesson"].tap()
        reveal(app.buttons["library_fox"])
        app.buttons["library_fox"].tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Start folding"),
                                                object: app.buttons["startLesson"])
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        app.buttons["startLesson"].tap()
        for (landscape, step) in [(false, 3), (true, 4)] {
            orient(landscape)
            app.buttons["stepList"].tap()
            let row = app.buttons["jumpStep_\(step)"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            capture("iPad_\(direction)_Step_row_before_center_tap")
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "STEP \(step) OF "),
                                                   object: app.staticTexts["stepCounter"])
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
            ready(app.buttons["nextStep"])
            capture("iPad_\(direction)_Step_row_selected")
        }
    }

    private func orient(_ landscape: Bool) {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let frame = self?.app.frame else { return false }
            return landscape ? frame.width > frame.height : frame.height > frame.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 8), .completed)
    }

    private func reveal(_ element: XCUIElement, towardsTop: Bool = false) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        // iPad leaves the underlying horizontal lesson picker in the AX tree.
        // Target the scroll view containing this sheet's content explicitly.
        let key = element.identifier.isEmpty ? element.label : element.identifier
        let scroll = app.scrollViews.containing(.any, identifier: key).firstMatch
        XCTAssertTrue(scroll.exists, "No containing scroll view for \(key)")
        for _ in 0..<7 {
            if element.isHittable { break }
            if towardsTop { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        if !element.isHittable { capture("Unreachable_\(key)") }
        XCTAssertTrue(element.isHittable)
    }

    private func jump(to step: Int) {
        ready(app.buttons["stepList"])
        app.buttons["stepList"].tap()
        let row = app.buttons["jumpStep_\(step)"]
        // SwiftUI List is exposed as a CollectionView on this iPad runtime.
        let scroll = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for _ in 0..<10 {
            if row.exists && row.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(row.isHittable)
        // The full label is a rectangular hit target in the current app.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        // Selecting a List row commits through sheet onDismiss. The background
        // Next button remains enabled while that dismissal is still pending.
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "STEP \(step) OF "),
            object: app.staticTexts["stepCounter"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
        ready(app.buttons["nextStep"])
    }

    private func ready(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
    }

    private func assertLessonControls() {
        assertVisible(["nextStep", "backStep", "replayStep", "foldNotes", "playPause", "playbackSpeed",
                       "stepList", "topView", "angleView", "toggleHints"])
        XCTAssertTrue(app.sliders["foldProgress"].isHittable)
        XCTAssertTrue(app.frame.contains(app.staticTexts["stepInstruction"].frame))
        XCTAssertTrue(app.frame.contains(app.staticTexts["stepTitle"].frame))
    }

    private func assertVisible(_ ids: [String]) {
        for id in ids {
            let element = app.buttons[id]
            XCTAssertTrue(element.isHittable, "Control is not reachable: \(id)")
            XCTAssertTrue(app.frame.contains(element.frame), "Control is outside the app: \(id), \(element.frame)")
        }
    }

    private func capture(_ name: String) {
        // Element screenshots crop in unrotated coordinates on this runtime.
        // Capture the full physical screen to retain both landscape edges.
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
        // assertVisible/assertLessonControls below each capture already verify
        // typed control bounds and hit testing. Avoid a second generic AX-tree
        // walk solely for text attachments: the retained English capture run
        // crashed in XCTest's injected log-fault callback during those queries.
    }
}
