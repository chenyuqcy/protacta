import XCTest
@testable import Protacta

/// Playback policy only: no renderer, camera, microphone or physical fold is
/// simulated. Synthetic timestamps exercise the same clock used by displayLink.
final class LessonPlaybackTests: XCTestCase {
    @MainActor
    func testAutoPlayStartsPausedFirstFoldAndRequiresManualFinishAtTheEnd() throws {
        let store = LearningProgressStore(defaults: nil)
        let controller = LessonController(progressStore: store, opensClassicDart: true)
        XCTAssertEqual(controller.stepIndex, 1)
        XCTAssertEqual(controller.progress, 0)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.nextTitle, "Play")

        controller.setAutoPlay(true)
        XCTAssertEqual(controller.stepIndex, 1, "The home shortcut must not skip the first fold")
        XCTAssertTrue(controller.isPlaying)
        controller.goToStep(controller.lastStep, autoplay: false)
        controller.setAutoPlay(true)
        finishCurrentAnimation(controller)
        controller.advancePlayback(at: 1000)

        XCTAssertFalse(controller.autoPlay)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertFalse(controller.completed)
        XCTAssertEqual(controller.progress, 1)
        XCTAssertEqual(controller.nextTitle, "Finish")
        XCTAssertFalse(try XCTUnwrap(store.record(for: .dart)).completed)
        controller.next()
        XCTAssertTrue(controller.completed)
        XCTAssertTrue(try XCTUnwrap(store.record(for: .dart)).completed)
    }

    @MainActor
    func testDwellAdvancesOnceAndPauseDuringDwellDoesNotReplayOrAdvance() {
        let advancing = makeDwell()
        advancing.advancePlayback(at: 101)
        XCTAssertEqual(advancing.stepIndex, 2)
        advancing.advancePlayback(at: 102)
        XCTAssertEqual(advancing.stepIndex, 3)
        XCTAssertTrue(advancing.isPlaying)
        advancing.advancePlayback(at: 103)
        XCTAssertEqual(advancing.stepIndex, 3)

        let paused = makeDwell()
        paused.togglePlayback()
        XCTAssertFalse(paused.autoPlay)
        XCTAssertFalse(paused.isPlaying)
        XCTAssertEqual(paused.progress, 1, "Pausing a dwell must not replay its completed fold")
        paused.advancePlayback(at: 1000)
        XCTAssertEqual(paused.stepIndex, 2)
        XCTAssertEqual(paused.progress, 1)
    }

    @MainActor
    func testExplicitNavigationAndVoiceInterruptionsCancelPendingAutoAdvance() {
        let actions: [(String, (LessonController) -> Void)] = [
            ("pause", { $0.pauseAndSave() }),
            ("auto-play off", { $0.setAutoPlay(false) }),
            ("replay", { $0.replay() }),
            ("seek", { $0.scrub(to: 0.4) }),
            ("select step", { $0.goToStep(7, autoplay: false) }),
            ("back", { $0.back() }),
            ("restart", { $0.begin() }),
            ("background", { $0.background() }),
            ("leave AR", { $0.leaveAR() }),
            ("camera failure", { $0.handleCameraFailure("test") }),
            ("voice pause", { _ = $0.performVoiceCommand(.pause) }),
            ("voice read step", { _ = $0.performVoiceCommand(.readStep) }),
            ("voice explain", { _ = $0.performVoiceCommand(.why) }),
            ("voice restart", { _ = $0.performVoiceCommand(.restart) })
        ]
        for (name, action) in actions {
            let controller = makeDwell()
            action(controller)
            let selected = controller.stepIndex
            XCTAssertFalse(controller.autoPlay, name)
            controller.advancePlayback(at: 1000)
            controller.advancePlayback(at: 1003)
            XCTAssertEqual(controller.stepIndex, selected, name)
            XCTAssertFalse(controller.completed, name)
        }
    }

    @MainActor
    func testTrackingInterruptionCancelsPendingDwellAndNeverAutoResumes() {
        let controller = makeDwell()
        // Inject policy flags, not an ARFrame or a claimed physical anchor.
        controller.isAR = true
        controller.placed = true
        controller.trackingReady = true
        controller.checkTabletopFrameHealth(timestamp: nil, now: 100.1,
                                           normal: false, anchorPresent: false)
        XCTAssertFalse(controller.autoPlay)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertFalse(controller.trackingReady)
        controller.trackingReady = true
        controller.advancePlayback(at: 1000)
        XCTAssertEqual(controller.stepIndex, 2)
        XCTAssertFalse(controller.isPlaying)
    }

    @MainActor
    func testSkipAheadAtFinalStepDoesNotConfirmTheLesson() {
        let controller = LessonController(progressStore: LearningProgressStore(defaults: nil), opensClassicDart: true)
        controller.goToStep(controller.lastStep, autoplay: false)
        controller.setAutoPlay(true)
        controller.skipAhead()
        XCTAssertFalse(controller.completed)
        XCTAssertFalse(controller.autoPlay)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.progress, 1)
        controller.setAutoPlay(true)
        XCTAssertFalse(controller.completed)
        XCTAssertFalse(controller.autoPlay)
    }

    @MainActor
    func testSupportedSpeedPersistsAndInvalidRatesCannotEnterPlayback() {
        let store = LearningProgressStore(defaults: nil)
        let controller = LessonController(progressStore: store, opensClassicDart: true)
        controller.setSpeed(2)
        controller.pauseAndSave()
        let restored = LessonController(progressStore: store, opensClassicDart: true)
        XCTAssertEqual(restored.playbackRate, 2)
        XCTAssertFalse(restored.slowMotion)
        XCTAssertFalse(restored.isPlaying)
        for rate in [Double.nan, .infinity, -.infinity, 0, -1, 0.75, 10] {
            restored.setSpeed(rate)
            XCTAssertEqual(restored.playbackRate, 2)
        }
        restored.setSpeed(0.5)
        XCTAssertTrue(restored.slowMotion)
        restored.setSpeed(1)
        XCTAssertFalse(restored.slowMotion)
    }

    @MainActor
    private func makeDwell() -> LessonController {
        let controller = LessonController(progressStore: LearningProgressStore(defaults: nil), opensClassicDart: true)
        controller.goToStep(2, autoplay: false)
        controller.setAutoPlay(true)
        finishCurrentAnimation(controller)
        XCTAssertTrue(controller.autoPlay)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.stepIndex, 2)
        return controller
    }

    @MainActor
    private func finishCurrentAnimation(_ controller: LessonController) {
        controller.progress = 0.99999
        controller.advancePlayback(at: 100)
        controller.advancePlayback(at: 100.06)
        XCTAssertEqual(controller.progress, 1)
    }
}
