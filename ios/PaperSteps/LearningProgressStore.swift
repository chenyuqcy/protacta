import CryptoKit
import Foundation

/// Local learning state only. Access rights and AR placement must be restored
/// separately by the controller; neither belongs in this archive.
@MainActor
final class LearningProgressStore {
    struct Record: Codable, Equatable {
        let lessonID: String
        let contentRevision: String
        let stepIndex: Int
        let progress: Float
        let completed: Bool
        let slowMotion: Bool
        let hintsVisible: Bool
        let updatedAt: Date
    }

    static let storageKey = "org.realitycore.protacta.prototype.learningProgress"
    private static let schemaVersion = 1
    private let defaults: UserDefaults?
    private let now: () -> Date
    private var memoryRecords: [String: Record] = [:]

    /// Pass nil for a session-only store, or an isolated defaults suite in tests.
    init(defaults: UserDefaults? = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    func record(for lesson: OrigamiLesson) -> Record? {
        loadRecords()[lesson.rawValue]
    }

    var latestLesson: OrigamiLesson? {
        let latest = loadRecords().values.max { left, right in
            if left.updatedAt != right.updatedAt { return left.updatedAt < right.updatedAt }
            return left.lessonID < right.lessonID
        }
        return latest.flatMap { OrigamiLesson(rawValue: $0.lessonID) }
    }

    @discardableResult
    func save(lesson: OrigamiLesson, stepIndex: Int, progress: Float, completed: Bool,
              slowMotion: Bool, hintsVisible: Bool) -> Bool {
        let record = Record(lessonID: lesson.rawValue,
                            contentRevision: Self.contentRevisions[lesson.rawValue] ?? "",
                            stepIndex: stepIndex, progress: progress, completed: completed,
                            slowMotion: slowMotion, hintsVisible: hintsVisible, updatedAt: now())
        guard Self.isValid(record, for: lesson) else { return false }
        var records = loadRecords()
        records[lesson.rawValue] = record
        return persist(records)
    }

    func remove(lesson: OrigamiLesson) {
        var records = loadRecords()
        records.removeValue(forKey: lesson.rawValue)
        _ = persist(records)
    }

    private func loadRecords() -> [String: Record] {
        let records: [String: Record]
        if let defaults {
            guard let data = defaults.data(forKey: Self.storageKey),
                  let archive = try? JSONDecoder().decode(Archive.self, from: data),
                  archive.schemaVersion == Self.schemaVersion else { return [:] }
            records = archive.records
        } else {
            records = memoryRecords
        }
        return records.filter { key, record in
            guard let lesson = OrigamiLesson(rawValue: key) else { return false }
            return Self.isValid(record, for: lesson)
        }
    }

    private func persist(_ records: [String: Record]) -> Bool {
        guard let defaults else {
            memoryRecords = records
            return true
        }
        guard let data = try? JSONEncoder().encode(Archive(schemaVersion: Self.schemaVersion, records: records)) else {
            return false
        }
        defaults.set(data, forKey: Self.storageKey)
        return true
    }

    private static func isValid(_ record: Record, for lesson: OrigamiLesson) -> Bool {
        guard record.lessonID == lesson.rawValue,
              record.contentRevision == contentRevisions[lesson.rawValue],
              record.updatedAt.timeIntervalSinceReferenceDate.isFinite,
              (0...lesson.lastStep).contains(record.stepIndex),
              record.progress.isFinite, (0...1).contains(record.progress),
              record.stepIndex != 0 || record.progress == 1 else { return false }
        return !record.completed || (record.stepIndex == lesson.lastStep && record.progress == 1)
    }

    /// Text, step IDs and their order participate in each lesson's fingerprint.
    /// Bump only the corresponding animation revision when geometry changes the
    /// meaning of a saved pose without changing its written lesson steps.
    private static let animationRevisions: [String: Int] = [
        "crane": 1, "star": 1, "frog": 1, "turtle": 1,
        "fullRabbit": 1, "sittingDog": 1, "fullFox": 1, "elephant": 1,
        "butterfly": 1, "dart": 1, "fox": 1, "rabbit": 1
    ]
    private static let contentRevisions: [String: String] = Dictionary(uniqueKeysWithValues: OrigamiLesson.allCases.map { lesson in
        var fields = ["Protacta lesson content v1", lesson.rawValue,
                      String(animationRevisions[lesson.rawValue] ?? 1)]
        for step in lesson.steps {
            fields.append(contentsOf: [String(step.id), step.title, step.instruction, step.cue, step.explanation])
        }
        // Length prefixes keep embedded delimiters and line breaks unambiguous.
        let signature = fields.map { "\($0.utf8.count):\($0)" }.joined()
        let digest = SHA256.hash(data: Data(signature.utf8)).map { String(format: "%02x", $0) }.joined()
        return (lesson.rawValue, digest)
    })

    private struct Archive: Codable {
        let schemaVersion: Int
        let records: [String: Record]
        private enum CodingKeys: String, CodingKey { case schemaVersion, records }

        init(schemaVersion: Int, records: [String: Record]) {
            self.schemaVersion = schemaVersion
            self.records = records
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            let entries = try container.nestedContainer(keyedBy: LessonKey.self, forKey: .records)
            var decoded: [String: Record] = [:]
            for key in entries.allKeys {
                // One malformed lesson must not erase other valid lesson saves.
                if let record = try? entries.decode(Record.self, forKey: key) {
                    decoded[key.stringValue] = record
                }
            }
            records = decoded
        }

        private struct LessonKey: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
    }
}
