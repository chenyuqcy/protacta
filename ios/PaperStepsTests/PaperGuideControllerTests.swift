import XCTest
@testable import Protacta

final class PaperGuideControllerTests: XCTestCase {
    @MainActor
    func testRegistrationRestartDoesNotInvalidateCameraAuthorizationToken() {
        let controller = makeController()
        controller.enterPaperGuide()
        let revision = controller.cameraSessionRevision
        XCTAssertTrue(controller.acceptsCameraAuthorization(revision: revision))
        controller.restartPaperGuideTracking()
        controller.restartPaperGuideTracking()
        XCTAssertEqual(controller.cameraSessionRevision, revision)
        XCTAssertTrue(controller.acceptsCameraAuthorization(revision: revision),
                      "Resetting rectangle registration must not cancel camera startup")
        controller.leaveAR()
        XCTAssertFalse(controller.acceptsCameraAuthorization(revision: revision))
    }

    @MainActor
    func testBackgroundCannotResumeAnOutstandingCameraAuthorization() {
        let controller = makeController()
        controller.enterPaperGuide()
        let revision = controller.cameraSessionRevision
        controller.background()
        XCTAssertTrue(controller.needsRescan)
        XCTAssertFalse(controller.acceptsCameraAuthorization(revision: revision))
        XCTAssertNil(controller.paperGuide.registration)
    }

    @MainActor
    func testPaperGuideCannotUseTablePlacementToEnableAnimation() {
        let controller = makeController()
        controller.enterPaperGuide()
        // A stale tabletop flag must not turn the real-paper view into a model.
        controller.placed = true
        controller.trackingReady = true
        XCTAssertFalse(controller.canAnimate)
        XCTAssertFalse(controller.placementGesturesEnabled)
        controller.next()
        XCTAssertEqual(controller.stepIndex, 0)
    }

    @MainActor
    func testLearnerConfirmationStoresTeachingStateWithoutCameraApproval() {
        let store = LearningProgressStore(defaults: nil)
        let controller = LessonController(progressStore: store)
        controller.selectLesson(.dart)
        controller.begin()
        controller.enterPaperGuide()
        XCTAssertNil(controller.paperGuide.registration)
        controller.confirmFirstPaperFold()
        XCTAssertFalse(controller.isPaperGuide)
        XCTAssertFalse(controller.isAR)
        XCTAssertEqual(controller.stepIndex, 1)
        XCTAssertEqual(controller.progress, 1)
        XCTAssertFalse(controller.completed)
        XCTAssertEqual(store.record(for: .dart)?.stepIndex, 1)
    }

    @MainActor
    func testLaterLessonStepIsUnsupportedUntilUserStartsANewSheet() {
        let controller = makeController()
        controller.goToStep(4)
        controller.scrub(to: 1)
        controller.enterPaperGuide()
        XCTAssertEqual(controller.paperGuide.status, .unsupported)
        XCTAssertNil(controller.paperGuide.registration)
        controller.startPaperGuideWithNewSheet()
        XCTAssertEqual(controller.stepIndex, 0)
        XCTAssertEqual(controller.paperGuide.status, .searching)
    }

    @MainActor
    func testCameraFailureInvalidatesPendingAuthorizationAndRequiresRecovery() {
        let controller = makeController()
        controller.enterPaperGuide()
        let revision = controller.cameraSessionRevision
        controller.handleCameraFailure("Camera interrupted")
        XCTAssertFalse(controller.acceptsCameraAuthorization(revision: revision))
        XCTAssertTrue(controller.needsRescan)
        XCTAssertNil(controller.paperGuide.registration)
        XCTAssertTrue(controller.paperGuideMessage.contains("Camera interrupted"))
    }

    @MainActor
    private func makeController() -> LessonController {
        let controller = LessonController(progressStore: LearningProgressStore(defaults: nil))
        controller.selectLesson(.dart)
        controller.begin()
        return controller
    }
}
