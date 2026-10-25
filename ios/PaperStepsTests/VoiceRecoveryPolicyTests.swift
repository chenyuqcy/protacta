import XCTest
@testable import Foliafold

final class VoiceRecoveryPolicyTests: XCTestCase {
    private let failure = VoiceTaskFailure(NSError(domain: "TestSpeechTask", code: 1))

    func testSpeechTaskRecoveryHasThreeIncreasingDelaysThenStops() {
        var policy = VoiceRecoveryPolicy()
        XCTAssertEqual(policy.nextDelayNanoseconds(for: failure, canRecover: true), 750_000_000)
        XCTAssertEqual(policy.nextDelayNanoseconds(for: failure, canRecover: true), 1_500_000_000)
        XCTAssertEqual(policy.nextDelayNanoseconds(for: failure, canRecover: true), 3_000_000_000)
        for _ in 0..<10 {
            XCTAssertNil(policy.nextDelayNanoseconds(for: failure, canRecover: true))
        }
        XCTAssertEqual(policy.attempts, 3)
        XCTAssertEqual(policy.lastFailure, failure)
    }

    func testInvalidPermissionsOrForegroundStateDoNotSpendOrScheduleARetry() {
        var policy = VoiceRecoveryPolicy()
        XCTAssertNil(policy.nextDelayNanoseconds(for: failure, canRecover: false))
        XCTAssertEqual(policy.attempts, 0)
        XCTAssertEqual(policy.lastFailure, failure)
    }

    func testNewTaskErrorsDoNotEarnAnUnlimitedRetryBudget() {
        var policy = VoiceRecoveryPolicy()
        for code in 1...3 {
            let newTaskFailure = VoiceTaskFailure(NSError(domain: "TestSpeechTask", code: code))
            XCTAssertNotNil(policy.nextDelayNanoseconds(for: newTaskFailure, canRecover: true))
        }
        XCTAssertNil(policy.nextDelayNanoseconds(for: failure, canRecover: true))
        // Production resets only for an explicit activation or accepted command.
        policy.reset()
        XCTAssertEqual(policy.attempts, 0)
        XCTAssertNil(policy.lastFailure)
        XCTAssertEqual(policy.nextDelayNanoseconds(for: failure, canRecover: true), 750_000_000)
    }

    func testErrorDiagnosticsKeepDomainAndCodeWithoutUserInfoOrTranscript() {
        let error = NSError(domain: "TestSpeechTask", code: 42,
                            userInfo: [NSLocalizedDescriptionKey: "Transient details"])
        let diagnostics = VoiceTaskFailure(error)
        XCTAssertEqual(diagnostics.domain, "TestSpeechTask")
        XCTAssertEqual(diagnostics.code, 42)
    }
}
