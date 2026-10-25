import Foundation

/// A person's declared practice progress. It has no camera/check-result input.
struct EverydayTutorialSession {
    let courseID: EverydayTutorialID
    private(set) var currentAction = 1
    private(set) var completed = false
    private(set) var confirmedActions: [Int] = []

    var confirmedCount: Int { confirmedActions.count }

    init(courseID: EverydayTutorialID) {
        self.courseID = courseID
    }

    @discardableResult
    mutating func confirmCurrentAction() -> Bool {
        guard !completed else { return false }
        let count = EverydayTutorialCourse.course(courseID).actions.count
        if !confirmedActions.contains(currentAction) { confirmedActions.append(currentAction) }
        if currentAction == count { completed = true }
        else { currentAction += 1 }
        return true
    }

    /// Reviewing earlier instructions withdraws later declarations; it does not
    /// unfold fabric or untie a physical knot on the learner's behalf.
    @discardableResult
    mutating func previousAction() -> Bool {
        guard completed || currentAction > 1 else { return false }
        if !completed { currentAction -= 1 }
        completed = false
        confirmedActions.removeAll { $0 >= currentAction }
        return true
    }

    mutating func restart() {
        currentAction = 1
        completed = false
        confirmedActions = []
    }

    fileprivate init(courseID: EverydayTutorialID, currentAction: Int, completed: Bool, confirmedActions: [Int]) {
        self.courseID = courseID
        self.currentAction = currentAction
        self.completed = completed
        self.confirmedActions = confirmedActions
    }
}

/// Small, per-course local records; no photos, voice transcripts, transactions,
/// camera pose or inferred mastery are stored here. Use appDefault in the app.
final class EverydayTutorialProgressStore {
    static let storageKey = "org.realitycore.protacta.prototype.everydayTutorialProgress"
    static let uiTestingSuiteName = "org.realitycore.protacta.prototype.everydayUITests"
    private static let schemaVersion = 1
    private let defaults: UserDefaults?
    private var memoryArchive: Data?

    /// Explicit nil makes a new isolated, in-memory store.
    init(defaults: UserDefaults? = .standard) { self.defaults = defaults }

    private static let sharedAppStore: EverydayTutorialProgressStore = {
        let process = ProcessInfo.processInfo
        if process.arguments.contains("--ui-testing") {
            // Relaunch tests share an isolated persistent domain. The app may
            // clear it once when --reset-everyday-progress is explicitly set.
            return EverydayTutorialProgressStore(defaults: UserDefaults(suiteName: uiTestingSuiteName))
        }
        let testing = process.environment["XCTestConfigurationFilePath"] != nil ||
            NSClassFromString("XCTestCase") != nil
        return EverydayTutorialProgressStore(defaults: testing ? nil : .standard)
    }()

    static func appDefault() -> EverydayTutorialProgressStore { sharedAppStore }

    func load(courseID: EverydayTutorialID) -> EverydayTutorialSession? {
        guard let record = readRecords()[courseID.rawValue] else { return nil }
        return EverydayTutorialSession(courseID: courseID, currentAction: record.currentAction,
                                       completed: record.completed, confirmedActions: record.confirmedActions)
    }

    @discardableResult
    func save(_ session: EverydayTutorialSession) -> Bool {
        let record = Record(courseID: session.courseID, courseRevision: EverydayTutorialCourse.course(session.courseID).revision,
                            currentAction: session.currentAction, completed: session.completed,
                            confirmedActions: session.confirmedActions)
        guard Self.valid(record) else { return false }
        var records = readRecords()
        records[session.courseID.rawValue] = record
        return writeRecords(records)
    }

    func clear(courseID: EverydayTutorialID) {
        var records = readRecords()
        records.removeValue(forKey: courseID.rawValue)
        _ = writeRecords(records)
    }

    private func readRecords() -> [String: Record] {
        guard let data = defaults?.data(forKey: Self.storageKey) ?? memoryArchive,
              data.count <= 64 * 1024,
              let archive = try? JSONDecoder().decode(Archive.self, from: data),
              archive.schemaVersion == Self.schemaVersion else { return [:] }
        return archive.records.filter { $0.key == $0.value.courseID.rawValue && Self.valid($0.value) }
    }

    private func writeRecords(_ records: [String: Record]) -> Bool {
        guard records.count <= EverydayTutorialID.allCases.count,
              records.allSatisfy({ $0.key == $0.value.courseID.rawValue && Self.valid($0.value) }),
              let data = try? JSONEncoder().encode(Archive(schemaVersion: Self.schemaVersion, records: records)),
              data.count <= 64 * 1024 else { return false }
        if let defaults { defaults.set(data, forKey: Self.storageKey) }
        else { memoryArchive = data }
        return true
    }

    private static func valid(_ record: Record) -> Bool {
        let course = EverydayTutorialCourse.course(record.courseID)
        let count = course.actions.count
        guard record.courseRevision == course.revision,
              (1...count).contains(record.currentAction),
              !record.completed || record.currentAction == count else { return false }
        let expected = record.completed ? Array(1...count) : Array(1..<record.currentAction)
        return record.confirmedActions == expected
    }

    private struct Record: Codable {
        let courseID: EverydayTutorialID
        let courseRevision: String
        let currentAction: Int
        let completed: Bool
        let confirmedActions: [Int]
    }

    private struct Archive: Codable {
        let schemaVersion: Int
        let records: [String: Record]

        init(schemaVersion: Int, records: [String: Record]) {
            self.schemaVersion = schemaVersion
            self.records = records
        }

        private enum CodingKeys: String, CodingKey { case schemaVersion, records }
        private struct CourseKey: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            let nested = try container.nestedContainer(keyedBy: CourseKey.self, forKey: .records)
            var decoded: [String: Record] = [:]
            for key in nested.allKeys where EverydayTutorialID(rawValue: key.stringValue) != nil {
                // One malformed or obsolete course must not erase others.
                if let record = try? nested.decode(Record.self, forKey: key) { decoded[key.stringValue] = record }
            }
            records = decoded
        }
    }
}
