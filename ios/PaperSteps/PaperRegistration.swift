import CoreGraphics
import Foundation

/// Converts raw Vision observations into the same normalized coordinate space
/// as the displayed AR camera feed. Vision's lower-left origin is flipped once;
/// the supplied ARFrame display transform handles rotation and aspect-fill.
enum PaperImageCoordinates {
    static func viewportQuadrilateral(visionCorners: [CGPoint],
                                      displayTransform: CGAffineTransform) -> PaperQuadrilateral? {
        guard visionCorners.count == 4,
              [displayTransform.a, displayTransform.b, displayTransform.c,
               displayTransform.d, displayTransform.tx, displayTransform.ty].allSatisfy(\.isFinite),
              visionCorners.allSatisfy({ point in
                  point.x.isFinite && point.y.isFinite
                      && (0...1).contains(point.x) && (0...1).contains(point.y)
              }) else { return nil }
        let displayed = visionCorners.map {
            CGPoint(x: $0.x, y: 1 - $0.y).applying(displayTransform)
        }
        // A rectangle may be wholly inside the sensor image but clipped by the
        // camera view's aspect-fill crop. Real-paper mode requires every corner
        // visible; do not normalize or clamp a partial sheet into the viewport.
        guard displayed.allSatisfy({ point in
            point.x.isFinite && point.y.isFinite
                && (0...1).contains(point.x) && (0...1).contains(point.y)
        }) else { return nil }
        return PaperQuadrilateral.ordered(displayed)
    }
}

/// Four corresponding paper corners in normalized viewport coordinates.
///
/// The labels identify corners of the tutorial's paper, rather than their
/// current screen positions. Once the user confirms direction, preserve that
/// identity with `rotated(by:)` instead of sorting each tracked frame again.
struct PaperQuadrilateral: Equatable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    static let unit = PaperQuadrilateral(topLeft: CGPoint(x: 0, y: 0),
                                         topRight: CGPoint(x: 1, y: 0),
                                         bottomRight: CGPoint(x: 1, y: 1),
                                         bottomLeft: CGPoint(x: 0, y: 1))

    var points: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    /// Rejects collapsed, concave, crossed or implausibly off-screen results.
    /// It deliberately does not impose a physical paper aspect ratio: camera
    /// perspective changes the apparent lengths of its edges.
    var isValid: Bool {
        let corners = points
        let allowed = -0.05...1.05
        guard corners.allSatisfy({ point in
            point.x.isFinite && point.y.isFinite
                && allowed.contains(Double(point.x)) && allowed.contains(Double(point.y))
        }) else { return false }

        // A paper occupying less than 0.25% of the viewport is not a useful
        // registration target. Tiny edges and nearly straight corners also
        // make the projective solve unreliable.
        guard abs(Self.signedArea(corners)) >= 0.0025 else { return false }
        var winding: Double = 0
        for index in corners.indices {
            let a = corners[index]
            let b = corners[(index + 1) % 4]
            let c = corners[(index + 2) % 4]
            let first = Self.vector(from: a, to: b)
            let second = Self.vector(from: b, to: c)
            let firstLength = hypot(first.x, first.y)
            let secondLength = hypot(second.x, second.y)
            guard firstLength >= 0.005, secondLength >= 0.005 else { return false }
            let cross = first.x * second.y - first.y * second.x
            guard abs(cross) > firstLength * secondLength * 0.0001 else { return false }
            if index == 0 { winding = cross }
            else if cross * winding <= 0 { return false }
        }
        // For four vertices, consistently nonzero turns imply a simple convex
        // cycle. A bow-tie cannot satisfy this condition.
        return true
    }

    /// Orders an unordered set clockwise in screen coordinates (positive y
    /// points down), beginning at the corner nearest the viewport's upper-left.
    /// This geometric convention cannot establish a blank sheet's semantic
    /// direction; that still needs a distinctive landmark or user confirmation.
    static func ordered(_ points: [CGPoint]) -> PaperQuadrilateral? {
        let allowed = -0.05...1.05
        guard points.count == 4,
              points.allSatisfy({ point in
                  point.x.isFinite && point.y.isFinite
                      && allowed.contains(Double(point.x)) && allowed.contains(Double(point.y))
              }) else { return nil }
        let center = CGPoint(x: points.reduce(0) { $0 + $1.x } / 4,
                             y: points.reduce(0) { $0 + $1.y } / 4)
        var cycle = points.sorted { first, second in
            let firstAngle = atan2(Double(first.y - center.y), Double(first.x - center.x))
            let secondAngle = atan2(Double(second.y - center.y), Double(second.x - center.x))
            if firstAngle != secondAngle { return firstAngle < secondAngle }
            if first.y != second.y { return first.y < second.y }
            return first.x < second.x
        }
        if signedArea(cycle) < 0 { cycle.reverse() }
        let start = cycle.indices.min { first, second in
            let a = cycle[first], b = cycle[second]
            let firstDistance = Double(a.x) * Double(a.x) + Double(a.y) * Double(a.y)
            let secondDistance = Double(b.x) * Double(b.x) + Double(b.y) * Double(b.y)
            if firstDistance != secondDistance { return firstDistance < secondDistance }
            if a.y != b.y { return a.y < b.y }
            return a.x < b.x
        }!
        cycle = (0..<4).map { cycle[($0 + start) % 4] }
        let result = PaperQuadrilateral(topLeft: cycle[0], topRight: cycle[1],
                                        bottomRight: cycle[2], bottomLeft: cycle[3])
        return result.isValid ? result : nil
    }

    /// Changes corner correspondence without moving, sorting or reflecting the
    /// observed quadrilateral. One turn produces [TR, BR, BL, TL].
    func rotated(by quarterTurns: Int) -> PaperQuadrilateral {
        let offset = ((quarterTurns % 4) + 4) % 4
        let cycle = points
        return PaperQuadrilateral(topLeft: cycle[offset], topRight: cycle[(offset + 1) % 4],
                                  bottomRight: cycle[(offset + 2) % 4], bottomLeft: cycle[(offset + 3) % 4])
    }

    private static func vector(from first: CGPoint, to second: CGPoint) -> (x: Double, y: Double) {
        (Double(second.x - first.x), Double(second.y - first.y))
    }

    private static func signedArea(_ corners: [CGPoint]) -> Double {
        corners.indices.reduce(0) { area, index in
            let a = corners[index], b = corners[(index + 1) % corners.count]
            return area + Double(a.x) * Double(b.y) - Double(b.x) * Double(a.y)
        } / 2
    }
}

/// A planar projective map from unit paper coordinates to the camera viewport.
/// It describes one visible flat paper surface, not arbitrary folded 3D paper.
struct PaperRegistration {
    // Row-major homography, with its last coefficient normalized to one.
    private let coefficients: [Double]

    init?(quadrilateral: PaperQuadrilateral) {
        guard quadrilateral.isValid else { return nil }
        var equations: [[Double]] = []
        for (source, target) in zip(PaperQuadrilateral.unit.points, quadrilateral.points) {
            let u = Double(source.x), v = Double(source.y)
            let x = Double(target.x), y = Double(target.y)
            equations.append([u, v, 1, 0, 0, 0, -x * u, -x * v, x])
            equations.append([0, 0, 0, u, v, 1, -y * u, -y * v, y])
        }
        guard let solution = Self.solve(equations) else { return nil }
        coefficients = solution + [1]

        // A convex paper must remain on one side of the projective horizon.
        // Check independent corner residuals as well as the linear solve.
        for (source, target) in zip(PaperQuadrilateral.unit.points, quadrilateral.points) {
            let denominator = coefficients[6] * Double(source.x)
                + coefficients[7] * Double(source.y) + 1
            guard denominator > 1e-8, let mapped = map(source),
                  hypot(Double(mapped.x - target.x), Double(mapped.y - target.y)) < 1e-7 else { return nil }
        }
    }

    func map(_ point: CGPoint) -> CGPoint? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        let u = Double(point.x), v = Double(point.y)
        let first = coefficients[6] * u, second = coefficients[7] * v
        let denominator = first + second + 1
        let scale = max(1, abs(first) + abs(second))
        guard denominator.isFinite, scale.isFinite, abs(denominator) > 1e-10 * scale else { return nil }
        let x = (coefficients[0] * u + coefficients[1] * v + coefficients[2]) / denominator
        let y = (coefficients[3] * u + coefficients[4] * v + coefficients[5]) / denominator
        guard x.isFinite, y.isFinite else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// Gauss-Jordan elimination with partial pivoting. All input coordinates are
    /// bounded viewport values, so a small pivot signals a degenerate system.
    private static func solve(_ equations: [[Double]]) -> [Double]? {
        var rows = equations
        let count = 8
        for column in 0..<count {
            var pivot = column
            for row in (column + 1)..<count where abs(rows[row][column]) > abs(rows[pivot][column]) {
                pivot = row
            }
            let divisor = rows[pivot][column]
            guard divisor.isFinite, abs(divisor) > 1e-12 else { return nil }
            if pivot != column { rows.swapAt(pivot, column) }
            for entry in column...count { rows[column][entry] /= divisor }
            for row in 0..<count where row != column {
                let multiplier = rows[row][column]
                for entry in column...count { rows[row][entry] -= multiplier * rows[column][entry] }
            }
        }
        let solution = rows.map { $0[count] }
        return solution.allSatisfy(\.isFinite) ? solution : nil
    }
}
