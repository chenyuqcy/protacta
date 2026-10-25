import Foundation
import XCTest
@testable import Protacta

/// Uses isolated defaults suites or nil; never changes production learning
/// history, purchases or spatial placement, and never creates an AR session.
final class LearningProgressStoreTests: XCTestCase {
    @MainActor
    func testPartialFoldAndPreferencesSurviveAStoreReload() throws {
        try withDefaults { defaults in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = LearningProgressStore(defaults: defaults, now: { date })
            XCTAssertTrue(store.save(lesson: .crane, stepIndex: 9, progress: 0.375,
                                     completed: false, slowMotion: true, hintsVisible: false))
            let saved = try XCTUnwrap(store.record(for: .crane))
            let reloaded = LearningProgressStore(defaults: defaults)
            XCTAssertEqual(reloaded.record(for: .crane), saved)
            XCTAssertEqual(saved.lessonID, "crane")
            XCTAssertEqual(saved.stepIndex, 9)
            XCTAssertEqual(saved.progress, 0.375)
            XCTAssertFalse(saved.completed)
            XCTAssertTrue(saved.slowMotion)
            XCTAssertFalse(saved.hintsVisible)
            XCTAssertEqual(saved.updatedAt, date)
            XCTAssertEqual(saved.contentRevision.count, 64)
            XCTAssertEqual(reloaded.latestLesson, .crane)
        }
    }

    @MainActor
    func testLatestLessonFollowsSaveDateAndRemovingOneKeepsOthers() throws {
        try withDefaults { defaults in
            var date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = LearningProgressStore(defaults: defaults, now: { date })
            XCTAssertTrue(save(.dart, into: store))
            date = date.addingTimeInterval(60)
            XCTAssertTrue(save(.fox, into: store))
            XCTAssertEqual(store.latestLesson, .fox)
            let dart = try XCTUnwrap(store.record(for: .dart))

            store.remove(lesson: .fox)
            let reloaded = LearningProgressStore(defaults: defaults)
            XCTAssertNil(reloaded.record(for: .fox))
            XCTAssertEqual(reloaded.record(for: .dart), dart)
            XCTAssertEqual(reloaded.latestLesson, .dart)
            reloaded.remove(lesson: .crane)
            XCTAssertEqual(reloaded.record(for: .dart), dart)
            reloaded.remove(lesson: .dart)
            XCTAssertNil(LearningProgressStore(defaults: defaults).latestLesson)
        }
    }

    @MainActor
    func testNilDefaultsKeepsSessionProgressWithoutPersistingToAnotherStore() throws {
        let store = LearningProgressStore(defaults: nil)
        XCTAssertTrue(save(.dart, into: store))
        XCTAssertTrue(save(.fox, into: store))
        XCTAssertNotNil(store.record(for: .dart))
        XCTAssertNotNil(store.record(for: .fox))
        store.remove(lesson: .fox)
        XCTAssertNotNil(store.record(for: .dart))
        XCTAssertNil(store.record(for: .fox))
        let fresh = LearningProgressStore(defaults: nil)
        XCTAssertNil(fresh.record(for: .dart))
        XCTAssertNil(fresh.latestLesson)
    }

    @MainActor
    func testInvalidSaveCannotReplaceTheLastValidRecord() throws {
        try withDefaults { defaults in
            var date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = LearningProgressStore(defaults: defaults, now: { date })
            XCTAssertTrue(save(.dart, into: store))
            let saved = try XCTUnwrap(store.record(for: .dart))
            let lastStep = OrigamiLesson.dart.lastStep
            let invalid: [(Int, Float, Bool)] = [
                (-1, 1, false), (.max, 1, false), (lastStep + 1, 1, false),
                (2, -0.01, false), (2, 1.01, false), (2, .nan, false),
                (2, .infinity, false), (2, -.infinity, false),
                (0, 0.5, false), (2, 1, true), (lastStep, 0.99, true)
            ]
            for (index, progress, completed) in invalid {
                XCTAssertFalse(store.save(lesson: .dart, stepIndex: index, progress: progress,
                                          completed: completed, slowMotion: false, hintsVisible: true))
                XCTAssertEqual(store.record(for: .dart), saved)
            }
            for interval in [Double.nan, .infinity, -.infinity] {
                date = Date(timeIntervalSinceReferenceDate: interval)
                XCTAssertFalse(save(.dart, into: store))
                XCTAssertEqual(store.record(for: .dart), saved)
            }
        }
    }

    @MainActor
    func testBoundaryStepsAndARealCompletedLessonCanBeRestored() throws {
        try withDefaults { defaults in
            let store = LearningProgressStore(defaults: defaults)
            XCTAssertTrue(store.save(lesson: .dart, stepIndex: 0, progress: 1,
                                     completed: false, slowMotion: false, hintsVisible: true))
            XCTAssertEqual(store.record(for: .dart)?.stepIndex, 0)
            XCTAssertTrue(store.save(lesson: .dart, stepIndex: OrigamiLesson.dart.lastStep, progress: 0,
                                     completed: false, slowMotion: false, hintsVisible: true))
            XCTAssertEqual(store.record(for: .dart)?.progress, 0)
            XCTAssertTrue(store.save(lesson: .dart, stepIndex: OrigamiLesson.dart.lastStep, progress: 1,
                                     completed: true, slowMotion: true, hintsVisible: false))
            let restored = try XCTUnwrap(LearningProgressStore(defaults: defaults).record(for: .dart))
            XCTAssertTrue(restored.completed)
            XCTAssertEqual(restored.stepIndex, OrigamiLesson.dart.lastStep)
            XCTAssertEqual(restored.progress, 1)
        }
    }

    @MainActor
    func testUnknownArchiveVersionAndCorruptDataAreIgnored() throws {
        try withDefaults { defaults in
            let store = LearningProgressStore(defaults: defaults)
            XCTAssertTrue(save(.dart, into: store))
            var archive = try readArchive(defaults)
            archive["schemaVersion"] = 999
            try writeArchive(archive, to: defaults)
            XCTAssertNil(store.record(for: .dart))
            XCTAssertNil(store.latestLesson)
            defaults.set(Data("not a JSON archive".utf8), forKey: LearningProgressStore.storageKey)
            XCTAssertNil(store.record(for: .dart))
            XCTAssertNil(store.latestLesson)
            XCTAssertTrue(save(.fox, into: store))
            XCTAssertNotNil(LearningProgressStore(defaults: defaults).record(for: .fox))
        }
    }

    @MainActor
    func testStaleMismatchedUnknownAndMalformedRecordsDoNotHideValidLessons() throws {
        try withDefaults { defaults in
            let store = LearningProgressStore(defaults: defaults)
            for lesson in [OrigamiLesson.crane, .dart, .fox, .star, .frog] {
                XCTAssertTrue(save(lesson, into: store))
            }
            let validDart = try XCTUnwrap(store.record(for: .dart))
            var archive = try readArchive(defaults)
            var records = try XCTUnwrap(archive["records"] as? [String: Any])
            var crane = try XCTUnwrap(records["crane"] as? [String: Any])
            crane["contentRevision"] = "an obsolete lesson fingerprint"
            records["crane"] = crane
            var fox = try XCTUnwrap(records["fox"] as? [String: Any])
            fox["lessonID"] = "crane"
            records["fox"] = fox
            var star = try XCTUnwrap(records["star"] as? [String: Any])
            star["stepIndex"] = OrigamiLesson.star.lastStep + 1
            records["star"] = star
            var frog = try XCTUnwrap(records["frog"] as? [String: Any])
            frog["progress"] = "NaN"
            records["frog"] = frog
            records["not-a-supported-lesson"] = records["dart"]
            archive["records"] = records
            try writeArchive(archive, to: defaults)

            let reloaded = LearningProgressStore(defaults: defaults)
            for lesson in [OrigamiLesson.crane, .fox, .star, .frog] {
                XCTAssertNil(reloaded.record(for: lesson), lesson.rawValue)
            }
            XCTAssertEqual(reloaded.record(for: .dart), validDart)
            XCTAssertEqual(reloaded.latestLesson, .dart)
        }
    }

    @MainActor
    func testArchiveContainsOnlyLearningStateAndPerLessonRevisions() throws {
        try withDefaults { defaults in
            let store = LearningProgressStore(defaults: defaults)
            XCTAssertTrue(save(.crane, into: store))
            XCTAssertTrue(save(.dart, into: store))
            let archive = try readArchive(defaults)
            XCTAssertEqual(Set(archive.keys), ["schemaVersion", "records"])
            let records = try XCTUnwrap(archive["records"] as? [String: Any])
            let crane = try XCTUnwrap(records["crane"] as? [String: Any])
            XCTAssertEqual(Set(crane.keys), ["lessonID", "contentRevision", "stepIndex", "progress", "completed", "slowMotion", "hintsVisible", "updatedAt"])
            XCTAssertNotEqual(store.record(for: .crane)?.contentRevision, store.record(for: .dart)?.contentRevision)
        }
    }

    @MainActor
    private func save(_ lesson: OrigamiLesson, into store: LearningProgressStore) -> Bool {
        store.save(lesson: lesson, stepIndex: 1, progress: 0.5,
                   completed: false, slowMotion: false, hintsVisible: true)
    }

    @MainActor
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "org.realitycore.protacta.prototype.tests.learning.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @MainActor
    private func readArchive(_ defaults: UserDefaults) throws -> [String: Any] {
        let data = try XCTUnwrap(defaults.data(forKey: LearningProgressStore.storageKey))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @MainActor
    private func writeArchive(_ archive: [String: Any], to defaults: UserDefaults) throws {
        defaults.set(try JSONSerialization.data(withJSONObject: archive), forKey: LearningProgressStore.storageKey)
    }
}
