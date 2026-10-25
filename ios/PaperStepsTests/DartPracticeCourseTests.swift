import XCTest
@testable import Protacta

final class DartPracticeCourseTests: XCTestCase {
    func testCompleteCourseKeepsAllTenSourceActionsAndTheirWording() {
        XCTAssertEqual(DartPracticeCourse.actions.map(\.id), Array(1...10))
        XCTAssertEqual(DartPracticeCourse.actions.count, PaperLesson.steps.count - 1)
        for action in DartPracticeCourse.actions {
            let source = PaperLesson.steps[action.id]
            XCTAssertEqual(action.title, source.title)
            XCTAssertEqual(action.instruction, source.instruction)
            XCTAssertEqual(action.explanation, source.explanation)
            XCTAssertFalse(action.manualCheckpoint.isEmpty)
            XCTAssertFalse(action.commonMistake.isEmpty)
        }
    }

    func testOnlyDeclaredRestingStatesOfferPlanarCuesOrOutlineChecks() {
        let expected = Set([0, 2, 3, 4, 5, 6])
        for state in -2...12 {
            XCTAssertEqual(DartPracticeCourse.supportsOutlineCheck(state: state), expected.contains(state))
            XCTAssertEqual(DartPracticeCourse.supportsPlanarCue(beforeState: state), expected.contains(state))
        }
        XCTAssertFalse(DartPracticeCourse.supportsOutlineCheck(state: Int.min))
        XCTAssertFalse(DartPracticeCourse.supportsPlanarCue(beforeState: Int.max))
    }

    func testPreparationAndReopenedOutlineDoNotClaimToVerifyTheCrease() {
        XCTAssertTrue(DartPracticeCourse.requiresRealPaperReview)
        XCTAssertTrue(DartPracticeCourse.reviewNotice.contains("real-paper review"))
        XCTAssertTrue(DartPracticeCourse.creaseAmbiguityNote.contains("cannot show"))
        XCTAssertTrue(DartPracticeCourse.creaseAmbiguityNote.contains("center crease"))
        XCTAssertTrue(DartPracticeCourse.action(2).manualCheckpoint.contains("cannot verify"))
    }

    func testLaterActionsRetainManualHelpAndNoPlanarSupport() {
        for action in 7...10 {
            XCTAssertFalse(DartPracticeCourse.supportsOutlineCheck(state: action))
            XCTAssertFalse(DartPracticeCourse.supportsPlanarCue(beforeState: action))
            XCTAssertFalse(DartPracticeCourse.action(action).manualCheckpoint.isEmpty)
            XCTAssertFalse(DartPracticeCourse.action(action).commonMistake.isEmpty)
        }
        XCTAssertTrue(DartPracticeCourse.action(7).manualCheckpoint.contains("underneath"))
        XCTAssertTrue(DartPracticeCourse.action(10).manualCheckpoint.contains("not a camera-verified"))
    }

    func testLookupBoundsAreSafeAndRevisionIsAContentFingerprint() {
        XCTAssertEqual(DartPracticeCourse.action(Int.min).id, 1)
        XCTAssertEqual(DartPracticeCourse.action(Int.max).id, 10)
        XCTAssertEqual(DartPracticeCourse.action(5).id, 5)
        XCTAssertEqual(DartPracticeCourse.revision.count, 64)
    }
}
