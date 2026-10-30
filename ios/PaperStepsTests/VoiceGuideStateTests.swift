import XCTest
@testable import Protacta

final class VoiceGuideStateTests: XCTestCase {
    @MainActor
    func testUnavailableVoiceFeedbackRemainsVisibleWhileDisabledAndStopClearsIt() async throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This unavailable-input check must never request physical microphone permission.")
        #else
        let voice = VoiceGuide()
        XCTAssertNil(voice.feedbackMessage)
        await voice.startListening()
        XCTAssertFalse(voice.isEnabled)
        XCTAssertFalse(voice.isListening)
        XCTAssertNotNil(voice.feedbackMessage)
        XCTAssertEqual(voice.feedbackMessage, voice.status)
        let failure = voice.feedbackMessage
        voice.contextDidChange()
        XCTAssertEqual(voice.feedbackMessage, failure, "Moving to another step does not repair unavailable voice input")
        voice.stop()
        XCTAssertNil(voice.feedbackMessage)
        #endif
    }

    func testStablePartialDispatchesOnceEvenWhenFinalResultArrives() throws {
        var gate = VoiceUtteranceGate()
        gate.update("Next fold")
        let candidate = try XCTUnwrap(gate.candidate)
        XCTAssertEqual(gate.consumeStable(candidate), .next)
        XCTAssertNil(gate.consumeFinal("Next fold"))
        XCTAssertNil(gate.consumeStable(candidate))
    }

    func testChangedPartialInvalidatesEarlierCommandWithoutWaitingForFinal() throws {
        var gate = VoiceUtteranceGate()
        gate.update("Next fold")
        let candidate = try XCTUnwrap(gate.candidate)
        gate.update("Next fold is difficult")
        XCTAssertNil(gate.consumeStable(candidate))
        XCTAssertNil(gate.candidate)
        XCTAssertNil(gate.consumeFinal("Next fold is difficult"))
    }

    func testReturningToSameTextDoesNotValidateAnOldTimer() throws {
        var gate = VoiceUtteranceGate()
        gate.update("Pause")
        let old = try XCTUnwrap(gate.candidate)
        gate.update("Pause the")
        gate.update("Pause")
        XCTAssertNil(gate.consumeStable(old))
        XCTAssertEqual(gate.consumeStable(try XCTUnwrap(gate.candidate)), .pause)
    }

    func testUnchangedPartialDoesNotResetItsStabilityRevision() throws {
        var gate = VoiceUtteranceGate()
        XCTAssertTrue(gate.update("Show me again"))
        let candidate = try XCTUnwrap(gate.candidate)
        XCTAssertFalse(gate.update("Show me again"))
        XCTAssertEqual(gate.candidate, candidate)
        XCTAssertEqual(gate.consumeStable(candidate), .replay)
    }

    func testFinalUsesLatestFullPhraseAndClosesSessionEvenWhenUnsupported() throws {
        var gate = VoiceUtteranceGate()
        gate.update("Next fold")
        let old = try XCTUnwrap(gate.candidate)
        XCTAssertNil(gate.consumeFinal("Next fold and then go back"))
        XCTAssertTrue(gate.isConsumed)
        XCTAssertNil(gate.consumeStable(old))
        XCTAssertNil(gate.consumeFinal("Next fold"))
    }

    func testFreshSessionCanRepeatSameCommand() {
        var first = VoiceUtteranceGate()
        XCTAssertEqual(first.consumeFinal("Show me again"), .replay)
        var second = VoiceUtteranceGate()
        XCTAssertEqual(second.consumeFinal("Show me again"), .replay)
    }
    func testRestartCannotDispatchTwiceFromStableAndFinalRevisions() throws {
        var gate = VoiceUtteranceGate()
        gate.update("Restart lesson")
        let candidate = try XCTUnwrap(gate.candidate)
        XCTAssertEqual(gate.consumeStable(candidate), .restart)
        XCTAssertNil(gate.consumeFinal("Restart lesson"))
        XCTAssertFalse(gate.update("Next step"))
    }

    func testRestartRevisionWithNegationDoesNotResetTheLesson() throws {
        var gate = VoiceUtteranceGate()
        gate.update("Restart lesson")
        let candidate = try XCTUnwrap(gate.candidate)
        gate.update("Do not restart lesson")
        XCTAssertNil(gate.consumeStable(candidate))
        XCTAssertNil(gate.consumeFinal("Do not restart lesson"))
    }

}
