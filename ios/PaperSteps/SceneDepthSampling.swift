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
        let lowX = max(0, ((x - 8) / 8) * 8)
        let lowY = max(0, ((y - 8) / 8) * 8)
        let highX = min(snapshot.width, ((x + width + 8 + 7) / 8) * 8)
        let highY = min(snapshot.height, ((y + height + 8 + 7) / 8) * 8)
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
        guard (0..<3).allSatisfy({ minimum[$0].isFinite && maximum[$0].isFinite && minimum[$0] <= maximum[$0] }) else { return nil }
        return project(corners: corners(minimum: minimum, maximum: maximum), into: snapshot).region
    }
    static func corners(minimum: SIMD3<Float>, maximum: SIMD3<Float>) -> [SIMD3<Float>] {
        [minimum.x, maximum.x].flatMap { x in
            [minimum.y, maximum.y].flatMap { y in [minimum.z, maximum.z].map { SIMD3(x, y, $0) } }
        }
    }
    struct Projection: Sendable { let region: SceneDepthRegion?; let reason: String }
    static func project(corners: [SIMD3<Float>], into snapshot: SceneDepthSnapshot) -> Projection {
        guard snapshot.width >= 2, snapshot.height >= 2, corners.count == 8,
              snapshot.calibration.x > 0, snapshot.calibration.y > 0 else {
            return Projection(region: nil, reason: "Invalid target or calibration")
        }
        let inverse = simd_inverse(snapshot.cameraTransform)
        var low = SIMD2<Float>(repeating: .infinity), high = SIMD2<Float>(repeating: -.infinity)
        for point in corners {
            let camera = inverse * SIMD4<Float>(point, 1)
            guard camera.x.isFinite, camera.y.isFinite, camera.z.isFinite else {
                return Projection(region: nil, reason: "Nonfinite target projection")
            }
            guard camera.z < -0.05 else { return Projection(region: nil, reason: "Target crosses camera near plane") }
            let p = SIMD2(snapshot.calibration.x * camera.x / -camera.z + snapshot.calibration.z,
                          snapshot.calibration.y * -camera.y / -camera.z + snapshot.calibration.w)
            guard p.x.isFinite, p.y.isFinite else { return Projection(region: nil, reason: "Invalid image projection") }
            low = simd_min(low, p); high = simd_max(high, p)
        }
        // Clamp before converting large projections to integer coordinates.
        let x0 = Int(floor(max(0, min(Float(snapshot.width), low.x))))
        let y0 = Int(floor(max(0, min(Float(snapshot.height), low.y))))
        let x1 = Int(ceil(max(0, min(Float(snapshot.width), high.x))))
        let y1 = Int(ceil(max(0, min(Float(snapshot.height), high.y))))
        guard x1 - x0 >= 2, y1 - y0 >= 2 else { return Projection(region: nil, reason: "Target outside depth image") }
        return Projection(region: Self(x: x0, y: y0, width: x1 - x0, height: y1 - y0), reason: "Oriented target region")
    }
}

struct SceneDepthSampling: Sendable {
    struct Plan: Sendable {
        let region: SceneDepthRegion
        let pixelStep: Int
        let reason: String
        let projectedArea: Int
        init(region: SceneDepthRegion, pixelStep: Int, reason: String = "Legacy full image", projectedArea: Int = 0) {
            self.region = region; self.pixelStep = pixelStep; self.reason = reason; self.projectedArea = projectedArea
        }
    }
    private var retained: SceneDepthRegion?
    private var sourceSize = SIMD2<Int>.zero
    private var pendingShrink: SceneDepthRegion?
    private var shrinkFrames = 0
    mutating func reset() { retained = nil; sourceSize = .zero; pendingShrink = nil; shrinkFrames = 0 }
    mutating func plan(for snapshot: SceneDepthSnapshot, minimum: SIMD3<Float>?, maximum: SIMD3<Float>?) -> Plan {
        plan(for: snapshot, worldCorners: minimum.flatMap { low in maximum.map { SceneDepthRegion.corners(minimum: low, maximum: $0) } })
    }
    mutating func plan(for snapshot: SceneDepthSnapshot, worldCorners: [SIMD3<Float>]?) -> Plan {
        let size = SIMD2(snapshot.width, snapshot.height)
        guard let worldCorners else {
            reset(); return Plan(region: .full(snapshot), pixelStep: 2, reason: "No placed target")
        }
        let projection = SceneDepthRegion.project(corners: worldCorners, into: snapshot)
        guard let required = projection.region else {
            reset(); return Plan(region: .full(snapshot), pixelStep: 2, reason: projection.reason)
        }
        // Keep a padded region while it still covers the model. Small camera
        // jitter must not keep changing calibration and discarding history.
        if sourceSize != size || retained?.contains(required, margin: 4) != true {
            retained = required.padded(in: snapshot); sourceSize = size
            pendingShrink = nil; shrinkFrames = 0
        } else if let retained, required.padded(in: snapshot).area < retained.area * 2 / 3 {
            // A close/large initial view must not pin the entire session to a
            // coarse full-image region. Shrink only after six stable samples.
            if pendingShrink?.contains(required, margin: 4) == true { shrinkFrames += 1 }
            else { pendingShrink = required.padded(in: snapshot); shrinkFrames = 1 }
            if shrinkFrames >= 6 {
                self.retained = pendingShrink; pendingShrink = nil; shrinkFrames = 0
            }
        } else { pendingShrink = nil; shrinkFrames = 0 }
        let region = retained ?? .full(snapshot)
        return Plan(region: region, pixelStep: region.area <= 20_000 ? 1 : 2,
                    reason: region.area <= 20_000 ? "Native oriented region" : shrinkFrames > 0 ? "Waiting for stable smaller region" : "Region over native work budget",
                    projectedArea: required.area)
    }
}
