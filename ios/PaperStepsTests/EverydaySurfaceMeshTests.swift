import XCTest
import simd
@testable import Protacta

final class EverydaySurfaceMeshTests: XCTestCase {
    func testCurvedNormalOffsetsCullOnlyCollapsedSkinSlivers() throws {
        let cloth = EverydayMeshPart(id: "curved-sliver",
                                     positions: [[0, 0, 0], [0, 0, 0.001], [0.000002, 0, 0]],
                                     triangles: [0, 1, 2], colorIndex: 0, isMoving: false,
                                     surfaceThickness: 0.002,
                                     surfaceNormals: [[0, 1, 0], [0, 1, 0], [-0.0015, 1, 0]])
        let surface = try EverydaySurfaceMesh.make(part: cloth)
        let faces = stride(from: 0, to: surface.triangles.count, by: 3).map {
            Array(surface.triangles[$0..<($0 + 3)])
        }
        XCTAssertFalse(faces.contains([0, 1, 2]), "The front offset collapses below the render tolerance")
        XCTAssertTrue(faces.contains([5, 4, 3]), "The opposite skin stays valid and must be retained")
        assertValid(surface)
    }

    func testAuthoredClothNormalsDriveSmoothShadingAndSkinOffsets() throws {
        let direction = SIMD3<Float>(0, 0.8, 0.6)
        let part = EverydayMeshPart(id: "curved-cloth", positions: [[0, 0, 0], [0, 0, 1], [1, 0, 0]],
                                    triangles: [0, 1, 2], colorIndex: 0, isMoving: false,
                                    surfaceThickness: 0.002,
                                    surfaceNormals: Array(repeating: direction * 3, count: 3))
        let surface = try EverydaySurfaceMesh.make(part: part)
        for index in 0..<3 {
            XCTAssertLessThan(simd_distance(surface.normals[index], direction), 1e-6)
            XCTAssertLessThan(simd_distance(surface.positions[index], part.positions[index] + direction * 0.001), 1e-6)
            XCTAssertLessThan(simd_distance(surface.positions[index + 3], part.positions[index] - direction * 0.001), 1e-6)
        }
        for invalid in [[SIMD3<Float>(0, 1, 0)], Array(repeating: SIMD3<Float>.zero, count: 3),
                        Array(repeating: SIMD3<Float>(.nan, 1, 0), count: 3)] {
            var bad = part; bad.surfaceNormals = invalid
            XCTAssertThrowsError(try EverydaySurfaceMesh.make(part: bad))
        }
    }

    func testDuplicatedTriangleVerticesDoNotCreateAnInternalWall() throws {
        let points: [SIMD3<Float>] = [[-1, 0, -1], [-1, 0, 1], [1, 0, 1],
                                     [-1, 0, -1], [1, 0, 1], [1, 0, -1]]
        let mesh = try EverydaySurfaceMesh.make(part: part(points, rest: points))
        XCTAssertEqual(mesh.triangles.count / 3, 12,
                       "Two faces per side and two sidewall triangles per four boundary edges")
        XCTAssertEqual(mesh.positions.map(\.y).max()!, 0.00035, accuracy: 0.000001)
        XCTAssertEqual(mesh.positions.map(\.y).min()!, -0.00035, accuracy: 0.000001)
        assertValid(mesh)
    }

    func testFoldedContactDoesNotWeldDifferentRestLayers() throws {
        let rest: [SIMD3<Float>] = [[-1, 0, -1], [-1, 0, 1], [0, 0, 1],
                                   [1, 0, -1], [1, 0, 1], [2, 0, 1]]
        let posed = Array(rest.prefix(3)) + Array(rest.prefix(3))
        let mesh = try EverydaySurfaceMesh.make(part: part(posed, rest: rest))
        XCTAssertEqual(mesh.triangles.count / 3, 16,
                       "Two coincident layers still each retain three perimeter edges")
        assertValid(mesh)
    }

    func testInvalidGeometryIsRejectedBeforeIndexingOrQuantization() {
        let points: [SIMD3<Float>] = [[0, 0, 0], [0, 0, 1], [1, 0, 1]]
        var invalid = part(points, rest: points)
        invalid = EverydayMeshPart(id: "shirt_fixture", positions: points, triangles: [0, 1, 99], colorIndex: 1, isMoving: false)
        XCTAssertThrowsError(try EverydaySurfaceMesh.make(part: invalid))
        XCTAssertThrowsError(try EverydaySurfaceMesh.make(part: part([], rest: [])))
        XCTAssertThrowsError(try EverydaySurfaceMesh.make(part: part(points, rest: [[0, 0, 0]])))
        XCTAssertThrowsError(try EverydaySurfaceMesh.make(part: part(points, rest: [[.nan, 0, 0], points[1], points[2]])))
        XCTAssertThrowsError(try EverydaySurfaceMesh.make(part: part([[.infinity, 0, 0], points[1], points[2]], rest: nil)))
        invalid = part(points, rest: points)
        invalid.fabricUVs = [[0, 0]]
        XCTAssertThrowsError(try EverydaySurfaceMesh.make(part: invalid))
        invalid.fabricUVs = [[0, .nan], [0, 1], [1, 1]]
        XCTAssertThrowsError(try EverydaySurfaceMesh.make(part: invalid))
        invalid.fabricUVs = [[0, 0], [0, .infinity], [1, 1]]
        XCTAssertThrowsError(try EverydaySurfaceMesh.make(part: invalid))
    }

    func testFoldedFacesKeepTheirAuthoredFabricCoordinatesOnBothSides() throws {
        let rest: [SIMD3<Float>] = [[-0.2, 0, 0], [0, 0, 0.3], [0.2, 0, 0],
                                   [-0.2, 0, 0], [0.2, 0, 0], [0, 0, -0.3]]
        let uvs = rest.map { SIMD2<Float>($0.x, $0.z) }
        var prior: EverydaySurfaceMesh.Surface?
        for angle: Float in [0.2, 0.6, 1.2, 2.0] {
            var points = rest
            points[5] = [0, 0.3 * sin(angle), -0.3 * cos(angle)]
            var folded = part(points, rest: rest)
            folded.fabricUVs = uvs
            let surface = try EverydaySurfaceMesh.make(part: folded)
            XCTAssertEqual(Array(surface.textureCoordinates.prefix(rest.count)), uvs)
            XCTAssertEqual(Array(surface.textureCoordinates[rest.count..<(2 * rest.count)]), uvs)
            if let prior {
                XCTAssertNotEqual(surface.positions, prior.positions)
                XCTAssertEqual(surface.textureCoordinates, prior.textureCoordinates,
                               "Crease bridges and sides must not remap their fabric as they move")
            }
            assertValid(surface)
            assertNondegenerateTextureTriangles(surface)
            prior = surface
        }
    }

    func testSidewallTextureWidthUsesPhysicalThicknessInsteadOfAWholeTile() throws {
        let points: [SIMD3<Float>] = [[0, 0, 0], [0, 0, 0.3], [0.4, 0, 0]]
        var cloth = part(points, rest: points)
        cloth.fabricUVs = points.map { SIMD2<Float>($0.x, $0.z) }
        let surface = try EverydaySurfaceMesh.make(part: cloth)
        // Each boundary quad emits six vertices after the paired front/back.
        for index in stride(from: points.count * 2, to: surface.positions.count, by: 6) {
            let along = surface.textureCoordinates[index + 2] - surface.textureCoordinates[index + 1]
            let across = surface.textureCoordinates[index + 1] - surface.textureCoordinates[index]
            XCTAssertEqual(simd_length(across), cloth.surfaceThickness, accuracy: 1e-7)
            XCTAssertEqual(simd_dot(along, across), 0, accuracy: 1e-7)
            XCTAssertEqual(simd_length(along),
                           simd_distance(surface.positions[index + 2], surface.positions[index + 1]), accuracy: 1e-6)
        }
        assertNondegenerateTextureTriangles(surface)
        assertValid(surface)
    }

    func testClothFabricUVsRemainStableThroughoutEachAction() throws {
        for id in [EverydayTutorialID.towel, .tShirt, .flatBedsheet] {
            for action in EverydayTutorialCourse.course(id).actions.indices {
                let start = EverydayMeshGeometry.parts(courseID: id, actionIndex: action, progress: 0)
                for progress in [0.25, 0.5, 0.75, 1.0] {
                    let posed = EverydayMeshGeometry.parts(courseID: id, actionIndex: action, progress: progress)
                    XCTAssertEqual(start.map(\.id), posed.map(\.id))
                    for (a, b) in zip(start, posed) {
                        let uvs = try XCTUnwrap(a.fabricUVs, "Cloth needs authored material coordinates: \(a.id)")
                        XCTAssertEqual(uvs, b.fabricUVs, "\(id) action \(action): fabric must not swim")
                        let mesh = try EverydaySurfaceMesh.make(part: b)
                        XCTAssertEqual(Array(mesh.textureCoordinates.prefix(b.positions.count)), uvs)
                        if b.surfaceThickness > 0 {
                            XCTAssertEqual(Array(mesh.textureCoordinates[b.positions.count..<(b.positions.count * 2)]), uvs)
                        }
                    }
                }
            }
        }
    }

    func testAllCoursesProduceFiniteSurfacesWhileScrubbingAndAtActionBoundaries() throws {
        for course in EverydayTutorialCourse.all {
            for action in course.actions.indices {
                for amount in [0.0, 0.01, 0.25, 0.5, 0.75, 0.99, 1.0] {
                    let parts = EverydayMeshGeometry.parts(courseID: course.id, actionIndex: action, progress: amount)
                    for part in parts {
                        let surface = try EverydaySurfaceMesh.make(part: part)
                        assertValid(surface, context: "\(course.id) \(action) \(amount) \(part.id)")
                        if part.fabricUVs != nil { assertNondegenerateTextureTriangles(surface) }
                    }
                }
                if action + 1 < course.actions.count {
                    let end = EverydayMeshGeometry.parts(courseID: course.id, actionIndex: action, progress: 1)
                    let start = EverydayMeshGeometry.parts(courseID: course.id, actionIndex: action + 1, progress: 0)
                    for (a, b) in zip(end, start) {
                        let first = try EverydaySurfaceMesh.make(part: a), next = try EverydaySurfaceMesh.make(part: b)
                        XCTAssertEqual(first.triangles, next.triangles, "Action boundaries preserve visible shell topology")
                        XCTAssertEqual(first.textureCoordinates, next.textureCoordinates,
                                       "Action changes must not reset the weave")
                        XCTAssertEqual(first.positions.count, next.positions.count)
                        for (p, q) in zip(first.positions, next.positions) {
                            XCTAssertLessThan(simd_distance(p, q), 0.000002)
                        }
                    }
                }
            }
        }
    }

    func testTubeAndRibbonMeshesKeepTheirExistingClosedSurface() throws {
        for id in [EverydayTutorialID.squareKnot, .fourInHand] {
            for part in EverydayMeshGeometry.parts(courseID: id, actionIndex: 2, progress: 0.37)
            where !part.id.hasPrefix("tie-collar-") {
                let mesh = try EverydaySurfaceMesh.make(part: part)
                XCTAssertEqual(Array(mesh.positions.prefix(part.positions.count)), part.positions,
                               "\(part.id) already has physical thickness")
                XCTAssertEqual(mesh.triangles.map { mesh.positions[Int($0)] },
                               part.triangles.map { part.positions[Int($0)] },
                               "UV chart splits must preserve every triangle's geometry and winding")
                XCTAssertEqual(Array(mesh.textureCoordinates.prefix(part.positions.count)),
                               part.fabricUVs ?? Array(repeating: .zero, count: part.positions.count),
                               "Closed volumes retain authored material coordinates without adding a shell")
                if part.closedRibbonThickness == nil {
                    XCTAssertEqual(mesh.positions, part.positions)
                    XCTAssertEqual(mesh.triangles, part.triangles)
                }
            }
        }
    }

    func testClosedRibbonEdgeAndCapChartsStayValidAndFixedAcrossTheWholeLesson() throws {
        var reference: [String: EverydaySurfaceMesh.Surface] = [:]
        for action in EverydayTutorialCourse.course(.fourInHand).actions.indices {
            for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
                for part in EverydayMeshGeometry.parts(courseID: .fourInHand, actionIndex: action, progress: progress)
                where part.closedRibbonThickness != nil {
                    let mesh = try EverydaySurfaceMesh.make(part: part)
                    assertNondegenerateTextureTriangles(mesh)
                    XCTAssertEqual(mesh.triangles.map { mesh.positions[Int($0)] },
                                   part.triangles.map { part.positions[Int($0)] })
                    if let first = reference[part.id] {
                        XCTAssertEqual(mesh.triangles, first.triangles)
                        XCTAssertEqual(mesh.textureCoordinates, first.textureCoordinates,
                                       "Thin edge/cap weave must not swim during tying or scrubbing")
                    } else { reference[part.id] = mesh }
                    for uv in mesh.textureCoordinates.dropFirst(part.positions.count) {
                        // Side charts use thickness across; caps use thickness vertically.
                        XCTAssertTrue(uv.x == 0 || uv.x == part.closedRibbonThickness ||
                                      uv.y == 0 || uv.y == part.closedRibbonThickness)
                    }
                }
            }
        }
        XCTAssertFalse(reference.isEmpty)
    }

    func testClosedMeshesHaveOutwardWindingAndNormals() throws {
        for id in [EverydayTutorialID.squareKnot, .fourInHand] {
            for part in EverydayMeshGeometry.parts(courseID: id, actionIndex: 0, progress: 0)
            where part.surfaceThickness == 0 {
                let mesh = try EverydaySurfaceMesh.make(part: part)
                var volume: Double = 0
                for i in stride(from: 0, to: mesh.triangles.count, by: 3) {
                    let p = (0..<3).map { mesh.positions[Int(mesh.triangles[i + $0])] }
                    volume += Double(simd_dot(p[0], simd_cross(p[1], p[2]))) / 6
                }
                XCTAssertGreaterThan(volume, 0, "\(part.id) must face outward with normal backface culling")
                let ringSize = id == .squareKnot ? 10 : 4
                let center = part.positions.prefix(ringSize).reduce(SIMD3<Float>.zero, +) / Float(ringSize)
                for i in 0..<ringSize {
                    XCTAssertGreaterThan(simd_dot(mesh.normals[i], part.positions[i] - center), 0,
                                         "\(part.id) normals must face away from its cross-section")
                }
            }
        }
    }

    func testClothShellThicknessScalesWithTheRealObjectFit() throws {
        let scale = SIMD3<Float>(0.2, sqrt(0.06), 0.3)
        for id in [EverydayTutorialID.towel, .tShirt, .flatBedsheet] {
            let plain = EverydayMeshGeometry.parts(courseID: id, actionIndex: 0, progress: 0)
            let fitted = EverydayMeshGeometry.parts(courseID: id, actionIndex: 0, progress: 0, objectScale: scale)
            for (a, b) in zip(plain, fitted) {
                XCTAssertEqual(b.surfaceThickness, a.surfaceThickness * scale.y, accuracy: 0.0000001)
                let mesh = try EverydaySurfaceMesh.make(part: b)
                for index in b.positions.indices {
                    XCTAssertEqual(simd_distance(mesh.positions[index], b.positions[index]),
                                   b.surfaceThickness / 2, accuracy: 0.0000001)
                }
                assertValid(mesh)
            }
        }
    }

    private func part(_ points: [SIMD3<Float>], rest: [SIMD3<Float>]?) -> EverydayMeshPart {
        EverydayMeshPart(id: "shirt_fixture", positions: points,
                         triangles: (0..<points.count).map(UInt32.init), colorIndex: 1,
                         isMoving: false, restPositions: rest, surfaceThickness: 0.0007)
    }

    private func assertValid(_ mesh: EverydaySurfaceMesh.Surface, context: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(mesh.positions.count, mesh.normals.count, context, file: file, line: line)
        XCTAssertEqual(mesh.positions.count, mesh.textureCoordinates.count, context, file: file, line: line)
        XCTAssertFalse(mesh.triangles.isEmpty, context, file: file, line: line)
        XCTAssertEqual(mesh.triangles.count % 3, 0, context, file: file, line: line)
        for normal in mesh.normals {
            XCTAssertTrue(normal.x.isFinite && normal.y.isFinite && normal.z.isFinite, context, file: file, line: line)
            XCTAssertEqual(simd_length(normal), 1, accuracy: 0.0001, context, file: file, line: line)
        }
        XCTAssertTrue(mesh.textureCoordinates.allSatisfy { $0.x.isFinite && $0.y.isFinite },
                      context, file: file, line: line)
        for i in stride(from: 0, to: mesh.triangles.count, by: 3) {
            let indices = (0..<3).map { Int(mesh.triangles[i + $0]) }
            guard indices.allSatisfy({ mesh.positions.indices.contains($0) }) else {
                XCTFail("Invalid triangle: \(context)", file: file, line: line); continue
            }
            let p = indices.map { mesh.positions[$0] }
            XCTAssertGreaterThan(simd_length_squared(simd_cross(p[1] - p[0], p[2] - p[0])), 1e-18,
                                 context, file: file, line: line)
        }
    }

    private func assertNondegenerateTextureTriangles(_ mesh: EverydaySurfaceMesh.Surface,
                                                     file: StaticString = #filePath, line: UInt = #line) {
        for index in stride(from: 0, to: mesh.triangles.count, by: 3) {
            let uv = (0..<3).map { mesh.textureCoordinates[Int(mesh.triangles[index + $0])] }
            let a = uv[1] - uv[0], b = uv[2] - uv[0]
            XCTAssertGreaterThan(abs(a.x * b.y - a.y * b.x), 1e-12,
                                 "Normal-mapped faces and seam strips need a valid UV frame", file: file, line: line)
        }
    }
}
