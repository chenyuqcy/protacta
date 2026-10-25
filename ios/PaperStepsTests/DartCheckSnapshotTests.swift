import CoreGraphics
import CoreFoundation
import CoreVideo
import Foundation
import XCTest
@testable import Protacta

final class DartCheckSnapshotTests: XCTestCase {
    func testCameraYUVRangesReachSnapshotWithoutRowOrRangeChanges() throws {
        // AR camera buffers use a separate Y plane. These hardcoded asymmetric
        // black/white/midgray bands check that path, not only generated BGRA.
        let expected: [UInt8] = [0, 255, 126, 190]
        for format in [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange] {
            var optional: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 96, format, nil, &optional), kCVReturnSuccess)
            let buffer = try XCTUnwrap(optional)
            XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, []), kCVReturnSuccess)
            let base = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(buffer, 0)).assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            let encoded: [UInt8] = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ? [16, 235, 125, 180] : expected
            let lowerOrder = [3, 2, 0, 1]
            for row in 0..<96 {
                for column in 0..<64 {
                    let band = column / 16
                    base[row * stride + column] = encoded[row < 48 ? band : lowerOrder[band]]
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let image = try XCTUnwrap(PrintedPaperTracker.luminanceImage(pixelBuffer: buffer, maximumDimension: 96))
            let snapshot = try XCTUnwrap(DartCheckSnapshot(image: image, result: check(outcome: .cannotJudge),
                                                          rawSheetQuadrilateral: nil, displayTransform: .identity,
                                                          viewportSize: CGSize(width: 320, height: 480), isSynthetic: true, now: 100.1))
            let data = try XCTUnwrap(snapshot.cgImage.dataProvider?.data)
            let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
            for band in 0..<4 {
                XCTAssertEqual(bytes[band * 16 + 4], expected[band])
                XCTAssertEqual(bytes[60 * 64 + band * 16 + 4], expected[lowerOrder[band]])
            }
        }
    }
    func testGrayscaleRasterPreservesAsymmetricTopLeftPixelsAndOwnsItsBytes() throws {
        var pixels = Array(repeating: UInt8(100), count: 64 * 96)
        pixels[0] = 17
        pixels[63] = 31
        pixels[64] = 59
        pixels[(96 - 1) * 64] = 173
        pixels[pixels.count - 1] = 239
        let input = PaperLuminanceImage(width: 64, height: 96, pixels: pixels)
        let snapshot = try XCTUnwrap(make(image: input))
        pixels[0] = 255
        let data = try XCTUnwrap(snapshot.cgImage.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        XCTAssertEqual(CFDataGetLength(data), 64 * 96)
        XCTAssertEqual(bytes[0], 17)
        XCTAssertEqual(bytes[63], 31)
        XCTAssertEqual(bytes[64], 59)
        XCTAssertEqual(bytes[(96 - 1) * 64], 173)
        XCTAssertEqual(bytes[64 * 96 - 1], 239)
        XCTAssertEqual(snapshot.cgImage.width, 64)
        XCTAssertEqual(snapshot.cgImage.height, 96)
        XCTAssertEqual(snapshot.cgImage.bitsPerComponent, 8)
        XCTAssertEqual(snapshot.cgImage.bitsPerPixel, 8)
        XCTAssertEqual(snapshot.cgImage.bytesPerRow, 64)
        XCTAssertEqual(snapshot.cgImage.colorSpace?.model, .monochrome)
    }

    func testFrozenPortraitRotationAndAspectCropMapRawCoordinatesExactlyOnce() throws {
        // raw (x,y) -> viewport (1-y, 1.2*x-0.1), a 90-degree rotation plus crop.
        let transform = CGAffineTransform(a: 0, b: 1.2, c: -1, d: 0, tx: 1, ty: -0.1)
        let snapshot = try XCTUnwrap(make(transform: transform))
        let origin = try XCTUnwrap(snapshot.viewportPoint(forSheetPoint: .zero))
        XCTAssertEqual(origin.x, 0.9, accuracy: 0.000001)
        XCTAssertEqual(origin.y, 0.14, accuracy: 0.000001)
        let independent = try XCTUnwrap(snapshot.viewportPoint(forSheetPoint: CGPoint(x: 0.25, y: 0.75)))
        XCTAssertEqual(independent.x, 0.3, accuracy: 0.000001)
        XCTAssertEqual(independent.y, 0.32, accuracy: 0.000001)
        XCTAssertEqual(snapshot.displayTransform, transform)
        XCTAssertEqual(snapshot.viewportSize, CGSize(width: 300, height: 600))
        XCTAssertEqual(snapshot.cgImage.width, 64, "Raw raster must not be rotated into a second image")
        XCTAssertEqual(snapshot.cgImage.height, 96)
    }

    func testSemanticCornerRotationIsPreservedRatherThanSorted() throws {
        let rotated = quad.rotated(by: 2)
        let snapshot = try XCTUnwrap(make(quad: rotated))
        let origin = try XCTUnwrap(snapshot.viewportPoint(forSheetPoint: .zero))
        XCTAssertEqual(origin.x, quad.bottomRight.x, accuracy: 0.000001)
        XCTAssertEqual(origin.y, quad.bottomRight.y, accuracy: 0.000001)
        XCTAssertEqual(snapshot.rawSheetQuadrilateral, rotated)
    }

    func testOutlineAndMismatchUseTheSameFrozenProjectionAndKeepResultScope() throws {
        let mismatch = CGPoint(x: 0.25, y: 0.75)
        let snapshot = try XCTUnwrap(make(result: check(outcome: .needsAdjustment, points: [mismatch])))
        let expected = try XCTUnwrap(snapshot.viewportPoint(forSheetPoint: mismatch))
        XCTAssertEqual(snapshot.mismatchViewportPoints, [expected])
        XCTAssertEqual(snapshot.outlineViewportPoints.count, (DartOutlineChecker.outline(state: 2)?.count ?? 0))
        XCTAssertEqual(snapshot.result.outcome, .needsAdjustment)
        XCTAssertEqual(snapshot.result.message, "Visible outline only; compare hidden creases yourself.")
        XCTAssertEqual(snapshot.action, 2)
        XCTAssertEqual(snapshot.capturedUptime, 100)
        XCTAssertFalse(snapshot.isSynthetic)
        XCTAssertNotEqual(snapshot.id, try XCTUnwrap(make()).id)
    }

    func testUnknownWithoutPoseCanFreezeImageButCannotInventProjectedGeometry() throws {
        let snapshot = try XCTUnwrap(make(result: check(outcome: .cannotJudge), quad: nil, synthetic: true))
        XCTAssertNil(snapshot.rawSheetQuadrilateral)
        XCTAssertTrue(snapshot.outlineViewportPoints.isEmpty)
        XCTAssertTrue(snapshot.mismatchViewportPoints.isEmpty)
        XCTAssertNil(snapshot.viewportPoint(forSheetPoint: CGPoint(x: 0.5, y: 0.5)))
        XCTAssertTrue(snapshot.isSynthetic)
        XCTAssertEqual(snapshot.cgImage.width, 64)
        XCTAssertNil(make(result: check(outcome: .visibleMatch), quad: nil))
        XCTAssertNil(make(result: check(outcome: .cannotJudge, points: [.zero]), quad: nil))
    }

    func testUnsupportedActionsOnlyFreezeCannotJudgeWithAuthoredHelpScope() {
        for state in [1, 7, 8, 9, 10] {
            XCTAssertNotNil(make(result: check(state: state, outcome: .cannotJudge), quad: nil))
            XCTAssertNil(make(result: check(state: state, outcome: .visibleMatch)))
            XCTAssertNil(make(result: check(state: state, outcome: .needsAdjustment)))
        }
        XCTAssertNil(make(result: check(state: 0, outcome: .cannotJudge), quad: nil))
        XCTAssertNil(make(result: check(state: 11, outcome: .cannotJudge), quad: nil))
    }

    func testStaleFutureAndNonFiniteTimestampsCannotCreateSnapshots() {
        XCTAssertNotNil(make(now: 100.34))
        XCTAssertNil(make(now: 100.36))
        XCTAssertNil(make(now: 99.99))
        XCTAssertNil(make(now: .infinity))
        XCTAssertNil(make(result: check(timestamp: .nan)))
        XCTAssertNil(make(result: check(timestamp: -1)))
    }

    func testInvalidLuminanceSizesAndTruncatedBuffersAreRejected() {
        for image in [PaperLuminanceImage(width: 63, height: 96, pixels: []),
                      PaperLuminanceImage(width: 64, height: 63, pixels: []),
                      PaperLuminanceImage(width: 4097, height: 64, pixels: []),
                      PaperLuminanceImage(width: Int.max, height: Int.max, pixels: []),
                      PaperLuminanceImage(width: 64, height: 96, pixels: Array(repeating: 0, count: 100))] {
            XCTAssertNil(make(image: image))
        }
    }

    func testInvalidPoseTransformsAndViewportsAreRejected() {
        let collapsed = PaperQuadrilateral(topLeft: .zero, topRight: .zero, bottomRight: .zero, bottomLeft: .zero)
        XCTAssertNil(make(quad: collapsed))
        let outside = PaperQuadrilateral(topLeft: CGPoint(x: -0.01, y: 0.1), topRight: CGPoint(x: 0.8, y: 0.1),
                                         bottomRight: CGPoint(x: 0.8, y: 0.9), bottomLeft: CGPoint(x: -0.01, y: 0.9))
        XCTAssertNil(make(quad: outside))
        XCTAssertNil(make(transform: CGAffineTransform(a: 1, b: 0, c: 0, d: 0, tx: 0, ty: 0)))
        XCTAssertNil(make(transform: CGAffineTransform(a: .nan, b: 0, c: 0, d: 1, tx: 0, ty: 0)))
        XCTAssertNil(make(size: CGSize(width: 0, height: 600)))
        XCTAssertNil(make(size: CGSize(width: 300, height: CGFloat.infinity)))
        XCTAssertNil(make(transform: CGAffineTransform(translationX: 0.3, y: 0)), "Do not clamp a cropped outline into view")
    }

    func testMismatchPointsAreBoundedAndQueryRejectsNonfiniteOrOutsidePoints() throws {
        XCTAssertNil(make(result: check(points: Array(repeating: .zero, count: 65))))
        XCTAssertNil(make(result: check(points: [CGPoint(x: -0.01, y: 0.5)])))
        XCTAssertNil(make(result: check(points: [CGPoint(x: .nan, y: 0.5)])))
        let snapshot = try XCTUnwrap(make())
        XCTAssertNil(snapshot.viewportPoint(forSheetPoint: CGPoint(x: 1.1, y: 0.5)))
        XCTAssertNil(snapshot.viewportPoint(forSheetPoint: CGPoint(x: 0.5, y: .nan)))
    }

    private var quad: PaperQuadrilateral {
        PaperQuadrilateral(topLeft: CGPoint(x: 0.2, y: 0.1), topRight: CGPoint(x: 0.8, y: 0.1),
                           bottomRight: CGPoint(x: 0.8, y: 0.9), bottomLeft: CGPoint(x: 0.2, y: 0.9))
    }

    private func check(state: Int = 2, outcome: PaperCheckOutcome = .visibleMatch,
                       points: [CGPoint] = [], timestamp: TimeInterval = 100) -> DartOutlineCheckResult {
        DartOutlineCheckResult(checkpointID: "dart-visible-outline-\(state)-v1", referenceState: state,
                               outcome: outcome, message: "Visible outline only; compare hidden creases yourself.",
                               mismatchedPoints: points, timestamp: timestamp)
    }

    private func make(image: PaperLuminanceImage? = nil, result: DartOutlineCheckResult? = nil,
                      quad: PaperQuadrilateral? = PaperQuadrilateral(topLeft: CGPoint(x: 0.2, y: 0.1), topRight: CGPoint(x: 0.8, y: 0.1),
                                                                    bottomRight: CGPoint(x: 0.8, y: 0.9), bottomLeft: CGPoint(x: 0.2, y: 0.9)),
                      transform: CGAffineTransform = .identity,
                      size: CGSize = CGSize(width: 300, height: 600), synthetic: Bool = false,
                      now: TimeInterval = 100.1) -> DartCheckSnapshot? {
        DartCheckSnapshot(image: image ?? PaperLuminanceImage(width: 64, height: 96, pixels: Array(repeating: 200, count: 64 * 96)),
                          result: result ?? check(), rawSheetQuadrilateral: quad,
                          displayTransform: transform, viewportSize: size, isSynthetic: synthetic, now: now)
    }
}
