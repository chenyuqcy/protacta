import CoreGraphics
import simd
import XCTest
@testable import Protacta

/// Ideal authored-geometry checks, not optical or real-paper acceptance. A code
/// can remain inside the silhouette while another material layer covers it.
final class DartPracticePaperVisibilityTests: XCTestCase {
    func testObsoleteFirstRowIsCoveredByTheCorrectNarrowingFolds() throws {
        for (state, center): (Int, CGPoint) in [
            (5, CGPoint(x: 0.16, y: 0.72)),
            (6, CGPoint(x: 0.84, y: 0.72))
        ] {
            let frame = PaperGeometry.frame(step: state, progress: 1)
            let patch = try materialPatch(center: center, sideMM: 14, in: frame)
            let overlap = try largestHigherLayerOverlap(patch, in: frame)
            XCTAssertGreaterThan(overlap / area(patch.outline), 0.80,
                                 "The PTC1 matrix is mostly hidden although its source material stays stationary")
        }
    }

    func testCurrentMatricesAndTheirEntireQuietZonesStayStationaryAndTopLayerVisible() throws {
        let layout = try XCTUnwrap(DartPracticePaperLayout.bundled)
        XCTAssertEqual(layout.layoutID, "protacta-dart-a4-ptc2")
        XCTAssertEqual(layout.layoutRevision, 2)
        for state in [0, 2, 3, 4, 5, 6] {
            let frame = PaperGeometry.frame(step: state, progress: 1)
            for marker in layout.markers {
                let center = CGPoint(x: marker.center.x, y: marker.center.y)
                // Test both the ink matrix and full surrounding white quiet
                // zone as continuous polygons, not just sampled corner points.
                for sideMM in [layout.codeSideMM, layout.codeSideMM + 2 * layout.quietZoneMM] {
                    let context = "state=\(state), marker=\(marker.payload), side=\(sideMM)mm"
                    let patch = try materialPatch(center: center, sideMM: sideMM, in: frame)
                    let original = sourceRectangle(center: center, sideMM: sideMM)
                    for (actual, source) in zip(patch.outline, original) {
                        XCTAssertEqual(actual.x, source.x, accuracy: 0.000003, context)
                        XCTAssertEqual(actual.y, source.y, accuracy: 0.000003, context)
                    }
                    XCTAssertEqual(try largestHigherLayerOverlap(patch, in: frame), 0,
                                   accuracy: 1e-10, context)
                }
            }
        }
    }

    private struct MaterialPatch {
        let outline: [CGPoint] // Current physical x/z plane in metres.
        let height: Float
        let sourceFace: Int
    }

    private func sourceRectangle(center: CGPoint, sideMM: Double) -> [CGPoint] {
        let x = (Double(center.x) - 0.5) * Double(PaperGeometry.width)
        let z = (Double(center.y) - 0.5) * Double(PaperGeometry.height)
        let half = sideMM / 2000
        return [CGPoint(x: x - half, y: z - half), CGPoint(x: x + half, y: z - half),
                CGPoint(x: x + half, y: z + half), CGPoint(x: x - half, y: z + half)]
    }

    /// Material correspondence uses each vertex's original `source`, then
    /// barycentric interpolation into its current position plus layer offset.
    /// All four corners in one convex source face proves that the whole box
    /// stays in that material face and does not cross a moving hinge.
    private func materialPatch(center: CGPoint, sideMM: Double, in frame: PaperFrame,
                               file: StaticString = #filePath, line: UInt = #line) throws -> MaterialPatch {
        let source = sourceRectangle(center: center, sideMM: sideMM)
        for (index, face) in frame.faces.enumerated() {
            let current = source.compactMap { materialPosition($0, in: face) }
            guard current.count == 4 else { continue }
            let low = try XCTUnwrap(current.map(\.y).min(), file: file, line: line)
            let high = try XCTUnwrap(current.map(\.y).max(), file: file, line: line)
            XCTAssertEqual(high, low, accuracy: 0.000003,
                           "A resting code footprint must be planar", file: file, line: line)
            return MaterialPatch(outline: current.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.z)) },
                                 height: (low + high) / 2, sourceFace: index)
        }
        XCTFail("The whole source footprint must remain in one material face", file: file, line: line)
        throw NSError(domain: "DartPracticePaperVisibilityTests", code: 1)
    }

    private func materialPosition(_ point: CGPoint, in face: PaperFace) -> SIMD3<Float>? {
        guard face.vertices.count >= 3 else { return nil }
        let source = SIMD2<Float>(Float(point.x), Float(point.y))
        let a = face.vertices[0]
        for index in 1..<(face.vertices.count - 1) {
            let b = face.vertices[index], c = face.vertices[index + 1]
            let ab = b.source - a.source, ac = c.source - a.source, ap = source - a.source
            let determinant = ab.x * ac.y - ab.y * ac.x
            guard abs(determinant) > 1e-12 else { continue }
            let u = (ap.x * ac.y - ap.y * ac.x) / determinant
            let v = (ab.x * ap.y - ab.y * ap.x) / determinant
            guard u >= -1e-6, v >= -1e-6, u + v <= 1 + 1e-6 else { continue }
            let start = a.position + a.separation
            return start + ((b.position + b.separation) - start) * u +
                ((c.position + c.separation) - start) * v
        }
        return nil
    }

    private func largestHigherLayerOverlap(_ patch: MaterialPatch, in frame: PaperFrame,
                                            file: StaticString = #filePath, line: UInt = #line) throws -> Double {
        var largest = 0.0
        for (index, face) in frame.faces.enumerated() where index != patch.sourceFace {
            let points = face.vertices.map { $0.position + $0.separation }
            let low = try XCTUnwrap(points.map(\.y).min(), file: file, line: line)
            let high = try XCTUnwrap(points.map(\.y).max(), file: file, line: line)
            XCTAssertEqual(high, low, accuracy: 0.000003,
                           "Visibility test requires a resting horizontal face", file: file, line: line)
            guard low > patch.height + 0.000003 else { continue }
            let footprint = points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.z)) }
            largest = max(largest, area(intersection(patch.outline, with: footprint)))
        }
        return largest
    }

    /// Sutherland-Hodgman clips the entire code polygon against a convex face.
    /// This catches a covering flap crossing the middle of an otherwise clear
    /// QR box; testing only its four corners would miss that obstruction.
    private func intersection(_ polygon: [CGPoint], with clip: [CGPoint]) -> [CGPoint] {
        guard clip.count >= 3 else { return [] }
        let winding = signedArea(clip) >= 0 ? 1.0 : -1.0
        var result = polygon
        for index in clip.indices {
            guard !result.isEmpty else { return [] }
            let a = clip[index], b = clip[(index + 1) % clip.count]
            let input = result
            result = []
            for position in input.indices {
                let p = input[position], q = input[(position + 1) % input.count]
                let dp = winding * cross(a, b, p), dq = winding * cross(a, b, q)
                let pInside = dp >= -1e-12, qInside = dq >= -1e-12
                if pInside { result.append(p) }
                if pInside != qInside, abs(dp - dq) > 1e-15 {
                    let t = dp / (dp - dq)
                    result.append(CGPoint(x: p.x + CGFloat(t) * (q.x - p.x),
                                          y: p.y + CGFloat(t) * (q.y - p.y)))
                }
            }
        }
        return result
    }

    private func cross(_ a: CGPoint, _ b: CGPoint, _ p: CGPoint) -> Double {
        Double((b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x))
    }

    private func signedArea(_ polygon: [CGPoint]) -> Double {
        guard polygon.count >= 3 else { return 0 }
        return polygon.indices.reduce(0) { total, index in
            let a = polygon[index], b = polygon[(index + 1) % polygon.count]
            return total + Double(a.x * b.y - b.x * a.y) / 2
        }
    }

    private func area(_ polygon: [CGPoint]) -> Double { abs(signedArea(polygon)) }
}
