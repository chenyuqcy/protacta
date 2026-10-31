import XCTest

final class AssemblyPlayerUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--tutorial-hub"]
        app.launch()
        let product = app.buttons["hubProductManual"]
        reveal(product); product.tap()
        let open = app.buttons["aerisAssemblyPlayer"]
        XCTAssertTrue(open.waitForExistence(timeout: 15)); reveal(open); open.tap()
        XCTAssertTrue(app.buttons["assemblyNext"].waitForExistence(timeout: 20))
        let viewport = app.descendants(matching: .any).matching(identifier: "assemblyViewportRegion").firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(viewport.frame.height, 150)
    }
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    func testPartSelectionExplodeReplayCompactModeAndReturnToLegacyGuide() {
        capture("Assembly_full_screen_initial")
        app.buttons["assemblyToggleDetails"].tap()
        app.buttons["assemblyPartMenu"].tap()
        app.buttons["Filter cartridge"].tap()
        XCTAssertTrue(app.staticTexts["assemblyPartDetail"].label.contains("pleated media"))
        app.buttons["assemblyExplode"].tap()
        XCTAssertEqual(app.buttons["assemblyExplode"].value as? String, "Exploded")
        XCTAssertFalse(app.sliders["assemblySlider"].isEnabled)
        capture("Assembly_exploded_filter_selected")
        app.buttons["assemblyExplode"].tap()
        let slider = app.sliders["assemblySlider"]
        slider.adjust(toNormalizedSliderPosition: 1)
        app.buttons["assemblyNext"].tap()
        XCTAssertTrue(app.staticTexts["assemblyCounter"].label.contains("2/3"))
        app.buttons["assemblyReplay"].tap()
        app.buttons["assemblySpeed"].tap()
        app.buttons["assemblyToggleDetails"].tap()
        XCTAssertFalse(app.sliders["assemblySlider"].exists)
        XCTAssertTrue(app.buttons["assemblyNext"].isHittable)
        XCTAssertTrue(app.buttons["assemblyVoice"].isHittable)
        capture("Assembly_compact_full_screen")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.staticTexts["assemblyCounter"].label.contains("2/3"))
        capture("Assembly_after_foreground")
        app.buttons["assemblyNext"].tap()
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "3/3"), object: app.staticTexts["assemblyCounter"])
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 5), .completed)
        app.buttons["assemblyToggleDetails"].tap()
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 1)
        capture("Assembly_reassembled")
        app.buttons["assemblyClose"].tap()
        let next = app.buttons["nextStep"]
        reveal(next)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in next.exists && next.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        next.tap()
        XCTAssertTrue(app.staticTexts["stepTitle"].label.contains("release tab"))
        XCTAssertFalse(next.isEnabled, "Leaving the structure viewer must not bypass the original tab gate")
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<10 {
            if element.isHittable { return }
            if element.exists && element.frame.midY < app.frame.midY { app.scrollViews.firstMatch.swipeDown() }
            else { app.scrollViews.firstMatch.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
