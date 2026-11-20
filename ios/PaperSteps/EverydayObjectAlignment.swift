import Foundation
import simd

/// The flat authored rectangle used for a learner's three-point calibration.
/// This is a manual correspondence, not camera recognition or cloth tracking.
struct EverydayObjectFootprint: Equatable {
    let minimum: SIMD3<Float>
    let maximum: SIMD3<Float>

    init?(minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        let extent = maximum - minimum
        guard (0..<3).allSatisfy({ minimum[$0].isFinite && maximum[$0].isFinite && extent[$0].isFinite && extent[$0] >= 0 }),
              extent.x > 0.01, extent.z > 0.01 else { return nil }
        self.minimum = minimum; self.maximum = maximum
    }
}

enum EverydayObjectAlignmentError: Error, Equatable {
    case invalidPoint, unevenSurface, sizeOutOfRange, wrongCorner, skewedRectangle

    var message: String {
        switch self {
        case .invalidPoint: return "The surface point is unavailable. Aim at the corner again."
        case .unevenSurface: return "Keep all three corners on the same flat surface."
        case .sizeOutOfRange: return "Choose corners 12 cm to 3 m apart. Try that corner again."
        case .wrongCorner: return "Choose the far-left corner, beyond the first edge."
        case .skewedRectangle: return "The sides should meet at a right angle. Aim at the far-left corner again."
        }
    }
}

struct EverydayObjectAlignment {
    let worldTransform: simd_float4x4
    let scale: SIMD3<Float>
    let contentOffset: SIMD3<Float>
    let width: Float
    let length: Float

    /// Near-left, near-right, far-left. Authored +X follows the near edge;
    /// authored -Z points away. Reflections and tilted/nonrectangular samples
    /// are rejected instead of silently distorting the teaching reference.
    static func solve(footprint: EverydayObjectFootprint, points: [SIMD3<Float>]) -> Result<Self, EverydayObjectAlignmentError> {
        guard points.count == 3 else { return .failure(.invalidPoint) }
        if let issue = validate(points: points) { return .failure(issue) }
        let nearLeft = points[0], nearRight = points[1], farLeft = points[2]
        let across = SIMD3<Float>(nearRight.x - nearLeft.x, 0, nearRight.z - nearLeft.z)
        let along = SIMD3<Float>(farLeft.x - nearLeft.x, 0, farLeft.z - nearLeft.z)
        let width = simd_length(across), length = simd_length(along)
        let x = across / width, y = SIMD3<Float>(0, 1, 0), z = simd_cross(x, y)
        let sx = width / (footprint.maximum.x - footprint.minimum.x)
        let sz = length / (footprint.maximum.z - footprint.minimum.z)
        let sy = sqrt(sx * sz)
        var transform = matrix_identity_float4x4
        transform.columns.0 = SIMD4(x, 0); transform.columns.1 = SIMD4(y, 0); transform.columns.2 = SIMD4(z, 0)
        transform.columns.3 = SIMD4(nearLeft.x, (nearLeft.y + nearRight.y + farLeft.y) / 3, nearLeft.z, 1)
        return .success(Self(worldTransform: transform, scale: [sx, sy, sz],
                             contentOffset: [-footprint.minimum.x, -footprint.minimum.y + 0.003 / sy, -footprint.maximum.z],
                             width: width, length: length))
    }

    /// Also validates partial capture so an invalid second point can be retried.
    static func validate(points: [SIMD3<Float>]) -> EverydayObjectAlignmentError? {
        guard !points.isEmpty, points.count <= 3,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { return .invalidPoint }
        guard let first = points.first else { return .invalidPoint }
        let heights = points.map(\.y)
        guard (heights.max()! - heights.min()!) <= 0.025 else { return .unevenSurface }
        for point in points.dropFirst() {
            let distance = simd_length(SIMD2(point.x - first.x, point.z - first.z))
            guard distance >= 0.12, distance <= 3 else { return .sizeOutOfRange }
        }
        if points.count == 3 {
            let x = simd_normalize(SIMD3<Float>(points[1].x - first.x, 0, points[1].z - first.z))
            let farEdge = SIMD3<Float>(points[2].x - first.x, 0, points[2].z - first.z)
            let along = simd_normalize(farEdge)
            guard simd_dot(along, -simd_cross(x, SIMD3<Float>(0, 1, 0))) > 0 else { return .wrongCorner }
            // A small angle across a bedsheet can still misplace the far corner
            // by tens of centimetres, so also bound absolute lateral error.
            guard abs(simd_dot(x, along)) <= 0.12,
                  abs(simd_dot(x, farEdge)) <= 0.025 else { return .skewedRectangle }
        }
        return nil
    }
}
