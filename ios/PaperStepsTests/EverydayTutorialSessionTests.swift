import Foundation
import XCTest
@testable import Protacta

final class EverydayTutorialSessionTests: XCTestCase {
    func testEveryCourseCompletesOnlyByConfirmingEachActionExactlyOnce() {
        for id in EverydayTutorialID.allCases {
            var session = EverydayTutorialSession(courseID: id)
            let count = EverydayTutorialCourse.course(id).actions.count
            XCTAssertEqual(session.currentAction, 1)
            XCTAssertFalse(session.completed)
            XCTAssertTrue(session.confirmedActions.isEmpty)
            XCTAssertFalse(session.previousAction())
            for action in 1...count {
                XCTAssertEqual(session.currentAction, action)
                XCTAssertTrue(session.confirmCurrentAction())
                XCTAssertEqual(session.confirmedActions, Array(1...action))
                XCTAssertEqual(session.confirmedCount, action)
            }
            XCTAssertEqual(session.currentAction, count)
            XCTAssertTrue(session.completed)
            XCTAssertFalse(session.confirmCurrentAction())
            XCTAssertEqual(session.confirmedCount, count)
        }
    }

    func testPreviousWithdrawsLaterConfirmationsAndReconfirmationDoesNotSkip() {
        for id in EverydayTutorialID.allCases {
            var session = EverydayTutorialSession(courseID: id)
            XCTAssertTrue(session.confirmCurrentAction())
            XCTAssertTrue(session.confirmCurrentAction())
            XCTAssertEqual(session.currentAction, 3)
            XCTAssertTrue(session.previousAction())
            XCTAssertEqual(session.currentAction, 2)
            XCTAssertEqual(session.confirmedActions, [1])
            XCTAssertTrue(session.confirmCurrentAction())
            XCTAssertEqual(session.currentAction, 3)
            XCTAssertEqual(session.confirmedActions, [1, 2])
            XCTAssertFalse(session.completed)
        }
    }

    func testCompletedCourseCanReopenLastActionAndRestartClearsOnlyItsAttempt() {
        var session = completed(.towel)
        XCTAssertTrue(session.previousAction())
        XCTAssertEqual(session.currentAction, 3)
        XCTAssertEqual(session.confirmedActions, [1, 2])
        XCTAssertFalse(session.completed)
        XCTAssertTrue(session.confirmCurrentAction())
        XCTAssertTrue(session.completed)
        session.restart()
        XCTAssertEqual(session.courseID, .towel)
        XCTAssertEqual(session.currentAction, 1)
        XCTAssertFalse(session.completed)
        XCTAssertTrue(session.confirmedActions.isEmpty)
    }

    func testExplicitNilStoresAreIsolatedButAppFactoryIsShared() throws {
        let first = EverydayTutorialProgressStore(defaults: nil)
        var shirt = EverydayTutorialSession(courseID: .tShirt)
        XCTAssertTrue(shirt.confirmCurrentAction())
        XCTAssertTrue(first.save(shirt))
        XCTAssertEqual(try XCTUnwrap(first.load(courseID: .tShirt)).currentAction, 2)
        XCTAssertNil(EverydayTutorialProgressStore(defaults: nil).load(courseID: .tShirt))
        XCTAssertTrue(EverydayTutorialProgressStore.appDefault() === EverydayTutorialProgressStore.appDefault())
    }

    func testAllFiveCourseRecordsRestoreIndependentlyAcrossStoreInstances() throws {
        try withDefaults { defaults in
            let original = EverydayTutorialProgressStore(defaults: defaults)
            for id in EverydayTutorialID.allCases {
                var session = EverydayTutorialSession(courseID: id)
                XCTAssertTrue(session.confirmCurrentAction())
                XCTAssertTrue(original.save(session))
            }
            let restored = EverydayTutorialProgressStore(defaults: defaults)
            for id in EverydayTutorialID.allCases {
                let session = try XCTUnwrap(restored.load(courseID: id))
                XCTAssertEqual(session.courseID, id)
                XCTAssertEqual(session.currentAction, 2)
                XCTAssertEqual(session.confirmedActions, [1])
                XCTAssertFalse(session.completed)
            }
            restored.clear(courseID: .towel)
            XCTAssertNil(restored.load(courseID: .towel))
            XCTAssertNotNil(restored.load(courseID: .tShirt))
            let data = try XCTUnwrap(defaults.data(forKey: EverydayTutorialProgressStore.storageKey))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual((object["records"] as? [String: Any])?.count, 4)
        }
    }

    func testCompletionAndReopenedConfirmationRestoreWithoutSkipping() throws {
        let store = EverydayTutorialProgressStore(defaults: nil)
        XCTAssertTrue(store.save(completed(.fourInHand)))
        var restored = try XCTUnwrap(store.load(courseID: .fourInHand))
        XCTAssertTrue(restored.completed)
        XCTAssertEqual(restored.currentAction, 7)
        XCTAssertEqual(restored.confirmedActions, Array(1...7))
        XCTAssertTrue(restored.previousAction())
        XCTAssertTrue(store.save(restored))
        var reopened = try XCTUnwrap(store.load(courseID: .fourInHand))
        XCTAssertFalse(reopened.completed)
        XCTAssertEqual(reopened.currentAction, 7)
        XCTAssertEqual(reopened.confirmedActions, Array(1...6))
        XCTAssertTrue(reopened.confirmCurrentAction())
        XCTAssertTrue(reopened.completed)
    }

    func testWrongRevisionOrMalformedCourseDoesNotEraseOtherCourseSaves() throws {
        try withDefaults { defaults in
            let store = EverydayTutorialProgressStore(defaults: defaults)
            XCTAssertTrue(store.save(completed(.towel)))
            XCTAssertTrue(store.save(completed(.squareKnot)))
            let original = try XCTUnwrap(defaults.data(forKey: EverydayTutorialProgressStore.storageKey))
            for damaged in [false, true] {
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
                var records = try XCTUnwrap(object["records"] as? [String: Any])
                if damaged {
                    records[EverydayTutorialID.towel.rawValue] = "corrupt course"
                } else {
                    var towel = try XCTUnwrap(records[EverydayTutorialID.towel.rawValue] as? [String: Any])
                    towel["courseRevision"] = "obsolete"
                    records[EverydayTutorialID.towel.rawValue] = towel
                }
                object["records"] = records
                defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: EverydayTutorialProgressStore.storageKey)
                XCTAssertNil(store.load(courseID: .towel))
                XCTAssertTrue(try XCTUnwrap(store.load(courseID: .squareKnot)).completed)
            }
        }
    }

    func testImpossibleStepsConfirmationsSchemaAndMismatchedCourseAreRejected() throws {
        try withDefaults { defaults in
            let store = EverydayTutorialProgressStore(defaults: defaults)
            var shirt = EverydayTutorialSession(courseID: .tShirt)
            XCTAssertTrue(shirt.confirmCurrentAction())
            XCTAssertTrue(store.save(shirt))
            let original = try XCTUnwrap(defaults.data(forKey: EverydayTutorialProgressStore.storageKey))
            let changes: [(String, Any)] = [("currentAction", 0), ("currentAction", 7), ("completed", true),
                                          ("confirmedActions", [1, 1]), ("confirmedActions", [1, 3]),
                                          ("courseID", EverydayTutorialID.towel.rawValue)]
            for (field, value) in changes {
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
                var records = try XCTUnwrap(object["records"] as? [String: Any])
                var record = try XCTUnwrap(records[EverydayTutorialID.tShirt.rawValue] as? [String: Any])
                record[field] = value
                records[EverydayTutorialID.tShirt.rawValue] = record
                object["records"] = records
                defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: EverydayTutorialProgressStore.storageKey)
                XCTAssertNil(store.load(courseID: .tShirt), field)
            }
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
            object["schemaVersion"] = 999
            defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: EverydayTutorialProgressStore.storageKey)
            XCTAssertNil(store.load(courseID: .tShirt))
        }
    }

    func testRecordsStayBoundedAndContainOnlyDeclaredTeachingProgress() throws {
        try withDefaults { defaults in
            let store = EverydayTutorialProgressStore(defaults: defaults)
            for id in EverydayTutorialID.allCases { XCTAssertTrue(store.save(completed(id))) }
            let data = try XCTUnwrap(defaults.data(forKey: EverydayTutorialProgressStore.storageKey))
            XCTAssertLessThan(data.count, 64 * 1024)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let records = try XCTUnwrap(object["records"] as? [String: [String: Any]])
            XCTAssertEqual(records.count, 5)
            for record in records.values {
                XCTAssertEqual(Set(record.keys), Set(["courseID", "courseRevision", "currentAction", "completed", "confirmedActions", "updatedAt"]))
                XCTAssertNotNil(record["updatedAt"] as? NSNumber)
                XCTAssertLessThanOrEqual((record["confirmedActions"] as? [Int])?.count ?? 100, 7)
            }
        }
    }

    func testRecentPracticeOrdersByLatestSaveAndExcludesCompletedCourses() throws {
        var timestamp = Date(timeIntervalSince1970: 1_000)
        let store = EverydayTutorialProgressStore(defaults: nil, now: { timestamp })
        var shirt = EverydayTutorialSession(courseID: .tShirt)
        XCTAssertTrue(shirt.confirmCurrentAction())
        XCTAssertTrue(store.save(shirt))
        timestamp = Date(timeIntervalSince1970: 2_000)
        XCTAssertTrue(store.save(EverydayTutorialSession(courseID: .towel)))
        timestamp = Date(timeIntervalSince1970: 3_000)
        XCTAssertTrue(store.save(completed(.flatBedsheet)))

        XCTAssertEqual(store.inProgress(limit: 5).map(\.courseID), [.towel, .tShirt])
        XCTAssertEqual(store.inProgress(limit: 1).map(\.courseID), [.towel])
        let shirtBefore = try XCTUnwrap(store.inProgress(limit: 5).last)
        XCTAssertEqual(shirtBefore.currentAction, 2)
        XCTAssertEqual(shirtBefore.updatedAt, Date(timeIntervalSince1970: 1_000))

        timestamp = Date(timeIntervalSince1970: 4_000)
        XCTAssertTrue(store.save(shirt))
        XCTAssertEqual(store.inProgress(limit: 5).map(\.courseID), [.tShirt, .towel])
        XCTAssertEqual(store.inProgress(limit: 1).first?.updatedAt, timestamp)
        XCTAssertEqual(try XCTUnwrap(store.load(courseID: .tShirt)).confirmedActions, [1],
                       "Updating recency must not change the learner's confirmations")
    }

    func testLegacyRecordsWithoutDatesStillResumeAndSortBehindNewPractice() throws {
        try withDefaults { defaults in
            // This is the schema written before the homepage stored recency.
            let records: [String: Any] = [
                EverydayTutorialID.towel.rawValue: [
                    "courseID": EverydayTutorialID.towel.rawValue,
                    "courseRevision": EverydayTutorialCourse.course(.towel).revision,
                    "currentAction": 2, "completed": false, "confirmedActions": [1]
                ],
                EverydayTutorialID.tShirt.rawValue: [
                    "courseID": EverydayTutorialID.tShirt.rawValue,
                    "courseRevision": EverydayTutorialCourse.course(.tShirt).revision,
                    "currentAction": 3, "completed": false, "confirmedActions": [1, 2]
                ]
            ]
            let archive: [String: Any] = ["schemaVersion": 1, "records": records]
            defaults.set(try JSONSerialization.data(withJSONObject: archive),
                         forKey: EverydayTutorialProgressStore.storageKey)
            let store = EverydayTutorialProgressStore(defaults: defaults,
                now: { Date(timeIntervalSince1970: 5_000) })
            let shirt = try XCTUnwrap(store.load(courseID: .tShirt))
            XCTAssertEqual(shirt.currentAction, 3)
            XCTAssertEqual(shirt.confirmedActions, [1, 2])
            XCTAssertEqual(try XCTUnwrap(store.load(courseID: .towel)).currentAction, 2)
            XCTAssertEqual(store.inProgress(limit: 5).map(\.courseID), [.tShirt, .towel])
            XCTAssertTrue(store.inProgress(limit: 5).allSatisfy { $0.updatedAt == .distantPast })

            XCTAssertTrue(store.save(EverydayTutorialSession(courseID: .squareKnot)))
            let relaunched = EverydayTutorialProgressStore(defaults: defaults)
            XCTAssertEqual(relaunched.inProgress(limit: 5).map(\.courseID), [.squareKnot, .tShirt, .towel])
            XCTAssertEqual(try XCTUnwrap(relaunched.load(courseID: .tShirt)).confirmedActions, [1, 2])
        }
    }

    func testEqualRecencyHasStableOrderingIndependentOfSaveOrder() {
        let expected: [EverydayTutorialID] = [.flatBedsheet, .fourInHand, .squareKnot, .tShirt, .towel]
        for order in [expected, Array(expected.reversed())] {
            let store = EverydayTutorialProgressStore(defaults: nil,
                now: { Date(timeIntervalSince1970: 6_000) })
            for id in order { XCTAssertTrue(store.save(EverydayTutorialSession(courseID: id))) }
            XCTAssertEqual(store.inProgress(limit: 100).map(\.courseID), expected)
            XCTAssertEqual(store.inProgress(limit: 2).map(\.courseID), Array(expected.prefix(2)))
        }
    }

    func testNonpositiveRecentLimitReturnsNoCardsWithoutDeletingProgress() throws {
        let store = EverydayTutorialProgressStore(defaults: nil)
        var session = EverydayTutorialSession(courseID: .towel)
        XCTAssertTrue(session.confirmCurrentAction())
        XCTAssertTrue(store.save(session))
        for limit in [Int.min, -1, 0] { XCTAssertTrue(store.inProgress(limit: limit).isEmpty) }
        XCTAssertEqual(try XCTUnwrap(store.load(courseID: .towel)).currentAction, 2)
        XCTAssertEqual(store.inProgress(limit: 1).map(\.courseID), [.towel])
    }

    private func completed(_ id: EverydayTutorialID) -> EverydayTutorialSession {
        var session = EverydayTutorialSession(courseID: id)
        for _ in EverydayTutorialCourse.course(id).actions { XCTAssertTrue(session.confirmCurrentAction()) }
        return session
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "org.realitycore.protacta.tests.everyday.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }
}
