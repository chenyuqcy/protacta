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
                            XCTAssertGreaterThan(simd_length_squared(simd_cross(b - a, c - a)), 1e-17)
                        }
                    }
                }
            }
        }
    }

    func testCompletedLinensAndShirtHaveTheExpectedFoldedFootprints() {
        let towel = bounds(frame(.towel, 2, 1))
        XCTAssertEqual(towel.maximum.x - towel.minimum.x, 0.20, accuracy: 0.00001)
        XCTAssertEqual(towel.maximum.z - towel.minimum.z, 0.45, accuracy: 0.00001)
        let sheet = bounds(frame(.flatBedsheet, 3, 1))
        XCTAssertEqual(sheet.maximum.x - sheet.minimum.x, 0.18, accuracy: 0.00001)
        XCTAssertEqual(sheet.maximum.z - sheet.minimum.z, 0.215, accuracy: 0.00001)
        let shirt = bounds(frame(.tShirt, 5, 1))
        XCTAssertEqual(shirt.maximum.x - shirt.minimum.x, 0.24, accuracy: 0.00001)
        XCTAssertEqual(shirt.maximum.z - shirt.minimum.z, 0.165, accuracy: 0.00001)
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
