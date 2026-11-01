import Foundation
import XCTest
import simd
@testable import Protacta

/// Synthetic projected-triangle ownership checks, not observed camera quality.
final class SceneDepthPersonCoverageTests: XCTestCase {
    private let k = SIMD4<Float>(100, 100, 5, 4)

    private func metadata(pose: simd_float4x4 = matrix_identity_float4x4,
                          calibration: SIMD4<Float>? = nil) -> SceneDepthSnapshot {
        // The coverage proof must not require copies of depth/confidence maps.
        SceneDepthSnapshot(width: 11, height: 9, depths: [], confidence: [],
                           calibration: calibration ?? k, cameraTransform: pose, timestamp: 1.033)
    }

    private func pixel(_ x: Float, _ y: Float, depth: Float = 0.5) -> SIMD3<Float> {
        [(x - k.z) / k.x * depth, -(y - k.w) / k.y * depth, -depth]
    }

    private func surface(_ positions: [SIMD3<Float>], triangles: [UInt32]) -> SceneDepthSurface {
        SceneDepthSurface(positions: positions, triangles: triangles, rejectedSamples: 0,
                          rejectedDiscontinuities: 0, rejectedSupportTriangles: 0)
    }

    private func quad(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float) -> SceneDepthSurface {
        surface([pixel(left, top), pixel(right, top), pixel(right, bottom), pixel(left, bottom)],
                triangles: [0, 1, 2, 0, 2, 3])
    }

    private func person(_ x: Int = 5, _ y: Int = 4) -> [Bool] {
        var mask = Array(repeating: false, count: 99); mask[y * 11 + x] = true
        return mask
    }

    private func disjoint(_ mesh: SceneDepthSurface, current: SceneDepthSnapshot? = nil,
                          sourcePose: simd_float4x4 = matrix_identity_float4x4,
                          mask: [Bool]? = nil) -> Bool {
        SceneDepthPersonCoverage.isDisjoint(surface: mesh, sourceCameraTransform: sourcePose,
                                            current: current ?? metadata(), personMask: mask ?? person())
    }

    func testSamePoseMeshWithAGenuineHoleDoesNotCompeteWithThePerson() {
        let panels = [quad(0, 1, 3, 7), quad(7, 1, 10, 7), quad(3, 0, 7, 2), quad(3, 6, 7, 8)]
        var points: [SIMD3<Float>] = [], triangles: [UInt32] = []
        for panel in panels {
            let offset = UInt32(points.count)
            points += panel.positions; triangles += panel.triangles.map { $0 + offset }
        }
        // The mesher keeps invalid positions as zero but never references them.
        // Such vertices must not be mistaken for a near-plane crossing.
        points.append(.zero)
        XCTAssertTrue(disjoint(surface(points, triangles: triangles)))
        XCTAssertFalse(disjoint(quad(3, 2, 7, 6)))
    }

    func testCameraTranslationMovesAnOldTriangleIntoTheCurrentPersonRegion() {
        let mesh = quad(1, 3, 3, 5)
        XCTAssertTrue(disjoint(mesh))
        var pose = matrix_identity_float4x4; pose.columns.3.x = -0.01
        // Current camera moving left shifts the old mesh two pixels right.
        // The current person bitmap is deliberately unchanged.
        XCTAssertFalse(disjoint(mesh, current: metadata(pose: pose)))
    }

    func testSourceCameraPoseIsUsedRatherThanTreatingMeshPositionsAsWorldCoordinates() {
        let mesh = quad(1, 3, 3, 5)
        var source = matrix_identity_float4x4; source.columns.3.x = 0.01
        XCTAssertFalse(disjoint(mesh, sourcePose: source))
    }

    func testCameraRotationMovesAnOldTriangleIntoTheCurrentPersonRegion() {
        let mesh = quad(1, 3, 3, 5)
        XCTAssertTrue(disjoint(mesh))
        let turned = simd_float4x4(simd_quatf(angle: 0.02, axis: [0, 1, 0]))
        XCTAssertFalse(disjoint(mesh, current: metadata(pose: turned)))
    }

    func testChangedCalibrationMovesTheMeshDespiteAnIdenticalCameraPoseAndMask() {
        let mesh = quad(1, 3, 3, 5)
        XCTAssertTrue(disjoint(mesh))
        var changed = k; changed.z += 2
        XCTAssertFalse(disjoint(mesh, current: metadata(calibration: changed)))
    }

    func testConservativeBoundingBoxRejectsEvenAPersonOutsideTheTriangleInterior() {
        let mesh = surface([pixel(1, 1), pixel(4, 1), pixel(1, 4)], triangles: [0, 1, 2])
        XCTAssertFalse(disjoint(mesh, mask: person(4, 4)),
                       "A conservative box may reject extra custom depth but cannot draw through a person")
    }

    func testCompletelyOffscreenTrianglesDoNotCompeteOrOverflowPixelConversions() {
        XCTAssertTrue(disjoint(quad(-10, 2, -5, 6)))
        XCTAssertTrue(disjoint(quad(20, 2, 25, 6)))
        XCTAssertTrue(disjoint(surface([[1e12, 0, -0.5], [1e12 + 1e6, 0, -0.5], [1e12, 1, -0.5]],
                                        triangles: [0, 1, 2])))
    }

    func testNearPlaneCrossingBehindCameraAndInvalidGeometryFailClosed() {
        var near = quad(1, 3, 3, 5); near.positions[0].z = -0.005
        XCTAssertFalse(disjoint(near))
        var behind = quad(1, 3, 3, 5); behind.positions[0].z = 0.2
        XCTAssertFalse(disjoint(behind))
        // Shared y/z coordinates keep this fixture truly degenerate in Float.
        XCTAssertFalse(disjoint(surface([[-0.02, 0, -0.5], [0, 0, -0.5], [0.02, 0, -0.5]],
                                        triangles: [0, 1, 2])))
        XCTAssertFalse(disjoint(surface([pixel(1, 1), pixel(2, 2), pixel(3, 1)], triangles: [0, 1])))
        XCTAssertFalse(disjoint(surface([pixel(1, 1), pixel(2, 2), pixel(3, 1)], triangles: [0, 1, 99])))
        var nonfinite = quad(1, 3, 3, 5); nonfinite.positions[0].x = .nan
        XCTAssertFalse(disjoint(nonfinite))
        var source = matrix_identity_float4x4; source.columns.0.x = 0
        XCTAssertFalse(disjoint(quad(1, 3, 3, 5), sourcePose: source))
    }

    func testMalformedCurrentMetadataAndMaskFailClosedButImageArraysMayBeEmpty() {
        let mesh = quad(1, 3, 3, 5)
        XCTAssertTrue(disjoint(mesh, current: metadata()))
        XCTAssertFalse(disjoint(mesh, mask: []))
        var variants: [SceneDepthSnapshot] = []
        var value = metadata(); value.width = 1; variants.append(value)
        value = metadata(); value.width = 5000; variants.append(value)
        value = metadata(); value.width = 4096; value.height = 4096; variants.append(value)
        value = metadata(); value.calibration.x = 0; variants.append(value)
        value = metadata(); value.calibration.y = -.infinity; variants.append(value)
        value = metadata(); value.calibration.w = .nan; variants.append(value)
        value = metadata(); value.cameraTransform[0].x = 0; variants.append(value)
        value = metadata(); value.cameraTransform[3].w = 0; variants.append(value)
        value = metadata(); value.timestamp = .nan; variants.append(value)
        for invalid in variants { XCTAssertFalse(disjoint(mesh, current: invalid)) }
    }

    func testNoPersonAndEmptyGeometryHaveNoCompetingCoverage() {
        let noPerson = Array(repeating: false, count: 99)
        XCTAssertTrue(disjoint(surface([], triangles: []), mask: noPerson))
        XCTAssertTrue(disjoint(surface([], triangles: [])))
        // No-person fast path still validates camera metadata and mask shape.
        var invalid = metadata(); invalid.calibration.x = 0
        XCTAssertFalse(disjoint(surface([], triangles: []), current: invalid, mask: noPerson))
    }

    func testClearObservationRejectsAnInvalidNonPersonRegionWithOnlyOneExcludedPixel() {
        XCTAssertFalse(SceneDepthClearObservation.isReliable(pixelCount: 100, excludedPixels: 1, reliableNonPersonPixels: 0))
        XCTAssertFalse(SceneDepthClearObservation.isReliable(pixelCount: 100, excludedPixels: 1, reliableNonPersonPixels: 12))
        XCTAssertFalse(SceneDepthClearObservation.isReliable(pixelCount: 100, excludedPixels: 0, reliableNonPersonPixels: 89))
        XCTAssertFalse(SceneDepthClearObservation.isReliable(pixelCount: 10, excludedPixels: 0, reliableNonPersonPixels: 9))
    }

    func testClearObservationAcceptsReliableSupportPlaneAndFullyExcludedPersonROI() {
        XCTAssertTrue(SceneDepthClearObservation.isReliable(pixelCount: 100, excludedPixels: 0, reliableNonPersonPixels: 90))
        XCTAssertTrue(SceneDepthClearObservation.isReliable(pixelCount: 100, excludedPixels: 20, reliableNonPersonPixels: 72))
        XCTAssertTrue(SceneDepthClearObservation.isReliable(pixelCount: 10, excludedPixels: 0, reliableNonPersonPixels: 10))
        XCTAssertTrue(SceneDepthClearObservation.isReliable(pixelCount: 100, excludedPixels: 100, reliableNonPersonPixels: 0))
    }

    func testMalformedClearObservationCountsFailClosed() {
        for counts in [(0, 0, 0), (-1, 0, 0), (100, -1, 90), (100, 101, 0),
                       (100, 20, -1), (100, 20, 81), (Int.max, 0, Int.max)] {
            XCTAssertFalse(SceneDepthClearObservation.isReliable(pixelCount: counts.0, excludedPixels: counts.1,
                                                                  reliableNonPersonPixels: counts.2))
        }
    }

    func testHighConfidenceCheckerAndStripeEmptyMeshesAreNotReliableClearObservations() {
        for checker in [true, false] {
            var snapshot = metadata()
            snapshot.depths = (0..<99).map { index in
                let x = index % snapshot.width, y = index / snapshot.width
                return (x + (checker ? y : 0)).isMultiple(of: 2) ? 0.5 : 0.8
            }
            snapshot.confidence = Array(repeating: 2, count: 99)
            let mesh = SceneDepthMesher.build(snapshot, supportPlaneY: nil, pixelStep: 1,
                                              policy: .stableEquipment)
            XCTAssertTrue(mesh.triangles.isEmpty)
            XCTAssertGreaterThan(mesh.rejectedDiscontinuities, 0)
            XCTAssertEqual(mesh.rejectedSamples, 0)
            XCTAssertTrue(SceneDepthClearObservation.isReliable(pixelCount: 99, excludedPixels: 0,
                                                               reliableNonPersonPixels: 99))
            XCTAssertFalse(SceneDepthClearObservation.isReliableEmpty(surface: mesh, pixelCount: 99,
                                                                      excludedPixels: 0, reliableNonPersonPixels: 99))
        }
    }

    func testFreshSupportPlaneAndFullyPersonExcludedEmptyMeshesAreReliableClearObservations() {
        var support = metadata()
        support.cameraTransform = simd_float4x4(simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]))
        support.cameraTransform.columns.3.y = 0.5
        support.depths = Array(repeating: 0.5, count: 99)
        support.confidence = Array(repeating: 2, count: 99)
        let plane = SceneDepthMesher.build(support, supportPlaneY: 0, pixelStep: 1,
                                           policy: .stableEquipment)
        XCTAssertTrue(plane.triangles.isEmpty)
        XCTAssertEqual(plane.rejectedDiscontinuities, 0)
        XCTAssertGreaterThan(plane.rejectedSupportTriangles, 0)
        XCTAssertTrue(SceneDepthClearObservation.isReliableEmpty(surface: plane, pixelCount: 99,
                                                                 excludedPixels: 0, reliableNonPersonPixels: 99))

        var excluded = metadata()
        excluded.depths = Array(repeating: 0, count: 99)
        excluded.confidence = Array(repeating: 0, count: 99)
        let nativeOnly = SceneDepthMesher.build(excluded, supportPlaneY: nil, pixelStep: 1,
                                                policy: .stableEquipment)
        XCTAssertTrue(nativeOnly.triangles.isEmpty)
        XCTAssertEqual(nativeOnly.rejectedSupportTriangles, 0)
        XCTAssertTrue(SceneDepthClearObservation.isReliableEmpty(surface: nativeOnly, pixelCount: 99,
                                                                 excludedPixels: 99, reliableNonPersonPixels: 0))
    }

    func testEmptyObservationRequiresPositiveClearEvidenceAndRejectsNonemptyOrMalformedSurface() {
        let noEvidence = surface([], triangles: [])
        XCTAssertFalse(SceneDepthClearObservation.isReliableEmpty(surface: noEvidence, pixelCount: 99,
                                                                  excludedPixels: 0, reliableNonPersonPixels: 99))
        var partial = noEvidence
        partial.rejectedSupportTriangles = 1; partial.rejectedDiscontinuities = 1
        XCTAssertFalse(SceneDepthClearObservation.isReliableEmpty(surface: partial, pixelCount: 99,
                                                                  excludedPixels: 0, reliableNonPersonPixels: 99))
        var nonempty = quad(1, 1, 3, 3); nonempty.rejectedSupportTriangles = 10
        XCTAssertFalse(SceneDepthClearObservation.isReliableEmpty(surface: nonempty, pixelCount: 99,
                                                                  excludedPixels: 0, reliableNonPersonPixels: 99))
        XCTAssertFalse(SceneDepthClearObservation.isReliableEmpty(surface: nonempty, pixelCount: 99,
                                                                  excludedPixels: 99, reliableNonPersonPixels: 0))
        var malformed = noEvidence; malformed.rejectedSupportTriangles = -1
        XCTAssertFalse(SceneDepthClearObservation.isReliableEmpty(surface: malformed, pixelCount: 99,
                                                                  excludedPixels: 99, reliableNonPersonPixels: 0))
        var support = noEvidence; support.rejectedSupportTriangles = 1
        XCTAssertFalse(SceneDepthClearObservation.isReliableEmpty(surface: support, pixelCount: 99,
                                                                  excludedPixels: 1, reliableNonPersonPixels: 0))
    }
}
