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
    private func makeController() -> LessonController {
        let controller = LessonController(progressStore: LearningProgressStore(defaults: nil),
                                          practiceStore: PracticeProgressStore(defaults: nil))
        controller.selectLesson(.dart)
        controller.enterDartPractice()
        return controller
    }
}
