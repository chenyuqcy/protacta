#if DEBUG && targetEnvironment(simulator)
import CoreGraphics
import Foundation
import XCTest
@testable import Protacta

final class DartPracticeSyntheticComparisonTests: XCTestCase {
    func testReopenedFlatSheetMatchesBoundaryWithoutProvingCenterCrease() throws {
        let sample = make(action: 2)
        XCTAssertEqual(sample.result.outcome, .visibleMatch)
        XCTAssertTrue(sample.result.message.contains("Synthetic comparison"))
        XCTAssertTrue(sample.result.message.contains("cannot verify"))
        XCTAssertTrue(sample.result.message.contains("crease"))
        XCTAssertTrue(sample.result.message.contains("hidden layers"))
        let snapshot = try XCTUnwrap(sample.snapshot)
        XCTAssertTrue(snapshot.isSynthetic)
        XCTAssertEqual(snapshot.action, 2)
        XCTAssertEqual(snapshot.displayTransform, .identity)
        XCTAssertEqual(snapshot.viewportSize, CGSize(width: 390, height: 500))
        XCTAssertEqual(snapshot.cgImage.width, 250)
        XCTAssertEqual(snapshot.cgImage.height, 320)
        XCTAssertTrue(snapshot.mismatchViewportPoints.isEmpty)
    }

    func testUnmadeCornerAndNarrowingFoldsProduceRealAdjustmentPoints() throws {
        for action in 3...6 {
            let sample = make(action: action)
            XCTAssertEqual(sample.result.outcome, .needsAdjustment, "Action \(action): \(sample.result.message)")
            XCTAssertEqual(sample.result.referenceState, action)
            XCTAssertEqual(sample.result.timestamp, 100)
            XCTAssertTrue(sample.result.message.contains("visible outline differs"))
            XCTAssertFalse(sample.result.mismatchedPoints.isEmpty)
            XCTAssertLessThanOrEqual(sample.result.mismatchedPoints.count, 24)
            XCTAssertTrue(sample.result.mismatchedPoints.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
            let snapshot = try XCTUnwrap(sample.snapshot)
            XCTAssertTrue(snapshot.isSynthetic)
            XCTAssertEqual(snapshot.mismatchViewportPoints.count, sample.result.mismatchedPoints.count)
            XCTAssertTrue(snapshot.mismatchViewportPoints.allSatisfy {
                (0.219999...0.780001).contains($0.x) && (0.119999...0.880001).contains($0.y)
            })
        }
    }

    func testMissingPaperProducesUnknownAndNoInventedOverlayGeometry() throws {
        let sample = make(action: 3, visible: false)
        XCTAssertEqual(sample.result.outcome, .cannotJudge)
        XCTAssertTrue(sample.result.mismatchedPoints.isEmpty)
        let snapshot = try XCTUnwrap(sample.snapshot)
        XCTAssertTrue(snapshot.isSynthetic)
        XCTAssertNil(snapshot.rawSheetQuadrilateral)
        XCTAssertTrue(snapshot.outlineViewportPoints.isEmpty)
        XCTAssertTrue(snapshot.mismatchViewportPoints.isEmpty)
        let data = try XCTUnwrap(snapshot.cgImage.dataProvider?.data)
        let pixels = try XCTUnwrap(CFDataGetBytePtr(data))
        XCTAssertTrue((0..<CFDataGetLength(data)).allSatisfy { pixels[$0] == 25 })
    }

    func testUnsupportedAndOutOfCourseActionsCannotReceiveApproval() {
        for action in [-1, 0, 1, 7, 8, 9, 10, 11] {
            let sample = make(action: action)
            XCTAssertEqual(sample.result.outcome, .cannotJudge)
            XCTAssertTrue(sample.result.mismatchedPoints.isEmpty)
            XCTAssertTrue(sample.result.message.contains("Synthetic comparison"))
            XCTAssertNil(sample.snapshot)
        }
    }

    func testRasterMatchesCapturedViewportAspectWithoutExceedingMemoryBound() throws {
        for size in [CGSize(width: 390, height: 500), CGSize(width: 800, height: 300), CGSize(width: 100, height: 100)] {
            let snapshot = try XCTUnwrap(make(action: 3, size: size).snapshot)
            XCTAssertEqual(snapshot.viewportSize, size)
            XCTAssertGreaterThanOrEqual(snapshot.cgImage.width, 64)
            XCTAssertGreaterThanOrEqual(snapshot.cgImage.height, 64)
            XCTAssertLessThanOrEqual(snapshot.cgImage.width, 320)
            XCTAssertLessThanOrEqual(snapshot.cgImage.height, 320)
            XCTAssertEqual(Double(snapshot.cgImage.width) / Double(snapshot.cgImage.height),
                           Double(size.width / size.height), accuracy: 0.01)
            XCTAssertEqual(snapshot.cgImage.bytesPerRow, snapshot.cgImage.width)
            XCTAssertEqual(snapshot.cgImage.bitsPerPixel, 8)
        }
    }

    func testInvalidViewportFallsBackButTinyOrExtremeViewportCannotJudge() throws {
        for size in [CGSize.zero, CGSize(width: CGFloat.nan, height: 300), CGSize(width: 390, height: CGFloat.infinity)] {
            let snapshot = try XCTUnwrap(make(action: 3, size: size).snapshot)
            XCTAssertEqual(snapshot.viewportSize, CGSize(width: 390, height: 500))
        }
        for size in [CGSize(width: 10, height: 500), CGSize(width: 500, height: 10),
                     CGSize(width: 64, height: 4000), CGSize(width: 4000, height: 64)] {
            let sample = make(action: 3, size: size)
            XCTAssertEqual(sample.result.outcome, .cannotJudge)
            XCTAssertNil(sample.snapshot)
        }
    }

    func testStaleFutureAndInvalidTimesCannotMakeCurrentSnapshots() {
        for (timestamp, now) in [(100.0, 100.36), (100.0, 99.9), (Double.nan, 100.0),
                                 (-1.0, 100.0), (100.0, Double.infinity)] {
            let sample = DartPracticeSyntheticComparison.make(action: 3, sheetVisible: true,
                                                               viewportSize: CGSize(width: 390, height: 500),
                                                               timestamp: timestamp, now: now)
            XCTAssertEqual(sample.result.outcome, .cannotJudge)
            XCTAssertNil(sample.snapshot)
        }
    }

    func testRenderedBeforePixelsReallyContainTheUnfoldedCorner() throws {
        let sample = make(action: 3)
        let snapshot = try XCTUnwrap(sample.snapshot)
        let data = try XCTUnwrap(snapshot.cgImage.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        let width = snapshot.cgImage.width, height = snapshot.cgImage.height
        // Before action 3, this original top-left corner is still white. The
        // action-3 target removes it; an invented 'match' would miss this error.
        let raw = try XCTUnwrap(snapshot.viewportPoint(forSheetPoint: CGPoint(x: 0.1, y: 0.1)))
        XCTAssertEqual(bytes[Int(raw.y * CGFloat(height)) * width + Int(raw.x * CGFloat(width))], 245)
        XCTAssertEqual(bytes[0], 25)
        let image = PaperLuminanceImage(width: width, height: height,
                                        pixels: Array(UnsafeBufferPointer(start: bytes, count: width * height)))
        let rerun = DartOutlineChecker.evaluate(image: image, pose: snapshot.rawSheetQuadrilateral,
                                                state: 3, timestamp: sample.result.timestamp)
        XCTAssertEqual(rerun.outcome, .needsAdjustment)
        XCTAssertEqual(rerun.mismatchedPoints, sample.result.mismatchedPoints)
    }

    private func make(action: Int, visible: Bool = true,
                      size: CGSize = CGSize(width: 390, height: 500)) -> DartPracticeSyntheticComparison {
        DartPracticeSyntheticComparison.make(action: action, sheetVisible: visible, viewportSize: size,
                                             timestamp: 100, now: 100.1)
    }
}
#endif
