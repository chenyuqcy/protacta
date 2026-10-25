import XCTest
import StoreKitTest
import UIKit

/// Candidate/proof screenshots only. Run this class serially, with Release
/// configuration, on a large portrait iPhone simulator. The local StoreKit
/// fixture is shared with other billing tests, so this class needs that lane.
/// Captures are original full-screen pixels: no image edits or UI injection.
/// A fixture price is not an approved App Store price; studio views are not AR.
final class ReleaseScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!
    private var storeSession: SKTestSession!
    private let productID = "org.realitycore.foliafold.complete"
    private var fixturePrice = ""
    private var captureRecords = [[String: Any]]()
    private var acceptedFixturePurchase = false

    // This is the identifier order in OrigamiLesson.allCases, not an AX child
    // index. It lets an already-scrolled library move toward the requested row.
    private let lessonOrder = ["crane", "star", "frog", "turtle", "fullRabbit", "sittingDog",
                               "fullFox", "elephant", "butterfly", "dart", "fox", "rabbit"]

    override func setUp() async throws {
        continueAfterFailure = false
        #if DEBUG
        throw XCTSkip("Screenshot proof requires -configuration Release.")
        #endif
        #if !targetEnvironment(simulator)
        throw XCTSkip("This fixture screenshot suite is for an iPhone simulator only.")
        #endif
        await MainActor.run { XCUIDevice.shared.orientation = .portrait }
        let pixels = try XCTUnwrap(XCUIScreen.main.screenshot().image.cgImage)
        XCTAssertGreaterThan(pixels.height, pixels.width, "Use portrait orientation")
        XCTAssertGreaterThanOrEqual(pixels.width, 1242, "Use a large portrait iPhone simulator")

        storeSession = try SKTestSession(configurationFileNamed: "FoliafoldTesting")
        storeSession.resetToDefaultState()
        storeSession.clearTransactions()
        storeSession.disableDialogs = true
        captureRecords = []
        acceptedFixturePurchase = false

        // Read the same controlled expectation as LibraryPurchaseUITests. The
        // app still loads Product.displayPrice and purchases through StoreKit.
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "FoliafoldTesting", withExtension: "storekit"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let settings = try XCTUnwrap(fixture["settings"] as? [String: Any])
        XCTAssertEqual(settings["_storefront"] as? String, "USA")
        let products = try XCTUnwrap(fixture["products"] as? [[String: Any]])
        let product = try XCTUnwrap(products.first { $0["productID"] as? String == productID })
        let amount = try XCTUnwrap(product["displayPrice"] as? String)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: settings["_locale"] as? String ?? "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        fixturePrice = try XCTUnwrap(formatter.string(from: NSDecimalNumber(string: amount)))

        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertLessThan(app.frame.width, 700, "Use iPhone, not iPad, for this screenshot set")
        XCTAssertTrue(app.buttons["startLesson"].waitForExistence(timeout: 15))
        let locked = NSPredicate(format: "exists == true AND label CONTAINS %@", "Unlock this lesson")
        await fulfillment(of: [expectation(for: locked, evaluatedWith: app.buttons["startLesson"])], timeout: 15)
        XCTAssertTrue(storeSession.allTransactions().isEmpty)
    }

    override func tearDownWithError() throws {
        defer {
            app?.terminate()
            storeSession?.clearTransactions()
            storeSession?.resetToDefaultState()
            app = nil
            storeSession = nil
        }
        // Preserve partial evidence too, if a later visual/control assertion
        // fails. Every raw image is named and described as candidate proof.
        if !captureRecords.isEmpty {
            let manifest: [String: Any] = [
                "status": "CANDIDATE_PROOF_NOT_APPROVED_FOR_SUBMISSION",
                "configuration": "Release",
                "captureMethod": "XCUIScreen.main.screenshot; original full native pixels",
                "environment": "iPhone simulator; 3D studio; no physical camera AR evidence",
                "billing": "FoliafoldTesting local StoreKit fixture; displayed fixture price is not approved production pricing",
                "purchaseProductID": productID,
                "appAcceptedLocalStoreKitPurchase": acceptedFixturePurchase,
                "simulatorModel": ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unreported",
                "images": captureRecords
            ]
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "CandidateProof_CAPTURE_METADATA_NOT_APPROVED.json"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testCaptureReleaseCandidateProofSet() {
        XCTAssertTrue(app.staticTexts["The Paper Crane"].exists)
        capture("01_Crane_Welcome_LOCKED", lesson: "crane")

        openLibrary()
        revealLibraryRow("crane")
        XCTAssertTrue(app.buttons["library_star"].exists)
        capture("02_Library_Top_PREMIUM_LOCKED")
        revealLibraryRow("fullFox")
        capture("03_Library_Middle_PREMIUM_LOCKED")
        revealLibraryRow("rabbit")
        XCTAssertTrue(app.buttons["library_dart"].isHittable)
        XCTAssertTrue(app.buttons["library_fox"].isHittable)
        capture("04_Library_Bottom_FREE_AND_PREMIUM")
        app.buttons["closeLibrary"].tap()
        absent(app.buttons["closeLibrary"])

        app.buttons["startLesson"].tap()
        let purchase = app.buttons["purchaseLibrary"]
        ready(purchase, timeout: 20)
        let lifetime = app.buttons["purchasePlan_lifetime"]
        ready(lifetime)
        revealSheetControl(lifetime)
        lifetime.tap()
        XCTAssertTrue(app.buttons["closeUnlock"].exists)
        XCTAssertTrue(purchase.label.contains(fixturePrice), "Use the actual app StoreKit product price")
        revealSheetControl(app.staticTexts["Small folds.\nMore possibilities."], towardsTop: true)
        capture("05_Paywall_Top_LOCAL_FIXTURE_PRICE_NOT_APPROVED", fixturePriceView: true)
        revealSheetControl(purchase)
        capture("06_Paywall_Purchase_LOCAL_FIXTURE_PRICE_NOT_APPROVED", fixturePriceView: true)
        XCTAssertTrue(storeSession.allTransactions().isEmpty, "Screenshots before purchase must remain locked")
        purchase.tap() // Production UI -> PurchaseStore -> local verified StoreKit.
        waitLabel(app.buttons["startLesson"], contains: "Start folding", timeout: 20)
        absent(app.buttons["closeUnlock"])
        XCTAssertTrue(storeSession.allTransactions().contains { $0.productIdentifier == productID },
                      "A real local StoreKit transaction must back the app unlock")
        acceptedFixturePurchase = true
        capture("07_Crane_Welcome_LOCAL_PURCHASE_ACCEPTED", lesson: "crane")

        beginCurrentLesson()
        jump(to: 9, total: 28)
        XCTAssertEqual(app.staticTexts["stepTitle"].label, "Lift the first petal")
        midpoint()
        capture("08_Crane_Petal_09_MIDPOINT", lesson: "crane", step: 9, progress: 0.5)

        for target in [("star", 13), ("frog", 22), ("fullRabbit", 25),
                       ("sittingDog", 28), ("fullFox", 24), ("elephant", 40)] {
            selectLesson(target.0)
            beginCurrentLesson()
            jump(to: target.1, total: target.1)
            app.buttons["angleView"].tap()
            capture("09_\(target.0)_FINAL_\(target.1)", lesson: target.0, step: target.1, progress: 1)
        }

        jump(to: 33, total: 40)
        midpoint()
        capture("10_Elephant_33_MIDPOINT", lesson: "elephant", step: 33, progress: 0.5)
        let title = app.staticTexts["stepTitle"].label
        app.buttons["foldNotes"].tap()
        XCTAssertTrue(app.buttons["closeNotes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[title].exists)
        XCTAssertTrue(app.staticTexts["Written fold notes"].exists)
        capture("11_Elephant_33_WHY_WRITTEN_NOTES", lesson: "elephant", step: 33, progress: 0.5)
        app.buttons["closeNotes"].tap()
        absent(app.buttons["closeNotes"])
    }

    private func openLibrary() {
        ready(app.buttons["chooseLesson"])
        app.buttons["chooseLesson"].tap()
        XCTAssertTrue(app.buttons["closeLibrary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews["lessonLibraryScroll"].exists)
    }

    private func revealLibraryRow(_ id: String) {
        let target = app.buttons["library_\(id)"]
        let scroll = app.scrollViews["lessonLibraryScroll"]
        guard let targetIndex = lessonOrder.firstIndex(of: id) else { XCTFail("Unknown lesson ID \(id)"); return }
        for _ in 0..<9 {
            if target.isHittable { return }
            let visible = lessonOrder.indices.filter { app.buttons["library_\(lessonOrder[$0])"].isHittable }
            if let first = visible.min(), targetIndex < first { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(target.isHittable, "Could not reveal \(id)")
    }

    private func selectLesson(_ id: String) {
        openLibrary()
        revealLibraryRow(id)
        app.buttons["library_\(id)"].tap()
        absent(app.buttons["closeLibrary"])
        waitLabel(app.buttons["startLesson"], contains: "Start folding")
    }

    private func beginCurrentLesson() {
        ready(app.buttons["startLesson"])
        XCTAssertTrue(app.buttons["startLesson"].label.contains("Start folding"))
        app.buttons["startLesson"].tap()
        waitLabel(app.staticTexts["stepCounter"], equals: "BEFORE YOU BEGIN")
    }

    private func jump(to step: Int, total: Int) {
        ready(app.buttons["stepList"])
        app.buttons["stepList"].tap()
        XCTAssertTrue(app.buttons["closeSteps"].waitForExistence(timeout: 5))
        let target = app.buttons["jumpStep_\(step)"]
        for _ in 0..<12 {
            if target.isHittable { break }
            let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "jumpStep_")).allElementsBoundByIndex
            let visibleSteps = rows.filter(\.isHittable).compactMap { Int($0.identifier.dropFirst("jumpStep_".count)) }
            if let first = visibleSteps.min(), step < first { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(target.isHittable, "Step \(step) must be visible before tapping")
        target.tap()
        // The sheet's onDismiss callback changes the lesson state. Waiting only
        // for Next would accept the previous step before that callback arrives.
        absent(app.buttons["closeSteps"])
        waitLabel(app.staticTexts["stepCounter"], equals: "STEP \(step) OF \(total)", timeout: 12)
        ready(app.buttons["nextStep"], timeout: 20)
        XCTAssertFalse(app.staticTexts["stepInstruction"].label.isEmpty)
    }

    private func midpoint() {
        app.buttons["angleView"].tap()
        let slider = app.sliders["foldProgress"]
        XCTAssertTrue(slider.isHittable)
        slider.adjust(toNormalizedSliderPosition: 0.5)
        waitLabel(app.buttons["nextStep"], contains: "Finish this fold")
    }

    private func revealSheetControl(_ target: XCUIElement, towardsTop: Bool = false) {
        // Choose the sheet that contains the actual button, rather than the
        // underlying horizontal lesson picker left in the accessibility tree.
        let key = target.identifier.isEmpty ? target.label : target.identifier
        let scroll = app.scrollViews.containing(.any, identifier: key).firstMatch
        for _ in 0..<4 {
            if target.isHittable { break }
            XCTAssertTrue(scroll.exists)
            if towardsTop { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(target.isHittable)
    }

    private func ready(_ element: XCUIElement, timeout: TimeInterval = 12) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }
    private func absent(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }
    private func waitLabel(_ element: XCUIElement, contains text: String, timeout: TimeInterval = 12) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }
    private func waitLabel(_ element: XCUIElement, equals text: String, timeout: TimeInterval = 12) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func capture(_ name: String, lesson: String = "", step: Int? = nil,
                         progress: Double? = nil, fixturePriceView: Bool = false) {
        Thread.sleep(forTimeInterval: 0.35) // Let the completed native frame settle.
        let screenshot = XCUIScreen.main.screenshot()
        guard let pixels = screenshot.image.cgImage else { XCTFail("Missing native screenshot pixels"); return }
        XCTAssertGreaterThan(pixels.height, pixels.width)
        let attachmentName = "CandidateProof_\(name)"
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = attachmentName
        attachment.lifetime = .keepAlways
        add(attachment)
        var record: [String: Any] = [
            "name": attachmentName,
            "status": "CANDIDATE_PROOF_NOT_APPROVED",
            "pixelWidth": pixels.width, "pixelHeight": pixels.height,
            "lesson": lesson, "physicalAR": false, "imageModified": false,
            "localStoreKitPurchaseAccepted": acceptedFixturePurchase,
            "isLocalFixturePaywallView": fixturePriceView,
            "priceApprovedForProduction": false
        ]
        if let step { record["step"] = step }
        if let progress { record["requestedSliderProgress"] = progress }
        if fixturePriceView {
            record["actualFixturePurchaseButton"] = app.buttons["purchaseLibrary"].label
            record["fixturePurchaseButtonIsHittable"] = app.buttons["purchaseLibrary"].isHittable
        }
        captureRecords.append(record)
    }
}
