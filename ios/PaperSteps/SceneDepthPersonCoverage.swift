import Foundation
import simd

/// Tests the CURRENT projection of actual historical mesh triangles. A bitmap
/// hole in the old camera grid does not prove disjointness after camera motion.
enum SceneDepthPersonCoverage {
    static let maximumPixels = 1_048_576
    private static let maximumVertices = 1_048_576

    static func isDisjoint(surface: SceneDepthSurface, sourceCameraTransform: simd_float4x4,
                           current: SceneDepthSnapshot, personMask: [Bool]) -> Bool {
        guard validMetadata(current), validPose(sourceCameraTransform),
              personMask.count == current.width * current.height else { return false }
        // Without a current person region there is no competing hand coverage.
        // The caller separately owns freshness and mesh validity for rendering.
        guard personMask.contains(true) else { return true }
        guard surface.positions.count <= maximumVertices,
              surface.triangles.count <= maximumVertices * 6,
              surface.triangles.count.isMultiple(of: 3),
              surface.positions.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { return false }
        guard !surface.triangles.isEmpty else { return true }

        let width = current.width, height = current.height, stride = width + 1
        var integral = Array(repeating: UInt32(0), count: stride * (height + 1))
        for y in 0..<height {
            var row: UInt32 = 0
            for x in 0..<width {
                if personMask[y * width + x] { row += 1 }
                integral[(y + 1) * stride + x + 1] = integral[y * stride + x + 1] + row
            }
        }

        let sourceToCurrent = simd_inverse(current.cameraTransform) * sourceCameraTransform
        let k = current.calibration
        var projected = Array<SIMD2<Float>?>(repeating: nil, count: surface.positions.count)
        func project(_ index: Int) -> SIMD2<Float>? {
            if let cached = projected[index] { return cached }
            let point = sourceToCurrent * SIMD4<Float>(surface.positions[index], 1)
            let depth = -point.z
            guard point.x.isFinite, point.y.isFinite, depth.isFinite,
                  point.w.isFinite, abs(point.w - 1) < 0.0001,
                  depth > 0.01 else { return nil }
            let pixel = SIMD2(k.x * point.x / depth + k.z, -k.y * point.y / depth + k.w)
            guard pixel.x.isFinite, pixel.y.isFinite else { return nil }
            projected[index] = pixel
            return pixel
        }

        for triangle in Swift.stride(from: 0, to: surface.triangles.count, by: 3) {
            let a = Int(surface.triangles[triangle])
            let b = Int(surface.triangles[triangle + 1])
            let c = Int(surface.triangles[triangle + 2])
            guard a < surface.positions.count, b < surface.positions.count, c < surface.positions.count else { return false }
            let normal = simd_cross(surface.positions[b] - surface.positions[a], surface.positions[c] - surface.positions[a])
            let area = simd_length_squared(normal)
            guard area.isFinite, area > 0,
                  let pa = project(a), let pb = project(b), let pc = project(c) else { return false }
            let low = simd_min(pa, simd_min(pb, pc)), high = simd_max(pa, simd_max(pb, pc))
            // Pixel centres are integer image coordinates. Include any pixel
            // footprint touching the projected bounding box, even outside the
            // triangle itself; conservative rejection cannot clip a real hand.
            if high.x < -0.5 || high.y < -0.5
                || low.x > Float(width) - 0.5 || low.y > Float(height) - 0.5 { continue }
            // Clamp floating-point bounds BEFORE integer conversion; extreme
            // but finite offscreen projections must not trap or allocate.
            let x0 = Int(ceil(max(0, min(Float(width), low.x - 0.5))))
            let y0 = Int(ceil(max(0, min(Float(height), low.y - 0.5))))
            let x1 = Int(floor(max(0, min(Float(width - 1), high.x + 0.5)))) + 1
            let y1 = Int(floor(max(0, min(Float(height - 1), high.y + 0.5)))) + 1
            guard x0 < x1, y0 < y1 else { continue }
            let covered = integral[y1 * stride + x1] + integral[y0 * stride + x0]
                - integral[y0 * stride + x1] - integral[y1 * stride + x0]
            if covered != 0 { return false }
        }
        return true
    }

    /// Lightweight current-frame metadata may deliberately omit image arrays.
    private static func validMetadata(_ current: SceneDepthSnapshot) -> Bool {
        guard current.width >= 2, current.height >= 2,
              current.width <= 4096, current.height <= 4096,
              current.width * current.height <= maximumPixels,
              current.timestamp.isFinite,
              current.calibration.x.isFinite, current.calibration.y.isFinite,
              current.calibration.z.isFinite, current.calibration.w.isFinite,
              current.calibration.x > 0, current.calibration.y > 0 else { return false }
        return validPose(current.cameraTransform)
    }

    private static func validPose(_ transform: simd_float4x4) -> Bool {
        guard (0..<4).allSatisfy({ column in (0..<4).allSatisfy { transform[column][$0].isFinite } }),
              abs(transform[0].w) < 0.00001, abs(transform[1].w) < 0.00001,
              abs(transform[2].w) < 0.00001, abs(transform[3].w - 1) < 0.00001 else { return false }
        let x = SIMD3(transform[0].x, transform[0].y, transform[0].z)
        let y = SIMD3(transform[1].x, transform[1].y, transform[1].z)
        let z = SIMD3(transform[2].x, transform[2].y, transform[2].z)
        return abs(simd_length_squared(x) - 1) < 0.005
            && abs(simd_length_squared(y) - 1) < 0.005
            && abs(simd_length_squared(z) - 1) < 0.005
            && abs(simd_dot(x, y)) < 0.005 && abs(simd_dot(x, z)) < 0.005 && abs(simd_dot(y, z)) < 0.005
            && simd_dot(simd_cross(x, y), z) > 0.99
    }
}

/// Counts are on the same current ROI/grid, before temporal filling. A single
/// recognised hand pixel cannot certify that the rest of object depth is clear.
enum SceneDepthClearObservation {
    /// Reliable samples alone do not establish a clear view: mutually
    /// discontinuous samples can produce no usable triangles at all. Outside a
    /// wholly native-person region, an empty mesh needs positive support-plane
    /// rejection evidence and no rejected depth discontinuities.
    static func isReliableEmpty(surface: SceneDepthSurface, pixelCount: Int, excludedPixels: Int,
                                reliableNonPersonPixels: Int) -> Bool {
        guard surface.triangles.isEmpty,
              surface.rejectedSamples >= 0, surface.rejectedDiscontinuities >= 0,
              surface.rejectedSupportTriangles >= 0,
              isReliable(pixelCount: pixelCount, excludedPixels: excludedPixels,
                         reliableNonPersonPixels: reliableNonPersonPixels) else { return false }
        if excludedPixels == pixelCount { return true }
        return surface.rejectedDiscontinuities == 0 && surface.rejectedSupportTriangles > 0
    }

    static func isReliable(pixelCount: Int, excludedPixels: Int, reliableNonPersonPixels: Int) -> Bool {
        guard pixelCount > 0, pixelCount <= SceneDepthPersonCoverage.maximumPixels,
              excludedPixels >= 0, excludedPixels <= pixelCount else { return false }
        let nonPersonCount = pixelCount - excludedPixels
        guard reliableNonPersonPixels >= 0, reliableNonPersonPixels <= nonPersonCount else { return false }
        if nonPersonCount == 0 { return true }
        let requiredCoverage = (nonPersonCount * 9 + 9) / 10
        return reliableNonPersonPixels >= min(12, nonPersonCount)
            && reliableNonPersonPixels >= requiredCoverage
    }
}
