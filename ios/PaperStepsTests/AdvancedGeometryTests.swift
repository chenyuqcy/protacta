import XCTest
import simd
@testable import Protacta

/// These tests establish render stability, retained material identity and lesson
/// continuity. They do not certify rigid folding, collision freedom or physical
/// knot topology for the authored squash, petal, knot and pinch animations.
final class AdvancedGeometryTests: XCTestCase {
    private struct LessonFixture {
        let name: String
        let steps: [LessonStep]
        let count: Int
        let frame: (Int, Float) -> PaperFrame
    }

    private var lessons: [LessonFixture] {
        [LessonFixture(name: "Crane", steps: CraneLessonContent.steps,
                       count: CraneGeometry.stepCount, frame: CraneGeometry.frame),
         LessonFixture(name: "Star", steps: StarLessonContent.steps,
                       count: StarGeometry.stepCount, frame: StarGeometry.frame)]
    }

    func testLessonStatesMatchGeometryStates() {
        for lesson in lessons {
            XCTAssertEqual(lesson.steps.count, lesson.count, lesson.name)
            XCTAssertEqual(lesson.steps.map(\.id), Array(0..<lesson.count), lesson.name)
            for step in lesson.steps {
                XCTAssertFalse(step.title.isEmpty, "\(lesson.name) step \(step.id)")
                XCTAssertFalse(step.instruction.isEmpty, "\(lesson.name) step \(step.id)")
            }
        }
    }

    func testEveryAdvancedPoseHasFinitePaperAboveTheTable() {
        for lesson in lessons {
            let original = lesson.frame(0, 0).faces.flatMap(\.vertices).map(\.source)
            let low = original.reduce(SIMD2<Float>(repeating: .greatestFiniteMagnitude), simd_min)
            let high = original.reduce(SIMD2<Float>(repeating: -.greatestFiniteMagnitude), simd_max)
            for step in 0..<lesson.count {
                for sample in 0...16 {
                    let frame = lesson.frame(step, Float(sample) / 16)
                    let context = "\(lesson.name), step \(step), sample \(sample)"
                    XCTAssertFalse(frame.faces.isEmpty, context)
                    XCTAssertTrue(frame.area.isFinite, context)
                    XCTAssertGreaterThan(frame.area, 0.0000001, context)
                    XCTAssertTrue(frame.tableLift.isFinite, context)
                    for face in frame.faces {
                        XCTAssertGreaterThanOrEqual(face.vertices.count, 3, context)
                        for vertex in face.vertices {
                            assertFinite(vertex.position, context)
                            assertFinite(vertex.separation, context)
                            XCTAssertTrue(vertex.source.x.isFinite && vertex.source.y.isFinite, context)
                            for axis in 0..<2 {
                                XCTAssertGreaterThanOrEqual(vertex.source[axis], low[axis] - 0.000003, context)
                                XCTAssertLessThanOrEqual(vertex.source[axis], high[axis] + 0.000003, context)
                            }
                            XCTAssertGreaterThanOrEqual(vertex.position.y, -0.00001, context)
                            XCTAssertGreaterThanOrEqual((vertex.position + vertex.separation).y,
                                                        -0.00001, context)
                        }
                    }
                    for path in frame.actionPaths {
                        for point in path { assertFinite(point, context) }
                    }
                    if let crease = frame.crease {
                        assertFinite(crease.start, context)
                        assertFinite(crease.end, context)
                    }
                }
            }
        }
    }

    func testStepTransitionsKeepTheSameMaterialInPlace() throws {
        for lesson in lessons {
            let originalFrame = lesson.frame(0, 0)
            let original = originalFrame.faces.flatMap(\.vertices).map(\.source)
            let low = original.reduce(SIMD2<Float>(repeating: .greatestFiniteMagnitude), simd_min)
            let high = original.reduce(SIMD2<Float>(repeating: -.greatestFiniteMagnitude), simd_max)
            for step in 0..<(lesson.count - 1) {
                let before = lesson.frame(step, 1)
                let after = lesson.frame(step + 1, 0)
                var coveredSamples = 0
                // Source-space samples survive changes in mesh tessellation.
                // Compare rendered positions including layer offsets: some
                // deforming stages bake those offsets into their vertex data.
                for x in 0..<15 {
                    for y in 0..<9 {
                        let uv = SIMD2<Float>((Float(x) + 0.31) / 15, (Float(y) + 0.43) / 9)
                        let source = low + (high - low) * uv
                        // A diamond-shaped source domain does not fill its box.
                        // Exclude only samples absent from the ORIGINAL sheet;
                        // material that disappears in a later state must fail.
                        guard position(of: source, in: originalFrame) != nil else { continue }
                        coveredSamples += 1
                        let context = "\(lesson.name), boundary \(step) -> \(step + 1), material \(source)"
                        let a = try XCTUnwrap(position(of: source, in: before), "Before: \(context)")
                        let b = try XCTUnwrap(position(of: source, in: after), "After: \(context)")
                        XCTAssertLessThanOrEqual(simd_distance(a, b), 0.00005, context)
                    }
                }
                XCTAssertGreaterThan(coveredSamples, 30, "Insufficient source coverage for \(lesson.name)")
            }
        }
    }

    func testAdvancedProgressClampsAndRejectsNonFiniteValues() {
        for lesson in lessons {
            for step in [0, lesson.count / 2, lesson.count - 1] {
                let start = lesson.frame(step, 0)
                for progress: Float in [-100, .nan, .infinity, -.infinity] {
                    assertSameRenderVertices(start, lesson.frame(step, progress), lesson.name)
                }
                assertSameRenderVertices(lesson.frame(step, 1), lesson.frame(step, 100), lesson.name)
            }
            assertSameRenderVertices(lesson.frame(0, 0.4), lesson.frame(-100, 0.4), lesson.name)
            assertSameRenderVertices(lesson.frame(lesson.count - 1, 0.4), lesson.frame(100, 0.4), lesson.name)
        }
    }

    func testFinishedCraneIsOpenAndThreeDimensional() {
        let final = CraneGeometry.frame(step: CraneGeometry.stepCount - 1, progress: 1)
        let bounds = renderedBounds(final)
        let span = bounds.high - bounds.low
        // These broad outcome bounds catch an accidentally closed or planar
        // final pose. Identifying wings, beak and tail is also visually reviewed.
        XCTAssertGreaterThan(span.y, 0.015, "The completed crane must rise above its paper-thin starting state")
        XCTAssertGreaterThan(span.x, 0.020, "The open crane must have a visible span")
        XCTAssertGreaterThan(span.z, 0.020, "The neck/tail direction must retain visible length")
    }

    func testFinishedStarHasFivePointsAndPuffedFaces() {
        let wrapped = StarGeometry.frame(step: 8, progress: 1)
        let final = StarGeometry.frame(step: StarGeometry.lastStep, progress: 1)
        let wrappedBounds = renderedBounds(wrapped), finalBounds = renderedBounds(final)
        let flatHeight = wrappedBounds.high.y - wrappedBounds.low.y
        let finalHeight = finalBounds.high.y - finalBounds.low.y
        XCTAssertGreaterThan(finalHeight, 0.005, "A lucky star should have visible thickness")
        XCTAssertGreaterThan(finalHeight, flatHeight * 1.5, "Pressing the edges should puff the faces")

        let profile = (0..<360).map { index in
            radialExtent(final, angle: Float(index) * .pi / 180)
        }
        let maximumVertexRadius = final.faces.flatMap(\.vertices).map {
            simd_length(SIMD2<Float>($0.position.x + $0.separation.x, $0.position.z + $0.separation.z))
        }.max() ?? 0
        XCTAssertLessThanOrEqual(profile.max() ?? 0, maximumVertexRadius + 0.000001,
                                 "A ray intersection cannot lie outside all mesh vertices")
        let candidatePeaks = profile.indices.filter { index in
            let value = profile[index]
            let left = profile[(index + 348) % 360]
            let right = profile[(index + 12) % 360]
            return value >= profile[(index + 359) % 360]
                && value >= profile[(index + 1) % 360]
                && value > min(left, right) + 0.00008
        }.sorted { profile[$0] > profile[$1] }
        var peaks = [Int]()
        for candidate in candidatePeaks {
            let separate = peaks.allSatisfy { existing in
                let difference = abs(candidate - existing)
                return min(difference, 360 - difference) >= 35
            }
            if separate { peaks.append(candidate) }
        }
        XCTAssertEqual(peaks.count, 5, "Projected star silhouette peaks: \(peaks.sorted())")

        // A plain pentagon also has five corners. Check that each side is
        // actually indented relative to the pre-pinch wrapped pentagon.
        for side in 0..<5 {
            let angle = -.pi / 2 + (Float(side) + 0.5) * 2 * .pi / 5
            let oldRadius = radialExtent(wrapped, angle: angle)
            let newRadius = radialExtent(final, angle: angle)
            XCTAssertGreaterThan(oldRadius, 0.005)
            XCTAssertLessThan(newRadius, oldRadius * 0.90, "Side \(side) is still pentagonal")
        }
    }

    func testStarPinchShadingStaysOnTheMaterialSide() throws {
        XCTAssertNil(StarGeometry.smoothPinchNormals(for: StarGeometry.frame(step: 8, progress: 1), step: 8, progress: 1),
                     "Rigid wrap creases retain their original shading")
        XCTAssertNil(StarGeometry.smoothPinchNormals(for: StarGeometry.frame(step: 9, progress: 0), step: 9, progress: 0),
                     "Smooth shading must blend in continuously with inflation")
        let frame = StarGeometry.frame(step: 13, progress: 1)
        let normals = try XCTUnwrap(StarGeometry.smoothPinchNormals(for: frame, step: 13, progress: 1))
        XCTAssertEqual(normals.count, frame.faces.count)
        var changed = 0
        for (index, face) in frame.faces.enumerated() {
            XCTAssertEqual(normals[index].count, face.vertices.count)
            for normal in normals[index] {
                assertFinite(normal, "Smoothed star normal")
                XCTAssertEqual(simd_length(normal), 1, accuracy: 0.00001)
                XCTAssertGreaterThan(simd_dot(normal, face.normal), 0.35,
                                     "Smoothing must not cross a fold to the opposite material side")
                if simd_distance(normal, face.normal) > 0.01 { changed += 1 }
            }
        }
        XCTAssertGreaterThan(changed, 100, "The authored tessellation should actually receive smooth shading")
    }

    private func position(of source: SIMD2<Float>, in frame: PaperFrame) -> SIMD3<Float>? {
        for face in frame.faces where face.vertices.count >= 3 {
            let a = face.vertices[0]
            for i in 1..<(face.vertices.count - 1) {
                let b = face.vertices[i], c = face.vertices[i + 1]
                let ab = b.source - a.source, ac = c.source - a.source, ap = source - a.source
                let determinant = cross(ab, ac)
                guard abs(determinant) > 1e-12 else { continue }
                let u = cross(ap, ac) / determinant, v = cross(ab, ap) / determinant
                if u >= -0.00001 && v >= -0.00001 && u + v <= 1.00001 {
                    let pa = a.position + a.separation, pb = b.position + b.separation, pc = c.position + c.separation
                    return pa + (pb - pa) * u + (pc - pa) * v
                }
            }
        }
        return nil
    }

    private func radialExtent(_ frame: PaperFrame, angle: Float) -> Float {
        // Double arithmetic avoids cancellation where a ray nearly follows a
        // tiny clipped material edge. Float produced intersections outside the
        // entire mesh bounds; the pass criteria and tolerances are unchanged.
        func cross(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { a.x * b.y - a.y * b.x }
        let direction = SIMD2<Double>(cos(Double(angle)), sin(Double(angle)))
        var extent: Double = 0
        for face in frame.faces {
            for index in face.vertices.indices {
                let va = face.vertices[index], vb = face.vertices[(index + 1) % face.vertices.count]
                let pa = va.position + va.separation, pb = vb.position + vb.separation
                let a = SIMD2<Double>(Double(pa.x), Double(pa.z)), b = SIMD2<Double>(Double(pb.x), Double(pb.z))
                let edge = b - a, determinant = cross(direction, edge)
                guard abs(determinant) > 1e-10 else { continue }
                let distance = cross(a, edge) / determinant
                let fraction = cross(a, direction) / determinant
                if distance >= 0 && fraction >= -0.00001 && fraction <= 1.00001 {
                    extent = max(extent, distance)
                }
            }
        }
        return Float(extent)
    }

    private func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }

    private func renderedBounds(_ frame: PaperFrame) -> (low: SIMD3<Float>, high: SIMD3<Float>) {
        let positions = frame.faces.flatMap(\.vertices).map { $0.position + $0.separation }
        return (positions.reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude), simd_min),
                positions.reduce(SIMD3<Float>(repeating: -.greatestFiniteMagnitude), simd_max))
    }

    private func assertFinite(_ vector: SIMD3<Float>, _ context: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(vector.x.isFinite && vector.y.isFinite && vector.z.isFinite,
                      context, file: file, line: line)
    }

    private func assertSameRenderVertices(_ a: PaperFrame, _ b: PaperFrame, _ context: String,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let av = a.faces.flatMap(\.vertices), bv = b.faces.flatMap(\.vertices)
        XCTAssertEqual(av.count, bv.count, context, file: file, line: line)
        for (first, second) in zip(av, bv) {
            XCTAssertLessThanOrEqual(simd_distance(first.position + first.separation,
                                                  second.position + second.separation),
                                     0.000003, context, file: file, line: line)
        }
    }
}
