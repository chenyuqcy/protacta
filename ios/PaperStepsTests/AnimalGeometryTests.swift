import XCTest
import simd
@testable import Foliafold

final class AnimalGeometryTests: XCTestCase {
    private let expectedArea = AnimalGeometry.sideLength * AnimalGeometry.sideLength

    func testEveryAnimalHasMatchingEnglishTeachingSteps() {
        for kind in AnimalKind.allCases {
            let steps = AnimalLessonContent.steps(for: kind)
            XCTAssertEqual(steps.count, AnimalGeometry.stepCount(kind: kind), kind.rawValue)
            XCTAssertEqual(steps.map(\.id), Array(steps.indices))
            XCTAssertTrue(AnimalLessonContent.sourceURL(for: kind).absoluteString.hasPrefix("https://"))
            for step in steps {
                XCTAssertFalse(step.title.isEmpty)
                XCTAssertFalse(step.instruction.isEmpty)
                XCTAssertFalse(step.cue.isEmpty)
                XCTAssertFalse(step.explanation.isEmpty)
                let content = step.title + step.instruction + step.cue + step.explanation
                XCTAssertNil(content.range(of: "[\\p{Han}]", options: .regularExpression))
            }
        }
    }

    func testDenseAnimalFoldsKeepTheUncutSquareRigidAndConnected() {
        for kind in AnimalKind.allCases {
            var maxAreaError: Float = 0
            var maxLengthError: Float = 0
            var maxSeam: Float = 0
            var minimumY: Float = .greatestFiniteMagnitude
            for step in 0..<AnimalGeometry.stepCount(kind: kind) {
                for sample in 0...40 {
                    let frame = AnimalGeometry.frame(kind: kind, step: step, progress: Float(sample) / 40)
                    maxAreaError = max(maxAreaError, abs(frame.area - expectedArea))
                    let vertices = frame.faces.flatMap(\.vertices)
                    for face in frame.faces {
                        for a in face.vertices {
                            XCTAssertTrue(a.position.x.isFinite && a.position.y.isFinite && a.position.z.isFinite)
                            minimumY = min(minimumY, a.position.y)
                            for b in face.vertices {
                                maxLengthError = max(maxLengthError, abs(simd_distance(a.position, b.position) - simd_distance(a.source, b.source)))
                            }
                            for b in vertices where simd_distance(a.source, b.source) < 0.0000005 {
                                maxSeam = max(maxSeam, simd_distance(a.position, b.position))
                            }
                        }
                    }
                }
            }
            XCTAssertLessThan(maxAreaError, 0.0000004, kind.rawValue)
            XCTAssertLessThan(maxLengthError, 0.00002, kind.rawValue)
            XCTAssertLessThan(maxSeam, 0.00002, kind.rawValue)
            XCTAssertGreaterThanOrEqual(minimumY, 0, kind.rawValue)
        }
    }

    func testSuccessiveStepsContinueFromTheSameMaterialPose() {
        for kind in AnimalKind.allCases {
            for step in 1..<AnimalGeometry.stepCount(kind: kind) {
                let before = AnimalGeometry.frame(kind: kind, step: step - 1, progress: 1)
                let after = AnimalGeometry.frame(kind: kind, step: step, progress: 0)
                for vertex in before.faces.flatMap(\.vertices) {
                    guard let position = materialPosition(vertex.source, in: after) else {
                        XCTFail("Lost material at \(kind.rawValue), step \(step), \(vertex.source)")
                        continue
                    }
                    XCTAssertLessThan(simd_distance(vertex.position, position), 0.0004,
                                      "Pose jump at \(kind.rawValue), step \(step)")
                }
            }
        }
    }

    func testClampsDoNotProduceInvalidPaper() {
        for kind in AnimalKind.allCases {
            for (step, progress): (Int, Float) in [(-100, -.infinity), (999, .nan), (1, -2), (3, 5)] {
                let frame = AnimalGeometry.frame(kind: kind, step: step, progress: progress)
                XCTAssertFalse(frame.faces.isEmpty)
                XCTAssertEqual(frame.area, expectedArea, accuracy: 0.0000004)
                XCTAssertTrue(frame.bounds.minimum.x.isFinite)
            }
        }
    }

    func testButterflyFinishesWithRaisedWingsAndFourSeparateTips() {
        let frame = AnimalGeometry.frame(kind: .butterfly, step: AnimalGeometry.stepCount(kind: .butterfly) - 1, progress: 1)
        XCTAssertGreaterThan(frame.bounds.maximum.x - frame.bounds.minimum.x, 0.12)
        XCTAssertGreaterThan(frame.bounds.maximum.y - frame.bounds.minimum.y, 0.015)
        let lowerTips = frame.faces.flatMap(\.vertices).filter { $0.position.z > 0.067 }
        XCTAssertTrue(lowerTips.contains { $0.position.x < -0.004 })
        XCTAssertTrue(lowerTips.contains { $0.position.x > 0.004 })
    }

    func testFlatSeamMaskHandlesTjunctionsAndRetainsTheSourcePerimeter() {
        let h = AnimalGeometry.sideLength / 2
        let left = panel([[-h, h], [0, h], [0, -h], [-h, -h]])
        let upper = panel([[0, h], [h, h], [h, 0], [0, 0]])
        let lower = panel([[0, 0], [h, 0], [h, -h], [0, -h]])
        let masked = AnimalGeometry.removingFlatSeamOutlines(from: [left, upper, lower])
        XCTAssertEqual(masked[0].outlinedEdges, [true, false, true, true])
        XCTAssertEqual(masked[1].outlinedEdges, [true, true, false, false])
        XCTAssertEqual(masked[2].outlinedEdges, [false, true, true, false])
        let partial = AnimalGeometry.removingFlatSeamOutlines(from: [left, upper])
        XCTAssertEqual(partial[0].outlinedEdges?[1], true, "A partly shared edge must not disappear in full")
    }

    func testFlatSeamMaskKeepsFoldsMovingBoundariesAndUnrelatedOverlaps() {
        let h = AnimalGeometry.sideLength / 2
        let left = panel([[-h, h], [0, h], [0, -h], [-h, -h]])
        let right = panel([[0, h], [h, h], [h, -h], [0, -h]])
        for angle: Float in [.pi / 2, .pi] {
            var folded = right
            folded.vertices = right.vertices.map { v in
                var result = v
                result.position = [v.position.x * cos(angle), v.position.x * sin(angle), v.position.z]
                return result
            }
            let masked = AnimalGeometry.removingFlatSeamOutlines(from: [left, folded])
            XCTAssertEqual(masked[0].outlinedEdges?[1], true)
            XCTAssertEqual(masked[1].outlinedEdges?[3], true, "A real folded hinge must remain visible")
        }
        var moving = right
        moving.isMoving = true
        XCTAssertEqual(AnimalGeometry.removingFlatSeamOutlines(from: [left, moving])[0].outlinedEdges?[1], true)
        var unrelated = right
        for i in unrelated.vertices.indices { unrelated.vertices[i].source.x += 0.02 }
        XCTAssertEqual(AnimalGeometry.removingFlatSeamOutlines(from: [left, unrelated])[0].outlinedEdges?[1], true,
                       "Coincident 3D edges alone do not establish material adjacency")
        var explicit = left
        explicit.outlinedEdges = [true, true, true, true]
        XCTAssertEqual(AnimalGeometry.removingFlatSeamOutlines(from: [explicit, right])[0].outlinedEdges, explicit.outlinedEdges)
    }

    func testRabbitFinalMasksFlatInternalSeamsWithoutChangingPaper() {
        let frame = AnimalGeometry.frame(kind: .rabbit, step: 9, progress: 1)
        XCTAssertTrue(frame.faces.contains { $0.outlinedEdges?.contains(false) == true })
        XCTAssertEqual(frame.area, expectedArea, accuracy: 0.0000004)
        for face in frame.faces { XCTAssertEqual(face.outlinedEdges?.count, face.vertices.count) }
    }

    private func panel(_ sources: [SIMD2<Float>]) -> PaperFace {
        PaperFace(vertices: sources.map { PaperVertex(position: [$0.x, 0, $0.y], source: $0) }, originalSide: 0)
    }

    private func materialPosition(_ source: SIMD2<Float>, in frame: PaperFrame) -> SIMD3<Float>? {
        func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }
        for face in frame.faces where face.vertices.count >= 3 {
            let a = face.vertices[0]
            for index in 1..<(face.vertices.count - 1) {
                let b = face.vertices[index], c = face.vertices[index + 1]
                let u = b.source - a.source, v = c.source - a.source, p = source - a.source
                let d = cross(u, v)
                guard abs(d) > 1e-12 else { continue }
                let x = cross(p, v) / d, y = cross(u, p) / d
                if x >= -0.0001 && y >= -0.0001 && x + y <= 1.0001 {
                    return a.position + x * (b.position - a.position) + y * (c.position - a.position)
                }
            }
        }
        return nil
    }
}
