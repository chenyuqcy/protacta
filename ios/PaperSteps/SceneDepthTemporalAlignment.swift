import Foundation
import simd

/// Forward-projects only previously observed surface points into the current
/// exposure. Empty/disoccluded pixels stay unknown; this is not hole filling.
enum SceneDepthTemporalAlignment {
    struct History: Sendable {
        let depths: [Float]
        let confidence: [UInt8]
        let heldFrames: [UInt8]
        let lastObservedAt: [TimeInterval]
    }

    static let maximumAge: TimeInterval = 0.12
    static let maximumTranslation: Float = 0.004
    static let maximumRotation: Float = 0.5 * .pi / 180

    /// These are cropped, calibrated image coordinates. A changed principal
    /// point or image size requires the same projection as a moving camera.
    static func reproject(_ previous: SceneDepthSnapshot, into current: SceneDepthSnapshot,
                          heldFrames: [UInt8], lastObservedAt: [TimeInterval]? = nil,
                          excluding excluded: [Bool]? = nil) -> History? {
        guard validSnapshot(previous), validSnapshot(current),
              heldFrames.count == previous.depths.count,
              lastObservedAt == nil || lastObservedAt?.count == previous.depths.count,
              excluded == nil || excluded?.count == current.depths.count,
              current.timestamp > previous.timestamp,
              current.timestamp - previous.timestamp < maximumAge else { return nil }

        let translation = SIMD3(current.cameraTransform[3].x - previous.cameraTransform[3].x,
                                current.cameraTransform[3].y - previous.cameraTransform[3].y,
                                current.cameraTransform[3].z - previous.cameraTransform[3].z)
        guard simd_length(translation) < maximumTranslation else { return nil }
        let oldRotation = simd_quatf(previous.cameraTransform)
        let newRotation = simd_quatf(current.cameraTransform)
        guard abs(simd_dot(oldRotation.vector, newRotation.vector)) > cos(maximumRotation * 0.5) else { return nil }

        let oldToCurrent = simd_inverse(current.cameraTransform) * previous.cameraTransform
        let count = current.depths.count
        var depths = Array(repeating: Float(0), count: count)
        var confidence = Array(repeating: UInt8(0), count: count)
        var alignedHolds = Array(repeating: UInt8(0), count: count)
        var observed = Array(repeating: TimeInterval(0), count: count)
        let oldK = previous.calibration, newK = current.calibration

        for index in previous.depths.indices {
            let depth = previous.depths[index], reliability = previous.confidence[index]
            let time = lastObservedAt?[index] ?? previous.timestamp
            let age = current.timestamp - time
            guard depth.isFinite, (0.12...3).contains(depth), (1...2).contains(reliability),
                  heldFrames[index] <= 2, time.isFinite, time <= previous.timestamp,
                  age >= 0, age < maximumAge else { continue }

            let x = Float(index % previous.width), y = Float(index / previous.width)
            // ARKit camera coordinates are right/up/back; image rows point down.
            let oldCamera = SIMD4<Float>((x - oldK.z) / oldK.x * depth,
                                         -(y - oldK.w) / oldK.y * depth, -depth, 1)
            let camera = oldToCurrent * oldCamera
            let currentDepth = -camera.z
            guard camera.x.isFinite, camera.y.isFinite, currentDepth.isFinite,
                  (0.12...3).contains(currentDepth) else { continue }
            let u = newK.x * camera.x / currentDepth + newK.z
            let v = -newK.y * camera.y / currentDepth + newK.w
            // Each source point has one nearest pixel footprint. Never splat it
            // into neighbors, interpolate unseen background, or extend the ROI.
            guard u.isFinite, v.isFinite,
                  u >= -0.5, v >= -0.5,
                  u < Float(current.width) - 0.5, v < Float(current.height) - 0.5 else { continue }
            let px = Int(u.rounded()), py = Int(v.rounded())
            guard px >= 0, px < current.width, py >= 0, py < current.height else { continue }
            let destination = py * current.width + px
            guard excluded?[destination] != true else { continue }
            let nearer = confidence[destination] == 0 || currentDepth < depths[destination]
            let equallyNear = currentDepth == depths[destination]
            let betterTie = equallyNear && (reliability > confidence[destination]
                || (reliability == confidence[destination] && time > observed[destination])
                || (reliability == confidence[destination] && time == observed[destination]
                    && heldFrames[index] < alignedHolds[destination]))
            guard nearer || betterTie else { continue }
            depths[destination] = currentDepth
            confidence[destination] = reliability
            alignedHolds[destination] = heldFrames[index]
            observed[destination] = time
        }
        return History(depths: depths, confidence: confidence, heldFrames: alignedHolds,
                       lastObservedAt: observed)
    }

    static func validSnapshot(_ value: SceneDepthSnapshot) -> Bool {
        guard value.width >= 2, value.height >= 2, value.width <= 4096, value.height <= 4096,
              value.depths.count == value.width * value.height,
              value.confidence.count == value.depths.count, value.timestamp.isFinite,
              value.calibration.x.isFinite, value.calibration.y.isFinite,
              value.calibration.z.isFinite, value.calibration.w.isFinite,
              value.calibration.x > 0, value.calibration.y > 0 else { return false }
        let transform = value.cameraTransform
        guard (0..<4).allSatisfy({ column in (0..<4).allSatisfy { transform[column][$0].isFinite } }),
              abs(transform[0].w) < 0.00001, abs(transform[1].w) < 0.00001,
              abs(transform[2].w) < 0.00001, abs(transform[3].w - 1) < 0.00001 else { return false }
        let x = SIMD3(transform[0].x, transform[0].y, transform[0].z)
        let y = SIMD3(transform[1].x, transform[1].y, transform[1].z)
        let z = SIMD3(transform[2].x, transform[2].y, transform[2].z)
        // Inversion/quaternion comparison is meaningful only for a rigid camera
        // pose. Reject singular, mirrored, sheared and non-affine test inputs.
        return abs(simd_length_squared(x) - 1) < 0.005
            && abs(simd_length_squared(y) - 1) < 0.005
            && abs(simd_length_squared(z) - 1) < 0.005
            && abs(simd_dot(x, y)) < 0.005 && abs(simd_dot(x, z)) < 0.005 && abs(simd_dot(y, z)) < 0.005
            && simd_dot(simd_cross(x, y), z) > 0.99
    }
}
