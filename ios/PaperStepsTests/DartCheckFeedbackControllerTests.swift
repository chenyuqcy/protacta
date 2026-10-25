import XCTest
@testable import Protacta

final class DartCheckFeedbackControllerTests: XCTestCase {
    @MainActor
    func testNewCheckRemovesOldImageAndLiveTextButKeepsHistoricalSummary() throws {
        let controller = makeController()
        try seedComparison(controller)
        let oldID = controller.practiceCheckSnapshot?.id
        XCTAssertNotNil(oldID)
        controller.checkPracticeAction()
        XCTAssertNil(controller.practiceCheckSnapshot)
        XCTAssertNil(controller.dartPractice.lastCheck)
        XCTAssertEqual(controller.dartPractice.checkSummaries.count, 1)
        XCTAssertTrue(controller.practiceCheckBusy)
        XCTAssertEqual(controller.dartPractice.currentAction, 3)
    }

    @MainActor
    func testRescanCameraFailureBackgroundExitAndTrackingLossClearComparison() throws {
        let transitions: [(String, (LessonController) -> Void)] = [
            ("rescan", { $0.restartPaperGuideTracking() }),
            ("camera failure", { $0.handleCameraFailure("Synthetic interruption") }),
            ("background", { $0.background() }),
            ("exit", { $0.leaveAR() }),
            ("tracking loss", { $0.handleDartPracticeTrackingLoss() })
        ]
        for (name, transition) in transitions {
            let controller = makeController()
            try seedComparison(controller)
            transition(controller)
            XCTAssertNil(controller.practiceCheckSnapshot, name)
            XCTAssertNil(controller.dartPractice.lastCheck, name)
            XCTAssertEqual(controller.dartPractice.checkSummaries.count, 1, name)
        }
    }

    @MainActor
    func testChangingActionOrRestartingDropsTheOldComparison() throws {
        let next = makeController(); try seedComparison(next)
        next.confirmPracticeAction()
        XCTAssertEqual(next.dartPractice.currentAction, 4)
        XCTAssertNil(next.practiceCheckSnapshot)
        XCTAssertNil(next.dartPractice.lastCheck)
        let previous = makeController(); try seedComparison(previous)
        previous.previousPracticeAction()
        XCTAssertEqual(previous.dartPractice.currentAction, 2)
        XCTAssertNil(previous.practiceCheckSnapshot)
        let restarted = makeController(); try seedComparison(restarted)
        restarted.restartDartPractice()
        XCTAssertEqual(restarted.dartPractice.currentAction, 1)
        XCTAssertNil(restarted.practiceCheckSnapshot)
        XCTAssertTrue(restarted.dartPractice.checkSummaries.isEmpty)
    }

    @MainActor
    func testTemporaryOcclusionKeepsTheExplicitlyFrozenComparison() throws {
        let controller = makeController()
        let timestamp = try seedComparison(controller)
        let imageID = try XCTUnwrap(controller.practiceCheckSnapshot?.id)
        let accepted = controller.receiveDartPracticeFrame(timestamp: timestamp + 0.01,
                                                           displayedPose: nil, request: nil, check: nil,
                                                           now: timestamp + 0.02)
        XCTAssertFalse(accepted, "A tracking update without a check request cannot replace a comparison")
        XCTAssertFalse(controller.practiceMarkerVisible)
        XCTAssertEqual(controller.practiceCheckSnapshot?.id, imageID)
        XCTAssertEqual(controller.dartPractice.lastCheck?.timestamp, timestamp)
        XCTAssertEqual(controller.dartPractice.currentAction, 3)
    }

    @MainActor
    func testOldRequestCannotReviveAnImageAfterNewCheck() throws {
        let controller = makeController()
        let timestamp = try seedComparison(controller)
        let old = DartPracticeCheckRequest(revision: -1, action: 3, requestedAt: timestamp)
        controller.checkPracticeAction()
        let accepted = controller.receiveDartPracticeFrame(timestamp: timestamp, displayedPose: quad,
                                                           request: old, check: result(at: timestamp),
                                                           now: timestamp + 0.01)
        XCTAssertFalse(accepted)
        XCTAssertNil(controller.practiceCheckSnapshot)
        XCTAssertNil(controller.dartPractice.lastCheck)
        XCTAssertTrue(controller.practiceCheckBusy)
    }

    @MainActor
    func testSnapshotReviewDoesNotTurnIntoPhysicalConfirmationOrPersistAnImage() throws {
        let store = PracticeProgressStore(defaults: nil)
        let controller = makeController(store: store)
        try seedComparison(controller)
        controller.showPracticeActionIn3D()
        XCTAssertNil(controller.practiceCheckSnapshot)
        XCTAssertEqual(controller.dartPractice.currentAction, 3)
        XCTAssertEqual(controller.dartPractice.confirmedActions, [1, 2])
        let restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored.checkSummaries.count, 1)
        XCTAssertNil(restored.lastCheck)
        XCTAssertEqual(controller.stepIndex, 3)
    }

    @MainActor
    func testReviewSuspendsLiveAnalysisWithoutChangingItsFrozenImage() throws {
        let controller = makeController()
        let timestamp = try seedComparison(controller)
        let imageID = try XCTUnwrap(controller.practiceCheckSnapshot?.id)
        XCTAssertTrue(controller.beginPracticeComparisonReview())
        XCTAssertTrue(controller.isReviewingPracticeComparison)
        XCTAssertNil(controller.paperGuide.registration)
        XCTAssertFalse(controller.practiceMarkerVisible)
        controller.expireDartPracticeCapture(at: timestamp + 10)
        let accepted = controller.receiveDartPracticeFrame(timestamp: timestamp + 0.01, displayedPose: quad,
                                                           request: nil, check: nil, now: timestamp + 0.02)
        XCTAssertFalse(accepted)
        XCTAssertEqual(controller.practiceCheckSnapshot?.id, imageID)
        controller.checkPracticeAction()
        XCTAssertNil(controller.practiceCheckRequest, "A new live check waits until the review is closed")
        controller.endPracticeComparisonReview()
        XCTAssertFalse(controller.isReviewingPracticeComparison)
        XCTAssertNil(controller.practiceCheckSnapshot)
        XCTAssertEqual(controller.dartPractice.currentAction, 3)
    }

    @MainActor
    func testBackgroundDuringReviewCannotResumeCameraOnModalDismissal() throws {
        let controller = makeController()
        try seedComparison(controller)
        XCTAssertTrue(controller.beginPracticeComparisonReview())
        let revision = controller.cameraSessionRevision
        controller.background()
        controller.endPracticeComparisonReview()
        XCTAssertTrue(controller.needsRescan)
        XCTAssertFalse(controller.isReviewingPracticeComparison)
        XCTAssertNil(controller.practiceCheckSnapshot)
        XCTAssertGreaterThan(controller.cameraSessionRevision, revision)
        XCTAssertEqual(controller.dartPractice.currentAction, 3)
    }

    @MainActor private func makeController(store: PracticeProgressStore = PracticeProgressStore(defaults: nil)) -> LessonController {
        let controller = LessonController(progressStore: LearningProgressStore(defaults: nil), practiceStore: store)
        controller.enterDartPractice()
        controller.confirmPracticeAction(); controller.confirmPracticeAction()
        return controller
    }

    @MainActor @discardableResult
    private func seedComparison(_ controller: LessonController) throws -> TimeInterval {
        let now = ProcessInfo.processInfo.systemUptime
        let result = result(at: now)
        XCTAssertTrue(controller.dartPractice.recordCheck(result, at: now))
        let image = PaperLuminanceImage(width: 64, height: 96, pixels: Array(repeating: 220, count: 64 * 96))
        controller.practiceCheckSnapshot = try XCTUnwrap(DartCheckSnapshot(image: image, result: result,
                                                                          rawSheetQuadrilateral: quad,
                                                                          displayTransform: .identity,
                                                                          viewportSize: CGSize(width: 320, height: 480),
                                                                          isSynthetic: true, now: now))
        return now
    }
    private var quad: PaperQuadrilateral {
        PaperQuadrilateral(topLeft: CGPoint(x: 0.2, y: 0.1), topRight: CGPoint(x: 0.8, y: 0.1),
                           bottomRight: CGPoint(x: 0.8, y: 0.9), bottomLeft: CGPoint(x: 0.2, y: 0.9))
    }
    private func result(at timestamp: TimeInterval) -> DartOutlineCheckResult {
        DartOutlineCheckResult(checkpointID: "synthetic-controller-comparison", referenceState: 3,
                               outcome: .needsAdjustment, message: "Synthetic visible-outline comparison.",
                               mismatchedPoints: [CGPoint(x: 0.12, y: 0.1)], timestamp: timestamp)
    }
}
