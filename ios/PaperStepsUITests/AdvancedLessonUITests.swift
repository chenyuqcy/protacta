import XCTest
import StoreKitTest

final class AdvancedLessonUITests: XCTestCase {
    private var app: XCUIApplication!
    private var storeSession: SKTestSession!

    override func setUp() async throws {
        continueAfterFailure = false
        storeSession = try SKTestSession(configurationFileNamed: "ProtactaTesting")
        storeSession.resetToDefaultState()
        storeSession.clearTransactions()
        storeSession.disableDialogs = true
        _ = try await storeSession.buyProduct(identifier: "org.realitycore.protacta.prototype.complete")
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 15))
        let ready = NSPredicate(format: "label CONTAINS %@", "Start folding")
        await fulfillment(of: [expectation(for: ready, evaluatedWith: app.buttons["startLesson"])], timeout: 10)
    }
    override func tearDownWithError() throws {
        app.terminate(); app = nil
        storeSession?.clearTransactions(); storeSession?.resetToDefaultState(); storeSession = nil
    }

    func testCraneAll28ActionsIncludingSquashPetalAndReverseFolds() {
        capture("Crane_00_Welcome")
        app.buttons["startLesson"].tap()
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Begin with a square")
        capture("Crane_00_White_square")
        for step in 1...28 {
            next()
            XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP \(step) OF 28")
            capture(String(format: "Crane_%02d_Complete", step))
            if [3, 9, 14, 22, 25, 27].contains(step) {
                app.scrubFold(to: 0.45)
                XCTAssertTrue(app.buttons["nextStep"].label.contains("Finish this fold"))
                capture(String(format: "Crane_%02d_Mid_motion", step))
                app.tapViewOption("angleView")
                capture(String(format: "Crane_%02d_Mid_angle", step))
                app.buttons["nextStep"].tap()
                enabled(app.buttons["nextStep"])
                XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP \(step) OF 28")
            }
            if step == 22 {
                XCTAssertEqual(app.staticTexts["stepTitle"].label, "Reverse the neck upward")
                app.tapFoldTool("foldNotes")
                XCTAssertTrue(app.buttons["closeNotes"].waitForExistence(timeout: 5))
                capture("Crane_22_Inside_reverse_explanation")
                app.buttons["closeNotes"].tap()
            }
        }
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Meet your finished crane")
        app.tapViewOption("topView")
        capture("Crane_28_Top")
        app.tapViewOption("angleView")
        next()
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "LESSON COMPLETE")
        capture("Crane_Finished")
        app.buttons["nextStep"].tap()
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Begin with a square")
    }

    func testLuckyStarFromStripThroughFivePinches() {
        app.selectOrigamiLesson("star")
        capture("Star_00_Welcome")
        app.buttons["startLesson"].tap()
        capture("Star_00_Paper_strip")
        for step in 1...13 {
            next()
            XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP \(step) OF 13")
            capture(String(format: "Star_%02d_Complete", step))
            if [1, 2, 3, 6, 8, 9, 13].contains(step) {
                app.scrubFold(to: 0.45)
                capture(String(format: "Star_%02d_Mid_motion", step))
                app.buttons["nextStep"].tap()
                enabled(app.buttons["nextStep"])
                XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP \(step) OF 13")
            }
        }
        app.tapViewOption("topView")
        capture("Star_13_Top")
        app.tapViewOption("angleView")
        next()
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "LESSON COMPLETE")
        capture("Star_Finished")
    }

    func testLibrarySwitchAndAdvancedARFallbackPreserveTheLesson() {
        app.buttons["startLesson"].tap()
        for _ in 0..<3 { next() }
        app.tapFoldTool("stepList")
        XCTAssertTrue(app.buttons["jumpStep_0"].waitForExistence(timeout: 5))
        capture("Crane_Step_index")
        app.buttons["jumpStep_0"].tap()
        XCTAssertTrue(app.buttons["nextStep"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Begin with a square"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Begin with a square")
        app.openOrigamiLibrary()
        XCTAssertTrue(app.buttons["library_star"].waitForExistence(timeout: 5))
        capture("Three_lesson_library")
        app.buttons["library_star"].tap()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 5))
        app.buttons["startLesson"].tap()
        next()
        #if targetEnvironment(simulator)
        app.buttons["openAR"].tap()
        XCTAssertTrue(app.buttons["returnTo3D"].waitForExistence(timeout: 5))
        app.buttons["returnTo3D"].tap()
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP 1 OF 13")
        #endif
        app.openOrigamiLibrary()
        app.buttons["library_crane"].tap()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 5))
        app.buttons["startLesson"].tap()
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Begin with a square")
    }

    private func next(file: StaticString = #filePath, line: UInt = #line) {
        enabled(app.buttons["nextStep"], file: file, line: line)
        app.buttons["nextStep"].tap()
        enabled(app.buttons["nextStep"], file: file, line: line)
    }
    private func enabled(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true AND NOT (identifier == %@ AND label CONTAINS %@)", "nextStep", "Pause fold"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, file: file, line: line)
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
