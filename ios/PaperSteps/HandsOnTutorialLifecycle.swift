import Combine
import UIKit

/// Coordinates the process-global idle timer across every participating scene
/// and tutorial module. Only the first owner saves the external value, and only
/// the last owner restores it; one window cannot release another window's hold.
@MainActor
final class HandsOnScreenAwakeCoordinator {
    private let read: () -> Bool
    private let write: (Bool) -> Void
    private var previous: Bool?
    private var owners: Set<UUID> = []

    init(read: @escaping () -> Bool, write: @escaping (Bool) -> Void) {
        self.read = read; self.write = write
    }

    fileprivate func contains(_ owner: UUID) -> Bool { owners.contains(owner) }

    fileprivate func acquire(_ owner: UUID) {
        guard owners.insert(owner).inserted else { return }
        guard owners.count == 1 else { return }
        previous = read()
        write(true)
    }

    fileprivate func release(_ owner: UUID) {
        guard owners.remove(owner) != nil, owners.isEmpty, let previous else { return }
        self.previous = nil
        write(previous)
    }
}

/// One explicit lifecycle owner. Inject a coordinator to exercise overlapping
/// modules without touching UIApplication; the convenience initializer creates
/// an isolated coordinator for existing single-owner tests.
@MainActor
final class HandsOnScreenAwakeLease: ObservableObject {
    private let coordinator: HandsOnScreenAwakeCoordinator
    private let owner = UUID()
    var isAcquired: Bool { coordinator.contains(owner) }

    private static let systemCoordinator = HandsOnScreenAwakeCoordinator(
        read: { UIApplication.shared.isIdleTimerDisabled },
        write: { UIApplication.shared.isIdleTimerDisabled = $0 })

    init(coordinator: HandsOnScreenAwakeCoordinator) {
        self.coordinator = coordinator
    }

    convenience init(read: @escaping () -> Bool, write: @escaping (Bool) -> Void) {
        self.init(coordinator: HandsOnScreenAwakeCoordinator(read: read, write: write))
    }

    static func system() -> HandsOnScreenAwakeLease {
        HandsOnScreenAwakeLease(coordinator: systemCoordinator)
    }

    func acquire() { coordinator.acquire(owner) }
    func release() { coordinator.release(owner) }
}

/// Completion removes the microphone controls, so it must stop the voice
/// session instead of rearming it. Already queued commands cannot reopen a
/// finished course after that boundary.
@MainActor
enum EverydayPracticeVoiceBoundary {
    @discardableResult
    static func confirm(_ session: inout EverydayTutorialSession,
                        stop: () -> Void, continueListening: () -> Void) -> Bool {
        guard session.confirmCurrentAction() else { stop(); return false }
        if session.completed { stop() }
        else { continueListening() }
        return true
    }

    static func permitsCommand(completed: Bool, stop: () -> Void) -> Bool {
        guard !completed else { stop(); return false }
        return true
    }
}
