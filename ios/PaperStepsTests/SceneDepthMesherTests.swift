import XCTest
import simd
@testable import Foliafold

final class SceneDepthMesherTests: XCTestCase {
    private func plane(depth: Float = 0.5, width: Int = 5, height: Int = 5) -> SceneDepthSnapshot {
        SceneDepthSnapshot(width: width, height: height, depths: Array(repeating: depth, count: width * height),
                           confidence: Array(repeating: 2, count: width * height),
                           calibration: [100, 100, Float(width - 1) / 2, Float(height - 1) / 2],
                           cameraTransform: matrix_identity_float4x4, timestamp: 10)
    }

    func testCalibratedDepthReprojectsToOriginalPixelsAndFacesCamera() {
        let snapshot = plane()
        let mesh = SceneDepthMesher.build(snapshot, supportPlaneY: nil, pixelStep: 1)
        XCTAssertEqual(mesh.triangles.count / 3, 32)
        for (index, p) in mesh.positions.enumerated() {
            let x = p.x / -p.z * snapshot.calibration.x + snapshot.calibration.z
            let y = -p.y / -p.z * snapshot.calibration.y + snapshot.calibration.w
            XCTAssertEqual(x, Float(index % 5), accuracy: 0.0001)
            XCTAssertEqual(y, Float(index / 5), accuracy: 0.0001)
            XCTAssertLessThan(p.z, -0.5, "Depth bias must move away from the camera, never create false foreground")
        }
        for i in stride(from: 0, to: mesh.triangles.count, by: 3) {
            let a = mesh.positions[Int(mesh.triangles[i])], b = mesh.positions[Int(mesh.triangles[i + 1])], c = mesh.positions[Int(mesh.triangles[i + 2])]
            XCTAssertGreaterThan(simd_cross(b - a, c - a).z, 0)
        }
    }

    func testLowConfidenceAndInvalidDepthCannotOcclude() {
        var snapshot = plane()
        snapshot.confidence[12] = 0
        snapshot.depths[0] = .nan; snapshot.depths[1] = .infinity
        snapshot.depths[2] = 0; snapshot.depths[3] = 8
        let mesh = SceneDepthMesher.build(snapshot, supportPlaneY: nil, pixelStep: 1)
        XCTAssertEqual(mesh.rejectedSamples, 5)
        for index in mesh.triangles { XCTAssertFalse([0, 1, 2, 3, 12].contains(Int(index))) }
        XCTAssertTrue(mesh.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
    }

    func testForegroundDoesNotGrowAcrossDepthDiscontinuities() {
        var snapshot = plane()
        for y in 0..<5 { for x in 3..<5 { snapshot.depths[y * 5 + x] = 1.1 } }
        let mesh = SceneDepthMesher.build(snapshot, supportPlaneY: nil, pixelStep: 1)
        XCTAssertGreaterThan(mesh.rejectedDiscontinuities, 0)
        for i in stride(from: 0, to: mesh.triangles.count, by: 3) {
            let values = mesh.triangles[i..<(i + 3)].map { snapshot.depths[Int($0)] }
            XCTAssertLessThan(values.max()! - values.min()!, 0.025)
        }
        XCTAssertFalse(mesh.triangles.isEmpty, "Reliable portions on both sides should remain")
    }

    func testTableNoiseIsSuppressedButRaisedHandRemains() {
        var table = plane()
        table.cameraTransform = simd_float4x4(simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]))
        table.cameraTransform.columns.3 = [0, 0.5, 0, 1]
        let flat = SceneDepthMesher.build(table, supportPlaneY: 0, pixelStep: 1)
        XCTAssertTrue(flat.triangles.isEmpty)
        XCTAssertEqual(flat.rejectedSupportTriangles, 32)
        table.depths = Array(repeating: 0.45, count: 25)
        let raised = SceneDepthMesher.build(table, supportPlaneY: 0, pixelStep: 1)
        XCTAssertEqual(raised.triangles.count / 3, 32, "A hand above the support plane must still occlude")
    }

    func testStaleAndRegressedFramesCannotRemainVisible() {
        XCTAssertTrue(SceneDepthMesher.isFresh(timestamp: 10, latestFrameTimestamp: 10.033, secondsSinceReceived: 0.04))
        XCTAssertFalse(SceneDepthMesher.isFresh(timestamp: 10, latestFrameTimestamp: 10.2, secondsSinceReceived: 0.04))
        XCTAssertFalse(SceneDepthMesher.isFresh(timestamp: 10, latestFrameTimestamp: 10, secondsSinceReceived: 0.2))
        XCTAssertFalse(SceneDepthMesher.isFresh(timestamp: 10, latestFrameTimestamp: 9.9, secondsSinceReceived: 0.01))
        XCTAssertFalse(SceneDepthMesher.isFresh(timestamp: .nan, latestFrameTimestamp: 10, secondsSinceReceived: 0.01))
    }

    func testMalformedCalibrationAndMissingConfidenceFailClosed() {
        var snapshot = plane()
        snapshot.confidence = []
        XCTAssertTrue(SceneDepthMesher.build(snapshot, supportPlaneY: nil).triangles.isEmpty)
        snapshot = plane(); snapshot.calibration.x = 0
        XCTAssertTrue(SceneDepthMesher.build(snapshot, supportPlaneY: nil).triangles.isEmpty)
    }
}
