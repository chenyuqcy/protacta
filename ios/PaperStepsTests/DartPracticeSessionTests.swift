import CoreGraphics
import Foundation
import XCTest
@testable import Protacta

final class DartPracticeSessionTests: XCTestCase {
    func testOnlyExplicitConfirmationsAdvanceAndCompleteAllTenActions() {
        var session = DartPracticeSession(startedAt: 100)
        XCTAssertEqual(session.currentAction, 1)
        XCTAssertFalse(session.completed)
        XCTAssertTrue(session.confirmedActions.isEmpty)
        for action in 1...10 {
            XCTAssertEqual(session.currentAction, action)
            XCTAssertTrue(session.confirmCurrentAction(at: 100 + Double(action)))
            XCTAssertEqual(session.confirmedActions, Array(1...action))
        }
        XCTAssertEqual(session.currentAction, 10)
        XCTAssertTrue(session.completed)
        XCTAssertFalse(session.confirmCurrentAction(at: 111))
        XCTAssertEqual(session.confirmedActions.count, 10)
    }

    func testMatchingOutlineRecordsEvidenceWithoutConfirmingOrAdvancing() {
        var session = atAction(2)
        XCTAssertTrue(session.recordCheck(result(state: 2, timestamp: 102), at: 102.1))
        XCTAssertEqual(session.currentAction, 2)
        XCTAssertEqual(session.confirmedActions, [1])
        XCTAssertFalse(session.completed)
        XCTAssertEqual(session.lastCheck?.outcome, .visibleMatch)
        XCTAssertEqual(session.checkSummaries.count, 1)
        XCTAssertTrue(session.confirmCurrentAction(at: 102.2))
        XCTAssertEqual(session.currentAction, 3)
        XCTAssertNil(session.lastCheck)
        XCTAssertEqual(session.checkSummaries.first?.referenceState, 2)
    }

    func testAdjustmentAndCannotJudgeLeaveManualConfirmationAvailable() {
        for outcome: PaperCheckOutcome in [.needsAdjustment, .cannotJudge] {
            var session = atAction(2)
            XCTAssertTrue(session.recordCheck(result(state: 2, outcome: outcome, timestamp: 102), at: 102.1))
            XCTAssertEqual(session.currentAction, 2)
            XCTAssertEqual(session.confirmedActions, [1])
            XCTAssertTrue(session.confirmCurrentAction(at: 102.2))
            XCTAssertEqual(session.currentAction, 3)
        }
    }

    func testWrongStepStaleFutureAndPreEntryChecksCannotReplaceEvidence() {
        var session = atAction(2)
        XCTAssertTrue(session.recordCheck(result(state: 2, timestamp: 102), at: 102.1))
        let invalid: [(DartOutlineCheckResult, TimeInterval)] = [
            (result(state: 3, timestamp: 102.2), 102.3),
            (result(state: 2, timestamp: 101.9), 102.3),
            (result(state: 2, timestamp: 100.9), 102.3),
            (result(state: 2, timestamp: 103), 106),
            (result(state: 2, timestamp: 108), 107),
            (result(state: 2, timestamp: .nan), 107)
        ]
        for (check, now) in invalid { XCTAssertFalse(session.recordCheck(check, at: now)) }
        XCTAssertEqual(session.lastCheck?.timestamp, 102)
        XCTAssertEqual(session.checkSummaries.count, 1)
        XCTAssertEqual(session.currentAction, 2)
    }

    func testUnsupportedStatesCannotBeApprovedByAnOutlineResult() {
        var session = atAction(7)
        XCTAssertFalse(session.recordCheck(result(state: 7, timestamp: 107), at: 107.1))
        XCTAssertNil(session.lastCheck)
        XCTAssertTrue(session.recordCheck(result(state: 7, outcome: .cannotJudge, timestamp: 107.2), at: 107.3))
        XCTAssertEqual(session.currentAction, 7)
        XCTAssertEqual(session.lastCheck?.outcome, .cannotJudge)
    }

    func testClearingLiveAnnotationsKeepsHistoricalTextButRejectsPendingOldResults() {
        var session = atAction(2)
        XCTAssertTrue(session.recordCheck(result(state: 2, timestamp: 102), at: 102.1))
        session.clearLiveCheck(at: 103)
        XCTAssertNil(session.lastCheck)
        XCTAssertEqual(session.checkSummaries.count, 1)
        XCTAssertEqual(session.currentAction, 2)
        XCTAssertEqual(session.confirmedActions, [1])
        XCTAssertFalse(session.recordCheck(result(state: 2, timestamp: 102.9), at: 103.1))
        XCTAssertTrue(session.recordCheck(result(state: 2, timestamp: 103.1), at: 103.2))
    }

    func testPreviousActionWithdrawsLaterConfirmationsAndRejectsOldCallbacksWhenRevisited() {
        var session = atAction(2)
        XCTAssertTrue(session.recordCheck(result(state: 2, timestamp: 102), at: 102.1))
        XCTAssertTrue(session.confirmCurrentAction(at: 102.2))
        XCTAssertTrue(session.previousAction(at: 103))
        XCTAssertEqual(session.currentAction, 2)
        XCTAssertEqual(session.confirmedActions, [1])
        XCTAssertNil(session.lastCheck)
        XCTAssertTrue(session.checkSummaries.isEmpty)
        XCTAssertFalse(session.recordCheck(result(state: 2, timestamp: 102.5), at: 103.1))
        XCTAssertTrue(session.recordCheck(result(state: 2, timestamp: 103.1), at: 103.2))
    }

    func testCompletionCanReopenFinalActionAndRestartStartsANewAttempt() {
        var session = atAction(10)
        XCTAssertTrue(session.confirmCurrentAction(at: 110))
        XCTAssertTrue(session.completed)
        XCTAssertFalse(session.recordCheck(result(state: 10, outcome: .cannotJudge, timestamp: 110.1), at: 110.2))
        XCTAssertTrue(session.previousAction(at: 111))
        XCTAssertFalse(session.completed)
        XCTAssertEqual(session.currentAction, 10)
        XCTAssertEqual(session.confirmedActions, Array(1...9))
        session.restart(at: 112)
        XCTAssertEqual(session.currentAction, 1)
        XCTAssertFalse(session.completed)
        XCTAssertTrue(session.confirmedActions.isEmpty)
        XCTAssertTrue(session.checkSummaries.isEmpty)
        XCTAssertNil(session.lastCheck)
        XCTAssertFalse(session.previousAction(at: 113))
    }

    func testLatestComparisonPerActionReplacesOlderSummaryAndHistoryIsBounded() {
        var session = DartPracticeSession(startedAt: 100)
        for action in 1...10 {
            let timestamp = 100 + Double(action)
            let outcome: PaperCheckOutcome = DartPracticeCourse.supportsOutlineCheck(state: action) ? .visibleMatch : .cannotJudge
            XCTAssertTrue(session.recordCheck(result(state: action, outcome: outcome, timestamp: timestamp), at: timestamp))
            XCTAssertTrue(session.recordCheck(result(state: action, outcome: .cannotJudge, timestamp: timestamp + 0.1), at: timestamp + 0.1))
            XCTAssertEqual(session.checkSummaries.count, action)
            XCTAssertTrue(session.confirmCurrentAction(at: timestamp + 0.2))
        }
        XCTAssertEqual(session.checkSummaries.count, 10)
        XCTAssertEqual(Set(session.checkSummaries.map(\.referenceState)).count, 10)
    }

    func testInMemoryStoreRestoresTeachingAndSummariesButNoLiveCameraEvidence() throws {
        let store = PracticeProgressStore(defaults: nil)
        var session = atAction(2)
        XCTAssertTrue(session.recordCheck(result(state: 2, timestamp: 102), at: 102.1))
        XCTAssertTrue(store.save(session))
        let restored = try XCTUnwrap(store.load(at: 200))
        XCTAssertEqual(restored.currentAction, 2)
        XCTAssertEqual(restored.confirmedActions, [1])
        XCTAssertEqual(restored.checkSummaries, session.checkSummaries)
        XCTAssertNil(restored.lastCheck)
        XCTAssertNil(PracticeProgressStore(defaults: nil).load(at: 200))
        store.clear()
        XCTAssertNil(store.load(at: 201))
    }

    func testDefaultsStoreSurvivesReloadWithoutPersistingImagesPointsOrTimestamps() throws {
        try withDefaults { defaults in
            let store = PracticeProgressStore(defaults: defaults)
            var session = atAction(2)
            XCTAssertTrue(session.recordCheck(result(state: 2, timestamp: 102), at: 102.1))
            XCTAssertTrue(store.save(session))
            let restored = try XCTUnwrap(PracticeProgressStore(defaults: defaults).load(at: 200))
            XCTAssertEqual(restored.checkSummaries, session.checkSummaries)
            XCTAssertNil(restored.lastCheck)
            let data = try XCTUnwrap(defaults.data(forKey: PracticeProgressStore.storageKey))
            let text = try XCTUnwrap(String(data: data, encoding: .utf8))
            for prohibited in ["mismatchedPoints", "timestamp", "quadrilateral", "registration", "image"] {
                XCTAssertFalse(text.contains(prohibited))
            }
        }
    }

    func testRevisionSchemaAndImpossibleConfirmationSequencesAreRejected() throws {
        try withDefaults { defaults in
            let store = PracticeProgressStore(defaults: defaults)
            XCTAssertTrue(store.save(atAction(3)))
            let original = try XCTUnwrap(defaults.data(forKey: PracticeProgressStore.storageKey))
            let changes: [(String, Any)] = [
                ("courseRevision", "obsolete-course"),
                ("schemaVersion", 999),
                ("currentAction", 0),
                ("currentAction", 11),
                ("completed", true),
                ("confirmedActions", [1, 1]),
                ("confirmedActions", [1, 3])
            ]
            for (key, value) in changes {
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
                object[key] = value
                defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: PracticeProgressStore.storageKey)
                XCTAssertNil(store.load(at: 200), key)
            }
        }
    }

    func testMalformedArchiveDoesNotLoadAndCompletedCourseCanRestore() throws {
        try withDefaults { defaults in
            let store = PracticeProgressStore(defaults: defaults)
            defaults.set(Data("not-json".utf8), forKey: PracticeProgressStore.storageKey)
            XCTAssertNil(store.load(at: 200))
            var session = atAction(10)
            XCTAssertTrue(session.confirmCurrentAction(at: 110))
            XCTAssertTrue(store.save(session))
            let restored = try XCTUnwrap(store.load(at: 200))
            XCTAssertTrue(restored.completed)
            XCTAssertEqual(restored.confirmedActions, Array(1...10))
            XCTAssertNil(restored.lastCheck)
        }
    }

    func testRestoredSessionRejectsCameraEvidenceFromBeforeRestoration() throws {
        let store = PracticeProgressStore(defaults: nil)
        XCTAssertTrue(store.save(atAction(2)))
        var restored = try XCTUnwrap(store.load(at: 200))
        XCTAssertFalse(restored.recordCheck(result(state: 2, timestamp: 199.9), at: 200.1))
        XCTAssertTrue(restored.recordCheck(result(state: 2, timestamp: 200.1), at: 200.2))
        XCTAssertEqual(restored.currentAction, 2)
        XCTAssertEqual(restored.confirmedActions, [1])
    }

    private func atAction(_ action: Int) -> DartPracticeSession {
        var session = DartPracticeSession(startedAt: 100)
        if action > 1 {
            for previous in 1..<action { XCTAssertTrue(session.confirmCurrentAction(at: 100 + Double(previous))) }
        }
        return session
    }

    private func result(state: Int, outcome: PaperCheckOutcome = .visibleMatch,
                        timestamp: TimeInterval) -> DartOutlineCheckResult {
        DartOutlineCheckResult(checkpointID: "C\(state)", referenceState: state, outcome: outcome,
                               message: "Draft visible-outline comparison; hidden creases are not assessed.",
                               mismatchedPoints: [CGPoint(x: 0.2, y: 0.3)], timestamp: timestamp)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "org.realitycore.protacta.tests.practice.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }
}
