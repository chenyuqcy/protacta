import XCTest
@testable import Protacta

/// Controller-boundary tests use the entitlement update API directly. StoreKit
/// verification and transaction events are covered separately by PurchaseStoreTests.
/// These tests do not create an ARView, run a camera session, or make a purchase.
final class LibraryAccessTests: XCTestCase {
    @MainActor
    func testLockedPremiumCannotBeginJumpToAStepOrEnterAR() {
        for lesson in OrigamiLesson.allCases.filter({ !$0.isFree }) {
            let controller = LessonController()
            controller.selectLesson(lesson)
            controller.updateLibraryAccess(false)
            XCTAssertFalse(controller.hasLessonAccess, lesson.rawValue)
            XCTAssertFalse(controller.canAnimate, lesson.rawValue)

            controller.begin()
            assertPreviewIsLocked(controller, lesson: lesson)
            controller.goToStep(1)
            assertPreviewIsLocked(controller, lesson: lesson)
            controller.enterAR()
            assertPreviewIsLocked(controller, lesson: lesson)
            controller.next()
            assertPreviewIsLocked(controller, lesson: lesson)
            XCTAssertNil(controller.arView, "Locked entry must not create a camera renderer")
        }
    }

    @MainActor
    func testBothFreeLessonsCanBeginNavigateAndRequestARWithoutAnEntitlement() {
        for lesson in [OrigamiLesson.dart, .fox] {
            let controller = LessonController()
            controller.selectLesson(lesson)
            controller.updateLibraryAccess(false)
            XCTAssertTrue(controller.hasLessonAccess, lesson.rawValue)
            XCTAssertTrue(controller.canAnimate, lesson.rawValue)
            controller.begin()
            XCTAssertTrue(controller.started)
            controller.goToStep(1)
            XCTAssertEqual(controller.stepIndex, 1)
            XCTAssertTrue(controller.isPlaying)
            controller.scrub(to: 0.4)
            XCTAssertEqual(controller.progress, 0.4, accuracy: 0.0001)
            XCTAssertFalse(controller.isPlaying)

            // This proves the access gate admits AR. No ARView is made, so it
            // makes no claim about camera permission, placement or tracking.
            controller.enterAR()
            XCTAssertTrue(controller.isAR)
            XCTAssertTrue(controller.started)
            XCTAssertEqual(controller.stepIndex, 1)
            controller.leaveAR()
            XCTAssertFalse(controller.isAR)
            XCTAssertEqual(controller.stepIndex, 1)
        }
    }

    @MainActor
    func testRevocationStopsAnAnimatingPremiumLessonAndRestoresItsLockedPreview() {
        let controller = LessonController()
        controller.updateLibraryAccess(true)
        controller.selectLesson(.crane)
        controller.begin()
        controller.goToStep(3)
        XCTAssertTrue(controller.started)
        XCTAssertTrue(controller.isPlaying)
        XCTAssertEqual(controller.stepIndex, 3)

        controller.updateLibraryAccess(false)
        assertPreviewIsLocked(controller, lesson: .crane)
        controller.begin()
        controller.goToStep(3)
        controller.enterAR()
        assertPreviewIsLocked(controller, lesson: .crane)
    }

    @MainActor
    func testRevocationLeavesPremiumARAndClearsPlacementState() {
        let controller = LessonController()
        controller.updateLibraryAccess(true)
        controller.selectLesson(.rabbit)
        controller.begin()
        controller.goToStep(5)
        controller.enterAR()
        XCTAssertTrue(controller.isAR)
        // Inject only controller state, without pretending a simulated camera
        // frame is physical AR placement evidence.
        controller.placed = true
        controller.trackingReady = true
        controller.canPlace = true
        XCTAssertTrue(controller.canAnimate)

        controller.updateLibraryAccess(false)
        assertPreviewIsLocked(controller, lesson: .rabbit)
        XCTAssertFalse(controller.placed)
        XCTAssertFalse(controller.trackingReady)
        XCTAssertFalse(controller.canPlace)
        XCTAssertFalse(controller.needsRescan)
    }

    @MainActor
    func testRevocationKeepsProgressInAFreeLesson() {
        let controller = LessonController()
        controller.updateLibraryAccess(true)
        controller.selectLesson(.fox)
        controller.begin()
        controller.goToStep(3)
        controller.scrub(to: 0.4)
        controller.updateLibraryAccess(false)

        XCTAssertTrue(controller.hasLessonAccess)
        XCTAssertTrue(controller.canAnimate)
        XCTAssertTrue(controller.started)
        XCTAssertEqual(controller.stepIndex, 3)
        XCTAssertEqual(controller.progress, 0.4, accuracy: 0.0001)
        XCTAssertFalse(controller.completed)
    }

    @MainActor
    private func assertPreviewIsLocked(_ controller: LessonController, lesson: OrigamiLesson,
                                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(controller.lesson, lesson, file: file, line: line)
        XCTAssertFalse(controller.hasLessonAccess, file: file, line: line)
        XCTAssertFalse(controller.canAnimate, file: file, line: line)
        XCTAssertFalse(controller.started, file: file, line: line)
        XCTAssertFalse(controller.isPlaying, file: file, line: line)
        XCTAssertFalse(controller.completed, file: file, line: line)
        XCTAssertFalse(controller.isAR, file: file, line: line)
        XCTAssertEqual(controller.stepIndex, 0, file: file, line: line)
        XCTAssertEqual(controller.progress, 1, file: file, line: line)
    }
}
