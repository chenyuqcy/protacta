import XCTest

/// Real navigation through the new progressive-disclosure UI. No feature is
/// exposed or auto-activated in the application for these helpers.
extension XCUIApplication {
    func revealLessonElement(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<10 {
            if element.isHittable { return }
            let scroll = scrollViews.firstMatch
            guard scroll.exists else { break }
            if element.exists && element.frame.midY > 0 && element.frame.midY < scroll.frame.midY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, "Unreachable: \(element.identifier)", file: file, line: line)
    }

    func openLessonHelp(file: StaticString = #filePath, line: UInt = #line) {
        if buttons["closeFoldHelp"].exists { return }
        XCTAssertTrue(buttons["foldHelp"].waitForExistence(timeout: 5), file: file, line: line)
        buttons["foldHelp"].tap()
        XCTAssertTrue(buttons["closeFoldHelp"].waitForExistence(timeout: 5), file: file, line: line)
    }

    func closeLessonHelp(file: StaticString = #filePath, line: UInt = #line) {
        buttons["closeFoldHelp"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: buttons["closeFoldHelp"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, file: file, line: line)
    }

    func tapViewOption(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        if !buttons[id].exists || !buttons[id].isHittable {
            XCTAssertTrue(buttons["viewportOptions"].waitForExistence(timeout: 5), file: file, line: line)
            buttons["viewportOptions"].tap()
        }
        XCTAssertTrue(buttons[id].waitForExistence(timeout: 5), file: file, line: line)
        buttons[id].tap()
    }

    func openOrigamiLibrary(file: StaticString = #filePath, line: UInt = #line) {
        tapViewOption("chooseLesson", file: file, line: line)
        XCTAssertTrue(buttons["closeLibrary"].waitForExistence(timeout: 5), file: file, line: line)
    }

    func selectOrigamiLesson(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        openOrigamiLibrary(file: file, line: line)
        let lesson = buttons["library_\(id)"]
        revealLessonElement(lesson, file: file, line: line)
        lesson.tap()
        XCTAssertTrue(buttons["startLesson"].waitForExistence(timeout: 5), file: file, line: line)
    }

    func scrubFold(to position: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        openLessonHelp(file: file, line: line)
        let slider = sliders["foldProgress"]
        revealLessonElement(slider, file: file, line: line)
        slider.adjust(toNormalizedSliderPosition: position)
        closeLessonHelp(file: file, line: line)
    }

    var foldProgressValue: String? { sliders["foldTimeline"].value as? String }
    var foldPlaybackLabel: String { buttons["nextStep"].label.contains("Pause fold") ? "Pause fold" : "Play fold" }

    func tapFoldTool(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        openLessonHelp(file: file, line: line)
        let tool = buttons[id == "replayStep" ? "replayFromHelp" : id]
        revealLessonElement(tool, file: file, line: line)
        tool.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: buttons["closeFoldHelp"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, file: file, line: line)
    }

    func openPaperTool(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        if staticTexts["stepCounter"].exists { tapFoldTool(id, file: file, line: line) }
        else { tapViewOption(id, file: file, line: line) }
    }
}
