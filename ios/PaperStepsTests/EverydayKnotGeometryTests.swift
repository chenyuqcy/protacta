import XCTest
import simd
@testable import Protacta

/// Mesh checks concern the authored spatial reference, not whether a real knot
/// is secure or whether a learner's tie is correct.
final class EverydayKnotGeometryTests: XCTestCase {
    func testStandingCordIsContinuousThroughTheFormerSeparateTubeJoins() throws {
        for action in 0..<5 {
            for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let parts = EverydayKnotGeometry.parts(courseID: .squareKnot, actionIndex: action, progress: progress)
                XCTAssertEqual(parts.map(\.id), ["cord-A", "cord-B"],
                               "Each coloured working end must include its standing section in the same mesh")
                let a = try XCTUnwrap(parts.first), b = try XCTUnwrap(parts.last)
                // At the colour boundary both tubes have the same circular
                // cross-section; their centre lines leave in opposite directions.
                for p in a.positions.prefix(10) {
                    let match = b.positions.prefix(10).map { simd_distance(p, $0) }.min()!
                    XCTAssertLessThan(match, 0.000002)
                }
                for part in parts {
                    let ringCount = (part.positions.count - 2) / 10
                    let centers = (0..<ringCount).map { ring in
                        part.positions[(ring * 10)..<(ring * 10 + 10)].reduce(SIMD3<Float>.zero, +) / 10
                    }
                    guard progress == 0 || progress == 1 else { continue }
                    // Find the actual former standing/working join in model
                    // space. A fixed ring fraction drifts into a tight half-knot
                    // as the total cord length changes between teaching poses.
                    let side: Float = part.id == "cord-A" ? -1 : 1
                    let dressed = action == 4 && progress == 1
                    let expected = SIMD3<Float>(side * (dressed ? 0.286 : 0.253), 0.05, dressed ? 0.165 : 0.286)
                    let ring = (1..<(ringCount - 1)).min {
                        simd_distance_squared(centers[$0], expected) < simd_distance_squared(centers[$1], expected)
                    }!
                    XCTAssertLessThan(simd_distance(centers[ring], expected), 0.012)
                    let incoming = simd_normalize(centers[ring] - centers[ring - 1])
                    let outgoing = simd_normalize(centers[ring + 1] - centers[ring])
                    XCTAssertGreaterThan(simd_dot(incoming, outgoing), 0.85,
                                         "Action \(action), progress \(progress), \(part.id): former join must stay smooth")
                }
            }
        }
    }

    func testWideTieNarrowsAtTheNeckAndRetainsItsBroadHangingBlade() throws {
        for action in 0..<7 {
            for progress in [0.0, 0.5, 1.0] {
                let wide = try XCTUnwrap(EverydayKnotGeometry.parts(courseID: .fourInHand,
                    actionIndex: action, progress: progress).first { $0.id == "tie-wide-W" })
                let neckWidth = simd_distance(wide.positions[0], wide.positions[1])
                let bladeRing = Int(Float(wide.positions.count / 4 - 1) * 0.88) * 4
                let bladeWidth = simd_distance(wide.positions[bladeRing], wide.positions[bladeRing + 1])
                XCTAssertLessThan(neckWidth, 0.021)
                XCTAssertGreaterThan(bladeWidth, 0.045)
                XCTAssertLessThan(neckWidth, bladeWidth * 0.5,
                                  "The neck strap must not read as a second full-width blade beside the knot")
            }
        }
    }

    func testDressedTieTucksItsReturnLoopInsideACompactKnot() throws {
        let wide = try XCTUnwrap(EverydayKnotGeometry.parts(courseID: .fourInHand, actionIndex: 6, progress: 1)
            .first { $0.id == "tie-wide-W" })
        let centers = stride(from: 0, to: wide.positions.count, by: 4).map { ring in
            wide.positions[ring..<(ring + 4)].reduce(SIMD3<Float>.zero, +) / 4
        }
        // The return route runs upward through the neck loop, then down behind
        // the front band. Its old 10+ cm excursion left a tall loose bight above
        // the finished knot even though every progression test passed.
        let returning = (1..<(centers.count - 1)).filter {
            $0 > centers.count / 4 && centers[$0 + 1].z < centers[$0 - 1].z - 0.0001
        }.map { centers[$0] }
        XCTAssertGreaterThan(returning.count, 2)
        let minimum = returning.reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude), simd_min)
        let maximum = returning.reduce(SIMD3<Float>(repeating: -.greatestFiniteMagnitude), simd_max)
        XCTAssertLessThan(maximum.z - minimum.z, 0.055, "The dressed return loop must fit inside a short knot")
        XCTAssertLessThan(maximum.x - minimum.x, 0.080)
        XCTAssertLessThan(maximum.y - minimum.y, 0.065)
    }

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

    func testSmallTimelineChangesDoNotFlipUprightStrandsOrTheirKeeper() {
        // In the old world-up framing, the fourth/fifth tie actions jumped by
        // up to 47 mm when the timeline moved only 0.5%. Sampling endpoints or
        // the midpoint never caught that visible twist.
        for (course, count) in [(EverydayTutorialID.squareKnot, 5), (.fourInHand, 7)] {
            for action in 0..<count {
                var previous = EverydayKnotGeometry.parts(courseID: course, actionIndex: action, progress: 0)
                for sample in 1...100 {
                    let current = EverydayKnotGeometry.parts(courseID: course, actionIndex: action,
                                                             progress: Double(sample) / 100)
                    for (a, b) in zip(previous, current) {
                        let displacement = zip(a.positions, b.positions).map { simd_distance($0, $1) }.max() ?? 0
                        XCTAssertLessThan(displacement, 0.0075,
                                          "\(course) action \(action), sample \(sample): \(a.id) must not flip")
                    }
                    previous = current
                }
            }
        }
    }

    func testTieRibbonDoesNotReverseItsCrossSectionBetweenNeighbouringRings() {
        // Temporal continuity alone misses a twist seam inside a single frame.
        for action in 0..<7 {
            for sample in 0...20 {
                let parts = EverydayKnotGeometry.parts(courseID: .fourInHand, actionIndex: action,
                                                         progress: Double(sample) / 20)
                for part in parts where !part.id.hasPrefix("tie-collar") {
                    let across = stride(from: 0, to: part.positions.count, by: 4).map { ring in
                        simd_normalize(part.positions[ring + 1] - part.positions[ring])
                    }
                    for ring in 1..<across.count {
                        XCTAssertGreaterThan(simd_dot(across[ring - 1], across[ring]), 0.5,
                                             "Action \(action), sample \(sample), \(part.id): twist seam at \(ring)")
                    }
                }
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

    func testRearKeeperStaysWithinTheBladeAndBehindItsFrontSilhouette() throws {
        var reference: EverydayMeshPart?
        for action in 0..<7 {
            for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let parts = EverydayKnotGeometry.parts(courseID: .fourInHand, actionIndex: action, progress: progress)
                let wide = try XCTUnwrap(parts.first { $0.id == "tie-wide-W" })
                let keeper = try XCTUnwrap(parts.first { $0.id == "tie-rear-keeper" })
                let ring = Int(Float(wide.positions.count / 4 - 1) * 0.91) * 4
                let center = wide.positions[ring..<(ring + 4)].reduce(SIMD3<Float>.zero, +) / 4
                let width = wide.positions[ring + 1] - wide.positions[ring]
                let side = simd_normalize(width)
                for point in keeper.positions {
                    XCTAssertLessThan(abs(simd_dot(point - center, side)), simd_length(width) / 2 - 0.0005,
                                      "Action \(action), progress \(progress): the keeper must not form ears beside W")
                    if (action == 0 && progress == 0) || (action == 6 && progress == 1) {
                        let cover = try XCTUnwrap(surfaceHits(wide, x: point.x, z: point.z).map(\.height).max())
                        XCTAssertGreaterThan(cover, point.y + 0.001,
                                             "The rear keeper must be hidden by W in the initial and finished front view")
                    }
                }
                if let reference {
                    XCTAssertEqual(keeper.positions.count, reference.positions.count)
                    XCTAssertEqual(keeper.triangles, reference.triangles)
                    XCTAssertEqual(keeper.fabricUVs, reference.fabricUVs,
                                   "The sewn keeper retains its topology and material coordinates throughout tying")
                } else { reference = keeper }
            }
        }
        // Fine timeline motion and exact action boundaries are also covered by
        // testSmallTimelineChangesDoNotFlipUprightStrandsOrTheirKeeper and
        // testEveryActionEndsExactlyWhereTheFollowingActionStarts.
    }

    func testFinishedNarrowTailRunsInsideTheRearKeeperGap() throws {
        let parts = EverydayKnotGeometry.parts(courseID: .fourInHand, actionIndex: 6, progress: 1)
        func centers(_ part: EverydayMeshPart) -> [SIMD3<Float>] {
            stride(from: 0, to: part.positions.count, by: 4).map { index in
                part.positions[index..<(index + 4)].reduce(.zero, +) / 4
            }
        }
        let keeper = try XCTUnwrap(parts.first { $0.id == "tie-rear-keeper" })
        let keeperCenters = centers(keeper)
        let rearBandCenter = keeperCenters[keeperCenters.count / 2]
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

    func testThreadedBladePassesBehindTheFrontBandBeforeAndAfterDressing() throws {
        // Ray intersections test rendered surfaces rather than just centreline
        // coordinates. The last route segment is W descending through the band;
        // the earlier crossing must cover it from the front (+Y).
        for (action, diagramZ) in [(4, Float(275)), (5, Float(185)), (6, Float(185))] {
            let wide = try XCTUnwrap(EverydayKnotGeometry.parts(courseID: .fourInHand, actionIndex: action, progress: 1)
                .first { $0.id == "tie-wide-W" })
            let hits = surfaceHits(wide, x: 0.0022, z: (diagramZ - 210) * 0.0022)
            let lastRing = try XCTUnwrap(hits.map(\.ring).max())
            let blade = try XCTUnwrap(hits.filter { $0.ring >= lastRing - 2 }.map(\.height).max())
            let band = try XCTUnwrap(hits.filter { $0.ring < lastRing - 4 }.map(\.height).max())
            XCTAssertGreaterThan(band, blade + 0.015, "Action \(action): W must pass behind the front band")
        }
    }

    func testDressingTheKnotDoesNotRollTheFreeBladeEdgeOn() throws {
        // Both endpoint silhouettes used to look broad while the interpolated
        // blade turned sideways halfway through action 6. It is being pulled
        // down, not twisted, so its lower straight section must stay readable.
        for sample in 0...20 {
            let wide = try XCTUnwrap(EverydayKnotGeometry.parts(courseID: .fourInHand, actionIndex: 5,
                                                              progress: Double(sample) / 20)
                .first { $0.id == "tie-wide-W" })
            let ringCount = wide.positions.count / 4
            for ring in Int(Float(ringCount) * 0.86)..<Int(Float(ringCount) * 0.96) {
                let across = simd_normalize(wide.positions[ring * 4 + 1] - wide.positions[ring * 4])
                XCTAssertLessThan(abs(across.y), 0.15, "The hanging blade must not roll edge-on")
                XCTAssertLessThan(across.x, -0.90, "Keep a consistent width direction throughout dressing")
            }
        }
    }

    func testFinishedNarrowTailIsCoveredByTheWideBladeAcrossItsWidth() throws {
        let parts = EverydayKnotGeometry.parts(courseID: .fourInHand, actionIndex: 6, progress: 1)
        let wide = try XCTUnwrap(parts.first { $0.id == "tie-wide-W" })
        let narrow = try XCTUnwrap(parts.first { $0.id == "tie-narrow-N" })
        // The lower tail must be behind W at its edges too. Centreline-only
        // checks missed the orange stripe from the previously twisted ribbon.
        let tail = narrow.positions.filter { $0.z > (Float(245) - 210) * 0.0022 }
        XCTAssertGreaterThan(tail.count, 10)
        for point in tail {
            let cover = try XCTUnwrap(surfaceHits(wide, x: point.x, z: point.z).map(\.height).max())
            XCTAssertGreaterThan(cover, point.y + 0.003)
        }
    }

    func testLoweredCollarActuallyCoversTheNeckBand() throws {
        let parts = EverydayKnotGeometry.parts(courseID: .fourInHand, actionIndex: 6, progress: 1)
        let neck = try XCTUnwrap(parts.first { $0.id == "tie-neck-loop" })
        let collars = parts.filter { $0.id.hasPrefix("tie-collar") }
        XCTAssertEqual(collars.count, 2)
        // Exclude end caps where the band enters the knot; the collar must cover
        // the rear and sides of the entire neck loop, not merely be present.
        let ringCount = neck.positions.count / 4
        for ring in stride(from: 2, to: ringCount - 2, by: 5) {
            let center = neck.positions[(ring * 4)..<(ring * 4 + 4)].reduce(.zero, +) / 4
            let cover = try XCTUnwrap(collars.flatMap { surfaceHits($0, x: center.x, z: center.z).map(\.height) }.max())
            XCTAssertGreaterThan(cover, center.y + 0.015)
        }
    }

    private func surfaceHits(_ part: EverydayMeshPart, x: Float, z: Float) -> [(ring: Int, height: Float)] {
        var hits: [(ring: Int, height: Float)] = []
        for offset in stride(from: 0, to: part.triangles.count, by: 3) {
            let ids = part.triangles[offset..<(offset + 3)].map(Int.init)
            let a = part.positions[ids[0]], b = part.positions[ids[1]], c = part.positions[ids[2]]
            let determinant = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
            guard abs(determinant) > 1e-10 else { continue }
            let u = ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / determinant
            let v = ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / determinant
            let w = 1 - u - v
            if min(u, min(v, w)) >= -0.0001 {
                hits.append((ring: ids.min()! / 4, height: a.y * u + b.y * v + c.y * w))
            }
        }
        return hits
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
