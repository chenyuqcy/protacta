import XCTest
import StoreKit
import StoreKitTest

/// All purchases in this file belong to the local StoreKit configuration.
/// Run serially with the other StoreKit tests: the test session is shared.
final class AnimalLessonUITests: XCTestCase {
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
        app?.terminate(); app = nil
        storeSession?.clearTransactions(); storeSession?.resetToDefaultState(); storeSession = nil
    }

    func testFoxAllSixFoldsFromDiamondToFace() {
        begin("fox", title: "Begin with a diamond")
        capture("Fox_00_White_diamond")
        for step in 1...6 {
            next()
            XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP \(step) OF 6")
            capture(String(format: "Fox_%02d_Complete", step))
        }
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Reveal your fox")
        finish("Fox")
    }

    func testRabbitAllNineFoldsAndSeparateEarLayers() {
        begin("rabbit", title: "Prepare a square")
        capture("Rabbit_00_White_diamond")
        for step in 1...9 {
            next()
            XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP \(step) OF 9")
            capture(String(format: "Rabbit_%02d_Complete", step))
            if step == 8 {
                app.sliders["foldProgress"].adjust(toNormalizedSliderPosition: 0.45)
                capture("Rabbit_08_Forehead_between_ears_midfold")
                app.buttons["nextStep"].tap()
                enabled(app.buttons["nextStep"])
                XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP 8 OF 9")
            }
        }
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Round the chin")
        finish("Rabbit")
    }

    func testButterflyAllEighteenFoldsWithPocketMidpoints() {
        begin("butterfly", title: "Prepare your square")
        capture("Butterfly_00_White_square")
        for step in 1...18 {
            next()
            XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP \(step) OF 18")
            capture(String(format: "Butterfly_%02d_Complete", step))
            if [8, 9, 17].contains(step) {
                app.sliders["foldProgress"].adjust(toNormalizedSliderPosition: 0.45)
                XCTAssertTrue(app.buttons["nextStep"].label.contains("Finish this fold"))
                capture(String(format: "Butterfly_%02d_Midfold_angle", step))
                app.buttons["topView"].tap()
                capture(String(format: "Butterfly_%02d_Midfold_top", step))
                app.buttons["angleView"].tap()
                app.buttons["nextStep"].tap()
                enabled(app.buttons["nextStep"])
                XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP \(step) OF 18")
            }
        }
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Open the other wing pair")
        finish("Butterfly")
    }

    func testLibraryPresentsAllAvailableLessons() {
        let lessons = [("crane", "The Paper Crane"), ("star", "The Lucky Star"),
                       ("dart", "The Classic Dart"), ("fox", "The Little Fox"),
                       ("rabbit", "The Paper Rabbit"), ("butterfly", "The Paper Butterfly"),
                       ("frog", "The Jumping Frog"), ("turtle", "The Paper Turtle"), ("fullRabbit", "The Standing Rabbit"), ("sittingDog", "The Sitting Dog"), ("fullFox", "The Long-Tail Fox"), ("elephant", "The Paper Elephant")]
        capture("Library_Twelve_lesson_intro_choices")
        begin("fox", title: "Begin with a diamond")
        app.buttons["chooseLesson"].tap()
        XCTAssertTrue(app.buttons["library_crane"].waitForExistence(timeout: 5))
        for (id, title) in lessons {
            let row = app.buttons["library_\(id)"]
            XCTAssertTrue(row.exists, title)
            XCTAssertTrue(row.label.contains(title), title)
            XCTAssertTrue(row.label.contains(["fox", "dart"].contains(id) ? "FREE LESSON" : "UNLOCKED"), title)
        }
        capture("Library_Twelve_lessons_upper")
        let butterfly = app.buttons["library_butterfly"]
        reveal(butterfly)
        capture("Library_Twelve_lessons_lower")
        butterfly.tap()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["startLesson"].label.contains("Start folding"))
        XCTAssertTrue(app.buttons["lesson_butterfly"].isSelected)
    }

    private func begin(_ id: String, title: String, file: StaticString = #filePath, line: UInt = #line) {
        if app.buttons["lesson_\(id)"].isHittable {
            app.buttons["lesson_\(id)"].tap()
        } else {
            app.buttons["chooseLesson"].tap()
            let row = app.buttons["library_\(id)"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            reveal(row)
            row.tap()
        }
        enabled(app.buttons["startLesson"], file: file, line: line)
        app.buttons["startLesson"].tap()
        XCTAssertTrue(app.staticTexts["stepTitle"].waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(app.staticTexts["stepTitle"].label, title, file: file, line: line)
    }

    private func finish(_ name: String) {
        app.buttons["topView"].tap()
        capture("\(name)_Finished_top")
        app.buttons["angleView"].tap()
        capture("\(name)_Finished_angle")
        next()
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "LESSON COMPLETE")
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Made by you.")
        capture("\(name)_Lesson_complete")
    }

    private func next(file: StaticString = #filePath, line: UInt = #line) {
        enabled(app.buttons["nextStep"], file: file, line: line)
        app.buttons["nextStep"].tap()
        enabled(app.buttons["nextStep"], file: file, line: line)
    }

    private func enabled(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, file: file, line: line)
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<5 {
            if element.isHittable { return }
            app.scrollViews["lessonLibraryScroll"].swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}

/// This class starts without an entitlement and buys only by pressing the
/// production paywall button, inside SKTestSession's local environment.
final class LibraryPurchaseUITests: XCTestCase {
    private var app: XCUIApplication!
    private var storeSession: SKTestSession!
    private var expectedPrice: String!
    private var expectedPlanPrices = [String: String]()
    private let productID = "org.realitycore.protacta.prototype.complete"

    override func setUp() async throws {
        continueAfterFailure = false
        storeSession = try SKTestSession(configurationFileNamed: "ProtactaTesting")
        storeSession.resetToDefaultState()
        storeSession.clearTransactions()
        storeSession.disableDialogs = true
        // Product.products queried from the UI runner has the runner's bundle
        // identity, not the app's StoreKit catalog. Read the controlled fixture
        // expectation here; the app must still fetch and purchase via StoreKit.
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ProtactaTesting", withExtension: "storekit"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
        let settings = try XCTUnwrap(fixture["settings"] as? [String: Any])
        XCTAssertEqual(settings["_storefront"] as? String, "USA")
        let products = try XCTUnwrap(fixture["products"] as? [[String: Any]])
        let groups = try XCTUnwrap(fixture["subscriptionGroups"] as? [[String: Any]])
        let subscriptions = groups.flatMap { $0["subscriptions"] as? [[String: Any]] ?? [] }
        let entries = products + subscriptions
        let entry = try XCTUnwrap(entries.first { $0["productID"] as? String == productID })
        let amount = try XCTUnwrap(entry["displayPrice"] as? String)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: settings["_locale"] as? String ?? "en_US")
        formatter.numberStyle = .currency; formatter.currencyCode = "USD"
        expectedPrice = try XCTUnwrap(formatter.string(from: NSDecimalNumber(string: amount)))
        for entry in entries {
            let id = try XCTUnwrap(entry["productID"] as? String)
            let price = try XCTUnwrap(entry["displayPrice"] as? String)
            expectedPlanPrices[id] = try XCTUnwrap(formatter.string(from: NSDecimalNumber(string: price)))
        }
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 15))
        let locked = NSPredicate(format: "label CONTAINS %@", "Unlock this lesson")
        await fulfillment(of: [expectation(for: locked, evaluatedWith: app.buttons["startLesson"])], timeout: 10)
    }

    override func tearDownWithError() throws {
        app?.terminate(); app = nil
        expectedPrice = nil
        expectedPlanPrices = [:]
        storeSession?.clearTransactions(); storeSession?.resetToDefaultState(); storeSession = nil
    }

    func testLockedPremiumCannotStartOrEnterARAndFreeLessonsRemainAvailable() {
        app.buttons["startLesson"].tap()
        assertPaywall()
        XCTAssertFalse(app.buttons["nextStep"].exists)
        XCTAssertFalse(app.buttons["stepList"].exists)
        XCTAssertFalse(app.buttons["closeAR"].exists)
        capture("Access_Locked_crane_start_paywall")
        closePaywall()

        app.buttons["openAR"].tap()
        assertPaywall()
        XCTAssertFalse(app.buttons["closeAR"].exists, "A locked lesson must not enter AR behind the paywall")
        XCTAssertFalse(app.buttons["placePaper"].exists)
        XCTAssertFalse(app.buttons["returnTo3D"].exists)
        closePaywall()

        app.buttons["chooseLesson"].tap()
        let fox = app.buttons["library_fox"]
        XCTAssertTrue(fox.waitForExistence(timeout: 5))
        for _ in 0..<5 {
            if fox.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(fox.isHittable)
        fox.tap()
        XCTAssertTrue(app.buttons["startLesson"].label.contains("Start folding"))
        app.buttons["startLesson"].tap()
        XCTAssertTrue(app.staticTexts["stepTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Begin with a diamond")
        XCTAssertFalse(app.buttons["purchaseLibrary"].exists)
        next()
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP 1 OF 6")
        capture("Access_Free_fox_without_purchase")

        app.buttons["chooseLesson"].tap()
        let dart = app.buttons["library_dart"]
        XCTAssertTrue(dart.waitForExistence(timeout: 5))
        for _ in 0..<4 {
            if dart.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(dart.isHittable)
        dart.tap()
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["startLesson"].label.contains("Start folding"))
        app.buttons["startLesson"].tap()
        XCTAssertTrue(app.staticTexts["stepTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Start with a blank sheet")
        next()
        XCTAssertEqual(app.staticTexts["stepCounter"].label, "STEP 1 OF 10")
        capture("Access_Free_dart_without_purchase")
        XCTAssertTrue(storeSession.allTransactions().isEmpty, "Neither free lesson may create a transaction")
    }

    func testDisplayedStoreKitPriceRestoreAndPaywallPurchaseUnlocks() {
        app.buttons["startLesson"].tap()
        assertPaywall()
        selectPlan("lifetime")
        let purchase = app.buttons["purchaseLibrary"]
        XCTAssertTrue(purchase.label.contains(expectedPrice), "The paywall must show the localized price returned by the app's StoreKit catalog")
        XCTAssertTrue(app.buttons["restorePurchases"].exists)
        XCTAssertTrue(app.buttons["restorePurchases"].label.contains("Restore Purchases"))
        capture("Access_Local_StoreKit_price_and_restore")
        revealPaywall(purchase)
        purchase.tap()

        let unlocked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", "Start folding"), object: app.buttons["startLesson"])
        XCTAssertEqual(XCTWaiter.wait(for: [unlocked], timeout: 15), .completed)
        absent(app.buttons["closeUnlock"])
        XCTAssertTrue(storeSession.allTransactions().contains { $0.productIdentifier == productID }, "The unlock must have a real local StoreKit transaction")
        capture("Access_Verified_purchase_unlocks_crane")
        app.buttons["startLesson"].tap()
        XCTAssertTrue(app.staticTexts["stepTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Begin with a square")
        XCTAssertTrue(app.buttons["nextStep"].exists)
        XCTAssertFalse(app.buttons["purchaseLibrary"].exists)
    }

    func testMonthlyAndAnnualChoicesShowTheirTermsAndMonthlyPurchaseUnlocks() {
        app.buttons["startLesson"].tap()
        assertPaywall()
        for (plan, term) in [("monthly", "/month"), ("annual", "/year")] {
            selectPlan(plan)
            let id = "org.realitycore.protacta.prototype.\(plan)"
            let price = expectedPlanPrices[id]!
            let choice = app.buttons["purchasePlan_\(plan)"]
            XCTAssertTrue(choice.label.contains(price))
            XCTAssertTrue(choice.label.contains("Auto-renewing subscription"))
            let purchase = app.buttons["purchaseLibrary"]
            XCTAssertTrue(purchase.label.contains("Subscribe"))
            XCTAssertTrue(purchase.label.contains(price + term))
            revealPaywall(purchase)
            capture("Subscriptions_\(plan)_LOCAL_STOREKIT_TEST_PRICE")
        }
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "purchaseTerms").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "purchasePrivacy").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "manageSubscriptions").firstMatch.exists)
        XCTAssertTrue(storeSession.allTransactions().isEmpty, "Choosing a term must not create a charge")

        selectPlan("monthly")
        let purchase = app.buttons["purchaseLibrary"]
        revealPaywall(purchase)
        purchase.tap()
        let unlocked = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", "Start folding"),
            object: app.buttons["startLesson"])
        XCTAssertEqual(XCTWaiter.wait(for: [unlocked], timeout: 15), .completed)
        absent(app.buttons["closeUnlock"])
        XCTAssertTrue(storeSession.allTransactions().contains {
            $0.productIdentifier == "org.realitycore.protacta.prototype.monthly"
        }, "The selected monthly plan must be the product purchased through the real paywall")
        capture("Subscriptions_Monthly_LOCAL_PURCHASE_UNLOCKED")
    }

    private func selectPlan(_ plan: String) {
        let choice = app.buttons["purchasePlan_\(plan)"]
        XCTAssertTrue(choice.waitForExistence(timeout: 10))
        revealPaywall(choice)
        XCTAssertTrue(choice.isEnabled)
        choice.tap()
    }

    private func revealPaywall(_ target: XCUIElement) {
        let scroll = app.scrollViews.containing(.any, identifier: target.identifier).firstMatch
        XCTAssertTrue(scroll.exists)
        for _ in 0..<6 {
            if target.isHittable { break }
            if target.frame.midY < scroll.frame.midY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(target.isHittable)
    }

    private func assertPaywall() {
        XCTAssertTrue(app.buttons["purchaseLibrary"].waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["purchaseLibrary"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        XCTAssertTrue(app.buttons["closeUnlock"].exists)
        XCTAssertFalse(app.buttons["purchaseLibrary"].label.contains("Please wait"))
    }

    private func closePaywall() {
        app.buttons["closeUnlock"].tap()
        absent(app.buttons["closeUnlock"])
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 5))
    }

    private func absent(_ element: XCUIElement) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    }

    private func next() {
        let button = app.buttons["nextStep"]
        let ready = { XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: button) }
        XCTAssertEqual(XCTWaiter.wait(for: [ready()], timeout: 15), .completed)
        button.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [ready()], timeout: 15), .completed)
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
