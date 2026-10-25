import CoreGraphics
import XCTest
@testable import Protacta

final class PaperGuideSessionTests: XCTestCase {
    private let generation = 7
    private let firstTime: TimeInterval = 100

    func testFirstObservationRequiresExplicitDirectionBeforeAnyRegistration() {
        var session = startedSession()
        session.receive(quad: sheet, timestamp: firstTime, generation: generation, now: firstTime)
        XCTAssertEqual(session.status, .needsDirection)
        XCTAssertFalse(session.directionConfirmed)
        XCTAssertNil(session.registration)
        XCTAssertTrue(session.confirmDirection(at: firstTime + 0.02))
        XCTAssertEqual(session.status, .aligned)
        XCTAssertTrue(session.directionConfirmed)
        XCTAssertNotNil(session.registration)
    }

    func testStaleFutureAndNonFiniteObservationsNeverProduceARegistration() {
        for (timestamp, now) in [(100.0, 100.36), (100.1, 100.0), (.nan, 100.0), (100.0, .infinity)] {
            var session = startedSession()
            session.receive(quad: sheet, timestamp: timestamp, generation: generation, now: now)
            XCTAssertNil(session.quadrilateral)
            XCTAssertNil(session.registration)
            XCTAssertFalse(session.confirmDirection(at: now))
        }
    }

    func testWrongGenerationAndOlderResultsCannotReplaceCurrentObservation() {
        var session = alignedSession()
        let original = session.quadrilateral
        session.receive(quad: nil, timestamp: firstTime + 0.1, generation: generation - 1, now: firstTime + 0.1)
        session.receive(quad: translated(sheet, x: 0.4), timestamp: firstTime - 0.1,
                        generation: generation, now: firstTime + 0.1)
        XCTAssertEqual(session.quadrilateral, original)
        XCTAssertEqual(session.status, .aligned)
        XCTAssertNotNil(session.registration)
    }

    func testFreshNoObservationHidesImmediatelyAndReappearanceNeedsConfirmation() {
        var session = alignedSession()
        session.receive(quad: nil, timestamp: firstTime + 0.1, generation: generation, now: firstTime + 0.1)
        XCTAssertEqual(session.status, .reacquiring)
        XCTAssertNil(session.quadrilateral)
        XCTAssertNil(session.registration)
        XCTAssertFalse(session.directionConfirmed)

        session.receive(quad: sheet, timestamp: firstTime + 0.2, generation: generation, now: firstTime + 0.2)
        XCTAssertEqual(session.status, .needsDirection)
        XCTAssertNil(session.registration)
    }

    func testDelayedCallbackCannotKeepAnExpiredRegistrationVisible() {
        var session = alignedSession()
        session.receive(quad: sheet, timestamp: firstTime - 0.1,
                        generation: generation, now: firstTime + 0.5)
        XCTAssertEqual(session.status, .reacquiring)
        XCTAssertNil(session.registration)
    }

    func testAnOlderPositiveResultCannotUndoNewerDetectionLoss() {
        var session = alignedSession()
        session.receive(quad: nil, timestamp: firstTime + 0.2, generation: generation, now: firstTime + 0.2)
        session.receive(quad: sheet, timestamp: firstTime + 0.1, generation: generation, now: firstTime + 0.21)
        XCTAssertEqual(session.status, .reacquiring)
        XCTAssertNil(session.quadrilateral)
        XCTAssertNil(session.registration)
    }

    func testFreshCallbackWithStaleImageInvalidatesAnEarlierRegistration() {
        var session = alignedSession()
        session.receive(quad: sheet, timestamp: firstTime + 0.1, generation: generation, now: firstTime + 0.5)
        XCTAssertEqual(session.status, .reacquiring)
        XCTAssertNil(session.registration)
        XCTAssertFalse(session.directionConfirmed)
    }

    func testInvalidQuadrilateralHidesAnAlreadyAlignedCue() {
        var session = alignedSession()
        let invalid = PaperQuadrilateral(topLeft: .zero, topRight: .zero,
                                         bottomRight: .zero, bottomLeft: .zero)
        session.receive(quad: invalid, timestamp: firstTime + 0.1, generation: generation, now: firstTime + 0.1)
        XCTAssertEqual(session.status, .reacquiring)
        XCTAssertNil(session.registration)
        XCTAssertFalse(session.directionConfirmed)
    }

    func testExpiryWithoutAnotherCameraCallbackHidesTheCue() {
        var session = alignedSession()
        session.expire(at: firstTime + 0.34)
        XCTAssertEqual(session.status, .aligned)
        session.expire(at: firstTime + 0.36)
        XCTAssertEqual(session.status, .reacquiring)
        XCTAssertNil(session.registration)
        XCTAssertNil(session.quadrilateral)
        XCTAssertFalse(session.directionConfirmed)
    }

    func testDirectionConfirmationCannotResurrectAnExpiredObservation() {
        var session = startedSession()
        session.receive(quad: sheet, timestamp: firstTime, generation: generation, now: firstTime)
        XCTAssertFalse(session.confirmDirection(at: firstTime + 0.36))
        XCTAssertEqual(session.status, .reacquiring)
        XCTAssertNil(session.registration)
    }

    func testCyclicDetectorCornerChangesPreserveConfirmedIdentitiesDuringSmallMovement() throws {
        var session = alignedSession()
        let moved = translated(sheet, x: 0.01)
        session.receive(quad: moved.rotated(by: 2), timestamp: firstTime + 0.1,
                        generation: generation, now: firstTime + 0.1)
        XCTAssertEqual(session.status, .aligned)
        XCTAssertEqual(session.quadrilateral, moved)
        let origin = try XCTUnwrap(session.registration?.map(.zero))
        XCTAssertEqual(origin.x, moved.topLeft.x, accuracy: 0.00001)
        XCTAssertEqual(origin.y, moved.topLeft.y, accuracy: 0.00001)
    }

    func testRotatedDirectionRemainsTheChosenIdentityOnNextObservation() {
        var session = alignedSession()
        session.rotateDirection(at: firstTime + 0.01)
        XCTAssertEqual(session.quadrilateral, sheet.rotated(by: 1))
        session.receive(quad: sheet, timestamp: firstTime + 0.1, generation: generation, now: firstTime + 0.1)
        XCTAssertEqual(session.quadrilateral, sheet.rotated(by: 1))
        XCTAssertEqual(session.status, .aligned)
    }

    func testRotatingAnUnconfirmedSheetDoesNotConfirmIt() {
        var session = startedSession()
        session.receive(quad: sheet, timestamp: firstTime, generation: generation, now: firstTime)
        session.rotateDirection(at: firstTime + 0.01)
        XCTAssertEqual(session.quadrilateral, sheet.rotated(by: 1))
        XCTAssertEqual(session.status, .needsDirection)
        XCTAssertNil(session.registration)
        XCTAssertFalse(session.directionConfirmed)
    }

    func testLargeJumpCannotInheritDirectionFromAnotherRectangle() {
        var session = alignedSession()
        let unrelated = translated(sheet, x: 0.35)
        session.receive(quad: unrelated, timestamp: firstTime + 0.1,
                        generation: generation, now: firstTime + 0.1)
        XCTAssertEqual(session.quadrilateral, unrelated)
        XCTAssertEqual(session.status, .needsDirection)
        XCTAssertFalse(session.directionConfirmed)
        XCTAssertNil(session.registration)
    }

    func testAbruptShapeChangeCannotInheritConfirmedDirection() {
        var session = alignedSession()
        let compressed = PaperQuadrilateral(topLeft: sheet.topLeft, topRight: sheet.topRight,
                                            bottomRight: CGPoint(x: 0.5, y: 0.3),
                                            bottomLeft: CGPoint(x: 0.1, y: 0.3))
        session.receive(quad: compressed, timestamp: firstTime + 0.1,
                        generation: generation, now: firstTime + 0.1)
        XCTAssertEqual(session.status, .needsDirection)
        XCTAssertFalse(session.directionConfirmed)
        XCTAssertNil(session.registration)
    }

    func testLongUnobservedIntervalRequiresNewConfirmationEvenAtSamePosition() {
        var session = alignedSession()
        session.receive(quad: sheet, timestamp: firstTime + 0.5, generation: generation, now: firstTime + 0.5)
        XCTAssertEqual(session.status, .needsDirection)
        XCTAssertFalse(session.directionConfirmed)
        XCTAssertNil(session.registration)
    }

    func testUnsupportedAndEndedSessionsCannotReviveFromIncomingFrames() {
        var session = alignedSession()
        session.setSupported(false)
        XCTAssertEqual(session.status, .unsupported)
        XCTAssertNil(session.registration)
        session.receive(quad: sheet, timestamp: firstTime + 0.1, generation: generation, now: firstTime + 0.1)
        XCTAssertNil(session.quadrilateral)
        session.setSupported(true)
        XCTAssertEqual(session.status, .reacquiring)
        session.invalidate()
        session.receive(quad: sheet, timestamp: firstTime + 0.2, generation: generation, now: firstTime + 0.2)
        XCTAssertNil(session.quadrilateral)

        session.start(generation: generation + 1)
        XCTAssertEqual(session.status, .searching)
        session.receive(quad: sheet, timestamp: firstTime + 0.3, generation: generation, now: firstTime + 0.3)
        XCTAssertNil(session.quadrilateral)
        session.receive(quad: sheet, timestamp: firstTime + 0.4, generation: generation + 1, now: firstTime + 0.4)
        XCTAssertEqual(session.status, .needsDirection)
    }

    private var sheet: PaperQuadrilateral {
        PaperQuadrilateral(topLeft: CGPoint(x: 0.1, y: 0.1), topRight: CGPoint(x: 0.5, y: 0.1),
                           bottomRight: CGPoint(x: 0.5, y: 0.7), bottomLeft: CGPoint(x: 0.1, y: 0.7))
    }

    private func translated(_ quad: PaperQuadrilateral, x: CGFloat) -> PaperQuadrilateral {
        let moved = quad.points.map { CGPoint(x: $0.x + x, y: $0.y) }
        return PaperQuadrilateral(topLeft: moved[0], topRight: moved[1],
                                  bottomRight: moved[2], bottomLeft: moved[3])
    }

    private func startedSession() -> PaperGuideSession {
        var session = PaperGuideSession()
        session.start(generation: generation)
        return session
    }

    private func alignedSession() -> PaperGuideSession {
        var session = startedSession()
        session.receive(quad: sheet, timestamp: firstTime, generation: generation, now: firstTime)
        XCTAssertTrue(session.confirmDirection(at: firstTime))
        return session
    }
}
