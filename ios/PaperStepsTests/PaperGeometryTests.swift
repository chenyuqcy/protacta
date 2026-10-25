import XCTest
import simd
@testable import Foliafold

final class PaperGeometryTests: XCTestCase {
    private let distanceTolerance: Float = 0.000003
    private let areaTolerance: Float = 0.000002
    private var expectedArea: Float { PaperGeometry.width * PaperGeometry.height }

    // An animation can look plausible while losing paper at a clipping boundary.
    // Check intermediate poses, not just the eleven completed illustrations.
    func testEveryFoldConservesTheSameSheet() {
        for step in 0..<PaperGeometry.stepCount {
            for sample in 0...24 {
                let progress = Float(sample) / 24
                let frame = PaperGeometry.frame(step: step, progress: progress)
                let context = "step=\(step), progress=\(progress)"
                XCTAssertFalse(frame.faces.isEmpty, context)
                XCTAssertEqual(frame.area, expectedArea, accuracy: areaTolerance, context)
                let materialArea = frame.faces.reduce(Float(0)) { $0 + sourceArea($1) }
                XCTAssertEqual(materialArea, expectedArea, accuracy: areaTolerance, context)

                for face in frame.faces {
                    XCTAssertGreaterThanOrEqual(face.vertices.count, 3, context)
                    // Every pair, rather than only perimeter edges, also detects
                    // a face shearing while keeping its outer edge lengths.
                    for i in face.vertices.indices {
                        for j in face.vertices.indices where j > i {
                            let a = face.vertices[i], b = face.vertices[j]
                            XCTAssertEqual(simd_distance(a.position, b.position),
                                           simd_distance(a.source, b.source),
                                           accuracy: distanceTolerance, context)
                        }
                    }
                }
            }
        }
    }

    func testEveryAnimationPoseIsFiniteAndClearsTheTable() {
        for step in 0..<PaperGeometry.stepCount {
            for sample in 0...24 {
                let frame = PaperGeometry.frame(step: step, progress: Float(sample) / 24)
                let context = "step=\(step), sample=\(sample)"
                XCTAssertTrue(frame.tableLift.isFinite, context)
                XCTAssertGreaterThanOrEqual(frame.tableLift, 0, context)
                for face in frame.faces {
                    assertFinite(face.normal, context)
                    for vertex in face.vertices {
                        assertFinite(vertex.position, context)
                        assertFinite(vertex.separation, context)
                        XCTAssertTrue(vertex.source.x.isFinite && vertex.source.y.isFinite, context)
                        XCTAssertLessThanOrEqual(abs(vertex.source.x),
                                                 PaperGeometry.width / 2 + distanceTolerance, context)
                        XCTAssertLessThanOrEqual(abs(vertex.source.y),
                                                 PaperGeometry.height / 2 + distanceTolerance, context)
                        XCTAssertGreaterThanOrEqual(vertex.position.y, -distanceTolerance, context)
                        XCTAssertGreaterThanOrEqual((vertex.position + vertex.separation).y,
                                                    -distanceTolerance, context)
                    }
                }
                if let crease = frame.crease {
                    assertFinite(crease.start, context)
                    assertFinite(crease.end, context)
                    XCTAssertGreaterThan(simd_distance(crease.start, crease.end), 0, context)
                }
                for path in frame.actionPaths {
                    for point in path { assertFinite(point, context) }
                }
            }
        }
    }

    func testAdjacentStepsDoNotReplaceOrJumpThePaper() throws {
        // A crease may split a polygon before any visible movement. Query the
        // same material locations barycentrically so topology need not match.
        for step in 0..<PaperGeometry.lastStep {
            let before = PaperGeometry.frame(step: step, progress: 1)
            let after = PaperGeometry.frame(step: step + 1, progress: 0)
            for xIndex in 0..<15 {
                for zIndex in 0..<21 {
                    let source = SIMD2<Float>(
                        (Float(xIndex) + 0.37) / 15 * PaperGeometry.width - PaperGeometry.width / 2,
                        (Float(zIndex) + 0.29) / 21 * PaperGeometry.height - PaperGeometry.height / 2
                    )
                    let a = try XCTUnwrap(materialPosition(source, in: before),
                                          "Material missing before transition \(step) at \(source)")
                    let b = try XCTUnwrap(materialPosition(source, in: after),
                                          "Material missing after transition \(step) at \(source)")
                    XCTAssertLessThanOrEqual(simd_distance(a, b), distanceTolerance,
                                             "Transition \(step) -> \(step + 1), material \(source)")
                }
            }
        }
    }

    func testOutOfRangeAndNonFiniteInputsAreSafe() {
        for step in 0..<PaperGeometry.stepCount {
            let start = PaperGeometry.frame(step: step, progress: 0)
            let finish = PaperGeometry.frame(step: step, progress: 1)
            assertSamePositions(start, PaperGeometry.frame(step: step, progress: -10))
            assertSamePositions(start, PaperGeometry.frame(step: step, progress: .nan))
            assertSamePositions(start, PaperGeometry.frame(step: step, progress: .infinity))
            assertSamePositions(start, PaperGeometry.frame(step: step, progress: -.infinity))
            assertSamePositions(finish, PaperGeometry.frame(step: step, progress: 5))
        }
        assertSamePositions(PaperGeometry.frame(step: 0, progress: 0.4),
                            PaperGeometry.frame(step: -100, progress: 0.4))
        assertSamePositions(PaperGeometry.frame(step: PaperGeometry.lastStep, progress: 0.4),
                            PaperGeometry.frame(step: 100, progress: 0.4))
    }

    func testBlankPreparationUnfoldingAndNoseFoldsMatchTheLesson() throws {
        let blank = PaperGeometry.frame(step: 0, progress: 0)
        let unfolded = PaperGeometry.frame(step: 2, progress: 1)
        let sources: [SIMD2<Float>] = [
            [-PaperGeometry.width / 2, -PaperGeometry.height / 2],
            [PaperGeometry.width / 2, -PaperGeometry.height / 2],
            [-PaperGeometry.width / 2, PaperGeometry.height / 2],
            [PaperGeometry.width / 2, PaperGeometry.height / 2], .zero
        ]
        for source in sources {
            let a = try XCTUnwrap(materialPosition(source, in: blank))
            let b = try XCTUnwrap(materialPosition(source, in: unfolded))
            XCTAssertEqual(a.x, source.x, accuracy: distanceTolerance)
            XCTAssertEqual(a.z, source.y, accuracy: distanceTolerance)
            XCTAssertLessThanOrEqual(simd_distance(a, b), distanceTolerance)
        }

        // The instructions say each original top edge meets the center line.
        // Check interior edge samples instead of the hinge point at the nose.
        for (step, side): (Int, Float) in [(3, -1), (4, 1)] {
            let frame = PaperGeometry.frame(step: step, progress: 1)
            for fraction: Float in [0.2, 0.5, 0.9] {
                let source = SIMD2<Float>(side * PaperGeometry.width / 2 * fraction,
                                          -PaperGeometry.height / 2)
                let position = try XCTUnwrap(materialPosition(source, in: frame))
                XCTAssertEqual(position.x, 0, accuracy: distanceTolerance,
                               "Corner fold \(step) did not reach the center line")
                XCTAssertEqual(position.z, -PaperGeometry.height / 2 + abs(source.x),
                               accuracy: distanceTolerance)
            }
        }
    }

    private func sourceArea(_ face: PaperFace) -> Float {
        guard face.vertices.count >= 3 else { return 0 }
        let a = face.vertices[0].source
        return (1..<(face.vertices.count - 1)).reduce(0) { total, i in
            let b = face.vertices[i].source - a
            let c = face.vertices[i + 1].source - a
            return total + abs(b.x * c.y - b.y * c.x) / 2
        }
    }

    private func materialPosition(_ source: SIMD2<Float>, in frame: PaperFrame) -> SIMD3<Float>? {
        for face in frame.faces where face.vertices.count >= 3 {
            let a = face.vertices[0]
            for i in 1..<(face.vertices.count - 1) {
                let b = face.vertices[i], c = face.vertices[i + 1]
                let ab = b.source - a.source, ac = c.source - a.source, ap = source - a.source
                let determinant = ab.x * ac.y - ab.y * ac.x
                guard abs(determinant) > 1e-12 else { continue }
                let u = (ap.x * ac.y - ap.y * ac.x) / determinant
                let v = (ab.x * ap.y - ab.y * ap.x) / determinant
                if u >= -0.00001 && v >= -0.00001 && u + v <= 1.00001 {
                    return a.position + (b.position - a.position) * u + (c.position - a.position) * v
                }
            }
        }
        return nil
    }

    private func assertFinite(_ value: SIMD3<Float>, _ context: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(value.x.isFinite && value.y.isFinite && value.z.isFinite,
                      "Non-finite position: \(context)", file: file, line: line)
    }

    private func assertSamePositions(_ a: PaperFrame, _ b: PaperFrame,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let verticesA = a.faces.flatMap(\.vertices), verticesB = b.faces.flatMap(\.vertices)
        XCTAssertEqual(verticesA.count, verticesB.count, file: file, line: line)
        for (first, second) in zip(verticesA, verticesB) {
            XCTAssertLessThanOrEqual(simd_distance(first.position, second.position),
                                     distanceTolerance, file: file, line: line)
        }
    }
}
