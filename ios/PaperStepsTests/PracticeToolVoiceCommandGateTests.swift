import XCTest
@testable import Protacta

final class PracticeToolVoiceCommandGateTests: XCTestCase {
    @MainActor
    func testQueuedCommandsCannotNavigateOrRequestNarrationBehindAPracticeTool() {
        let controller = makeController()
        controller.confirmPracticeAction(); controller.confirmPracticeAction()
        for command in [VoiceCommand.back, .replay, .restart, .readStep, .help, .why, .next] {
            var stops = 0, dispatches = 0
            let response = PracticeToolVoiceCommandGate.route(command, modalPresented: true, stopVoice: { stops += 1 }) {
                dispatches += 1
                return controller.performVoiceCommand($0)
            }
            XCTAssertNil(response, "A queued \(command) must produce neither narration nor feedback behind the modal")
            XCTAssertEqual(stops, 1, "Opening/routing behind a modal cancels listening, pending permission and narration through VoiceGuide.stop")
            XCTAssertEqual(dispatches, 0)
            XCTAssertEqual(controller.dartPractice.currentAction, 3)
            XCTAssertEqual(controller.dartPractice.confirmedActions, [1, 2])
            XCTAssertTrue(controller.isDartPractice)
            XCTAssertFalse(controller.practiceReferenceActive)
        }
    }

    @MainActor
    func testDismissedToolAllowsNavigationAndAReopenedToolBlocksItAgain() {
        let controller = makeController()
        controller.confirmPracticeAction(); controller.confirmPracticeAction()
        var stops = 0
        let previous = PracticeToolVoiceCommandGate.route(.back, modalPresented: false, stopVoice: { stops += 1 },
                                                          perform: controller.performVoiceCommand)
        XCTAssertEqual(previous, .message("Previous action. Compare your physical paper before continuing."))
        XCTAssertEqual(controller.dartPractice.currentAction, 2)
        XCTAssertEqual(stops, 0)

        let blockedReplay = PracticeToolVoiceCommandGate.route(.replay, modalPresented: true, stopVoice: { stops += 1 },
                                                               perform: controller.performVoiceCommand)
        XCTAssertNil(blockedReplay)
        XCTAssertTrue(controller.isDartPractice)
        XCTAssertFalse(controller.practiceReferenceActive)

        let replay = PracticeToolVoiceCommandGate.route(.replay, modalPresented: false, stopVoice: { stops += 1 },
                                                        perform: controller.performVoiceCommand)
        XCTAssertEqual(replay, .message("Showing this action in 3D. Your practice stays at the same action."))
        XCTAssertFalse(controller.isDartPractice)
        XCTAssertTrue(controller.practiceReferenceActive)
        XCTAssertEqual(controller.dartPractice.currentAction, 2)
        XCTAssertEqual(stops, 1)
    }

    @MainActor
    func testStopListeningCancelsBeforeNormalDispatchAndNeverDispatchesBehindAModal() {
        var events: [String] = []
        let response = PracticeToolVoiceCommandGate.route(.stopListening, modalPresented: false,
                                                          stopVoice: { events.append("stop") }) { _ in
            events.append("dispatch")
            return .message("Voice control is off.")
        }
        XCTAssertEqual(response, .message("Voice control is off."))
        XCTAssertEqual(events, ["stop", "dispatch"])
        events = []
        let blocked = PracticeToolVoiceCommandGate.route(.stopListening, modalPresented: true,
                                                         stopVoice: { events.append("stop") }) { _ in
            events.append("dispatch")
            return .message("Unexpected modal dispatch")
        }
        XCTAssertNil(blocked)
        XCTAssertEqual(events, ["stop"])
    }

    @MainActor
    func testOrdinaryConfirmationKeepsVoiceAdmissionUntilTheFinalAction() {
        let controller = makeController()
        var stops = 0
        for action in 1..<DartPracticeCourse.actions.count {
            XCTAssertEqual(controller.dartPractice.currentAction, action)
            DartPracticeVoiceBoundary.confirm(controller: controller, stopVoice: { stops += 1 })
            XCTAssertFalse(controller.dartPractice.completed)
            XCTAssertTrue(controller.canUseVoiceGuide)
        }
        XCTAssertEqual(controller.dartPractice.currentAction, 10)
        XCTAssertEqual(stops, 0)
    }

    @MainActor
    func testFinalConfirmationStopsBeforeMutationIncludingAfterViewingActionTenIn3D() {
        for viewedFinalReference in [false, true] {
            let controller = makeController()
            for _ in 1..<DartPracticeCourse.actions.count { controller.confirmPracticeAction() }
            if viewedFinalReference {
                controller.showPracticeActionIn3D()
                controller.scrub(to: 1)
                controller.enterDartPractice()
                XCTAssertEqual(controller.stepIndex, 10, "Final confirmation cannot rely on a change to this old 3D step")
            }
            XCTAssertTrue(controller.canUseVoiceGuide)
            var listening = true, stops = 0
            DartPracticeVoiceBoundary.confirm(controller: controller) {
                XCTAssertFalse(controller.dartPractice.completed, "Stop must run before confirmation removes the controls")
                XCTAssertFalse(controller.practiceProgressStore.load()?.completed ?? true)
                listening = false
                stops += 1
            }
            XCTAssertFalse(listening)
            XCTAssertEqual(stops, 1)
            XCTAssertTrue(controller.dartPractice.completed)
            XCTAssertFalse(controller.canUseVoiceGuide, "Pending/retry startup must reject a finished practice")
            XCTAssertTrue(controller.practiceProgressStore.load()?.completed ?? false)
        }
    }

    @MainActor
    func testFinishedPracticeRejectsQueuedCommandsAndDirectNavigationOrNarration() {
        let controller = makeController()
        for _ in 1...DartPracticeCourse.actions.count { controller.confirmPracticeAction() }
        // This completion bypasses the view's confirm callback. Live admission
        // still protects the state before SwiftUI's completion observer runs.
        XCTAssertFalse(controller.canUseVoiceGuide)
        for command in VoiceCommand.allCases {
            var stops = 0, dispatches = 0
            let response = PracticeToolVoiceCommandGate.route(command, modalPresented: false,
                practiceCompleted: controller.isDartPractice && controller.dartPractice.completed,
                stopVoice: { stops += 1 }) {
                    dispatches += 1
                    return controller.performVoiceCommand($0)
                }
            XCTAssertNil(response, command.rawValue)
            XCTAssertEqual(stops, 1, command.rawValue)
            XCTAssertEqual(dispatches, 0, command.rawValue)
            let direct = controller.performVoiceCommand(command)
            XCTAssertEqual(direct, command == .stopListening ? .message("Voice control is off.") :
                .message("Practice is finished. Use Start again with a new practice sheet to begin another attempt."))
            XCTAssertTrue(controller.isDartPractice, command.rawValue)
            XCTAssertTrue(controller.dartPractice.completed, command.rawValue)
            XCTAssertEqual(controller.dartPractice.confirmedActions, Array(1...10), command.rawValue)
            XCTAssertFalse(controller.practiceReferenceActive, command.rawValue)
            XCTAssertFalse(controller.slowMotion, command.rawValue)
        }
    }

    @MainActor
    func testVisibleRestartReopensPracticeAdmissionAndOrdinary3DRestartRemainsAvailable() {
        let controller = makeController()
        for _ in 1...DartPracticeCourse.actions.count { controller.confirmPracticeAction() }
        controller.restartDartPractice() // Same action as the visible Start again button.
        XCTAssertTrue(controller.canUseVoiceGuide)
        XCTAssertFalse(controller.dartPractice.completed)
        XCTAssertEqual(controller.dartPractice.currentAction, 1)
        XCTAssertTrue(controller.dartPractice.confirmedActions.isEmpty)
        var stops = 0
        let response = PracticeToolVoiceCommandGate.route(.readStep, modalPresented: false,
            practiceCompleted: controller.isDartPractice && controller.dartPractice.completed,
            stopVoice: { stops += 1 }, perform: controller.performVoiceCommand)
        let action = DartPracticeCourse.action(1)
        XCTAssertEqual(response, .narration("Action 1. \(action.title). \(action.instruction)"))
        XCTAssertEqual(stops, 0)

        for _ in 1...DartPracticeCourse.actions.count { controller.confirmPracticeAction() }
        controller.showPracticeActionIn3D()
        controller.scrub(to: 1)
        controller.next()
        XCTAssertFalse(controller.isDartPractice)
        XCTAssertTrue(controller.completed)
        XCTAssertTrue(controller.dartPractice.completed)
        XCTAssertTrue(controller.canUseVoiceGuide, "A finished ordinary 3D lesson keeps its explicit voice Restart")
        XCTAssertEqual(controller.performVoiceCommand(.restart),
                       .message("Lesson restarted with a flat sheet. Say Next fold when you are ready."))
        XCTAssertEqual(controller.stepIndex, 0)
        XCTAssertFalse(controller.completed)
        XCTAssertTrue(controller.dartPractice.completed, "Restarting 3D must not change separate learner confirmations")
    }

    @MainActor
    func testRestoredCompletedPracticeCannotStartVoiceUntilExplicitlyReopened() throws {
        let store = PracticeProgressStore(defaults: nil)
        let first = LessonController(progressStore: LearningProgressStore(defaults: nil), practiceStore: store)
        first.selectLesson(.dart); first.enterDartPractice()
        for _ in 1...DartPracticeCourse.actions.count { first.confirmPracticeAction() }
        first.shutdown()

        let restored = LessonController(progressStore: LearningProgressStore(defaults: nil), practiceStore: store)
        restored.selectLesson(.dart); restored.enterDartPractice()
        XCTAssertTrue(restored.dartPractice.completed)
        XCTAssertFalse(restored.canUseVoiceGuide)
        XCTAssertEqual(try XCTUnwrap(store.load()).confirmedActions, Array(1...10))
        restored.previousPracticeAction() // Explicit visible Previous action is also allowed.
        XCTAssertFalse(restored.dartPractice.completed)
        XCTAssertTrue(restored.canUseVoiceGuide)
        XCTAssertEqual(restored.dartPractice.confirmedActions, Array(1...9))
    }

    @MainActor
    private func makeController() -> LessonController {
        let controller = LessonController(progressStore: LearningProgressStore(defaults: nil),
                                          practiceStore: PracticeProgressStore(defaults: nil))
        controller.selectLesson(.dart)
        controller.enterDartPractice()
        return controller
    }
}
