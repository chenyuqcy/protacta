import XCTest
import simd
@testable import Protacta

/// Mesh checks concern the authored spatial reference, not whether a real knot
/// is secure or whether a learner's tie is correct.
final class EverydayKnotGeometryTests: XCTestCase {
    func testEveryActionEndsExactlyWhereTheFollowingActionStarts() {
        for (course, count) in [(EverydayTutorialID.squareKnot, 5), (.fourInHand, 7)] {
            for action in 0..<(count - 1) {
                let before = EverydayKnotGeometry.parts(courseID: course, actionIndex: action, progress: 1)
                let after = EverydayKnotGeometry.parts(courseID: course, actionIndex: action + 1, progress: 0)
                XCTAssertEqual(before.map(\.id), after.map(\.id))
                for (a, b) in zip(before, after) {
                    XCTAssertEqual(a.triangles, b.triangles, "\(course) action \(action): \(a.id)")
                    XCTAssertEqual(a.positions.count, b.positions.count)
                    for (p, q) in zip(a.positions, b.positions) {
                        XCTAssertLessThan(simd_distance(p, q), 0.000001, "\(course) action \(action): \(a.id)")
                    }
                }
            }
        }
    }

    func testAllActionsMoveContinuouslyAndKeepTheSameMeshTopology() {
        for (course, count) in [(EverydayTutorialID.squareKnot, 5), (.fourInHand, 7)] {
            for action in 0..<count {
                let start = EverydayKnotGeometry.parts(courseID: course, actionIndex: action, progress: 0)
                let middle = EverydayKnotGeometry.parts(courseID: course, actionIndex: action, progress: 0.5)
                let end = EverydayKnotGeometry.parts(courseID: course, actionIndex: action, progress: 1)
                XCTAssertEqual(start.map(\.id), end.map(\.id))
                XCTAssertEqual(start.map { $0.positions.count }, end.map { $0.positions.count })
                XCTAssertEqual(start.map(\.triangles), end.map(\.triangles))
                let moved = zip(start.flatMap(\.positions), end.flatMap(\.positions)).map { simd_distance($0, $1) }.max()!
                XCTAssertGreaterThan(moved, 0.015, "\(course) action \(action) must actually demonstrate movement")
                let inBetween = zip(start.flatMap(\.positions), middle.flatMap(\.positions)).map { simd_distance($0, $1) }.max()!
                XCTAssertGreaterThan(inBetween, 0.005)
                XCTAssertLessThan(inBetween, 0.7)
            }
        }
    }

    func testSampledFramesAreFiniteBoundedAndHaveNondegenerateFaces() {
        for (course, count) in [(EverydayTutorialID.squareKnot, 5), (.fourInHand, 7)] {
            for action in 0..<count {
                for sample in 0...12 {
                    let parts = EverydayKnotGeometry.parts(courseID: course, actionIndex: action, progress: Double(sample) / 12)
                    XCTAssertFalse(parts.isEmpty)
                    for part in parts {
                        XCTAssertEqual(part.triangles.count % 3, 0)
                        for p in part.positions {
                            XCTAssertTrue(p.x.isFinite && p.y.isFinite && p.z.isFinite)
                            XCTAssertLessThan(abs(p.x), 0.5)
                            XCTAssertGreaterThan(p.y, 0)
                            XCTAssertLessThan(p.y, 0.4)
                            XCTAssertLessThan(abs(p.z), 0.5)
                        }
                        for offset in stride(from: 0, to: part.triangles.count, by: 3) {
                            let ids = part.triangles[offset..<(offset + 3)].map(Int.init)
                            XCTAssertTrue(ids.allSatisfy { part.positions.indices.contains($0) })
                            let a = part.positions[ids[0]], b = part.positions[ids[1]], c = part.positions[ids[2]]
                            XCTAssertGreaterThan(simd_length_squared(simd_cross(b - a, c - a)), 1e-18,
                                                 "\(course) action \(action) sample \(sample): \(part.id) face \(offset / 3)")
                        }
                    }
                }
            }
        }
    }

    func testCordAndTieMeshesHaveDepthAndCorrectStableColors() throws {
        let knot = EverydayKnotGeometry.parts(courseID: .squareKnot, actionIndex: 0, progress: 1)
        let a = try XCTUnwrap(knot.first { $0.id == "cord-A" })
        let b = try XCTUnwrap(knot.first { $0.id == "cord-B" })
        XCTAssertEqual(a.colorIndex, 1)
        XCTAssertEqual(b.colorIndex, 2)
        // At the first crossing, the authored blue route is really higher than
        // orange, not painted over it in a flat diagram.
        let blueNearCrossing = a.positions.filter { abs($0.x) < 0.015 && abs($0.z - 0.022) < 0.025 }
        let orangeNearCrossing = b.positions.filter { abs($0.x) < 0.015 && abs($0.z - 0.022) < 0.025 }
        XCTAssertFalse(blueNearCrossing.isEmpty)
        XCTAssertFalse(orangeNearCrossing.isEmpty)
        XCTAssertGreaterThan(blueNearCrossing.map(\.y).min()!, orangeNearCrossing.map(\.y).max()! + 0.02)

        let tie = EverydayKnotGeometry.parts(courseID: .fourInHand, actionIndex: 4, progress: 1)
        let wide = try XCTUnwrap(tie.first { $0.id == "tie-wide-W" })
        XCTAssertGreaterThan(wide.positions.map(\.y).max()! - wide.positions.map(\.y).min()!, 0.08)
        XCTAssertEqual(wide.colorIndex, 1)
        XCTAssertEqual(tie.first { $0.id == "tie-narrow-N" }?.colorIndex, 2)
        XCTAssertTrue(tie.contains { $0.id == "tie-rear-keeper" })
    }

    func testFinalTieActionSlidesTheNarrowTailWhileKeepingWideBladeStable() throws {
        let a = EverydayKnotGeometry.parts(courseID: .fourInHand, actionIndex: 6, progress: 0)
        let b = EverydayKnotGeometry.parts(courseID: .fourInHand, actionIndex: 6, progress: 1)
        XCTAssertEqual(a.first { $0.id == "tie-wide-W" }?.positions, b.first { $0.id == "tie-wide-W" }?.positions)
        let narrowStart = try XCTUnwrap(a.first { $0.id == "tie-narrow-N" })
        let narrowEnd = try XCTUnwrap(b.first { $0.id == "tie-narrow-N" })
        XCTAssertGreaterThan(zip(narrowStart.positions, narrowEnd.positions).map { simd_distance($0, $1) }.max()!, 0.03)
        XCTAssertNotEqual(a.first { $0.id == "tie-collar-left" }?.positions, b.first { $0.id == "tie-collar-left" }?.positions)
    }

    func testFinishedNarrowTailRunsInsideTheRearKeeperGap() throws {
        let parts = EverydayKnotGeometry.parts(courseID: .fourInHand, actionIndex: 6, progress: 1)
        func centers(_ part: EverydayMeshPart) -> [SIMD3<Float>] {
            stride(from: 0, to: part.positions.count, by: 4).map { index in
                part.positions[index..<(index + 4)].reduce(.zero, +) / 4
            }
        }
        let keeper = try XCTUnwrap(parts.first { $0.id == "tie-rear-keeper" })
        let rearBandCenter = centers(keeper)[40]
        func nearest(to point: SIMD3<Float>, in part: EverydayMeshPart) -> SIMD3<Float> {
            centers(part).min {
                simd_length_squared(SIMD2($0.x - point.x, $0.z - point.z)) <
                simd_length_squared(SIMD2($1.x - point.x, $1.z - point.z))
            }!
        }
        let wide = nearest(to: rearBandCenter, in: try XCTUnwrap(parts.first { $0.id == "tie-wide-W" }))
        let narrow = nearest(to: rearBandCenter, in: try XCTUnwrap(parts.first { $0.id == "tie-narrow-N" }))
        XCTAssertLessThan(simd_distance(SIMD2(narrow.x, narrow.z), SIMD2(rearBandCenter.x, rearBandCenter.z)), 0.004)
        XCTAssertGreaterThan(narrow.y, rearBandCenter.y + 0.002)
        XCTAssertLessThan(narrow.y, wide.y - 0.002)
    }

    func testMalformedInputsClampWithoutGeneratingInvalidMeshes() {
        for course in [EverydayTutorialID.squareKnot, .fourInHand] {
            let first = EverydayKnotGeometry.parts(courseID: course, actionIndex: -100, progress: .nan)
            let expected = EverydayKnotGeometry.parts(courseID: course, actionIndex: 0, progress: 0)
            XCTAssertEqual(first.map(\.positions), expected.map(\.positions))
            let lastIndex = course == .squareKnot ? 4 : 6
            XCTAssertEqual(EverydayKnotGeometry.parts(courseID: course, actionIndex: Int.max, progress: 2).map(\.positions),
                           EverydayKnotGeometry.parts(courseID: course, actionIndex: lastIndex, progress: 1).map(\.positions))
        }
        XCTAssertTrue(EverydayKnotGeometry.parts(courseID: .towel, actionIndex: 0, progress: 0).isEmpty)
    }
}
