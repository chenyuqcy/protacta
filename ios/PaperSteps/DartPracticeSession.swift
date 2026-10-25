import Foundation

/// Historical comparison text only. No camera coordinates or freshness survive
/// saving; even `visibleMatch` means a boundary comparison, not fold validation.
struct DartPracticeCheckSummary: Codable, Equatable {
    let checkpointID: String
    let referenceState: Int
    let outcome: PaperCheckOutcome
    let message: String
}

struct DartPracticeSession {
    static let maximumCheckAge: TimeInterval = 2

    private(set) var currentAction = 1
    private(set) var completed = false
    private(set) var lastCheck: DartOutlineCheckResult?
    private(set) var confirmedActions: [Int] = []
    private(set) var checkSummaries: [DartPracticeCheckSummary] = []

    private var actionStartedAt: TimeInterval
    private var lastCheckTimestamp: TimeInterval?

    init(startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        actionStartedAt = startedAt.isFinite && startedAt >= 0 ? startedAt : ProcessInfo.processInfo.systemUptime
    }

    /// Only the learner confirms an action; a camera result never calls this.
    @discardableResult
    mutating func confirmCurrentAction(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard !completed, validTransitionTime(now) else { return false }
        if !confirmedActions.contains(currentAction) { confirmedActions.append(currentAction) }
        confirmedActions = Array(confirmedActions.sorted().prefix(DartPracticeCourse.actions.count))
        if currentAction == DartPracticeCourse.actions.count { completed = true }
        else { currentAction += 1 }
        resetLiveCheck(at: now)
        return true
    }

    /// Reopening an earlier action withdraws confirmations from that point on.
    /// It changes the lesson, not the physical paper; compare/restore it yourself.
    @discardableResult
    mutating func previousAction(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard validTransitionTime(now), completed || currentAction > 1 else { return false }
        let target = completed ? currentAction : currentAction - 1
        currentAction = target
        completed = false
        confirmedActions.removeAll { $0 >= target }
        checkSummaries.removeAll { $0.referenceState >= target }
        resetLiveCheck(at: now)
        return true
    }

    mutating func restart(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard validTransitionTime(now) else { return }
        currentAction = 1
        completed = false
        confirmedActions = []
        checkSummaries = []
        resetLiveCheck(at: now)
    }

    /// Drop point annotations when the live paper/camera context changes while
    /// retaining the explicitly historical text for this attempt.
    mutating func clearLiveCheck(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard validTransitionTime(now) else { return }
        resetLiveCheck(at: now)
    }

    /// The result belongs to the resting state after the current action. Camera
    /// generation and capture context must also be checked by the controller.
    @discardableResult
    mutating func recordCheck(_ result: DartOutlineCheckResult,
                              at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard !completed, result.referenceState == currentAction,
              Self.validSummary(Self.summary(of: result)),
              result.timestamp.isFinite, now.isFinite,
              result.timestamp >= actionStartedAt, now >= result.timestamp,
              now - result.timestamp <= Self.maximumCheckAge,
              lastCheckTimestamp.map({ result.timestamp > $0 }) ?? true else { return false }
        // No camera can approve the unsupported lifted/hidden states through an
        // outline-only result. An explicit cannot-judge message remains useful.
        guard DartPracticeCourse.supportsOutlineCheck(state: currentAction) || result.outcome == .cannotJudge else { return false }
        lastCheck = result
        lastCheckTimestamp = result.timestamp
        checkSummaries.removeAll { $0.referenceState == currentAction }
        checkSummaries.append(Self.summary(of: result))
        checkSummaries.sort { $0.referenceState < $1.referenceState }
        checkSummaries = Array(checkSummaries.prefix(DartPracticeCourse.actions.count))
        return true
    }

    private func validTransitionTime(_ now: TimeInterval) -> Bool {
        now.isFinite && now >= actionStartedAt && now >= (lastCheckTimestamp ?? actionStartedAt)
    }

    private mutating func resetLiveCheck(at now: TimeInterval) {
        lastCheck = nil
        lastCheckTimestamp = nil
        actionStartedAt = now
    }

    private static func summary(of result: DartOutlineCheckResult) -> DartPracticeCheckSummary {
        DartPracticeCheckSummary(checkpointID: result.checkpointID, referenceState: result.referenceState,
                                 outcome: result.outcome, message: result.message)
    }

    fileprivate static func validSummary(_ summary: DartPracticeCheckSummary) -> Bool {
        (1...DartPracticeCourse.actions.count).contains(summary.referenceState) &&
        !summary.checkpointID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        summary.checkpointID.utf8.count <= 128 &&
        !summary.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        summary.message.utf8.count <= 4_000 &&
        (DartPracticeCourse.supportsOutlineCheck(state: summary.referenceState) || summary.outcome == .cannotJudge)
    }

    fileprivate init(currentAction: Int, completed: Bool, confirmedActions: [Int],
                     checkSummaries: [DartPracticeCheckSummary], restoredAt: TimeInterval) {
        self.currentAction = currentAction
        self.completed = completed
        self.confirmedActions = confirmedActions
        self.checkSummaries = checkSummaries
        // A stored comparison is historical text, never a live camera check.
        lastCheck = nil
        lastCheckTimestamp = nil
        actionStartedAt = restoredAt
    }
}

/// Isolated local practice progress, independent of purchases and AR placement.
/// An explicit nil defaults argument creates an in-memory instance.
final class PracticeProgressStore {
    static let storageKey = "org.realitycore.protacta.prototype.dartPractice"
    private static let schemaVersion = 1
    private let defaults: UserDefaults?
    private var memoryArchive: Data?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
    }

    static func appDefault() -> PracticeProgressStore {
        let process = ProcessInfo.processInfo
        let testing = process.arguments.contains("--ui-testing") ||
            process.environment["XCTestConfigurationFilePath"] != nil ||
            NSClassFromString("XCTestCase") != nil
        return PracticeProgressStore(defaults: testing ? nil : .standard)
    }

    func load(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> DartPracticeSession? {
        guard now.isFinite, now >= 0,
              let data = defaults?.data(forKey: Self.storageKey) ?? memoryArchive,
              data.count <= 100_000,
              let archive = try? JSONDecoder().decode(Archive.self, from: data),
              archive.schemaVersion == Self.schemaVersion,
              archive.courseRevision == DartPracticeCourse.revision,
              Self.valid(archive) else { return nil }
        return DartPracticeSession(currentAction: archive.currentAction, completed: archive.completed,
                                   confirmedActions: archive.confirmedActions,
                                   checkSummaries: archive.checkSummaries, restoredAt: now)
    }

    @discardableResult
    func save(_ session: DartPracticeSession) -> Bool {
        let archive = Archive(schemaVersion: Self.schemaVersion, courseRevision: DartPracticeCourse.revision,
                              currentAction: session.currentAction, completed: session.completed,
                              confirmedActions: session.confirmedActions, checkSummaries: session.checkSummaries)
        guard Self.valid(archive), let data = try? JSONEncoder().encode(archive) else { return false }
        if let defaults { defaults.set(data, forKey: Self.storageKey) }
        else { memoryArchive = data }
        return true
    }

    func clear() {
        defaults?.removeObject(forKey: Self.storageKey)
        memoryArchive = nil
    }

    private static func valid(_ archive: Archive) -> Bool {
        let count = DartPracticeCourse.actions.count
        guard (1...count).contains(archive.currentAction),
              !archive.completed || archive.currentAction == count else { return false }
        let expectedConfirmations = archive.completed ? Array(1...count) : Array(1..<archive.currentAction)
        guard archive.confirmedActions == expectedConfirmations,
              archive.checkSummaries.count <= count,
              Set(archive.checkSummaries.map(\.referenceState)).count == archive.checkSummaries.count else { return false }
        return archive.checkSummaries.allSatisfy {
            DartPracticeSession.validSummary($0) && $0.referenceState <= archive.currentAction
        }
    }

    private struct Archive: Codable {
        let schemaVersion: Int
        let courseRevision: String
        let currentAction: Int
        let completed: Bool
        let confirmedActions: [Int]
        let checkSummaries: [DartPracticeCheckSummary]
    }
}
