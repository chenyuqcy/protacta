import XCTest
import QuartzCore
@testable import Protacta

final class DartPracticeControllerTests: XCTestCase {
    @MainActor
    func testVisualResultNeverConfirmsOrAdvancesAnAction() {
        let controller = makeController()
        controller.confirmPracticeAction(); controller.confirmPracticeAction()
        XCTAssertEqual(controller.dartPractice.currentAction, 3)
        let now = CACurrentMediaTime()
        let request = DartPracticeCheckRequest(revision: 9, action: 3, requestedAt: now - 0.01)
        controller.practiceCheckRequest = request; controller.practiceCheckBusy = true
        controller.receiveDartPracticeFrame(timestamp: now, displayedPose: quad, request: request,
                                           check: result(action: 3, at: now), now: now)
        XCTAssertEqual(controller.dartPractice.lastCheck?.outcome, .visibleMatch)
        XCTAssertEqual(controller.dartPractice.currentAction, 3)
        XCTAssertEqual(controller.dartPractice.confirmedActions, [1, 2])
        XCTAssertFalse(controller.practiceCheckBusy)
    }

    @MainActor
    func testChangingActionCancelsInFlightCheck() {
        let controller = makeController()
        controller.confirmPracticeAction(); controller.confirmPracticeAction()
        let now = CACurrentMediaTime()
        let request = DartPracticeCheckRequest(revision: 2, action: 3, requestedAt: now)
        controller.practiceCheckRequest = request; controller.practiceCheckBusy = true
        controller.confirmPracticeAction()
        controller.receiveDartPracticeFrame(timestamp: now + 0.01, displayedPose: quad, request: request,
                                           check: result(action: 3, at: now + 0.01), now: now + 0.02)
        XCTAssertEqual(controller.dartPractice.currentAction, 4)
        XCTAssertNil(controller.dartPractice.lastCheck)
        XCTAssertNil(controller.practiceCheckRequest)
        XCTAssertFalse(controller.practiceCheckBusy)
    }

    @MainActor
    func testStaleOrPreRequestFramesCannotProvideCheck() {
        let controller = makeController()
        controller.confirmPracticeAction(); controller.confirmPracticeAction()
        let now = CACurrentMediaTime()
        let request = DartPracticeCheckRequest(revision: 2, action: 3, requestedAt: now)
        controller.practiceCheckRequest = request; controller.practiceCheckBusy = true
        controller.receiveDartPracticeFrame(timestamp: now - 1, displayedPose: quad, request: request,
                                           check: result(action: 3, at: now - 1), now: now)
        XCTAssertFalse(controller.practiceMarkerVisible)
        controller.receiveDartPracticeFrame(timestamp: now - 0.01, displayedPose: quad, request: request,
                                           check: result(action: 3, at: now - 0.01), now: now)
        XCTAssertNil(controller.dartPractice.lastCheck)
        XCTAssertTrue(controller.practiceCheckBusy)
        controller.expireDartPracticeCapture(at: now + 3)
        XCTAssertEqual(controller.dartPractice.lastCheck?.outcome, .cannotJudge)
        XCTAssertFalse(controller.practiceCheckBusy)
    }

    @MainActor
    func testTrackingLossInvalidatesRegistrationAndPendingCheck() {
        let controller = makeController()
        controller.confirmPracticeAction(); controller.confirmPracticeAction()
        let now = CACurrentMediaTime()
        controller.receiveDartPracticeFrame(timestamp: now, displayedPose: quad, request: nil, check: nil, now: now)
        XCTAssertNotNil(controller.paperGuide.registration)
        let revision = controller.paperRegistrationRevision
        controller.practiceCheckRequest = DartPracticeCheckRequest(revision: 1, action: 3, requestedAt: now)
        controller.practiceCheckBusy = true
        controller.handleDartPracticeTrackingLoss()
        XCTAssertGreaterThan(controller.paperRegistrationRevision, revision)
        XCTAssertNil(controller.paperGuide.registration)
        XCTAssertFalse(controller.practiceMarkerVisible)
        XCTAssertNil(controller.practiceCheckRequest)
        controller.receiveDartPracticeFrame(timestamp: now + 0.01, displayedPose: quad, request: nil, check: nil, now: now + 0.02)
        XCTAssertNil(controller.paperGuide.registration, "An old queued frame cannot restore cues while tracking is limited")
    }

    @MainActor
    func testBackgroundPreservesPracticeButRemovesCaptureAndRequiresRecovery() {
        let controller = makeController()
        controller.confirmPracticeAction(); controller.confirmPracticeAction()
        let now = CACurrentMediaTime()
        controller.receiveDartPracticeFrame(timestamp: now, displayedPose: quad, request: nil, check: nil, now: now)
        controller.background()
        XCTAssertTrue(controller.isDartPractice)
        XCTAssertEqual(controller.dartPractice.currentAction, 3)
        XCTAssertTrue(controller.needsRescan)
        XCTAssertNil(controller.paperGuide.registration)
        XCTAssertFalse(controller.practiceMarkerVisible)
        XCTAssertEqual(controller.practiceProgressStore.load()?.currentAction, 3)
    }

    @MainActor
    func testReferenceAndVoiceKeepPracticeProgressIndependentFromAnimation() {
        let controller = makeController()
        controller.confirmPracticeAction(); controller.confirmPracticeAction()
        XCTAssertEqual(controller.performVoiceCommand(.next), .message("Tap I have made this fold when you want to confirm the action and continue. Voice navigation does not confirm the paper."))
        XCTAssertEqual(controller.dartPractice.currentAction, 3)
        _ = controller.performVoiceCommand(.replay)
        XCTAssertFalse(controller.isAR)
        XCTAssertTrue(controller.practiceReferenceActive)
        XCTAssertEqual(controller.stepIndex, 3)
        controller.scrub(to: 1)
        XCTAssertEqual(controller.dartPractice.currentAction, 3)
        controller.enterDartPractice()
        XCTAssertEqual(controller.dartPractice.currentAction, 3)
        XCTAssertFalse(controller.practiceReferenceActive)
    }

    @MainActor
    func testAllTenConfirmationsAndReopenCompletion() {
        let controller = makeController()
        for _ in 1...10 { controller.confirmPracticeAction() }
        XCTAssertTrue(controller.dartPractice.completed)
        XCTAssertEqual(controller.dartPractice.confirmedActions, Array(1...10))
        XCTAssertTrue(controller.completed)
        XCTAssertTrue(controller.needsRescan)
        controller.previousPracticeAction()
        XCTAssertFalse(controller.dartPractice.completed)
        XCTAssertFalse(controller.completed)
        XCTAssertEqual(controller.dartPractice.currentAction, 10)
        XCTAssertEqual(controller.dartPractice.confirmedActions, Array(1...9))
    }

    @MainActor
    func testSpokenHelpUsesPracticeActionRatherThanAnOldAnimationStep() {
        let controller = makeController()
        controller.confirmPracticeAction(); controller.confirmPracticeAction()
        controller.stepIndex = 8
        let action = DartPracticeCourse.action(3)
        XCTAssertEqual(controller.performVoiceCommand(.readStep),
                       .narration("Action 3. \(action.title). \(action.instruction)"))
        XCTAssertEqual(controller.performVoiceCommand(.why), .narration(action.explanation))
        guard case .narration(let help) = controller.performVoiceCommand(.help) else { return XCTFail("Expected authored practice help") }
        XCTAssertTrue(help.contains(action.manualCheckpoint))
        XCTAssertEqual(controller.dartPractice.currentAction, 3)
    }

    func testCodedDirectionSurvivesDisplayRotationAndRejectsCrop() {
        let rotation = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1, ty: 1)
        let mapped = DartPracticeCameraCoordinates.viewportQuadrilateral(rawTopLeft: quad, displayTransform: rotation)
        XCTAssertEqual(mapped?.topLeft.x ?? 0, 0.8, accuracy: 0.0001)
        XCTAssertEqual(mapped?.topLeft.y ?? 0, 0.9, accuracy: 0.0001)
        XCTAssertNil(DartPracticeCameraCoordinates.viewportQuadrilateral(rawTopLeft: quad,
                      displayTransform: CGAffineTransform(scaleX: 2, y: 1)))
    }

    func testCueGeometryOnlyExistsForSupportedStartingStates() {
        XCTAssertNotNil(DartPracticeCueGeometry(action: 1))
        XCTAssertNil(DartPracticeCueGeometry(action: 2))
        for action in 3...7 { XCTAssertNotNil(DartPracticeCueGeometry(action: action)) }
        for action in 8...10 { XCTAssertNil(DartPracticeCueGeometry(action: action)) }
    }

    @MainActor private func makeController() -> LessonController {
        let controller = LessonController(progressStore: LearningProgressStore(defaults: nil), practiceStore: PracticeProgressStore(defaults: nil))
        controller.selectLesson(.dart)
        controller.enterDartPractice()
        return controller
    }
    private var quad: PaperQuadrilateral {
        PaperQuadrilateral(topLeft: CGPoint(x: 0.2, y: 0.1), topRight: CGPoint(x: 0.8, y: 0.1),
                           bottomRight: CGPoint(x: 0.8, y: 0.9), bottomLeft: CGPoint(x: 0.2, y: 0.9))
    }
    private func result(action: Int, at timestamp: TimeInterval) -> DartOutlineCheckResult {
        DartOutlineCheckResult(checkpointID: "synthetic-controller-test", referenceState: action,
                               outcome: .visibleMatch, message: "Synthetic outline only.", mismatchedPoints: [], timestamp: timestamp)
    }
}
