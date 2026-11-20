import XCTest
import simd
@testable import Protacta

final class EverydayObjectAlignmentTests: XCTestCase {
    private let footprint = EverydayObjectFootprint(minimum: [-0.3, 0.004, -0.4], maximum: [0.3, 0.004, 0.4])!

    func testCalibrationMapsThreeAuthoredCornersToWorldCorners() throws {
        let points: [SIMD3<Float>] = [[0.2, 0.7, 0.1], [0.8, 0.7, 0.1], [0.2, 0.7, -1.1]]
        let result = try EverydayObjectAlignment.solve(footprint: footprint, points: points).get()
        let source: [SIMD3<Float>] = [[-0.3, 0.004, 0.4], [0.3, 0.004, 0.4], [-0.3, 0.004, -0.4]]
        for (vertex, target) in zip(source, points) {
            let mapped = result.worldTransform * SIMD4((vertex + result.contentOffset) * result.scale, 1)
            XCTAssertEqual(mapped.x, target.x, accuracy: 0.00001)
            XCTAssertEqual(mapped.z, target.z, accuracy: 0.00001)
            XCTAssertEqual(mapped.y, target.y + 0.003, accuracy: 0.00001)
        }
        XCTAssertEqual(result.scale.x, 1, accuracy: 0.00001)
        XCTAssertEqual(result.scale.z, 1.5, accuracy: 0.00001)
        XCTAssertEqual(result.scale.y, sqrt(1.5), accuracy: 0.00001)
    }

    func testRotatedCalibrationPreservesHandednessAndAnimationHeight() throws {
        let result = try EverydayObjectAlignment.solve(footprint: footprint,
            points: [[1, 0.5, 2], [1, 0.5, 1.4], [-0.2, 0.5, 2]]).get()
        XCTAssertEqual(simd_determinant(result.worldTransform), 1, accuracy: 0.00001)
        let raised = result.worldTransform * SIMD4(SIMD3<Float>(0, 0.2, 0) * result.scale, 0)
        XCTAssertGreaterThan(raised.y, 0)
        XCTAssertEqual(raised.x, 0, accuracy: 0.00001)
        XCTAssertEqual(raised.z, 0, accuracy: 0.00001)
    }

    func testCalibratedFootprintCanBeADeclaredShirtBodySubset() throws {
        let shirt = try XCTUnwrap(EverydayObjectFootprint(minimum: [-0.22, 0.001, -0.26], maximum: [0.22, 0.001, 0.34]))
        let result = try EverydayObjectAlignment.solve(footprint: shirt,
            points: [[0, 0, 0], [0.44, 0, 0], [0, 0, -0.6]]).get()
        XCTAssertEqual(result.scale.x, 1, accuracy: 0.00001)
        XCTAssertEqual(result.scale.z, 1, accuracy: 0.00001)
        // The sleeve remains outside the torso rectangle; it is not cropped.
        let sleeve = result.worldTransform * SIMD4((SIMD3<Float>(-0.37, 0.001, -0.22) + result.contentOffset) * result.scale, 1)
        XCTAssertLessThan(sleeve.x, 0)
    }

    func testRejectsWrongOrderAndSkewRatherThanMirroringOrShearingCloth() {
        XCTAssertEqual(EverydayObjectAlignment.validate(points: [[0, 0, 0], [0.6, 0, 0], [0, 0, 0.8]]), .wrongCorner)
        XCTAssertEqual(EverydayObjectAlignment.validate(points: [[0, 0, 0], [0.6, 0, 0], [0.3, 0, -0.8]]), .skewedRectangle)
        XCTAssertEqual(EverydayObjectAlignment.validate(points: [[0, 0, 0], [0.6, 0, 0], [0.6, 0, -0.8]]), .skewedRectangle)
        XCTAssertEqual(EverydayObjectAlignment.validate(points: [[0, 0, 0], [2, 0, 0], [0.15, 0, -2.5]]), .skewedRectangle,
                       "Small angular error on a large bedsheet still needs an absolute corner-error limit")
    }

    func testPartialCaptureRejectsCoincidentNonfiniteAndNonflatPoints() {
        XCTAssertNil(EverydayObjectAlignment.validate(points: [[0, 0.8, 0]]))
        XCTAssertEqual(EverydayObjectAlignment.validate(points: [[0, 0, 0], [0.01, 0, 0]]), .sizeOutOfRange)
        XCTAssertEqual(EverydayObjectAlignment.validate(points: [[0, 0, 0], [3.1, 0, 0]]), .sizeOutOfRange)
        XCTAssertEqual(EverydayObjectAlignment.validate(points: [[0, 0, 0], [.nan, 0, 0]]), .invalidPoint)
        XCTAssertEqual(EverydayObjectAlignment.validate(points: [[0, 0, 0], [0.6, 0.08, 0]]), .unevenSurface)
        XCTAssertEqual(EverydayObjectAlignment.validate(points: []), .invalidPoint)
    }

    func testInvalidAuthoredBoundsCannotProduceCalibration() {
        XCTAssertNil(EverydayObjectFootprint(minimum: .zero, maximum: .zero))
        XCTAssertNil(EverydayObjectFootprint(minimum: .zero, maximum: [.infinity, 1, 1]))
        XCTAssertNil(EverydayObjectFootprint(minimum: .zero, maximum: [-1, 1, 1]))
        XCTAssertNil(EverydayObjectFootprint(minimum: [-Float.greatestFiniteMagnitude, 0, 0], maximum: [.greatestFiniteMagnitude, 1, 1]))
        if case .success = EverydayObjectAlignment.solve(footprint: footprint, points: [[0, 0, 0]]) {
            XCTFail("A partial capture must not commit a placement")
        }
    }

    @MainActor
    func testStartingCalibrationCannotStartCameraOrMutateAnUnreadyController() {
        let controller = TutorialTabletopARController()
        XCTAssertFalse(controller.beginObjectAlignment(footprint: footprint))
        XCTAssertFalse(controller.isAligningObject)
        XCTAssertFalse(controller.canCaptureObjectAlignmentPoint)
        XCTAssertFalse(controller.isObjectAligned)
        controller.captureObjectAlignmentPoint()
        controller.cancelObjectAlignment()
        XCTAssertNil(controller.view)
        XCTAssertFalse(controller.placed)
        XCTAssertEqual(controller.objectAlignmentPointCount, 0)
        controller.stop()
    }
}
