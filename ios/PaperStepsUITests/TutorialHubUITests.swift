import XCTest
import UIKit

/// Normal hub navigation with authored diagrams. These checks do not verify
/// physical folds, knot topology on real cord, or camera registration.
final class TutorialHubUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["PROTACTA_PROGRESS_TEST_SUITE"] = "org.realitycore.protacta.prototype.uitests.\(UUID().uuidString)"
        app.launchArguments = ["--ui-testing", "--tutorial-hub", "--reset-everyday-progress", "--reset-learning-progress"]
        app.launch()
        XCTAssertTrue(app.buttons["hubOrigami"].waitForExistence(timeout: 15))
    }
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    func testClassicDartCardStartsFirstFoldAndRestoresPausedProgressAfterRelaunch() throws {
        let card = app.buttons["hubClassicDart"]
        XCTAssertTrue(card.isHittable)
        XCTAssertTrue(card.label.contains("Try the first fold"))
        capture("Classic_Dart_first_fold_home_card")
        card.tap()

        let counter = app.staticTexts["stepCounter"]
        let timeline = app.sliders["foldTimeline"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10))
        XCTAssertEqual(counter.label, "STEP 1 OF 10")
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Make the center crease")
        XCTAssertTrue(timeline.isHittable)
        XCTAssertEqual(app.foldProgressValue, "0%")
        XCTAssertFalse(app.buttons["startLesson"].exists)

        let next = app.buttons["nextStep"]
        XCTAssertTrue(next.label.contains("Play"))
        next.tap()
        let firstFoldFinished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Next"), object: next)
        XCTAssertEqual(XCTWaiter.wait(for: [firstFoldFinished], timeout: 5), .completed)
        XCTAssertEqual(app.foldProgressValue, "100%")
        next.tap()
        let stepTwo = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "STEP 2 OF 10"), object: counter)
        XCTAssertEqual(XCTWaiter.wait(for: [stepTwo], timeout: 5), .completed)
        timeline.adjust(toNormalizedSliderPosition: 0.4)
        let pausedProgress = try XCTUnwrap(app.foldProgressValue)
        XCTAssertTrue(app.buttons["nextStep"].label.contains("Continue"))
        app.buttons["returnTutorialHub"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("Continue · Step 2"))
        capture("Classic_Dart_resume_home_card")
        let resume = app.buttons["hubResume_origami_dart"]
        XCTAssertTrue(resume.isHittable, "Imron's Resume card must read the same saved fold")
        resume.tap()
        XCTAssertTrue(counter.waitForExistence(timeout: 10))
        XCTAssertEqual(counter.label, "STEP 2 OF 10")
        XCTAssertEqual(app.foldProgressValue, pausedProgress)
        app.buttons["returnTutorialHub"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--ui-testing", "--tutorial-hub"]
        app.launch()
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        XCTAssertTrue(card.label.contains("Continue · Step 2"))
        card.tap()
        XCTAssertTrue(counter.waitForExistence(timeout: 10))
        XCTAssertEqual(counter.label, "STEP 2 OF 10")
        XCTAssertEqual(app.foldProgressValue, pausedProgress)
        XCTAssertTrue(app.buttons["nextStep"].label.contains("Continue"))
    }

    func testImronPlansAndOrigamiGridKeepTheLatestPlayerReachable() {
        app.buttons["hubPricing"].tap()
        if AppReleaseIdentity.productPrefix == "org.realitycore.foliafold" {
            XCTAssertTrue(app.buttons["closeUnlock"].waitForExistence(timeout: 5))
            for plan in ["monthly", "annual", "lifetime"] {
                XCTAssertTrue(app.buttons["purchasePlan_\(plan)"].exists)
            }
            XCTAssertFalse(app.buttons["choosePlan"].exists,
                           "The public release must show the real storefront, not prototype pricing")
            XCTAssertTrue(app.buttons["restorePurchases"].exists)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "purchaseTerms").firstMatch.exists)
            capture("Public_Home_Purchase_Plans")
            app.buttons["closeUnlock"].tap()
        } else {
            XCTAssertTrue(app.buttons["closePlans"].waitForExistence(timeout: 5))
            capture("Build38_Imron_Plans_preview")
            app.buttons["plansPlan_0"].tap()
            let starterLessons = app.staticTexts["2 starter lessons (with AR guide)"]
            reveal(starterLessons)
            XCTAssertTrue(starterLessons.exists)
            let disclaimer = app.staticTexts["The dart and fox lessons stay free. Prices in Qatari Riyal. Prototype preview - no charges are made."]
            reveal(disclaimer)
            XCTAssertTrue(disclaimer.isHittable)
            app.buttons["closePlans"].tap()
        }
        XCTAssertTrue(app.buttons["hubOrigami"].waitForExistence(timeout: 5))
        app.buttons["hubOrigami"].tap()
        let dart = app.buttons["hubOrigamiLesson_dart"]
        XCTAssertTrue(dart.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["hubOrigamiLesson_fox"].exists)
        capture("Build38_Imron_Origami_grid")
        dart.tap()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 10))
        app.buttons["startLesson"].tap()
        XCTAssertTrue(app.buttons["autoPlayToggle"].waitForExistence(timeout: 5))
        for id in ["speed_half", "speed_one", "speed_two"] {
            XCTAssertTrue(app.buttons[id].isHittable)
        }
        app.buttons["nextStep"].tap()
        XCTAssertTrue(app.sliders["foldTimeline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["foldTimeline"].isHittable)
        capture("Build38_Imron_player_with_latest_Dart")
    }

    func testOrigamiLeadsTheCatalogAndFiltersKeepOtherTutorialsReachable() {
        let origami = app.buttons["hubOrigami"]
        XCTAssertEqual(app.buttons.matching(identifier: "hubOrigami").count, 1)
        XCTAssertTrue(origami.isHittable, "Origami should open directly from the first screen")
        let firstSection = app.staticTexts["catalogSection_clothes"]
        XCTAssertTrue(firstSection.exists)
        XCTAssertLessThan(origami.frame.minY, firstSection.frame.minY, "The origami hero precedes the grouped catalog")
        XCTAssertTrue(app.buttons["hubPhoneSetup"].exists)
        capture("Team_sections_Origami_first_home")
        origami.tap()
        let dartCard = app.buttons["hubOrigamiLesson_dart"]
        XCTAssertTrue(dartCard.waitForExistence(timeout: 10), "The origami hero opens the paper-model list")
        dartCard.tap()
        XCTAssertTrue(app.buttons["viewportOptions"].waitForExistence(timeout: 15))
        app.buttons["returnTutorialHub"].tap()
        waitForDismissal(app.buttons["returnTutorialHub"])

        selectHomeFilter("Everyday")
        let everydayCatalog = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let app = self?.app else { return false }
            return !app.buttons["hubOrigami"].exists && !app.buttons["hubEquipment_turbofan"].exists
                && app.buttons["hubCourse_towel"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [everydayCatalog], timeout: 5), .completed,
                       "Everyday must replace the hero and equipment with the everyday catalog")
        XCTAssertFalse(app.buttons["hubOrigami"].exists)
        XCTAssertFalse(app.buttons["hubEquipment_turbofan"].exists)
        XCTAssertTrue(app.buttons["hubCourse_towel"].exists)
        tapHome("hubCourse_towel")
        XCTAssertTrue(app.staticTexts["everydayCounter"].waitForExistence(timeout: 10))
        app.buttons["everydayClose"].tap()
        waitForDismissal(app.buttons["everydayClose"])

        selectHomeFilter("Equipment")
        XCTAssertFalse(origami.exists)
        XCTAssertFalse(app.buttons["hubCourse_towel"].exists)
        XCTAssertFalse(app.staticTexts["catalogSection_clothes"].exists)
        XCTAssertTrue(app.staticTexts["catalogSection_equipment"].exists)
        tapHome("hubEquipment_turbofan")
        XCTAssertTrue(app.buttons["assemblyNext"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["assemblyCounter"].label.contains("1/6"))
        app.buttons["assemblyClose"].tap()
        waitForDismissal(app.buttons["assemblyClose"])
        selectHomeFilter("All")
        XCTAssertTrue(origami.waitForExistence(timeout: 5))
        reveal(origami)
        XCTAssertTrue(origami.isHittable)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testOrigamiFilterShowsOnlyTheOrigamiEntryAndPhoneSetupReturnsToIt() {
        selectHomeFilter("Origami")
        XCTAssertTrue(app.buttons["hubOrigamiLesson_dart"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["hubOrigamiLesson_fox"].exists)
        XCTAssertFalse(app.buttons["hubOrigami"].exists, "The origami hero is replaced by the model grid")
        for id in ["hubCourse_towel", "hubCourse_t_shirt", "hubCourse_square_knot", "hubEquipment_gearmotor", "hubProductManual"] {
            XCTAssertFalse(app.buttons[id].exists, "Origami must exclude other tutorial categories: \(id)")
        }
        for id in ["catalogSection_clothes", "catalogSection_knots", "catalogSection_equipment"] {
            XCTAssertFalse(app.staticTexts[id].exists)
        }
        capture("Team_sections_Origami_filter")
        let setup = app.buttons["hubPhoneSetup"]; reveal(setup); setup.tap()
        XCTAssertTrue(app.buttons["closePhoneSetup"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists, "Phone setup must not start sensors")
        app.buttons["closePhoneSetup"].tap()
        waitForDismissal(app.buttons["closePhoneSetup"])
        XCTAssertTrue(app.segmentedControls["hubFilter"].buttons["Origami"].isSelected)
        let dart = app.buttons["hubOrigamiLesson_dart"]; reveal(dart); dart.tap()
        XCTAssertTrue(app.buttons["viewportOptions"].waitForExistence(timeout: 15))
    }

    func testAllFiveEverydayCoursesHaveCompleteConfirmedFlows() {
        capture("Protacta_course_hub")
        for (id, count) in [("t_shirt", 6), ("towel", 3), ("flat_bedsheet", 4), ("square_knot", 5), ("four_in_hand", 7)] {
            tapHome("hubCourse_\(id)")
            XCTAssertTrue(app.staticTexts["everydayCounter"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 1 OF \(count)")
            XCTAssertFalse(app.buttons["checkPracticeStep"].exists, "An illustrated course has no paper camera grader")
            capture("\(id)_start")
            for action in 1...count {
                XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION \(action) OF \(count)")
                let slider = app.sliders["everydayProgressSlider"]
                reveal(slider); slider.adjust(toNormalizedSliderPosition: 0.5)
                capture("\(id)_action\(action)_middle")
                XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION \(action) OF \(count)",
                               "Viewing a movement must not confirm the learner's physical action")
                slider.adjust(toNormalizedSliderPosition: 1)
                capture("\(id)_action\(action)_target")
                if action == count { capture("\(id)_final_visual") }
                tapPlayer("everydayConfirm")
            }
            XCTAssertTrue(app.staticTexts["everydayCompletion"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["everydayCompletion"].label.contains("confirmed by you"))
            app.buttons["everydayClose"].tap()
            XCTAssertTrue(app.buttons["hubOrigami"].waitForExistence(timeout: 5))
            tapHome("hubCourse_\(id)")
            XCTAssertTrue(app.staticTexts["everydayCompletion"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "everydayViewport").firstMatch.value as? String,
                           "Action \(count), movement 100 percent", "A restored completion must show the final visual")
            capture("\(id)_restored_complete")
            app.buttons["everydayClose"].tap()
        }
    }

    func testHelpReplayAndProgressSurviveReturnAndRelaunchIndependently() {
        tapHome("hubCourse_towel")
        tapPlayer("everydayConfirm")
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 2 OF 3")
        tapPlayer("everydayHelp")
        XCTAssertTrue(app.navigationBars["Help with this action"].waitForExistence(timeout: 5))
        let helpReplay = app.buttons["everydayHelpReplay"]
        reveal(helpReplay); helpReplay.tap()
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 2 OF 3")
        app.buttons["everydayClose"].tap()
        tapHome("hubCourse_t_shirt")
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 1 OF 6")
        app.buttons["everydayClose"].tap()
        app.terminate()
        app.launchArguments = ["--ui-testing", "--tutorial-hub"]
        app.launch()
        tapHome("hubCourse_towel")
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 2 OF 3")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 2 OF 3")
        tapPlayer("everydayPrevious")
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 1 OF 3")
    }

    func testOrigamiAndAerisAreReachableWithReleaseTabGate() {
        openOrigamiModel()
        XCTAssertTrue(app.buttons["viewportOptions"].waitForExistence(timeout: 15))
        app.buttons["returnTutorialHub"].tap()
        selectHomeFilter("All")
        tapHome("hubProductManual")
        let next = app.buttons["nextStep"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in next.exists && next.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        capture("Aeris_integrated_product_guide")
        reveal(next); next.tap()
        XCTAssertTrue(app.staticTexts["stepTitle"].label.contains("release tab"))
        XCTAssertFalse(next.isEnabled)
        let press = app.buttons["pressRelease"]
        reveal(press)
        let pressReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in press.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [pressReady], timeout: 5), .completed)
        press.tap()
        let released = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in next.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [released], timeout: 5), .completed)
        next.tap()
        XCTAssertTrue(app.staticTexts["stepTitle"].label.contains("rear cover"))
        let close = app.buttons["aerisClose"]; reveal(close); close.tap()
        XCTAssertTrue(app.buttons["hubOrigami"].waitForExistence(timeout: 5))
    }

    func testTieFrontBandFormsDuringItsActionAndRemainsForThreading() {
        capture("Protacta_hub_final_layout")
        tapHome("hubCourse_four_in_hand")
        tapPlayer("everydayConfirm"); tapPlayer("everydayConfirm")
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 3 OF 7")
        tapPlayer("everydayShowStart")
        capture("Tie_front_band_before")
        XCTAssertEqual(app.sliders["everydayProgressSlider"].value as? String, "0%")
        tapPlayer("everydayShowTarget")
        capture("Tie_front_band_target")
        XCTAssertEqual(app.sliders["everydayProgressSlider"].value as? String, "100%")
        tapPlayer("everydayConfirm")
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 4 OF 7")
        tapPlayer("everydayShowTarget")
        capture("Tie_neck_loop_after_band")
        for action in 5...7 {
            tapPlayer("everydayConfirm")
            XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION \(action) OF 7")
            let slider = app.sliders["everydayProgressSlider"]
            reveal(slider)
            slider.adjust(toNormalizedSliderPosition: 0.5)
            capture("Tie_action\(action)_middle")
            slider.adjust(toNormalizedSliderPosition: 1)
            capture("Tie_action\(action)_target")
        }
        tapPlayer("everydayConfirm")
        XCTAssertTrue(app.staticTexts["everydayCompletion"].waitForExistence(timeout: 5))
        capture("Tie_complete_threaded_reference")
    }

    func testTabletLandscapeCanPlayAndConfirmAnEverydayAction() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Tablet layout check") }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.app.frame.width > self.app.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        tapHome("hubCourse_t_shirt")
        let courseLandscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.app.frame.width > self.app.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [courseLandscape], timeout: 5), .completed)
        tapPlayer("everydayPlay")
        tapPlayer("everydaySpeed")
        XCTAssertEqual(app.buttons["everydaySpeed"].value as? String, "Slow")
        let confirm = app.buttons["everydayConfirm"]
        reveal(confirm)
        XCTAssertLessThanOrEqual(confirm.frame.maxX, app.frame.maxX)
        XCTAssertLessThanOrEqual(confirm.frame.maxY, app.frame.maxY)
        tapPlayer("everydayConfirm")
        XCTAssertEqual(app.staticTexts["everydayCounter"].label, "ACTION 2 OF 6")
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        // The iOS 26.5 Simulator can return a portrait raster even while its
        // accessibility window reports landscape. Record both; don't present
        // the raster as proof of physical-device landscape rendering.
        let screenShot = XCUIScreen.main.screenshot()
        let image = XCTAttachment(screenshot: screenShot)
        image.name = "Everyday_iPad_screen_capture"; image.lifetime = .keepAlways; add(image)
        let geometry = XCTAttachment(string: "App frame: \(app.frame); screenshot points: \(screenShot.image.size); image orientation: \(screenShot.image.imageOrientation.rawValue)")
        geometry.name = "Verified_iPad_geometry"; geometry.lifetime = .keepAlways; add(geometry)
        app.buttons["everydayClose"].tap()
    }

    private func tapHome(_ id: String) {
        let button = app.buttons[id]
        for _ in 0..<6 where !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
        for _ in 0..<6 where !button.isHittable { app.scrollViews.firstMatch.swipeDown() }
        XCTAssertTrue(button.isHittable, id); button.tap()
    }
    private func openOrigamiModel(_ id: String = "dart") {
        if !app.buttons["hubOrigamiLesson_\(id)"].exists { tapHome("hubOrigami") }
        let card = app.buttons["hubOrigamiLesson_\(id)"]
        reveal(card); card.tap()
    }
    private func selectHomeFilter(_ title: String) {
        let filter = app.segmentedControls["hubFilter"]
        reveal(filter)
        let segment = filter.buttons[title]
        XCTAssertTrue(segment.isHittable)
        segment.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: segment)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed,
                       "The category tap must reach the picker rather than an overlapping tutorial card")
        XCTAssertFalse(app.buttons["returnTutorialHub"].exists)
    }
    private func waitForDismissal(_ close: XCUIElement) {
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
    }
    private func tapPlayer(_ id: String) {
        if id == "everydayConfirm" && !app.buttons[id].label.contains("I've done it") {
            let slider = app.sliders["everydayProgressSlider"]
            if slider.exists { slider.adjust(toNormalizedSliderPosition: 1) }
        }
        if ["everydayShowStart", "everydayShowTarget", "everydayReplay", "everydaySpeed"].contains(id) {
            let more = app.buttons["everydayMore"]; reveal(more); more.tap()
        }
        let b = app.buttons[id]; reveal(b); b.tap()
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
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
