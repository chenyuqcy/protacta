import XCTest
import ARKit
import RealityKit
@testable import Protacta

/// Synthetic numerical contracts; physical edge quality is a separate gate.
final class EquipmentDepthStabilizerTests: XCTestCase {
    private func plane(_ depth: Float = 0.5, time: Double = 1) -> SceneDepthSnapshot {
        SceneDepthSnapshot(width: 5, height: 5, depths: Array(repeating: depth, count: 25),
            confidence: Array(repeating: 2, count: 25), calibration: [100, 100, 2, 2],
            cameraTransform: matrix_identity_float4x4, timestamp: time)
    }
    func testSmallStationaryNoiseDoesNotAlternateTheFilteredDepth() {
        var filter = EquipmentDepthStabilizer()
        _ = filter.filter(plane())
        for index in 1...12 {
            let input = plane(index.isMultiple(of: 2) ? 0.503 : 0.497, time: 1 + Double(index) / 30)
            let result = filter.filter(input)
            XCTAssertTrue(result.depths.allSatisfy { abs($0 - 0.5) < 0.000001 })
        }
    }
    func testRealForegroundOrBackgroundChangeBypassesHistoryImmediately() {
        var filter = EquipmentDepthStabilizer()
        _ = filter.filter(plane())
        XCTAssertEqual(filter.filter(plane(1.2, time: 1.033)).depths[12], 1.2)
        XCTAssertEqual(filter.filter(plane(0.3, time: 1.066)).depths[12], 0.3)
    }
    func testCameraMovementAndLongFrameGapCannotReuseDepthHistory() {
        var filter = EquipmentDepthStabilizer()
        _ = filter.filter(plane())
        var moving = plane(0.505, time: 1.033)
        moving.cameraTransform.columns.3.x = 0.02
        XCTAssertEqual(filter.filter(moving).depths[12], 0.505)
        XCTAssertEqual(filter.filter(plane(0.501, time: 2)).depths[12], 0.501)
    }
    func testInteriorHoleMayFillButAnUnsupportedOrEdgePixelDoesNotGrow() {
        var filter = EquipmentDepthStabilizer()
        var hole = plane(); hole.confidence[12] = 0
        XCTAssertEqual(filter.filter(hole).depths[12], 0.5)
        var invalid = plane(time: 1.033); invalid.confidence = Array(repeating: 0, count: 25)
        XCTAssertTrue(filter.filter(invalid).confidence.allSatisfy { $0 == 0 })
        var boundary = plane()
        for y in 0..<5 { for x in 3..<5 { boundary.depths[y * 5 + x] = 1.2 } }
        boundary.confidence[12] = 0
        filter.reset()
        XCTAssertEqual(filter.filter(boundary).confidence[12], 0)
    }
    func testEquipmentDepthToleranceDoesNotChangeThePaperPolicy() {
        let input = plane()
        let paper = SceneDepthMesher.build(input, supportPlaneY: nil, pixelStep: 1)
        let equipment = SceneDepthMesher.build(input, supportPlaneY: nil, pixelStep: 1, policy: .stableEquipment)
        XCTAssertLessThan(paper.positions[12].z, -0.5)
        XCTAssertEqual(equipment.positions[12].z, -0.492, accuracy: 0.000001)
        XCTAssertEqual(equipment.triangles.count, paper.triangles.count)
    }
    func testSparseFilterMatchesDenseFilterAtEveryMesherVertex() {
        var dense = EquipmentDepthStabilizer(), sparse = EquipmentDepthStabilizer()
        for frame in 0..<8 {
            var input = plane(frame.isMultiple(of: 2) ? 0.5 : 0.503, time: 1 + Double(frame) / 30)
            input.confidence[12] = 0
            for y in 0..<5 { input.depths[y * 5 + 4] = 1.2 }
            let full = dense.filter(input), sampled = sparse.filter(input, pixelStep: 2)
            for y in stride(from: 0, to: 5, by: 2) {
                for x in stride(from: 0, to: 5, by: 2) {
                    let index = y * 5 + x
                    XCTAssertEqual(sampled.depths[index], full.depths[index])
                    XCTAssertEqual(sampled.confidence[index], full.confidence[index])
                }
            }
        }
    }
    @MainActor
    func testStablePolicyHasOneDepthOwnerAndNoGroundingOrSceneMesh() {
        let supported = EquipmentOcclusionCapabilities(stableDepth: true, personDepth: true)
        let stable = EquipmentOcclusionConfiguration.make(mode: .stableEdges, capabilities: supported)
        XCTAssertTrue(stable.frameSemantics.contains(.sceneDepth))
        XCTAssertTrue(stable.frameSemantics.contains(.smoothedSceneDepth))
        XCTAssertFalse(stable.frameSemantics.contains(.personSegmentationWithDepth))
        XCTAssertEqual(stable.sceneReconstruction, [])
        let options = EquipmentOcclusionConfiguration.renderOptions(mode: .stableEdges, capabilities: supported)
        XCTAssertTrue(options.contains(.disablePersonOcclusion))
        XCTAssertTrue(options.contains(.disableGroundingShadows))
        let unsupported = EquipmentOcclusionCapabilities(stableDepth: false, personDepth: true)
        let fallback = EquipmentOcclusionConfiguration.make(mode: .stableEdges, capabilities: unsupported)
        XCTAssertTrue(fallback.frameSemantics.contains(.personSegmentationWithDepth))
        XCTAssertFalse(fallback.frameSemantics.contains(.smoothedSceneDepth))
        XCTAssertFalse(EquipmentOcclusionConfiguration.renderOptions(mode: .stableEdges, capabilities: unsupported).contains(.disablePersonOcclusion))
    }
}
