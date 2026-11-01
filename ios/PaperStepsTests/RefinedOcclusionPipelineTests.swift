import XCTest
import simd
@testable import Protacta

/// Pixel ownership and generated depth geometry, not rendered camera quality.
final class RefinedOcclusionPipelineTests: XCTestCase {
    func testNativePersonRegionCannotBeFilledBackIntoTheCustomObjectMesh() throws {
        let width = 20, height = 16
        var labels = Array(repeating: UInt8(0), count: width * height)
        for y in 6...9 { for x in 8...11 { labels[y * width + x] = 1 } }
        let person = SceneDepthPersonMask(width: width, height: height, values: labels)
        let mask = try XCTUnwrap(person.exclusionMask(depthWidth: width, depthHeight: height, radius: 2))
        let frame = snapshot(width: width, height: height, timestamp: 1)
        var filter = EquipmentDepthStabilizer()
        let filtered = filter.filter(frame, current: frame, excluding: mask)
        let mesh = SceneDepthMesher.build(filtered, supportPlaneY: nil, pixelStep: 1, policy: .stableEquipment)
        XCTAssertFalse(mesh.triangles.isEmpty, "Non-person real objects must remain eligible")
        for index in mask.indices where mask[index] {
            XCTAssertEqual(filtered.depths[index], 0)
            XCTAssertEqual(filtered.confidence[index], 0)
        }
        for vertex in mesh.triangles {
            XCTAssertFalse(mask[Int(vertex)], "A hard custom triangle must not own any native hand pixel")
        }
    }

    func testPersonExclusionUsesFullSensorCoordinatesBeforeCroppingTheObjectRegion() throws {
        let width = 20, height = 16
        var labels = Array(repeating: UInt8(0), count: width * height)
        labels[9 * width + 12] = 255
        let person = SceneDepthPersonMask(width: width, height: height, values: labels)
        let full = snapshot(width: width, height: height, timestamp: 1)
        let excluded = try XCTUnwrap(person.excludingPeople(from: full, radius: 1)).snapshot
        let region = SceneDepthRegion(x: 10, y: 7, width: 7, height: 6)
        let cropped = region.crop(excluded)
        XCTAssertEqual(cropped.confidence[(9 - region.y) * region.width + (12 - region.x)], 0)
        XCTAssertEqual(cropped.confidence[0], 2)
        XCTAssertEqual(cropped.calibration.z, full.calibration.z - Float(region.x))
        XCTAssertEqual(cropped.calibration.w, full.calibration.w - Float(region.y))
    }

    private func snapshot(width: Int, height: Int, timestamp: TimeInterval) -> SceneDepthSnapshot {
        SceneDepthSnapshot(width: width, height: height, depths: Array(repeating: 0.5, count: width * height),
                           confidence: Array(repeating: 2, count: width * height), calibration: [100, 100, 10, 8],
                           cameraTransform: matrix_identity_float4x4, timestamp: timestamp)
    }
}
