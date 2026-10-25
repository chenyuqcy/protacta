import CoreGraphics
import XCTest
@testable import Protacta

final class EverydayTutorialVisualTests: XCTestCase {
    func testVerticalPanelFoldKeepsTheHingeAndReflectsTheMovingEdge() {
        let points = [CGPoint(x: 100, y: 80), CGPoint(x: 165, y: 80), CGPoint(x: 100, y: 350)]
        let start = CGPoint(x: 165, y: 75), end = CGPoint(x: 165, y: 350)
        XCTAssertEqual(EverydayFoldProjection.points(points, hingeStart: start, hingeEnd: end, progress: 0), points)
        let target = EverydayFoldProjection.points(points, hingeStart: start, hingeEnd: end, progress: 1)
        assertPoint(target[0], equals: CGPoint(x: 230, y: 80))
        assertPoint(target[1], equals: points[1])
        assertPoint(target[2], equals: CGPoint(x: 230, y: 350))
        let half = EverydayFoldProjection.points(points, hingeStart: start, hingeEnd: end, progress: 0.5)
        for point in half { XCTAssertEqual(point.x, 165, accuracy: 1e-9) }
    }

    func testDiagonalSleeveFoldUsesItsSeamRatherThanAnAxisAlignedShortcut() {
        let start = CGPoint(x: 0, y: 0), end = CGPoint(x: 1, y: 1)
        let point = CGPoint(x: 0.2, y: 0.8)
        let target = EverydayFoldProjection.points([point], hingeStart: start, hingeEnd: end, progress: 1)[0]
        assertPoint(target, equals: CGPoint(x: 0.8, y: 0.2))
        let reversed = EverydayFoldProjection.points([point], hingeStart: end, hingeEnd: start, progress: 1)[0]
        assertPoint(reversed, equals: target)
        XCTAssertEqual(hypot(point.x - 0.5, point.y - 0.5), hypot(target.x - 0.5, target.y - 0.5), accuracy: 1e-9)
    }

    func testBottomToTopPairingForHalfThenQuarterHeight() {
        let bottom = [CGPoint(x: 250, y: 215), CGPoint(x: 300, y: 215)]
        let target = EverydayFoldProjection.points(bottom, hingeStart: CGPoint(x: 250, y: 147.5),
                                                   hingeEnd: CGPoint(x: 300, y: 147.5), progress: 1)
        assertPoint(target[0], equals: CGPoint(x: 250, y: 80))
        assertPoint(target[1], equals: CGPoint(x: 300, y: 80))
    }

    func testOutOfRangeProgressAndUnusableHingeDoNotProduceInvalidGeometry() {
        let points = [CGPoint(x: 10, y: 20)]
        let start = CGPoint(x: 0, y: 0), end = CGPoint(x: 0, y: 100)
        XCTAssertEqual(EverydayFoldProjection.points(points, hingeStart: start, hingeEnd: end, progress: -1), points)
        assertPoint(EverydayFoldProjection.points(points, hingeStart: start, hingeEnd: end, progress: 2)[0],
                    equals: CGPoint(x: -10, y: 20))
        XCTAssertEqual(EverydayFoldProjection.points(points, hingeStart: start, hingeEnd: start, progress: 0.7), points)
        XCTAssertEqual(EverydayFoldProjection.points(points, hingeStart: start, hingeEnd: end, progress: .nan), points)
    }

    private func assertPoint(_ actual: CGPoint, equals expected: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 1e-9, file: file, line: line)
    }
}
