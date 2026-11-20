import XCTest
import simd
@testable import Protacta

final class EverydayObjectGuideTests: XCTestCase {
    func testOnlyFlatClothLessonsOfferThreePhysicalLandmarks() throws {
        for id in [EverydayTutorialID.tShirt, .towel, .flatBedsheet] {
            let guide = try XCTUnwrap(EverydayObjectGuide.course(id))
            XCTAssertEqual(guide.pointNames.count, 3)
            XCTAssertEqual(Set(guide.pointNames).count, 3)
            XCTAssertFalse(guide.setup.isEmpty)
        }
        XCTAssertNil(EverydayObjectGuide.course(.squareKnot))
        XCTAssertNil(EverydayObjectGuide.course(.fourInHand))
    }

    func testClothCalibrationLandmarksExistOnTheActualStartingMesh() throws {
        for id in [EverydayTutorialID.tShirt, .towel, .flatBedsheet] {
            let guide = try XCTUnwrap(EverydayObjectGuide.course(id))
            let low = guide.footprint.minimum, high = guide.footprint.maximum
            let landmarks: [SIMD3<Float>] = [[low.x, low.y, high.z], [high.x, low.y, high.z], [low.x, low.y, low.z]]
            let points = EverydayMeshGeometry.parts(courseID: id, actionIndex: 0, progress: 0).flatMap(\.positions)
            for landmark in landmarks {
                XCTAssertTrue(points.contains(where: { simd_distance($0, landmark) < 0.0001 }),
                              "\(id): guide point must be on the item rather than empty bounding-box space")
            }
        }
    }
}
