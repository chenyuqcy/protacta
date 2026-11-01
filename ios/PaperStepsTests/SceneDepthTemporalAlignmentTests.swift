import Foundation
import XCTest
import simd
@testable import Protacta

/// Analytical synthetic camera geometry. These are not physical hand-edge or
/// learner measurements, and forward projection does not create unseen pixels.
final class SceneDepthTemporalAlignmentTests: XCTestCase {
    private func snapshot(width: Int = 9, height: Int = 7, depth: Float = 0.5,
                          k: SIMD4<Float> = [200, 200, 4, 3], time: Double = 1,
                          pose: simd_float4x4 = matrix_identity_float4x4) -> SceneDepthSnapshot {
        SceneDepthSnapshot(width: width, height: height,
                           depths: Array(repeating: depth, count: width * height),
                           confidence: Array(repeating: 2, count: width * height),
                           calibration: k, cameraTransform: pose, timestamp: time)
    }

    private func translation(x: Float = 0, y: Float = 0, z: Float = 0) -> simd_float4x4 {
        var pose = matrix_identity_float4x4
        pose.columns.3 = [x, y, z, 1]
        return pose
    }

    private func warp(_ old: SceneDepthSnapshot, to current: SceneDepthSnapshot,
                      holds: [UInt8]? = nil, observed: [TimeInterval]? = nil,
                      excluding mask: [Bool]? = nil) -> SceneDepthTemporalAlignment.History? {
        SceneDepthTemporalAlignment.reproject(old, into: current,
            heldFrames: holds ?? Array(repeating: 0, count: old.depths.count),
            lastObservedAt: observed, excluding: mask)
    }

    func testNearForegroundMovesToTheCurrentPixelWithItsHoldMetadata() throws {
        var old = snapshot(depth: 0)
        old.confidence = Array(repeating: 0, count: old.depths.count)
        let source = 3 * old.width + 4
        old.depths[source] = 0.2; old.confidence[source] = 2
        var holds = Array(repeating: UInt8(0), count: old.depths.count); holds[source] = 1
        var observed = Array(repeating: old.timestamp, count: old.depths.count); observed[source] = 0.98
        let current = snapshot(time: 1.033, pose: translation(x: 0.002))
        let aligned = try XCTUnwrap(warp(old, to: current, holds: holds, observed: observed))
        // fx * tx / depth = 200*.002/.2 = 2 pixels to the left.
        let destination = 3 * old.width + 2
        XCTAssertEqual(aligned.depths[destination], 0.2, accuracy: 0.000001)
        XCTAssertEqual(aligned.confidence[destination], 2)
        XCTAssertEqual(aligned.heldFrames[destination], 1)
        XCTAssertEqual(aligned.lastObservedAt[destination], 0.98)
        XCTAssertEqual(aligned.confidence[source], 0, "History cannot stay at the old image pixel")
        XCTAssertEqual(aligned.confidence.filter { $0 > 0 }.count, 1)
    }

    func testForwardCameraTranslationChangesPlaneDepthBeforeFiltering() throws {
        let old = snapshot(depth: 0.5)
        let current = snapshot(depth: 0.505, time: 1.033, pose: translation(z: 0.003))
        let aligned = try XCTUnwrap(warp(old, to: current))
        XCTAssertEqual(aligned.depths[31], 0.503, accuracy: 0.000001)
        var filter = EquipmentDepthStabilizer()
        _ = filter.filter(old)
        XCTAssertEqual(filter.filter(current).depths[31], 0.503, accuracy: 0.000001,
                       "The deadband must hold reprojected metric depth, not old camera depth")
    }

    func testRotatedCameraDepthMatchesAnAnalyticalWorldPlane() throws {
        let width = 17, height = 9
        let k = SIMD4<Float>(200, 200, 8, 4), distance: Float = 0.8
        let angle = Float(0.4 * Double.pi / 180)
        let pose = simd_float4x4(simd_quatf(angle: angle, axis: [0, 1, 0]))
        let old = snapshot(width: width, height: height, depth: distance, k: k)
        let current = snapshot(width: width, height: height, depth: distance, k: k, time: 1.033, pose: pose)
        let aligned = try XCTUnwrap(warp(old, to: current))
        var checked = 0
        for y in 1..<(height - 1) { for x in 2..<(width - 2) {
            let index = y * width + x
            guard aligned.confidence[index] > 0 else { continue }
            let rayX = (Float(x) - k.z) / k.x
            // The world plane is z=-distance; camera yaw rotates its ray.
            let expected = distance / (cos(angle) + sin(angle) * rayX)
            XCTAssertEqual(aligned.depths[index], expected, accuracy: 0.00005)
            checked += 1
        } }
        XCTAssertGreaterThan(checked, 50)
    }

    func testRotatedForegroundUsesTheNewPixelAndMetricDepth() throws {
        var old = snapshot(depth: 0)
        old.confidence = Array(repeating: 0, count: old.depths.count)
        old.depths[31] = 0.25; old.confidence[31] = 2
        let angle = Float(0.4 * Double.pi / 180)
        let pose = simd_float4x4(simd_quatf(angle: angle, axis: [0, 1, 0]))
        let current = snapshot(time: 1.033, pose: pose)
        let aligned = try XCTUnwrap(warp(old, to: current))
        let x = Int((current.calibration.x * tan(angle) + current.calibration.z).rounded())
        XCTAssertEqual(aligned.depths[3 * old.width + x], 0.25 * cos(angle), accuracy: 0.000001)
        XCTAssertEqual(aligned.confidence[31], 0)
        XCTAssertEqual(aligned.confidence.filter { $0 > 0 }.count, 1)
    }

    func testChangedCropCalibrationAndSizeMoveTheHistoryRatherThanResetOrReuseItsIndex() throws {
        var old = snapshot(depth: 0)
        old.confidence = Array(repeating: 0, count: old.depths.count)
        let source = 3 * old.width + 4
        old.depths[source] = 0.35; old.confidence[source] = 1
        var holds = Array(repeating: UInt8(0), count: old.depths.count); holds[source] = 2
        let current = snapshot(width: 7, height: 7, k: [200, 200, 2, 3], time: 1.033)
        let aligned = try XCTUnwrap(warp(old, to: current, holds: holds))
        let destination = 3 * current.width + 2
        XCTAssertEqual(aligned.depths.count, 49)
        XCTAssertEqual(aligned.depths[destination], 0.35)
        XCTAssertEqual(aligned.heldFrames[destination], 2)
        XCTAssertEqual(aligned.confidence[destination + 2], 0)

        // A fresh calibrated crop still participates in temporal stabilization.
        var sourcePlane = snapshot(k: [100, 100, 4, 3])
        for y in 0..<sourcePlane.height { for x in 0..<sourcePlane.width {
            sourcePlane.depths[y * sourcePlane.width + x] = 0.5 + Float(x) * 0.003
        } }
        var shifted = sourcePlane
        shifted.timestamp = 1.033; shifted.calibration.z -= 2
        for y in 0..<shifted.height { for x in 0..<shifted.width {
            shifted.depths[y * shifted.width + x] = 0.5 + Float(x + 2) * 0.003 + 0.004
        } }
        var filter = EquipmentDepthStabilizer(); _ = filter.filter(sourcePlane)
        XCTAssertEqual(filter.filter(shifted).depths[3 * shifted.width + 2], 0.512, accuracy: 0.000001)
    }

    func testNearestDepthWinsAProjectionCollisionAndTransportsThatSamplesMetadata() throws {
        var old = snapshot(width: 4, height: 3, depth: 0, k: [100, 100, 0, 1])
        old.confidence = Array(repeating: 0, count: old.depths.count)
        old.depths[5] = 1; old.confidence[5] = 2
        old.depths[6] = 0.3; old.confidence[6] = 1
        var holds = Array(repeating: UInt8(0), count: old.depths.count); holds[6] = 2
        var observed = Array(repeating: old.timestamp, count: old.depths.count); observed[6] = 0.99
        let current = snapshot(width: 4, height: 3, k: [1, 100, 0, 1], time: 1.033)
        let aligned = try XCTUnwrap(warp(old, to: current, holds: holds, observed: observed))
        XCTAssertEqual(aligned.depths[4], 0.3)
        XCTAssertEqual(aligned.confidence[4], 1, "A more reliable background cannot overtake a nearer point")
        XCTAssertEqual(aligned.heldFrames[4], 2)
        XCTAssertEqual(aligned.lastObservedAt[4], 0.99)
        XCTAssertEqual(aligned.confidence.filter { $0 > 0 }.count, 1)
    }

    func testDisoccludedPixelsAndOutOfViewSamplesStayUnknown() throws {
        var old = snapshot(width: 13, height: 3, depth: 1, k: [200, 200, 6, 1])
        for y in 0..<old.height { for x in 4...8 { old.depths[y * old.width + x] = 0.2 } }
        let current = snapshot(width: 13, height: 3, k: old.calibration, time: 1.033, pose: translation(x: 0.003))
        let aligned = try XCTUnwrap(warp(old, to: current))
        // The foreground shifts 3px while the background shifts only .6px.
        // The hidden background at x6/x7 was never observed in the old frame.
        for x in [6, 7] {
            XCTAssertEqual(aligned.confidence[old.width + x], 0)
            XCTAssertEqual(aligned.depths[old.width + x], 0)
        }
        XCTAssertEqual(aligned.depths[old.width + 3], 0.2, accuracy: 0.000001)
        XCTAssertEqual(aligned.depths[old.width + 9], 1, accuracy: 0.000001)
    }

    func testCurrentExclusionDiscardsReprojectedDepthAndHoldState() throws {
        var old = snapshot(depth: 0)
        old.confidence = Array(repeating: 0, count: old.depths.count)
        old.depths[31] = 0.2; old.confidence[31] = 2
        var holds = Array(repeating: UInt8(0), count: old.depths.count); holds[31] = 1
        let current = snapshot(time: 1.033, pose: translation(x: 0.002))
        var mask = Array(repeating: false, count: current.depths.count); mask[29] = true
        let aligned = try XCTUnwrap(warp(old, to: current, holds: holds, excluding: mask))
        XCTAssertTrue(aligned.confidence.allSatisfy { $0 == 0 })
        XCTAssertTrue(aligned.heldFrames.allSatisfy { $0 == 0 })
        XCTAssertTrue(aligned.lastObservedAt.allSatisfy { $0 == 0 })
        XCTAssertNil(warp(old, to: current, excluding: [true]))
    }

    func testMalformedGeometryAndHistoryMetadataAreRejected() {
        let old = snapshot(), current = snapshot(time: 1.033)
        var invalids: [SceneDepthSnapshot] = []
        var value = old; value.width = 0; invalids.append(value)
        value = old; value.depths.removeLast(); invalids.append(value)
        value = old; value.confidence.removeLast(); invalids.append(value)
        value = old; value.calibration.x = 0; invalids.append(value)
        value = old; value.calibration.w = .nan; invalids.append(value)
        value = old; value.cameraTransform[0].x = 0; invalids.append(value)
        value = old; value.cameraTransform[1].x = 0.2; invalids.append(value)
        value = old; value.cameraTransform[2].z = -1; invalids.append(value)
        value = old; value.cameraTransform[3].x = .infinity; invalids.append(value)
        value = old; value.cameraTransform[0].w = 0.2; invalids.append(value)
        value = old; value.timestamp = .nan; invalids.append(value)
        for input in invalids { XCTAssertNil(warp(input, to: current)) }
        XCTAssertNil(warp(old, to: current, holds: [0]))
        XCTAssertNil(warp(old, to: current, observed: [1]))
        var badCurrent = current; badCurrent.calibration.y = -1
        XCTAssertNil(warp(old, to: badCurrent))

        var unknown = old
        unknown.depths = Array(repeating: .nan, count: old.depths.count)
        XCTAssertTrue(warp(unknown, to: current)?.confidence.allSatisfy { $0 == 0 } == true)
    }

    func testAgeMotionAndBackwardsTimeCannotAdmitStaleHistory() throws {
        let old = snapshot()
        for time in [0.9, 1.0, 1.12, 2.0] { XCTAssertNil(warp(old, to: snapshot(time: time))) }
        XCTAssertNil(warp(old, to: snapshot(time: 1.033, pose: translation(x: 0.02))))
        let turn = simd_float4x4(simd_quatf(angle: .pi / 180, axis: [0, 1, 0]))
        XCTAssertNil(warp(old, to: snapshot(time: 1.033, pose: turn)))
        let observed = Array(repeating: TimeInterval(0.99), count: old.depths.count)
        let aged = try XCTUnwrap(warp(old, to: snapshot(time: 1.115), observed: observed))
        XCTAssertTrue(aged.confidence.allSatisfy { $0 == 0 }, "Per-pixel age must include earlier held frames")
        var future = observed; future[31] = 1.01
        let invalidObservation = try XCTUnwrap(warp(old, to: snapshot(time: 1.033), observed: future))
        XCTAssertEqual(invalidObservation.confidence[31], 0)
    }
}
