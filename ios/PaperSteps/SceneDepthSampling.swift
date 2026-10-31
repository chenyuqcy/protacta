import Foundation
import simd

/// Coordinates remain in the original camera-depth image. Cropping shifts the
/// principal point, never the camera pose, so every vertex keeps its calibration.
struct SceneDepthRegion: Equatable, Sendable {
    let x: Int, y: Int, width: Int, height: Int
    var area: Int { width * height }
    static func full(_ snapshot: SceneDepthSnapshot) -> Self {
        Self(x: 0, y: 0, width: snapshot.width, height: snapshot.height)
    }
    func contains(_ other: Self, margin: Int = 0) -> Bool {
        other.x >= x + margin && other.y >= y + margin &&
        other.x + other.width <= x + width - margin && other.y + other.height <= y + height - margin
    }
    func padded(in snapshot: SceneDepthSnapshot) -> Self {
        let lowX = max(0, ((x - 12) / 16) * 16)
        let lowY = max(0, ((y - 12) / 16) * 16)
        let highX = min(snapshot.width, ((x + width + 12 + 15) / 16) * 16)
        let highY = min(snapshot.height, ((y + height + 12 + 15) / 16) * 16)
        return Self(x: lowX, y: lowY, width: highX - lowX, height: highY - lowY)
    }
    func crop(_ snapshot: SceneDepthSnapshot) -> SceneDepthSnapshot {
        guard x >= 0, y >= 0, width >= 2, height >= 2,
              x + width <= snapshot.width, y + height <= snapshot.height,
              snapshot.depths.count == snapshot.width * snapshot.height,
              snapshot.confidence.count == snapshot.depths.count else { return snapshot }
        if self == Self.full(snapshot) { return snapshot }
        var depth = [Float](), confidence = [UInt8]()
        depth.reserveCapacity(area); confidence.reserveCapacity(area)
        for row in y..<(y + height) {
            let start = row * snapshot.width + x
            depth.append(contentsOf: snapshot.depths[start..<(start + width)])
            confidence.append(contentsOf: snapshot.confidence[start..<(start + width)])
        }
        var calibration = snapshot.calibration
        calibration.z -= Float(x); calibration.w -= Float(y)
        return SceneDepthSnapshot(width: width, height: height, depths: depth, confidence: confidence,
                                  calibration: calibration, cameraTransform: snapshot.cameraTransform,
                                  timestamp: snapshot.timestamp)
    }
    static func projected(minimum: SIMD3<Float>, maximum: SIMD3<Float>,
                          into snapshot: SceneDepthSnapshot) -> Self? {
        guard snapshot.width >= 2, snapshot.height >= 2,
              (0..<3).allSatisfy({ minimum[$0].isFinite && maximum[$0].isFinite && minimum[$0] <= maximum[$0] }),
              snapshot.calibration.x > 0, snapshot.calibration.y > 0 else { return nil }
        let inverse = simd_inverse(snapshot.cameraTransform)
        var low = SIMD2<Float>(repeating: .infinity), high = SIMD2<Float>(repeating: -.infinity)
        for x in [minimum.x, maximum.x] { for y in [minimum.y, maximum.y] { for z in [minimum.z, maximum.z] {
            let camera = inverse * SIMD4<Float>(x, y, z, 1)
            guard camera.z < -0.05 else { return nil }
            let p = SIMD2(snapshot.calibration.x * camera.x / -camera.z + snapshot.calibration.z,
                          snapshot.calibration.y * -camera.y / -camera.z + snapshot.calibration.w)
            guard p.x.isFinite, p.y.isFinite else { return nil }
            low = simd_min(low, p); high = simd_max(high, p)
        } } }
        // Clamp before converting large projections to integer coordinates.
        let x0 = Int(floor(max(0, min(Float(snapshot.width), low.x))))
        let y0 = Int(floor(max(0, min(Float(snapshot.height), low.y))))
        let x1 = Int(ceil(max(0, min(Float(snapshot.width), high.x))))
        let y1 = Int(ceil(max(0, min(Float(snapshot.height), high.y))))
        guard x1 - x0 >= 2, y1 - y0 >= 2 else { return nil }
        return Self(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}

struct SceneDepthSampling: Sendable {
    struct Plan: Sendable {
        let region: SceneDepthRegion
        let pixelStep: Int
    }
    private var retained: SceneDepthRegion?
    private var sourceSize = SIMD2<Int>.zero
    mutating func reset() { retained = nil; sourceSize = .zero }
    mutating func plan(for snapshot: SceneDepthSnapshot, minimum: SIMD3<Float>?, maximum: SIMD3<Float>?) -> Plan {
        let size = SIMD2(snapshot.width, snapshot.height)
        guard let minimum, let maximum,
              let required = SceneDepthRegion.projected(minimum: minimum, maximum: maximum, into: snapshot) else {
            reset(); return Plan(region: .full(snapshot), pixelStep: 2)
        }
        // Keep a padded region while it still covers the model. Small camera
        // jitter must not keep changing calibration and discarding history.
        if sourceSize != size || retained?.contains(required, margin: 4) != true {
            retained = required.padded(in: snapshot); sourceSize = size
        }
        let region = retained ?? .full(snapshot)
        return Plan(region: region, pixelStep: region.area <= 20_000 ? 1 : 2)
    }
}
