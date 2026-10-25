import XCTest
@testable import Protacta

/// Persistence and interaction-policy contracts. No camera session, physical
/// placement, real hand occlusion, or StoreKit transaction is simulated here.
final class LearningControllerTests: XCTestCase {
    @MainActor
    func testContinueRestoresAPausedFoldWithoutRestoringAROrStartingPlayback() {
        let store = LearningProgressStore(defaults: nil)
        let original = LessonController(progressStore: store)
        original.selectLesson(.dart)
        original.begin()
        original.goToStep(3)
        original.scrub(to: 0.4)
        original.toggleSlowMotion()
        original.toggleHints()
        // Inject flags only: camera/anchor transforms must never be persisted.
        original.isAR = true
        original.placed = true
        original.trackingReady = true
        original.saveLearningProgress()

        let restored = LessonController(progressStore: store)
        XCTAssertEqual(restored.lesson, .dart)
        XCTAssertFalse(restored.started, "Launching selects the last lesson but does not start it")
        XCTAssertFalse(restored.isAR)
        XCTAssertFalse(restored.isPlaying)
        XCTAssertNil(restored.arView)

        restored.continueLearning()
        assertPausedFold(restored, lesson: .dart, step: 3, progress: 0.4)
        XCTAssertTrue(restored.slowMotion)
        XCTAssertFalse(restored.hintsVisible)
        XCTAssertFalse(restored.placed)
        XCTAssertFalse(restored.trackingReady)
        XCTAssertTrue(restored.positionLocked)
        XCTAssertNil(restored.arView, "Continue must not request camera access or rebuild an old AR placement")
    }

    @MainActor
    func testSwitchingLessonsKeepsEachLessonsOwnPausedFold() {
        let store = LearningProgressStore(defaults: nil)
        let controller = LessonController(progressStore: store)
        controller.selectLesson(.dart)
        controller.begin()
        controller.goToStep(3)
        controller.scrub(to: 0.4)

        controller.selectLesson(.fox)
        XCTAssertFalse(controller.started)
        controller.continueLearning()
        XCTAssertTrue(controller.started, "A lesson without a saved record starts normally")
        XCTAssertEqual(controller.stepIndex, 0)
        controller.goToStep(2)
        controller.scrub(to: 0.65)

        controller.selectLesson(.dart)
        XCTAssertFalse(controller.started)
        controller.continueLearning()
        assertPausedFold(controller, lesson: .dart, step: 3, progress: 0.4)

        controller.selectLesson(.fox)
        controller.continueLearning()
        assertPausedFold(controller, lesson: .fox, step: 2, progress: 0.65)
    }

    @MainActor
    func testCompletionRestoresAsCompleteAndExplicitRestartReplacesOnlyThatLesson() {
        let store = LearningProgressStore(defaults: nil)
        let controller = LessonController(progressStore: store)
        controller.selectLesson(.fox)
        controller.begin()
        controller.goToStep(2)
        controller.scrub(to: 0.6)
        controller.selectLesson(.dart)
        controller.begin()
        controller.goToStep(controller.lastStep)
        controller.scrub(to: 1)
        controller.next()
        XCTAssertTrue(controller.completed)
        controller.pauseAndSave()

        let restored = LessonController(progressStore: store)
        XCTAssertEqual(restored.lesson, .dart)
        XCTAssertFalse(restored.started)
        restored.continueLearning()
        XCTAssertTrue(restored.started)
        XCTAssertTrue(restored.completed)
        XCTAssertEqual(restored.stepIndex, restored.lastStep)
        XCTAssertEqual(restored.progress, 1)
        XCTAssertFalse(restored.isPlaying)
        XCTAssertFalse(restored.isAR)
        XCTAssertNil(restored.arView)

        restored.begin()
        assertPausedFold(restored, lesson: .dart, step: 0, progress: 1)
        restored.selectLesson(.fox)
        restored.continueLearning()
        assertPausedFold(restored, lesson: .fox, step: 2, progress: 0.6)
        restored.selectLesson(.dart)
        restored.continueLearning()
        assertPausedFold(restored, lesson: .dart, step: 0, progress: 1)
    }

    @MainActor
    func testPremiumRevocationKeepsSavedProgressButRequiresAccessBeforeContinuing() {
        let store = LearningProgressStore(defaults: nil)
        let controller = LessonController(progressStore: store)
        controller.updateLibraryAccess(true)
        controller.selectLesson(.crane)
        controller.begin()
        controller.goToStep(12)
        controller.scrub(to: 0.35)
        controller.updateLibraryAccess(false)
        XCTAssertFalse(controller.started)
        XCTAssertFalse(controller.hasLessonAccess)

        let restored = LessonController(progressStore: store)
        XCTAssertEqual(restored.lesson, .crane)
        restored.continueLearning()
        XCTAssertFalse(restored.started)
        XCTAssertFalse(restored.isPlaying)
        XCTAssertFalse(restored.isAR)
        XCTAssertEqual(restored.stepIndex, 0)
        XCTAssertNil(restored.arView)

        restored.updateLibraryAccess(true)
        restored.continueLearning()
        assertPausedFold(restored, lesson: .crane, step: 12, progress: 0.35)
    }

    @MainActor
    func testPauseAndSaveRestoresCurrentPoseRatherThanAutomaticallyResumingAnimation() {
        let store = LearningProgressStore(defaults: nil)
        let controller = LessonController(progressStore: store)
        controller.selectLesson(.dart)
        controller.begin()
        controller.goToStep(3)
        controller.scrub(to: 0.4)
        controller.togglePlayback()
        XCTAssertTrue(controller.isPlaying)
        controller.pauseAndSave()
        XCTAssertFalse(controller.isPlaying)

        let restored = LessonController(progressStore: store)
        restored.continueLearning()
        assertPausedFold(restored, lesson: .dart, step: 3, progress: 0.4)
    }

    @MainActor
    func testPositionLockAndTrackingGateGesturesWithoutChangingLessonOrOcclusionPreference() {
        let controller = LessonController(progressStore: LearningProgressStore(defaults: nil))
        controller.selectLesson(.dart)
        controller.begin()
        controller.goToStep(3)
        controller.scrub(to: 0.4)
        XCTAssertTrue(controller.positionLocked)
        XCTAssertFalse(controller.placementGesturesEnabled)

        // These flags test controller policy only, not physical AR behavior.
        controller.isAR = true
        controller.placed = true
        controller.trackingReady = false
        controller.togglePositionLock()
        XCTAssertTrue(controller.positionLocked, "Tracking loss must not allow an unlock")
        XCTAssertFalse(controller.placementGesturesEnabled)

        controller.trackingReady = true
        controller.togglePositionLock()
        XCTAssertFalse(controller.positionLocked)
        XCTAssertTrue(controller.placementGesturesEnabled)
        controller.trackingReady = false
        XCTAssertFalse(controller.placementGesturesEnabled)
        controller.trackingReady = true
        XCTAssertFalse(controller.positionLocked, "Recovery keeps the user's lock preference")
        XCTAssertTrue(controller.placementGesturesEnabled)
        controller.needsRescan = true
        XCTAssertFalse(controller.placementGesturesEnabled)
        controller.needsRescan = false

        controller.togglePositionLock()
        XCTAssertTrue(controller.positionLocked)
        XCTAssertFalse(controller.placementGesturesEnabled)
        for mode in [AROcclusionMode.peopleOnly, .automatic] {
            controller.setOcclusionMode(mode)
            XCTAssertTrue(controller.positionLocked)
            XCTAssertFalse(controller.placementGesturesEnabled)
            XCTAssertEqual(controller.stepIndex, 3)
            XCTAssertEqual(controller.progress, 0.4, accuracy: 0.0001)
            XCTAssertFalse(controller.isPlaying)
        }
        XCTAssertNil(controller.arView)
    }

    @MainActor
    private func assertPausedFold(_ controller: LessonController, lesson: OrigamiLesson,
                                  step: Int, progress: Float,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(controller.lesson, lesson, file: file, line: line)
        XCTAssertTrue(controller.started, file: file, line: line)
        XCTAssertEqual(controller.stepIndex, step, file: file, line: line)
        XCTAssertEqual(controller.progress, progress, accuracy: 0.0001, file: file, line: line)
        XCTAssertFalse(controller.isPlaying, file: file, line: line)
        XCTAssertFalse(controller.completed, file: file, line: line)
        XCTAssertFalse(controller.isAR, file: file, line: line)
    }
}
