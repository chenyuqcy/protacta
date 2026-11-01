import XCTest
import simd
@testable import Protacta

final class SceneDepthPersonMaskTests: XCTestCase {
    func testDifferentResolutionsUseSensorCoordinatesAndPreserveSmallPersonLabels() throws {
        var labels = Array(repeating: UInt8(0), count: 4 * 4)
        labels[1 * 4 + 2] = 1
        let coarse = SceneDepthPersonMask(width: 4, height: 4, values: labels)
        let expanded = try XCTUnwrap(coarse.exclusionMask(depthWidth: 8, depthHeight: 8, radius: 0))
        let expected = Set([2 * 8 + 4, 2 * 8 + 5, 3 * 8 + 4, 3 * 8 + 5])
        XCTAssertEqual(Set(expanded.indices.filter { expanded[$0] }), expected)

        var fineLabels = Array(repeating: UInt8(0), count: 8 * 8)
        fineLabels[6 * 8 + 1] = 255
        let fine = SceneDepthPersonMask(width: 8, height: 8, values: fineLabels)
        let reduced = try XCTUnwrap(fine.exclusionMask(depthWidth: 4, depthHeight: 4, radius: 0))
        XCTAssertEqual(Set(reduced.indices.filter { reduced[$0] }), Set([3 * 4]))
        XCTAssertFalse(reduced[3], "Sensor rows/columns must not be transposed or mirrored")
    }

    func testDilationUsesDepthPixelsAndClipsAtAllEdges() throws {
        var labels = Array(repeating: UInt8(0), count: 7 * 5)
        labels[2 * 7 + 3] = 128
        let mask = SceneDepthPersonMask(width: 7, height: 5, values: labels)
        let margin = try XCTUnwrap(mask.exclusionMask(depthWidth: 7, depthHeight: 5, radius: 1))
        let expected = Set((1...3).flatMap { y in (2...4).map { y * 7 + $0 } })
        XCTAssertEqual(Set(margin.indices.filter { margin[$0] }), expected)
        XCTAssertEqual(try XCTUnwrap(mask.exclusionMask(depthWidth: 7, depthHeight: 5, radius: Int.max)).filter { $0 }.count, 35)
        XCTAssertEqual(try XCTUnwrap(mask.exclusionMask(depthWidth: 7, depthHeight: 5, radius: Int.min)).filter { $0 }.count, 1)

        for corner in [0, 6, 4 * 7, 5 * 7 - 1] {
            var edge = Array(repeating: UInt8(0), count: 35); edge[corner] = 2
            let result = try XCTUnwrap(SceneDepthPersonMask(width: 7, height: 5, values: edge)
                .exclusionMask(depthWidth: 7, depthHeight: 5, radius: 1))
            XCTAssertEqual(result.filter { $0 }.count, 4)
            XCTAssertTrue(result[corner])
        }
    }

    func testOnlyPersonUnionIsClearedAndCameraCalibrationIsUntouched() throws {
        let input = snapshot(width: 6, height: 4)
        var labels = Array(repeating: UInt8(0), count: 24)
        labels[1 * 6 + 1] = 1; labels[1 * 6 + 3] = 255
        let mask = SceneDepthPersonMask(width: 6, height: 4, values: labels)
        let bitmap = try XCTUnwrap(mask.exclusionMask(depthWidth: 6, depthHeight: 4, radius: 1))
        let result = try XCTUnwrap(mask.excludingPeople(from: input, radius: 1))
        XCTAssertEqual(result.excludedPixels, 15, "Overlapping margins count each depth pixel once")
        for i in input.depths.indices {
            XCTAssertEqual(result.snapshot.depths[i], bitmap[i] ? 0 : input.depths[i])
            XCTAssertEqual(result.snapshot.confidence[i], bitmap[i] ? 0 : input.confidence[i])
        }
        XCTAssertEqual(result.snapshot.calibration, input.calibration)
        XCTAssertEqual(result.snapshot.timestamp, input.timestamp)
        for column in 0..<4 { XCTAssertEqual(result.snapshot.cameraTransform[column], input.cameraTransform[column]) }
        XCTAssertEqual(input.depths, snapshot(width: 6, height: 4).depths, "Filtering must not mutate the owned input snapshot")
    }

    func testEmptyCurrentMaskImmediatelyRestoresTheFreshDepthWithoutRememberingHands() throws {
        let input = snapshot(width: 8, height: 6)
        var labels = Array(repeating: UInt8(0), count: 48); labels[2 * 8 + 3] = 1
        let occupied = try XCTUnwrap(SceneDepthPersonMask(width: 8, height: 6, values: labels)
            .excludingPeople(from: input, radius: 1))
        XCTAssertEqual(occupied.excludedPixels, 9)
        let empty = SceneDepthPersonMask(width: 8, height: 6, values: Array(repeating: 0, count: 48))
        let cleared = try XCTUnwrap(empty.excludingPeople(from: input))
        XCTAssertEqual(cleared.excludedPixels, 0)
        XCTAssertEqual(cleared.snapshot.depths, input.depths)
        XCTAssertEqual(cleared.snapshot.confidence, input.confidence)
        XCTAssertEqual(try XCTUnwrap(empty.exclusionMask(depthWidth: 8, depthHeight: 6)).filter { $0 }.count, 0)
    }

    func testMalformedAndRotatedLayoutsAreRejectedRatherThanGuessed() {
        let input = snapshot(width: 8, height: 6)
        for mask in [
            SceneDepthPersonMask(width: 0, height: 6, values: []),
            SceneDepthPersonMask(width: -1, height: 6, values: []),
            SceneDepthPersonMask(width: 4097, height: 1, values: []),
            SceneDepthPersonMask(width: Int.max, height: 1, values: []),
            SceneDepthPersonMask(width: 8, height: 6, values: Array(repeating: 0, count: 47)),
            SceneDepthPersonMask(width: 6, height: 8, values: Array(repeating: 0, count: 48)),
            SceneDepthPersonMask(width: 16, height: 6, values: Array(repeating: 0, count: 96))
        ] {
            XCTAssertNil(mask.excludingPeople(from: input))
            XCTAssertNil(mask.exclusionMask(depthWidth: 8, depthHeight: 6))
        }
        let mask = SceneDepthPersonMask(width: 8, height: 6, values: Array(repeating: 0, count: 48))
        XCTAssertNil(mask.exclusionMask(depthWidth: 0, depthHeight: 6))
        XCTAssertNil(mask.exclusionMask(depthWidth: 8, depthHeight: 4097))
        var malformed = input; malformed.depths.removeLast()
        XCTAssertNil(mask.excludingPeople(from: malformed))
        malformed = input; malformed.confidence.removeAll()
        XCTAssertNil(mask.excludingPeople(from: malformed))
    }

    func testSmallResolutionRoundingIsAcceptedWithoutRotatingTheMask() throws {
        let mask = SceneDepthPersonMask(width: 257, height: 192,
                                       values: Array(repeating: 1, count: 257 * 192))
        let result = try XCTUnwrap(mask.exclusionMask(depthWidth: 256, depthHeight: 192, radius: 0))
        XCTAssertEqual(result.count, 256 * 192)
        XCTAssertTrue(result.allSatisfy { $0 })
    }

    func testBakedProtectionRejectsNewHandPixelsButAcceptsAShrinkingHand() {
        let roi = SceneDepthRegion(x: 1, y: 1, width: 4, height: 3)
        var protected = Array(repeating: false, count: 7 * 5)
        protected[2 * 7 + 2] = true; protected[2 * 7 + 3] = true
        XCTAssertTrue(SceneDepthPersonMask.coversPersonRegion(protected: protected, required: protected, width: 7, region: roi))
        var shrink = protected; shrink[2 * 7 + 3] = false
        XCTAssertTrue(SceneDepthPersonMask.coversPersonRegion(protected: protected, required: shrink, width: 7, region: roi))
        var expansion = protected; expansion[3 * 7 + 4] = true
        XCTAssertFalse(SceneDepthPersonMask.coversPersonRegion(protected: protected, required: expansion, width: 7, region: roi),
                       "An old custom mesh must not cover a newly arrived native hand pixel")
        XCTAssertTrue(SceneDepthPersonMask.coversPersonRegion(protected: protected,
            required: Array(repeating: false, count: 35), width: 7, region: roi), "Complete withdrawal does not require stale person holes")
    }

    func testPersonChangesOutsideTheDisplayedRegionDoNotInvalidateItsProtection() {
        let roi = SceneDepthRegion(x: 2, y: 1, width: 3, height: 2)
        let protected = Array(repeating: false, count: 7 * 5)
        var required = protected
        for i in [0, 6, 4 * 7, 4 * 7 + 6, 1 * 7 + 1, 1 * 7 + 5] { required[i] = true }
        XCTAssertTrue(SceneDepthPersonMask.coversPersonRegion(protected: protected, required: required, width: 7, region: roi))
        required[1 * 7 + 2] = true
        XCTAssertFalse(SceneDepthPersonMask.coversPersonRegion(protected: protected, required: required, width: 7, region: roi),
                       "The first included pixel must be protected; ROI bounds are not shifted")
    }

    func testCoverageComparisonRejectsMalformedArraysAndUnsafeRegionBounds() {
        let pixels = Array(repeating: false, count: 7 * 5)
        let good = SceneDepthRegion(x: 0, y: 0, width: 7, height: 5)
        XCTAssertFalse(SceneDepthPersonMask.coversPersonRegion(protected: [], required: [], width: 7, region: good))
        XCTAssertFalse(SceneDepthPersonMask.coversPersonRegion(protected: pixels, required: Array(pixels.dropLast()), width: 7, region: good))
        for width in [0, -1, 4097, Int.max, 6] {
            XCTAssertFalse(SceneDepthPersonMask.coversPersonRegion(protected: pixels, required: pixels, width: width, region: good))
        }
        for roi in [
            SceneDepthRegion(x: -1, y: 0, width: 2, height: 2),
            SceneDepthRegion(x: 0, y: -1, width: 2, height: 2),
            SceneDepthRegion(x: 7, y: 0, width: 1, height: 1),
            SceneDepthRegion(x: 0, y: 5, width: 1, height: 1),
            SceneDepthRegion(x: 0, y: 0, width: 0, height: 2),
            SceneDepthRegion(x: 0, y: 0, width: 2, height: 0),
            SceneDepthRegion(x: 6, y: 4, width: 2, height: 1),
            SceneDepthRegion(x: 6, y: 4, width: 1, height: 2),
            SceneDepthRegion(x: Int.max, y: 0, width: Int.max, height: 2),
            SceneDepthRegion(x: 0, y: 0, width: Int.max, height: Int.max)
        ] {
            XCTAssertFalse(SceneDepthPersonMask.coversPersonRegion(protected: pixels, required: pixels, width: 7, region: roi))
        }
    }

    private func snapshot(width: Int, height: Int) -> SceneDepthSnapshot {
        SceneDepthSnapshot(width: width, height: height,
                           depths: (0..<(width * height)).map { 0.4 + Float($0) * 0.001 },
                           confidence: Array(repeating: 2, count: width * height),
                           calibration: [120, 121, 3, 2], cameraTransform: matrix_identity_float4x4, timestamp: 3.25)
    }
}
