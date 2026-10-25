import XCTest
@testable import Protacta

final class HandsOnTutorialLifecycleTests: XCTestCase {
    @MainActor
    func testLessonKeepsScreenAwakeAndRestoresTheActualPreviousValue() {
        for initial in [false, true] {
            var idleDisabled = initial
            var writes: [Bool] = []
            let lease = HandsOnScreenAwakeLease(read: { idleDisabled }, write: { idleDisabled = $0; writes.append($0) })
            lease.acquire(); lease.acquire()
            XCTAssertTrue(idleDisabled)
            XCTAssertTrue(lease.isAcquired)
            XCTAssertEqual(writes, [true], "Repeated active events must not overwrite the saved owner")
            lease.release(); lease.release()
            XCTAssertEqual(idleDisabled, initial)
            XCTAssertFalse(lease.isAcquired)
            XCTAssertEqual(writes, [true, initial])
        }
    }

    @MainActor
    func testBackgroundReleasesAndForegroundUsesTheNewOwnersValue() {
        var idleDisabled = false
        let lease = HandsOnScreenAwakeLease(read: { idleDisabled }, write: { idleDisabled = $0 })
        lease.acquire(); lease.release()
        XCTAssertFalse(idleDisabled)
        idleDisabled = true // Another owner takes over while this lesson is inactive.
        lease.acquire(); lease.release()
        XCTAssertTrue(idleDisabled, "Leaving this lesson must preserve the other owner's request")
    }

    @MainActor
    func testReleasingWithoutOwningDoesNotChangeTheSystemSetting() {
        var writes = 0
        let lease = HandsOnScreenAwakeLease(read: { false }, write: { _ in writes += 1 })
        lease.release()
        XCTAssertEqual(writes, 0)
    }

    @MainActor
    func testOverlappingWindowsRestoreTheOriginalValueOnlyAfterTheLastRelease() {
        for initial in [false, true] {
            for firstToClose in [0, 1] {
                var idleDisabled = initial
                var writes: [Bool] = []
                let coordinator = HandsOnScreenAwakeCoordinator(read: { idleDisabled },
                                                                 write: { idleDisabled = $0; writes.append($0) })
                let windows = [HandsOnScreenAwakeLease(coordinator: coordinator),
                               HandsOnScreenAwakeLease(coordinator: coordinator)]
                windows[0].acquire(); windows[1].acquire()
                XCTAssertEqual(writes, [true], "A second window must not save the first window's temporary true value")
                windows[firstToClose].release()
                XCTAssertTrue(idleDisabled, "The remaining visible lesson still owns its screen-awake request")
                XCTAssertEqual(writes, [true])
                windows[1 - firstToClose].release()
                XCTAssertEqual(idleDisabled, initial)
                XCTAssertEqual(writes, [true, initial])
            }
        }
    }

    @MainActor
    func testBackgroundAndForegroundOfOneWindowDoNotReplaceAnotherWindowsOriginalValue() {
        for initial in [false, true] {
            var idleDisabled = initial
            var writes: [Bool] = []
            let coordinator = HandsOnScreenAwakeCoordinator(read: { idleDisabled },
                                                             write: { idleDisabled = $0; writes.append($0) })
            let first = HandsOnScreenAwakeLease(coordinator: coordinator)
            let second = HandsOnScreenAwakeLease(coordinator: coordinator)
            first.acquire(); second.acquire()
            first.release() // This scene goes inactive while the other stays visible.
            XCTAssertTrue(idleDisabled)
            first.acquire() // Foregrounding must join the existing hold, not save true.
            second.release()
            XCTAssertTrue(idleDisabled)
            first.release()
            XCTAssertEqual(idleDisabled, initial)
            XCTAssertEqual(writes, [true, initial])
        }
    }

    @MainActor
    func testOrigamiEverydayAndProductOwnersCanOverlapAndCloseIdempotently() {
        var idleDisabled = false
        var writes: [Bool] = []
        let coordinator = HandsOnScreenAwakeCoordinator(read: { idleDisabled },
                                                         write: { idleDisabled = $0; writes.append($0) })
        let origami = HandsOnScreenAwakeLease(coordinator: coordinator)
        let everyday = HandsOnScreenAwakeLease(coordinator: coordinator)
        let product = HandsOnScreenAwakeLease(coordinator: coordinator)
        origami.acquire(); everyday.acquire(); product.acquire()
        origami.acquire(); product.acquire() // Repeated scene-active/onAppear events.
        everyday.release(); everyday.release()
        origami.release()
        XCTAssertTrue(idleDisabled, "The product lesson must retain ownership when the other modules close")
        XCTAssertTrue(product.isAcquired)
        XCTAssertEqual(writes, [true])
        product.release(); product.release()
        XCTAssertFalse(idleDisabled)
        XCTAssertEqual(writes, [true, false])

        // After all tutorial owners release, a different system owner may
        // change the value. The next overlap group must save that new value.
        idleDisabled = true
        everyday.acquire(); origami.acquire()
        everyday.release(); origami.release()
        XCTAssertTrue(idleDisabled)
        XCTAssertEqual(writes, [true, false, true, true])
    }

    @MainActor
    func testFinalConfirmationStopsEnabledVoiceInsteadOfRearmingIt() {
        for id in EverydayTutorialID.allCases {
            var session = EverydayTutorialSession(courseID: id)
            var listening = true
            var stopCount = 0
            var rearmCount = 0
            let count = EverydayTutorialCourse.course(id).actions.count
            for action in 1...count {
                XCTAssertTrue(EverydayPracticeVoiceBoundary.confirm(&session,
                    stop: { listening = false; stopCount += 1 },
                    continueListening: { listening = true; rearmCount += 1 }))
                XCTAssertEqual(listening, action < count)
            }
            XCTAssertTrue(session.completed)
            XCTAssertEqual(stopCount, 1)
            XCTAssertEqual(rearmCount, count - 1)
            let snapshot = session.confirmedActions
            XCTAssertFalse(EverydayPracticeVoiceBoundary.permitsCommand(completed: session.completed,
                                                                       stop: { listening = false }))
            XCTAssertFalse(listening)
            XCTAssertEqual(session.confirmedActions, snapshot)
        }
    }

    @MainActor
    func testRepeatedFinalConfirmCannotRearmAndRestartExplicitlyReopensTheBoundary() {
        var session = EverydayTutorialSession(courseID: .towel)
        for _ in 0..<3 { session.confirmCurrentAction() }
        var stopped = false, continued = false
        XCTAssertFalse(EverydayPracticeVoiceBoundary.confirm(&session, stop: { stopped = true },
                                                             continueListening: { continued = true }))
        XCTAssertTrue(stopped); XCTAssertFalse(continued)
        session.restart()
        stopped = false
        XCTAssertTrue(EverydayPracticeVoiceBoundary.permitsCommand(completed: session.completed,
                                                                  stop: { stopped = true }))
        XCTAssertFalse(stopped)
    }
}
