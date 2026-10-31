import XCTest
import simd
@testable import Protacta

final class SceneDepthSamplingTests: XCTestCase {
    private func snapshot() -> SceneDepthSnapshot {
        SceneDepthSnapshot(width: 256, height: 192, depths: Array(repeating: 0.5, count: 256 * 192),
                           confidence: Array(repeating: 2, count: 256 * 192), calibration: [200, 200, 128, 96],
                           cameraTransform: matrix_identity_float4x4, timestamp: 1)
    }
    func testModelAreaUsesNativePixelsAndKeepsAllProjectedCorners() throws {
        let input = snapshot(); var sampling = SceneDepthSampling()
        let required = try XCTUnwrap(SceneDepthRegion.projected(minimum: [-0.1, -0.1, -1.02], maximum: [0.1, 0.1, -0.98], into: input))
        let plan = sampling.plan(for: input, minimum: [-0.1, -0.1, -1.02], maximum: [0.1, 0.1, -0.98])
        XCTAssertEqual(plan.pixelStep, 1)
        XCTAssertTrue(plan.region.contains(required, margin: 4))
        XCTAssertLessThan(plan.region.area, input.width * input.height / 2)
    }
    func testSmallProjectionJitterKeepsCropAndCalibrationStable() {
        let input = snapshot(); var sampling = SceneDepthSampling()
        let first = sampling.plan(for: input, minimum: [-0.1, -0.1, -1.02], maximum: [0.1, 0.1, -0.98])
        for shift: Float in [-0.002, 0.002, 0.001, -0.001] {
            let next = sampling.plan(for: input, minimum: [-0.1 + shift, -0.1, -1.02], maximum: [0.1 + shift, 0.1, -0.98])
            XCTAssertEqual(next.region, first.region)
            XCTAssertEqual(next.region.crop(input).calibration, first.region.crop(input).calibration)
        }
    }
    func testCroppedDepthReprojectsToExactlyTheSameCameraPoints() {
        let input = snapshot(), region = SceneDepthRegion(x: 48, y: 32, width: 96, height: 80)
        let crop = region.crop(input)
        let full = SceneDepthMesher.build(input, supportPlaneY: nil, pixelStep: 1)
        let local = SceneDepthMesher.build(crop, supportPlaneY: nil, pixelStep: 1)
        for (x, y) in [(0, 0), (40, 30), (95, 79)] {
            let original = full.positions[(y + region.y) * input.width + x + region.x]
            let cropped = local.positions[y * region.width + x]
            XCTAssertEqual(cropped.x, original.x, accuracy: 0.000001)
            XCTAssertEqual(cropped.y, original.y, accuracy: 0.000001)
            XCTAssertEqual(cropped.z, original.z)
        }
    }
    func testCameraTranslationUsesWorldBoundsRatherThanTreatingThemAsCameraSpace() {
        var input = snapshot(); input.cameraTransform.columns.3.x = 0.4
        let actual = SceneDepthRegion.projected(minimum: [0.3, -0.1, -1.02], maximum: [0.5, 0.1, -0.98], into: input)
        let expected = SceneDepthRegion.projected(minimum: [-0.1, -0.1, -1.02], maximum: [0.1, 0.1, -0.98], into: snapshot())
        // Float conversion of world bounds may expand by one pixel; both must
        // still use the same central camera region.
        XCTAssertEqual(actual?.width ?? 0, expected?.width ?? 0, accuracy: 1)
        XCTAssertEqual(actual?.x ?? 0, expected?.x ?? 0, accuracy: 1)
    }
    func testMissingBehindCameraOrVeryLargeTargetUsesBoundedFallback() {
        let input = snapshot(); var sampling = SceneDepthSampling()
        let missing = sampling.plan(for: input, minimum: nil, maximum: nil)
        XCTAssertEqual(missing.region, .full(input)); XCTAssertEqual(missing.pixelStep, 2)
        let behind = sampling.plan(for: input, minimum: [-0.1, -0.1, 0.2], maximum: [0.1, 0.1, 0.5])
        XCTAssertEqual(behind.region, .full(input)); XCTAssertEqual(behind.pixelStep, 2)
        let large = sampling.plan(for: input, minimum: [-1, -1, -0.8], maximum: [1, 1, -0.6])
        XCTAssertEqual(large.region, .full(input)); XCTAssertEqual(large.pixelStep, 2)
    }
    func testInvalidCropAndNonfiniteProjectionCannotCreateBadMeshCoordinates() {
        let input = snapshot()
        XCTAssertEqual(SceneDepthRegion(x: -1, y: 0, width: 100, height: 100).crop(input).calibration, input.calibration)
        XCTAssertNil(SceneDepthRegion.projected(minimum: [.nan, 0, -1], maximum: [1, 1, -0.5], into: input))
    }
}
