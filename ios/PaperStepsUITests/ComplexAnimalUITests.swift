import XCTest
import StoreKitTest
import UIKit

final class ComplexAnimalUITests: XCTestCase {
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
        let unlocked = NSPredicate(format: "label CONTAINS %@", "Start folding")
        await fulfillment(of: [expectation(for: unlocked, evaluatedWith: app.buttons["startLesson"])], timeout: 10)
    }

    override func tearDownWithError() throws {
        app?.terminate()
        storeSession?.clearTransactions()
        storeSession?.resetToDefaultState()
        app = nil; storeSession = nil
    }

    func testCompleteElephantFortyActions() {
        walkNewAnimal(id:"elephant",last:40,first:"Prepare a large square",
                      midpoints:[27,30,33,34,35,36,37,38,39,40])
    }

    func testFullFoxTwentyFourActions() {
        walkNewAnimal(id:"fullFox",last:24,first:"Begin with one square",
                      midpoints:[3,5,7,12,13,16,17,22,24])
    }

    private func walkNewAnimal(id:String,last:Int,first:String,midpoints:Set<Int>) {
        app.openOrigamiLibrary()
        let library=app.scrollViews["lessonLibraryScroll"],row=app.buttons["library_\(id)"]
        for _ in 0..<8 where !row.isHittable {library.swipeUp()}
        XCTAssertTrue(row.isHittable);row.tap()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["startLesson"].label.contains("Start folding"))
        capture("\(id)_Welcome")
        app.buttons["startLesson"].tap()
        XCTAssertEqual(app.staticTexts["stepTitle"].label,first)
        capture("\(id)_00_Square");assertVisibleModelInterior()
        for step in 1...last {
            waitForNext();app.buttons["nextStep"].tap();waitForNext()
            XCTAssertEqual(app.staticTexts["stepCounter"].label,"STEP \(step) OF \(last)")
            if midpoints.contains(step) {
                capture("\(id)_\(step)_Endpoint")
                app.scrubFold(to: 0.5)
                capture("\(id)_\(step)_Midpoint")
                app.buttons["nextStep"].tap();waitForNext()
            }
        }
        app.tapViewOption("topView");capture("\(id)_Final_Top")
        app.tapViewOption("angleView");capture("\(id)_Final_Angle");assertVisibleModelInterior()
        app.tapFoldTool("replayStep");waitForNext()
        XCTAssertEqual(app.staticTexts["stepCounter"].label,"STEP \(last) OF \(last)")
        app.buttons["nextStep"].tap();waitForNext()
        XCTAssertEqual(app.staticTexts["stepCounter"].label,"LESSON COMPLETE")
        capture("\(id)_Complete")
    }

    private func assertVisibleModelInterior() {
        let image=app.screenshot().image
        guard let cg=image.cgImage else {XCTFail("No screenshot image");return}
        let w=cg.width,h=cg.height
        var pixels=[UInt8](repeating:0,count:w*h*4)
        let context=CGContext(data:&pixels,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(cg,in:CGRect(x:0,y:0,width:w,height:h))
        var low=255,high=0
        // iPhone portrait interior; a coarse blank-render regression check.
        // Screenshot review still verifies the actual model and folds.
        for y in stride(from:Int(Double(h)*0.24),to:Int(Double(h)*0.54),by:4) {
            for x in stride(from:Int(Double(w)*0.15),to:Int(Double(w)*0.85),by:4) {
                let value=Int(pixels[(y*w+x)*4]);low=min(low,value);high=max(high,value)
            }
        }
        XCTAssertGreaterThan(high-low,18,"Native model viewport is blank: interior red-channel range \(high-low)")
    }
    func testSittingDogTwentyEightActions() {
        XCTAssertTrue(app.buttons["viewportOptions"].waitForExistence(timeout:15));app.openOrigamiLibrary()
        let library=app.scrollViews["lessonLibraryScroll"],entry=app.buttons["library_sittingDog"]
        for _ in 0..<6 where !entry.isHittable {library.swipeUp()}
        XCTAssertTrue(entry.isHittable);entry.tap()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["startLesson"].label.contains("Start folding"))
        capture("SittingDog_Catalog_Welcome_Preview")
        app.buttons["startLesson"].tap()
        XCTAssertEqual(app.staticTexts["stepTitle"].label,"Prepare one square")
        capture("SittingDog_Catalog_00_Square")
        for step in 1...28 {
            waitForNext();app.buttons["nextStep"].tap();waitForNext()
            XCTAssertEqual(app.staticTexts["stepCounter"].label,"STEP \(step) OF 28")
            capture(String(format:"SittingDog_Catalog_%02d_Complete",step))
            if [3,7,12,14,19,20,21,22,24,28].contains(step) {
                app.scrubFold(to: 0.5)
                capture(String(format:"SittingDog_Catalog_%02d_Midfold_Angle",step))
                if step == 28 {app.tapViewOption("topView");capture("SittingDog_Catalog_28_Opening_Midpoint_Top");app.tapViewOption("angleView")}
                app.buttons["nextStep"].tap();waitForNext()
            }
        }
        app.tapViewOption("topView");capture("SittingDog_Catalog_28_Final_Top")
        app.tapViewOption("angleView");capture("SittingDog_Catalog_28_Final_Angle")
        app.tapFoldTool("replayStep");waitForNext()
        XCTAssertEqual(app.staticTexts["stepCounter"].label,"STEP 28 OF 28")
        capture("SittingDog_Catalog_28_Replayed_Opening")
        app.buttons["nextStep"].tap();waitForNext()
        XCTAssertEqual(app.staticTexts["stepCounter"].label,"LESSON COMPLETE")
        capture("SittingDog_Catalog_Complete")
    }

    func testStandingRabbitTwentyFiveActions() {
        XCTAssertTrue(app.buttons["viewportOptions"].waitForExistence(timeout:15));app.openOrigamiLibrary()
        let library=app.scrollViews["lessonLibraryScroll"],entry=app.buttons["library_fullRabbit"]
        for _ in 0..<6 where !entry.isHittable {library.swipeUp()}
        XCTAssertTrue(entry.isHittable);entry.tap()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["startLesson"].label.contains("Start folding"))
        capture("StandingRabbit_Catalog_Welcome_Preview")
        app.buttons["startLesson"].tap()
        XCTAssertEqual(app.staticTexts["stepTitle"].label,"Prepare the square")
        capture("StandingRabbit_Catalog_00_Square")
        for step in 1...25 {
            waitForNext();app.buttons["nextStep"].tap();waitForNext()
            XCTAssertEqual(app.staticTexts["stepCounter"].label,"STEP \(step) OF 25")
            capture(String(format:"StandingRabbit_Catalog_%02d_Complete",step))
            if [7,13,15,24,25].contains(step) {
                app.scrubFold(to: 0.5)
                capture(String(format:"StandingRabbit_Catalog_%02d_Midfold_Angle",step))
                if step == 25 {app.tapViewOption("topView");capture("StandingRabbit_Catalog_25_Opening_Midpoint_Top");app.tapViewOption("angleView")}
                app.buttons["nextStep"].tap();waitForNext()
            }
        }
        app.tapViewOption("topView");capture("StandingRabbit_Catalog_25_Final_Top")
        app.tapViewOption("angleView");capture("StandingRabbit_Catalog_25_Final_Angle")
        app.tapFoldTool("replayStep");waitForNext()
        XCTAssertEqual(app.staticTexts["stepCounter"].label,"STEP 25 OF 25")
        capture("StandingRabbit_Catalog_25_Replayed_Opening")
        app.buttons["nextStep"].tap();waitForNext()
        XCTAssertEqual(app.staticTexts["stepCounter"].label,"LESSON COMPLETE")
        capture("StandingRabbit_Catalog_Complete")
    }

    func testFullBodyFrogAllTwentyTwoActionsAndPocketReplay() {
        app.openOrigamiLibrary()
        let row = app.buttons["library_frog"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        for _ in 0..<5 {
            if row.isHittable { break }
            app.scrollViews["lessonLibraryScroll"].swipeUp()
        }
        XCTAssertTrue(row.isHittable)
        row.tap()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 5))
        capture("Frog_Welcome")
        app.buttons["startLesson"].tap()
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Prepare a long rectangle")
        capture("Frog_00_Rectangle")
        for step in 1...22 {
            next()
            XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP \(step) OF 22")
            XCTAssertFalse(app.staticTexts["stepInstruction"].label.isEmpty)
            capture(String(format: "Frog_%02d_Complete", step))
            if [5, 12, 13, 14, 15, 20, 21, 22].contains(step) {
                if [12, 13, 22].contains(step) {
                    app.scrubFold(to: 0.25)
                    capture(String(format: "Frog_%02d_Quarter_motion_angle", step))
                }
                // The precrease arrow must reverse with the reopening flap.
                app.scrubFold(to: [12, 13].contains(step) ? 0.75 : 0.5)
                XCTAssertTrue(app.buttons["nextStep"].label.contains("Finish this fold"))
                capture(String(format: "Frog_%02d_Midfold_angle", step))
                app.tapViewOption("topView")
                capture(String(format: "Frog_%02d_Midfold_top", step))
                app.tapViewOption("angleView")
                next()
                XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP \(step) OF 22")
            }
            if step == 15 {
                app.tapFoldTool("foldNotes")
                XCTAssertTrue(app.buttons["closeNotes"].waitForExistence(timeout: 5))
                capture("Frog_Pocket_explanation")
                app.buttons["closeNotes"].tap()
                #if targetEnvironment(simulator)
                app.buttons["openAR"].tap()
                XCTAssertTrue(app.buttons["returnTo3D"].waitForExistence(timeout: 5))
                app.buttons["returnTo3D"].tap()
                XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP 15 OF 22")
                #endif
            }
        }
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Turn over and release the legs")
        app.tapViewOption("topView"); capture("Frog_Finished_top")
        app.tapViewOption("angleView"); capture("Frog_Finished_angle")
        next()
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "LESSON COMPLETE")
        capture("Frog_Lesson_complete")
    }

    func testTurtleAllTwentyThreeActionsAndShellReplay() {
        app.openOrigamiLibrary()
        let row = app.buttons["library_turtle"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        for _ in 0..<6 {
            if row.isHittable { break }
            app.scrollViews["lessonLibraryScroll"].swipeUp()
        }
        XCTAssertTrue(row.isHittable)
        row.tap()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 5))
        capture("Turtle_Welcome")
        app.buttons["startLesson"].tap()
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Prepare your square")
        capture("Turtle_00_Square")
        for step in 1...23 {
            next()
            XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP \(step) OF 23")
            XCTAssertFalse(app.staticTexts["stepInstruction"].label.isEmpty)
            for identifier in ["nextStep", "backStep", "foldHelp"] {
                let control = app.buttons[identifier]
                XCTAssertTrue(control.isHittable, "Step \(step): \(identifier)")
                XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(control.frame), "Step \(step) clips \(identifier): \(control.frame)")
            }
            capture(String(format: "Turtle_%02d_Complete", step))
            if [13, 15, 16, 19, 20, 23].contains(step) {
                app.scrubFold(to: 0.5)
                XCTAssertTrue(app.buttons["nextStep"].label.contains("Finish this fold"))
                capture(String(format: "Turtle_%02d_Midfold_angle", step))
                app.tapViewOption("topView")
                capture(String(format: "Turtle_%02d_Midfold_top", step))
                app.tapViewOption("angleView")
                next()
                XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP \(step) OF 23")
            }
            if step == 16 {
                app.tapFoldTool("foldNotes")
                XCTAssertTrue(app.buttons["closeNotes"].waitForExistence(timeout: 5))
                capture("Turtle_Shell_explanation")
                app.buttons["closeNotes"].tap()
                #if targetEnvironment(simulator)
                app.buttons["openAR"].tap()
                XCTAssertTrue(app.buttons["returnTo3D"].waitForExistence(timeout: 5))
                app.buttons["returnTo3D"].tap()
                XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP 16 OF 23")
                #endif
            }
        }
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Finish the matching rear foot")
        app.tapViewOption("topView"); capture("Turtle_Finished_top")
        app.tapViewOption("angleView"); capture("Turtle_Finished_angle")
        next()
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "LESSON COMPLETE")
        capture("Turtle_Lesson_complete")
    }

    func testTurtlePreviewAndGuideCanSwitchRepeatedly() {
        for id in ["turtle", "star", "turtle", "crane", "turtle"] {
            app.openOrigamiLibrary()
            let row = app.buttons["library_\(id)"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            for _ in 0..<6 {
                if row.isHittable { break }
                app.scrollViews["lessonLibraryScroll"].swipeUp()
            }
            XCTAssertTrue(row.isHittable); row.tap()
            XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 5))
            app.buttons["startLesson"].tap()
            XCTAssertTrue(app.staticTexts["stepTitle"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["stepCounter"].label, "BEFORE YOU BEGIN")
            XCTAssertTrue(app.buttons["nextStep"].isHittable)
        }
        capture("Turtle_Repeated_preview_guide_switches")
    }

    private func next(file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons["nextStep"]
        func ready() {
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true AND NOT (identifier == %@ AND label CONTAINS %@)", "nextStep", "Pause fold"), object: button)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed, file: file, line: line)
        }
        ready(); button.tap(); ready()
    }

    private func waitForNext() {
        let e = expectation(for: NSPredicate(format: "exists == true AND enabled == true AND NOT (identifier == %@ AND label CONTAINS %@)", "nextStep", "Pause fold"), evaluatedWith: app.buttons["nextStep"])
        wait(for: [e], timeout: 20)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
