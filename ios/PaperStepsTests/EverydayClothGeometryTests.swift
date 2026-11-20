import XCTest
import simd
@testable import Protacta

final class EverydayClothGeometryTests: XCTestCase {
    private let courses: [(EverydayTutorialID, Int)] = [(.tShirt, 6), (.towel, 3), (.flatBedsheet, 4)]

    func testEveryAdjacentActionStartsAtThePreviousActionEndpoint() {
        for (course, count) in courses {
            for action in 0..<(count - 1) {
                let end = frame(course, action, 1), next = frame(course, action + 1, 0)
                XCTAssertEqual(end.map(\.id), next.map(\.id), "\(course) action \(action)")
                for (a, b) in zip(end, next) {
                    XCTAssertEqual(a.triangles, b.triangles)
                    XCTAssertEqual(a.positions.count, b.positions.count)
                    for (p, q) in zip(a.positions, b.positions) {
                        XCTAssertLessThan(simd_distance(p, q), 0.000001, "\(course) \(a.id)")
                    }
                }
            }
        }
    }

    func testEveryAuthoredActionShowsARealLiftAndChangesTheTargetShape() {
        for (course, count) in courses {
            for action in 0..<count {
                let start = frame(course, action, 0), middle = frame(course, action, 0.5), end = frame(course, action, 1)
                let initialY = points(start).map(\.y).max() ?? 0
                let finalY = points(end).map(\.y).max() ?? 0
                let liftedY = points(middle).map(\.y).max() ?? 0
                XCTAssertGreaterThan(liftedY, max(initialY, finalY) + 0.02, "\(course), action \(action)")
                let movement = zip(start, end).flatMap { a, b in zip(a.positions, b.positions).map { simd_distance($0, $1) } }.max() ?? 0
                XCTAssertGreaterThan(movement, 0.04, "\(course), action \(action) must animate its own movement")
                XCTAssertTrue(middle.contains(where: \.isMoving))
            }
        }
    }

    func testMeshTopologyIsStableAndAllSampledTrianglesAreFiniteAndNondegenerate() {
        for (course, count) in courses {
            let reference = frame(course, 0, 0)
            XCTAssertFalse(reference.isEmpty)
            XCTAssertLessThanOrEqual(reference.count, 32, "Keep runtime mesh/entity count bounded")
            for action in 0..<count {
                for sample in 0...20 {
                    let parts = frame(course, action, Double(sample) / 20)
                    XCTAssertEqual(parts.map(\.id), reference.map(\.id))
                    for (part, original) in zip(parts, reference) {
                        XCTAssertEqual(part.positions.count, original.positions.count)
                        XCTAssertEqual(part.triangles, original.triangles)
                        XCTAssertEqual(part.triangles.count % 3, 0)
                        XCTAssertFalse(part.triangles.isEmpty)
                        for point in part.positions {
                            XCTAssertTrue(point.x.isFinite && point.y.isFinite && point.z.isFinite)
                            XCTAssertGreaterThanOrEqual(point.y, -0.00001)
                            XCTAssertLessThan(abs(point.x), 0.6)
                            XCTAssertLessThan(abs(point.z), 0.6)
                            XCTAssertLessThan(point.y, 0.7)
                        }
                        for triangle in stride(from: 0, to: part.triangles.count, by: 3) {
                            let indices = Array(part.triangles[triangle..<(triangle + 3)]).map(Int.init)
                            XCTAssertTrue(indices.allSatisfy { part.positions.indices.contains($0) })
                            guard indices.allSatisfy({ part.positions.indices.contains($0) }) else { continue }
                            let a = part.positions[indices[0]], b = part.positions[indices[1]], c = part.positions[indices[2]]
                            XCTAssertGreaterThan(simd_length_squared(simd_cross(b - a, c - a)), 1e-18)
                        }
                    }
                }
            }
        }
    }

    func testCompletedLinensAndShirtHaveTheExpectedFoldedFootprints() {
        let towel = bounds(frame(.towel, 2, 1))
        // A finite-radius outer bend adds 6 / 12 mm to the old zero-radius
        // envelope. It must not be squeezed back into a paper-thin footprint.
        XCTAssertEqual(towel.maximum.x - towel.minimum.x, 0.206, accuracy: 0.00001)
        XCTAssertEqual(towel.maximum.z - towel.minimum.z, 0.462, accuracy: 0.00001)
        let sheet = bounds(frame(.flatBedsheet, 3, 1))
        XCTAssertEqual(sheet.maximum.x - sheet.minimum.x, 0.1875, accuracy: 0.00001)
        XCTAssertEqual(sheet.maximum.z - sheet.minimum.z, 0.2315, accuracy: 0.00001)
        let shirt = bounds(frame(.tShirt, 5, 1))
        XCTAssertEqual(shirt.maximum.x - shirt.minimum.x, 0.243, accuracy: 0.00001)
        XCTAssertEqual(shirt.maximum.z - shirt.minimum.z, 0.18, accuracy: 0.00001)
    }

    func testShirtStartsWithSleevesAndAnOpenNeckInsteadOfARectangularBillboard() {
        let shirt = frame(.tShirt, 0, 0)
        let initial = bounds(shirt)
        XCTAssertEqual(initial.maximum.x - initial.minimum.x, 0.74, accuracy: 0.00001)
        XCTAssertTrue(shirt.contains { $0.id.contains("sleeve_tip") })
        let neck = SIMD2<Float>(0, -0.29)
        var covered = false
        for part in shirt {
            for triangle in stride(from: 0, to: part.triangles.count, by: 3) {
                let p = (0..<3).map { part.positions[Int(part.triangles[triangle + $0])] }.map { SIMD2($0.x, $0.z) }
                if contains(neck, p[0], p[1], p[2]) { covered = true }
            }
        }
        XCTAssertFalse(covered, "The far centre must remain an actual neck opening")
    }

    func testInvalidInputsClampAndUnsupportedCoursesStayOutsideClothRenderer() {
        for (course, count) in courses {
            XCTAssertEqual(points(frame(course, -20, -.infinity)), points(frame(course, 0, 0)))
            XCTAssertEqual(points(frame(course, 0, .nan)), points(frame(course, 0, 0)))
            XCTAssertEqual(points(frame(course, 500, 2)), points(frame(course, count - 1, 1)))
        }
        XCTAssertTrue(frame(.squareKnot, 0, 0).isEmpty)
        XCTAssertTrue(frame(.fourInHand, 0, 0).isEmpty)
    }

    func testNonuniformCalibrationBendsFabricWithoutStretchingItsFreePanels() {
        let scales: [SIMD3<Float>] = [[1, sqrt(2), 2], [1.6, sqrt(1.28), 0.8]]
        for scale in scales {
            for (course, count) in [(EverydayTutorialID.tShirt, 6), (.flatBedsheet, 4)] {
                let initial = EverydayMeshGeometry.parts(courseID: course, actionIndex: 0, progress: 0, objectScale: scale)
                for action in 0..<count {
                    for progress in [0.0, 0.2, 0.5, 0.8, 1.0] {
                        let parts = EverydayMeshGeometry.parts(courseID: course, actionIndex: action,
                                                              progress: progress, objectScale: scale)
                        XCTAssertEqual(parts.map(\.id), initial.map(\.id))
                        for (before, after) in zip(initial, parts) {
                            XCTAssertEqual(before.triangles, after.triangles)
                            XCTAssertEqual(before.positions.count, after.positions.count)
                            for triangle in stride(from: 0, to: before.triangles.count, by: 3) {
                                let indices = (0..<3).map { Int(before.triangles[triangle + $0]) }
                                for edge in 0..<3 {
                                    let a = indices[edge], b = indices[(edge + 1) % 3]
                                    let original = simd_distance(before.positions[a], before.positions[b])
                                    let posed = simd_distance(after.positions[a], after.positions[b])
                                    // Chords shorten inside a rounded fold; a
                                    // rigid-panel equality would forbid bending.
                                    // The restrained free-edge drape may extend
                                    // a chord slightly, never pull a tiny edge
                                    // into a long filament at intersecting folds.
                                    XCTAssertLessThanOrEqual(posed, original * 1.025 + 0.000002,
                                                            "\(course) action \(action): cloth must not stretch across a fold")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testNonuniformCalibrationPreservesActionBoundariesAndFiniteMeshes() {
        let scales: [SIMD3<Float>] = [[1, sqrt(2), 2], [1.6, sqrt(1.28), 0.8]]
        for scale in scales {
            for (course, count) in courses {
                for action in 0..<count {
                    for sample in 0...10 {
                        let parts = EverydayMeshGeometry.parts(courseID: course, actionIndex: action,
                                                              progress: Double(sample) / 10, objectScale: scale)
                        XCTAssertFalse(parts.isEmpty)
                        XCTAssertTrue(parts.flatMap(\.positions).allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
                        for part in parts {
                            for triangle in stride(from: 0, to: part.triangles.count, by: 3) {
                                let p = (0..<3).map { part.positions[Int(part.triangles[triangle + $0])] }
                                XCTAssertGreaterThan(simd_length_squared(simd_cross(p[1] - p[0], p[2] - p[0])), 1e-18)
                            }
                        }
                    }
                    if action + 1 < count {
                        let end = EverydayMeshGeometry.parts(courseID: course, actionIndex: action, progress: 1, objectScale: scale)
                        let next = EverydayMeshGeometry.parts(courseID: course, actionIndex: action + 1, progress: 0, objectScale: scale)
                        XCTAssertEqual(end.map(\.id), next.map(\.id))
                        XCTAssertEqual(end.map(\.triangles), next.map(\.triangles))
                        for (p, q) in zip(end.flatMap(\.positions), next.flatMap(\.positions)) {
                            XCTAssertLessThan(simd_distance(p, q), 0.000001)
                        }
                    }
                }
            }
        }
    }

    func testInvalidCalibrationDimensionsFallBackToUnscaledGeometry() {
        for course in [EverydayTutorialID.towel, .tShirt, .flatBedsheet] {
            let original = EverydayMeshGeometry.parts(courseID: course, actionIndex: 0, progress: 0.5)
            for scale: SIMD3<Float> in [[0, 1, 1], [-1, 1, 1], [1, .nan, 1], [1, 1, .infinity]] {
                XCTAssertEqual(EverydayMeshGeometry.parts(courseID: course, actionIndex: 0, progress: 0.5, objectScale: scale), original)
            }
        }
    }

    func testFabricCoordinatesStayAttachedWhileScrubbingAndRespectCalibratedMetres() throws {
        for scale: SIMD3<Float> in [[1, 1, 1], [1.6, sqrt(1.28), 0.8]] {
            for (course, count) in courses {
                let reference = EverydayClothGeometry.parts(courseID: course, actionIndex: 0, progress: 0, objectScale: scale)
                for action in 0..<count {
                    for progress in [0.0, 0.2, 0.5, 0.8, 1.0, 0.25] {
                        let posed = EverydayClothGeometry.parts(courseID: course, actionIndex: action, progress: progress, objectScale: scale)
                        XCTAssertEqual(posed.map(\.id), reference.map(\.id))
                        for (part, rest) in zip(posed, reference) {
                            let coordinates = try XCTUnwrap(part.fabricUVs)
                            let sources = try XCTUnwrap(part.restPositions)
                            XCTAssertEqual(coordinates, rest.fabricUVs, "Fabric must not swim or reset at a step boundary")
                            XCTAssertEqual(coordinates.count, part.positions.count)
                            // The continuous towel (including its hem) stores
                            // calibrated source topology; other cloth is unscaled.
                            let uvScale = course == .towel ? SIMD3<Float>(repeating: 1) : scale
                            for (uv, source) in zip(coordinates, sources) {
                                XCTAssertEqual(uv.x, source.x * uvScale.x, accuracy: 0.000001)
                                XCTAssertEqual(uv.y, source.z * uvScale.z, accuracy: 0.000001)
                            }
                        }
                    }
                }
            }
        }
    }

    func testRaisedHemsExistOnlyAtActualOuterGarmentEdges() throws {
        let expected: [EverydayTutorialID: Set<String>] = [
            .towel: ["towel_hem"], .tShirt: ["shirt_collar", "shirt_cuffs", "shirt_hem"], .flatBedsheet: ["sheet_hem"]
        ]
        for (course, ids) in expected {
            let parts = frame(course, 0, 0).filter { ids.contains($0.id) }
            XCTAssertEqual(Set(parts.map(\.id)), ids)
            for part in parts {
                let sources = try XCTUnwrap(part.restPositions)
                XCTAssertFalse(sources.isEmpty)
                for p in sources {
                    switch part.id {
                    case "towel_hem":
                        XCTAssertTrue(abs(p.x) >= 0.28999 || abs(p.z) >= 0.43999,
                                      "The thirds/half-fold lines are not sewn hems")
                    case "sheet_hem":
                        XCTAssertTrue(abs(p.x) >= 0.35099 || abs(p.z) >= 0.42099)
                    case "shirt_cuffs": XCTAssertGreaterThanOrEqual(abs(p.x), 0.35799)
                    case "shirt_hem": XCTAssertGreaterThanOrEqual(p.z, 0.32799)
                    case "shirt_collar":
                        XCTAssertLessThanOrEqual(abs(p.x), 0.10001)
                        XCTAssertLessThanOrEqual(p.z, -0.239,
                                                "Only the neck opening has a collar; the chest fold is not a seam")
                    default: XCTFail("Unexpected detail")
                    }
                }
            }
        }
        let towel = frame(.towel, 0, 0)
        XCTAssertEqual(try XCTUnwrap(towel.first { $0.id == "towel_soft_body" }).surfaceThickness, 0.0026, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(towel.first { $0.id == "towel_hem" }).surfaceThickness, 0.0032, accuracy: 0.000001)
    }

    func testAttachedDetailShellsRemainValidAcrossEveryFoldAndReverseSeek() throws {
        let detailIDs: Set<String> = ["towel_hem", "shirt_collar", "shirt_cuffs", "shirt_hem", "sheet_hem"]
        for (course, count) in courses {
            for action in 0..<count {
                for progress in [0.0, 0.25, 0.5, 0.75, 1.0, 0.5, 0.0] {
                    for part in frame(course, action, progress) where detailIDs.contains(part.id) {
                        let surface = try EverydaySurfaceMesh.make(part: part)
                        XCTAssertFalse(surface.triangles.isEmpty)
                        XCTAssertEqual(surface.positions.count, surface.normals.count)
                        XCTAssertTrue(surface.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
                        XCTAssertTrue(surface.normals.allSatisfy { abs(simd_length($0) - 1) < 0.0001 })
                    }
                }
            }
        }
    }

    func testTowelBendHasIntermediateSurfaceDirectionsInsteadOfTwoRigidPlanes() throws {
        let body = try XCTUnwrap(frame(.towel, 0, 0.5).first { $0.id == "towel_soft_body" })
        let rest = try XCTUnwrap(body.restPositions)
        let surface = try EverydaySurfaceMesh.make(part: body)
        let curved = rest.indices.filter {
            rest[$0].x < -0.10 && rest[$0].x > -0.16 && abs(rest[$0].z + 0.30) < 0.00001
                && surface.normals[$0].y > 0.05 && surface.normals[$0].y < 0.95
        }
        XCTAssertGreaterThanOrEqual(curved.count, 6,
                                    "The lifted fabric needs a sampled curved band, not a sharp hinge")
    }

    func testShirtAndSheetRemainCurvedAfterTheFirstFoldLands() throws {
        for course in [EverydayTutorialID.tShirt, .flatBedsheet] {
            for progress in [0.5, 1.0] {
                var curvedNormals = 0
                for part in frame(course, 0, progress) where part.isMoving {
                    let surface = try EverydaySurfaceMesh.make(part: part)
                    // Source-face normals only: sidewalls must not be mistaken
                    // for the curved fabric surface this test is looking for.
                    curvedNormals += surface.normals.prefix(part.positions.count).filter {
                        abs($0.y) > 0.08 && abs($0.y) < 0.92
                    }.count
                }
                XCTAssertGreaterThan(curvedNormals, 20,
                                     "\(course) at \(progress) needs a resolved round bend, including the landed pose")
            }
        }
    }

    func testFlexibleBodiesKeepSharedSourceSeamsCoincident() throws {
        for scale: SIMD3<Float> in [[1, 1, 1], [1.6, sqrt(1.28), 0.8]] {
            for course in [EverydayTutorialID.tShirt, .flatBedsheet] {
                for action in EverydayTutorialCourse.course(course).actions.indices {
                    for progress in [0.0, 0.5, 1.0] {
                        let parts = EverydayMeshGeometry.parts(courseID: course, actionIndex: action,
                                                              progress: progress, objectScale: scale)
                        var shared: [SIMD3<Int32>: SIMD3<Float>] = [:]
                        for part in parts {
                            let rest = try XCTUnwrap(part.restPositions)
                            for (source, posed) in zip(rest, part.positions) {
                                let key = SIMD3<Int32>(Int32((source.x * 1e6).rounded()),
                                                       Int32((source.y * 1e6).rounded()), Int32((source.z * 1e6).rounded()))
                                if let neighbour = shared[key] {
                                    XCTAssertLessThan(simd_distance(neighbour, posed), 0.000005,
                                                      "\(course) action \(action): material classifications cannot open a seam")
                                } else { shared[key] = posed }
                            }
                        }
                    }
                }
            }
        }
    }

    func testFlexibleNormalsFollowFaceWindingAndMeetAcrossMaterialBoundaries() throws {
        for scale: SIMD3<Float> in [[1, 1, 1], [1.6, sqrt(1.28), 0.8]] {
            for course in [EverydayTutorialID.tShirt, .flatBedsheet] {
                for action in EverydayTutorialCourse.course(course).actions.indices {
                    for progress in [0.0, 0.5, 1.0] {
                        var shared: [SIMD3<Int32>: SIMD3<Float>] = [:]
                        let parts = EverydayMeshGeometry.parts(courseID: course, actionIndex: action,
                                                              progress: progress, objectScale: scale)
                        for part in parts {
                            let normals = try XCTUnwrap(part.surfaceNormals)
                            let rest = try XCTUnwrap(part.restPositions)
                            XCTAssertEqual(normals.count, part.positions.count)
                            for index in normals.indices {
                                XCTAssertEqual(simd_length(normals[index]), 1, accuracy: 0.0001)
                                let p = rest[index]
                                let key = SIMD3<Int32>(Int32((p.x * 1e6).rounded()), Int32((p.y * 1e6).rounded()), Int32((p.z * 1e6).rounded()))
                                if let neighbour = shared[key] {
                                    // Mirrored source polygons can reverse their
                                    // front face; the physical normal axis must
                                    // still be continuous across that boundary.
                                    XCTAssertGreaterThan(abs(simd_dot(neighbour, normals[index])), 0.995)
                                } else { shared[key] = normals[index] }
                            }
                            for i in stride(from: 0, to: part.triangles.count, by: 3) {
                                let indices = (0..<3).map { Int(part.triangles[i + $0]) }
                                let p = indices.map { part.positions[$0] }
                                let face = simd_normalize(simd_cross(p[1] - p[0], p[2] - p[0]))
                                let average = indices.map { normals[$0] }.reduce(SIMD3<Float>.zero, +)
                                XCTAssertGreaterThanOrEqual(simd_dot(face, average), -0.001,
                                                           "\(course) action \(action): shading normals must face the mesh front")
                            }
                        }
                    }
                }
            }
        }
    }

    private func frame(_ course: EverydayTutorialID, _ action: Int, _ progress: Double) -> [EverydayMeshPart] {
        EverydayClothGeometry.parts(courseID: course, actionIndex: action, progress: progress)
    }
    private func points(_ parts: [EverydayMeshPart]) -> [SIMD3<Float>] { parts.flatMap(\.positions) }
    private func bounds(_ parts: [EverydayMeshPart]) -> (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        let p = points(parts)
        return (p.reduce(SIMD3(repeating: .greatestFiniteMagnitude), simd_min),
                p.reduce(SIMD3(repeating: -.greatestFiniteMagnitude), simd_max))
    }
    private func contains(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
        func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        let d = [cross(a, b, p), cross(b, c, p), cross(c, a, p)]
        return d.allSatisfy { $0 >= -1e-8 } || d.allSatisfy { $0 <= 1e-8 }
    }
}
