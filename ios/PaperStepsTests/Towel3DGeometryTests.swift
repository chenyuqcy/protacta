import RealityKit
import XCTest
import simd
@testable import Protacta

final class Towel3DGeometryTests: XCTestCase {
    func testSuccessiveActionsKeepThePreviousFoldRatherThanResetTheTowel() {
        for action in 0..<2 {
            let previous = Towel3DGeometry.panels(actionIndex: action, progress: 1)
            let next = Towel3DGeometry.panels(actionIndex: action + 1, progress: 0)
            for (a, b) in zip(previous, next) {
                for (p, q) in zip(a.quads.flatMap { $0 }, b.quads.flatMap { $0 }) {
                    XCTAssertLessThan(simd_distance(p, q), 0.000001)
                }
            }
        }
    }

    func testThirdFoldsReduceWidthThenHalfFoldReducesLength() {
        let starting = Towel3DGeometry.bounds(of: Towel3DGeometry.panels(actionIndex: 0, progress: 0))
        let left = Towel3DGeometry.bounds(of: Towel3DGeometry.panels(actionIndex: 0, progress: 1))
        let thirds = Towel3DGeometry.bounds(of: Towel3DGeometry.panels(actionIndex: 1, progress: 1))
        let finished = Towel3DGeometry.bounds(of: Towel3DGeometry.panels(actionIndex: 2, progress: 1))
        XCTAssertEqual(starting.maximum.x - starting.minimum.x, 0.6, accuracy: 0.00001)
        XCTAssertEqual(left.maximum.x - left.minimum.x, 0.4, accuracy: 0.00001)
        XCTAssertEqual(thirds.maximum.x - thirds.minimum.x, 0.2, accuracy: 0.00001)
        XCTAssertEqual(finished.maximum.x - finished.minimum.x, 0.2, accuracy: 0.00001)
        XCTAssertEqual(finished.maximum.z - finished.minimum.z, 0.45, accuracy: 0.00001)
    }

    func testLeftAndRightFlapsLiftAboveTheTableAndEndAboveEarlierLayers() {
        for (action, column) in [(0, 0), (1, 2)] {
            let moving = Towel3DGeometry.panels(actionIndex: action, progress: 0.5)[column]
            XCTAssertGreaterThan(moving.quads.flatMap { $0 }.map(\.y).max()!, 0.19)
        }
        let folded = Towel3DGeometry.panels(actionIndex: 1, progress: 1)
        let heights = folded.map { $0.quads.flatMap { $0 }.map(\.y).min()! }
        XCTAssertGreaterThan(heights[0], heights[1])
        XCTAssertGreaterThan(heights[2], heights[0])
    }

    func testEveryFrameHasFiniteNondegenerateSurfacesIncludingAnEdgeOnFlap() {
        for action in 0..<3 {
            for sample in 0...40 {
                for panel in Towel3DGeometry.panels(actionIndex: action, progress: Double(sample) / 40) {
                    for quad in panel.quads {
                        for point in quad {
                            XCTAssertTrue(point.x.isFinite && point.y.isFinite && point.z.isFinite)
                            XCTAssertGreaterThanOrEqual(point.y, -0.00001)
                        }
                        XCTAssertGreaterThan(simd_length_squared(simd_cross(quad[1] - quad[0], quad[2] - quad[0])), 1e-8)
                    }
                }
            }
        }
    }

    func testUnsupportedInputsClampWithoutInvalidCoordinates() {
        XCTAssertEqual(Towel3DGeometry.panels(actionIndex: -20, progress: -.infinity).flatMap(\.quads),
                       Towel3DGeometry.panels(actionIndex: 0, progress: 0).flatMap(\.quads))
        XCTAssertEqual(Towel3DGeometry.panels(actionIndex: 20, progress: 2).flatMap(\.quads),
                       Towel3DGeometry.panels(actionIndex: 2, progress: 1).flatMap(\.quads))
    }

    @MainActor
    func testRuntimeMeshesRemainVisibleAcrossAllActionsAndReplay() throws {
        let model = Towel3DModel()
        for action in [0, 1, 2, 1, 0] {
            for progress in [0.0, 0.5, 1.0, 0.25] {
                model.update(actionIndex: action, progress: progress)
                XCTAssertEqual(model.root.children.count, 3)
                for child in model.root.children {
                    let render = try XCTUnwrap((child as? ModelEntity)?.model)
                    XCTAssertFalse(render.mesh.contents.models.isEmpty)
                    XCTAssertEqual(render.materials.count, 1)
                }
            }
        }
    }
}
