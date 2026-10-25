import XCTest
@testable import Protacta

/// Routes parsed commands through the production lesson controller. These tests
/// do not request microphone/camera access or claim speech recognition, audible
/// narration, physical tracking, or StoreKit transaction coverage.
final class LessonVoiceActionsTests: XCTestCase {
    @MainActor
    func testVoiceGuideAvailabilityRequiresAnExplicitlyStartedAccessibleLesson() {
        let store = LearningProgressStore(defaults: nil)
        let controller = LessonController(progressStore: store)
        XCTAssertFalse(controller.canUseVoiceGuide)
        controller.selectLesson(.dart)
        XCTAssertFalse(controller.canUseVoiceGuide, "A free preview must not enable the microphone panel")
        controller.begin()
        XCTAssertTrue(controller.canUseVoiceGuide)

        controller.selectLesson(.crane)
        XCTAssertFalse(controller.canUseVoiceGuide, "Selecting a locked premium lesson closes voice entry")
        controller.updateLibraryAccess(true)
        XCTAssertFalse(controller.canUseVoiceGuide, "An entitlement alone does not start a lesson")
        controller.begin()
        controller.goToStep(9)
        controller.scrub(to: 0.4)
        XCTAssertTrue(controller.canUseVoiceGuide)
        controller.updateLibraryAccess(false)
        XCTAssertFalse(controller.canUseVoiceGuide, "Revocation removes voice access from the stopped lesson")

        let restored = LessonController(progressStore: store)
        XCTAssertEqual(restored.lesson, .crane)
        XCTAssertFalse(restored.canUseVoiceGuide)
        restored.updateLibraryAccess(true)
        XCTAssertFalse(restored.started)
        XCTAssertFalse(restored.canUseVoiceGuide, "Restoring access and a saved record must not auto-start voice entry")
        restored.continueLearning()
        XCTAssertTrue(restored.canUseVoiceGuide)
        XCTAssertEqual(restored.stepIndex, 9)
        XCTAssertEqual(restored.progress, 0.4, accuracy: 0.0001)
    }

    @MainActor
    func testVoiceCommandsCannotStartAPreviewOrBypassPremiumAccess() {
        for lesson in [OrigamiLesson.dart, .crane] {
            let store = LearningProgressStore(defaults: nil)
            let controller = LessonController(progressStore: store)
            controller.selectLesson(lesson)
            for command in VoiceCommand.allCases where command != .stopListening {
                let response = controller.performVoiceCommand(command)
                XCTAssertEqual(response, .message(lesson.isFree
                    ? "Start or continue a lesson first."
                    : "This lesson requires full library access."), command.rawValue)
                XCTAssertEqual(controller.lesson, lesson)
                XCTAssertFalse(controller.started, command.rawValue)
                XCTAssertFalse(controller.isPlaying, command.rawValue)
                XCTAssertFalse(controller.completed, command.rawValue)
                XCTAssertFalse(controller.slowMotion, command.rawValue)
                XCTAssertEqual(controller.stepIndex, 0, command.rawValue)
                XCTAssertEqual(controller.progress, 1, command.rawValue)
                XCTAssertNil(store.record(for: lesson), command.rawValue)
                XCTAssertNil(controller.arView)
            }
            // Turning off listening must remain available even on a locked preview.
            XCTAssertEqual(controller.performVoiceCommand(.stopListening), .message("Voice control is off."))
            XCTAssertFalse(controller.started)
        }
    }

    @MainActor
    func testNextCannotSkipAPlayingFoldAndFinishesAPartialFoldBeforeAdvancing() {
        let controller = begunDart()
        _ = controller.performVoiceCommand(.next)
        XCTAssertEqual(controller.stepIndex, 1)
        XCTAssertTrue(controller.isPlaying)
        XCTAssertEqual(controller.progress, 0)

        XCTAssertEqual(controller.performVoiceCommand(.next), .message("The fold is playing. Wait for it to finish, or say Pause."))
        XCTAssertEqual(controller.stepIndex, 1)
        XCTAssertEqual(controller.progress, 0)
        XCTAssertTrue(controller.isPlaying)

        controller.scrub(to: 0.4)
        XCTAssertEqual(controller.performVoiceCommand(.next), .message("Finishing this fold."))
        XCTAssertEqual(controller.stepIndex, 1, "Next finishes a partial pose without skipping the fold")
        XCTAssertEqual(controller.progress, 0.4, accuracy: 0.0001)
        XCTAssertTrue(controller.isPlaying)

        controller.scrub(to: 1)
        _ = controller.performVoiceCommand(.next)
        XCTAssertEqual(controller.stepIndex, 2)
        XCTAssertEqual(controller.progress, 0)
        XCTAssertTrue(controller.isPlaying)
    }

    @MainActor
    func testFinalNextCompletesAndFurtherNextOrResumeDoNotRestartTheLesson() throws {
        let store = LearningProgressStore(defaults: nil)
        let controller = begunDart(store: store)
        controller.goToStep(controller.lastStep)
        controller.scrub(to: 1)

        XCTAssertEqual(controller.performVoiceCommand(.next), .message("Lesson complete."))
        XCTAssertTrue(controller.completed)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(try XCTUnwrap(store.record(for: .dart)).completed, true)
        for command in [VoiceCommand.next, .resume] {
            _ = controller.performVoiceCommand(command)
            XCTAssertTrue(controller.completed, command.rawValue)
            XCTAssertTrue(controller.started, command.rawValue)
            XCTAssertEqual(controller.stepIndex, controller.lastStep, command.rawValue)
            XCTAssertEqual(controller.progress, 1, command.rawValue)
            XCTAssertFalse(controller.isPlaying, command.rawValue)
        }
    }

    @MainActor
    func testRestartDuringPlaybackReturnsToAFlatSheetAndKeepsTheCurrentLessonAndPreferences() throws {
        let store = LearningProgressStore(defaults: nil)
        let controller = begunDart(store: store)
        controller.goToStep(3)
        _ = controller.performVoiceCommand(.slower)
        controller.toggleHints()
        XCTAssertTrue(controller.isPlaying)

        XCTAssertEqual(controller.performVoiceCommand(.restart),
                       .message("Lesson restarted with a flat sheet. Say Next fold when you are ready."))
        XCTAssertEqual(controller.lesson, .dart)
        XCTAssertTrue(controller.started)
        XCTAssertFalse(controller.completed)
        XCTAssertEqual(controller.stepIndex, 0)
        XCTAssertEqual(controller.progress, 1, "At step zero, progress one is the complete flat-sheet pose")
        XCTAssertFalse(controller.isPlaying)
        XCTAssertTrue(controller.slowMotion)
        XCTAssertFalse(controller.hintsVisible)
        let saved = try XCTUnwrap(store.record(for: .dart))
        XCTAssertEqual(saved.stepIndex, 0)
        XCTAssertEqual(saved.progress, 1)
        XCTAssertFalse(saved.completed)

        let restored = LessonController(progressStore: store)
        restored.continueLearning()
        XCTAssertEqual(restored.lesson, .dart)
        XCTAssertEqual(restored.stepIndex, 0)
        XCTAssertFalse(restored.isPlaying)
        XCTAssertFalse(restored.completed)
    }

    @MainActor
    func testRestartCompletedLessonResetsOnlyThatLessonsSavedProgress() throws {
        let store = LearningProgressStore(defaults: nil)
        let controller = begunDart(store: store)
        controller.goToStep(3)
        controller.scrub(to: 0.4)
        let dartProgress = try XCTUnwrap(store.record(for: .dart))
        controller.updateLibraryAccess(true)
        controller.selectLesson(.crane)
        controller.begin()
        controller.goToStep(controller.lastStep)
        controller.scrub(to: 1)
        _ = controller.performVoiceCommand(.next)
        XCTAssertTrue(controller.completed)

        _ = controller.performVoiceCommand(.restart)
        XCTAssertEqual(controller.lesson, .crane)
        XCTAssertTrue(controller.hasLessonAccess)
        XCTAssertTrue(controller.started)
        XCTAssertFalse(controller.completed)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.stepIndex, 0)
        XCTAssertEqual(controller.progress, 1)
        let craneProgress = try XCTUnwrap(store.record(for: .crane))
        XCTAssertEqual(craneProgress.stepIndex, 0)
        XCTAssertFalse(craneProgress.completed)
        // Selecting Crane saves Dart again, so compare teaching state, not the timestamp.
        let unchangedDart = try XCTUnwrap(store.record(for: .dart))
        XCTAssertEqual(unchangedDart.stepIndex, dartProgress.stepIndex)
        XCTAssertEqual(unchangedDart.progress, dartProgress.progress)
        XCTAssertEqual(unchangedDart.completed, dartProgress.completed)
    }

    @MainActor
    func testRestartAtTheBeginningKeepsPaperPausedUntilAnExplicitNextCommand() {
        let controller = begunDart()
        for _ in 0..<2 {
            _ = controller.performVoiceCommand(.restart)
            XCTAssertEqual(controller.stepIndex, 0)
            XCTAssertEqual(controller.progress, 1)
            XCTAssertFalse(controller.isPlaying)
            XCTAssertTrue(controller.started)
            XCTAssertFalse(controller.completed)
        }
        _ = controller.performVoiceCommand(.next)
        XCTAssertEqual(controller.stepIndex, 1)
        XCTAssertEqual(controller.progress, 0)
        XCTAssertTrue(controller.isPlaying)
    }

    @MainActor
    func testRestartPreservesPlacedARFlagsWithoutCreatingOrReplacingTheRenderer() {
        let controller = begunDart()
        controller.goToStep(3)
        // Controller-only fixture: this checks state routing, not camera tracking
        // or physical anchor stability, which need a real-device test.
        controller.isAR = true
        controller.placed = true
        controller.trackingReady = true
        controller.needsRescan = false
        controller.togglePositionLock()
        XCTAssertFalse(controller.positionLocked)

        _ = controller.performVoiceCommand(.restart)
        XCTAssertTrue(controller.isAR)
        XCTAssertTrue(controller.placed)
        XCTAssertTrue(controller.trackingReady)
        XCTAssertFalse(controller.needsRescan)
        XCTAssertFalse(controller.positionLocked)
        XCTAssertNil(controller.arView)
        XCTAssertEqual(controller.stepIndex, 0)
        XCTAssertEqual(controller.progress, 1)
        XCTAssertFalse(controller.isPlaying)
    }

    @MainActor
    func testRestartCannotResetPremiumProgressAfterAccessIsRevoked() throws {
        let store = LearningProgressStore(defaults: nil)
        let controller = LessonController(progressStore: store)
        controller.updateLibraryAccess(true)
        controller.selectLesson(.crane)
        controller.begin()
        controller.goToStep(9)
        controller.scrub(to: 0.4)
        controller.updateLibraryAccess(false)
        let saved = try XCTUnwrap(store.record(for: .crane))

        XCTAssertEqual(controller.performVoiceCommand(.restart),
                       .message("This lesson requires full library access."))
        XCTAssertFalse(controller.hasLessonAccess)
        XCTAssertFalse(controller.started)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.lesson, .crane)
        XCTAssertEqual(store.record(for: .crane), saved)
    }

    @MainActor
    func testSpeedCommandsAreIdempotentAndPersistWithoutChangingThePausedFold() {
        let store = LearningProgressStore(defaults: nil)
        let controller = begunDart(store: store)
        controller.goToStep(3)
        controller.scrub(to: 0.4)
        for _ in 0..<2 { _ = controller.performVoiceCommand(.slower) }
        XCTAssertTrue(controller.slowMotion, "Repeated Slower means half speed, not a toggle")
        XCTAssertEqual(controller.stepIndex, 3)
        XCTAssertEqual(controller.progress, 0.4, accuracy: 0.0001)
        XCTAssertFalse(controller.isPlaying)

        let restoredSlow = LessonController(progressStore: store)
        restoredSlow.continueLearning()
        XCTAssertTrue(restoredSlow.slowMotion)
        XCTAssertEqual(restoredSlow.stepIndex, 3)
        XCTAssertEqual(restoredSlow.progress, 0.4, accuracy: 0.0001)

        for _ in 0..<2 { _ = restoredSlow.performVoiceCommand(.normalSpeed) }
        XCTAssertFalse(restoredSlow.slowMotion)
        XCTAssertFalse(restoredSlow.isPlaying)
        let restoredNormal = LessonController(progressStore: store)
        restoredNormal.continueLearning()
        XCTAssertFalse(restoredNormal.slowMotion)
        XCTAssertEqual(restoredNormal.stepIndex, 3)
        XCTAssertEqual(restoredNormal.progress, 0.4, accuracy: 0.0001)
    }

    @MainActor
    func testNarrationUsesTheCurrentAuthoredStepAndPausesWithoutLosingItsPose() throws {
        let store = LearningProgressStore(defaults: nil)
        let controller = LessonController(progressStore: store)
        controller.updateLibraryAccess(true)
        controller.selectLesson(.crane)
        controller.begin()
        controller.goToStep(9)
        controller.scrub(to: 0.4)
        let help = try XCTUnwrap(FoldHelp.forStep(lesson: .crane, stepIndex: 9))

        for command in [VoiceCommand.readStep, .why, .explainSimply, .help] {
            controller.togglePlayback()
            XCTAssertTrue(controller.isPlaying)
            let response = controller.performVoiceCommand(command)
            guard case .narration(let text) = response else {
                XCTFail("Expected authored narration for \(command.rawValue)")
                continue
            }
            switch command {
            case .readStep:
                XCTAssertTrue(text.contains(controller.currentStep.title))
                XCTAssertTrue(text.contains(controller.currentStep.instruction))
            case .why:
                XCTAssertEqual(text, controller.currentStep.explanation)
            case .explainSimply:
                XCTAssertEqual(text, help.simplerInstruction)
            case .help:
                XCTAssertTrue(text.contains(help.simplerInstruction))
                XCTAssertTrue(text.contains(help.checkpoint))
                XCTAssertTrue(text.contains(help.commonMistake))
            default:
                XCTFail("Unexpected test command")
            }
            XCTAssertFalse(controller.isPlaying, command.rawValue)
            XCTAssertFalse(controller.completed, command.rawValue)
            XCTAssertEqual(controller.stepIndex, 9, command.rawValue)
            XCTAssertEqual(controller.progress, 0.4, accuracy: 0.0001)
            let saved = try XCTUnwrap(store.record(for: .crane))
            XCTAssertEqual(saved.stepIndex, 9)
            XCTAssertEqual(saved.progress, 0.4, accuracy: 0.0001)
        }
    }

    @MainActor
    func testUnplacedOrUnstableARBlocksMovementButStillAllowsStepExplanation() {
        let controller = begunDart()
        controller.goToStep(3)
        controller.scrub(to: 0.4)
        // Inject controller flags only; no simulated camera or anchor is made.
        controller.isAR = true
        for (placed, trackingReady, needsRescan) in [(false, false, false), (true, false, false), (true, true, true)] {
            controller.placed = placed
            controller.trackingReady = trackingReady
            controller.needsRescan = needsRescan
            for command in [VoiceCommand.next, .back, .replay, .restart, .resume] {
                XCTAssertEqual(controller.performVoiceCommand(command), .message("Place the paper and wait for stable tracking before playing a fold."))
                XCTAssertEqual(controller.stepIndex, 3, command.rawValue)
                XCTAssertEqual(controller.progress, 0.4, accuracy: 0.0001)
                XCTAssertFalse(controller.isPlaying, command.rawValue)
            }
            XCTAssertEqual(controller.performVoiceCommand(.why), .narration(controller.currentStep.explanation))
            XCTAssertTrue(controller.isAR)
            XCTAssertEqual(controller.placed, placed)
            XCTAssertEqual(controller.trackingReady, trackingReady)
            XCTAssertEqual(controller.needsRescan, needsRescan)
        }
        XCTAssertNil(controller.arView, "Voice commands must not create a camera renderer")
    }

    @MainActor
    func testResumeOnlyContinuesAnUnfinishedFoldAndDoesNotReplayOrAdvance() {
        let controller = begunDart()
        _ = controller.performVoiceCommand(.resume)
        XCTAssertEqual(controller.stepIndex, 0)
        XCTAssertEqual(controller.progress, 1)
        XCTAssertFalse(controller.isPlaying)

        controller.goToStep(3)
        controller.scrub(to: 0.4)
        XCTAssertEqual(controller.performVoiceCommand(.resume), .message("Continuing this fold."))
        XCTAssertTrue(controller.isPlaying)
        XCTAssertEqual(controller.stepIndex, 3)
        XCTAssertEqual(controller.progress, 0.4, accuracy: 0.0001)
        XCTAssertEqual(controller.performVoiceCommand(.resume), .message("The fold is already playing."))
        XCTAssertTrue(controller.isPlaying)
        XCTAssertEqual(controller.progress, 0.4, accuracy: 0.0001)

        _ = controller.performVoiceCommand(.pause)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.progress, 0.4, accuracy: 0.0001)
        controller.scrub(to: 1)
        _ = controller.performVoiceCommand(.resume)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.stepIndex, 3)
        XCTAssertEqual(controller.progress, 1)
    }

    @MainActor
    func testBackAndReplayRespectTheBeginningAndReuseExistingNavigationBehavior() {
        let controller = begunDart()
        _ = controller.performVoiceCommand(.back)
        _ = controller.performVoiceCommand(.replay)
        XCTAssertEqual(controller.stepIndex, 0)
        XCTAssertEqual(controller.progress, 1)
        XCTAssertFalse(controller.isPlaying)

        controller.goToStep(3)
        controller.scrub(to: 0.4)
        XCTAssertEqual(controller.performVoiceCommand(.replay), .message("Replaying this fold."))
        XCTAssertEqual(controller.stepIndex, 3)
        XCTAssertEqual(controller.progress, 0)
        XCTAssertTrue(controller.isPlaying)
        _ = controller.performVoiceCommand(.back)
        XCTAssertEqual(controller.stepIndex, 2)
        XCTAssertEqual(controller.progress, 1)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertFalse(controller.completed)
    }

    @MainActor
    private func begunDart(store: LearningProgressStore? = nil) -> LessonController {
        let controller = LessonController(progressStore: store ?? LearningProgressStore(defaults: nil))
        controller.selectLesson(.dart)
        controller.begin()
        return controller
    }
}
