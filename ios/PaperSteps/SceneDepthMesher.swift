import Foundation
import simd

/// A single ARKit depth exposure, with calibration and pose from that same frame.
/// Its arrays are owned copies, so geometry work never outlives a locked buffer.
struct SceneDepthSnapshot: Sendable {
    var width: Int
    var height: Int
    var depths: [Float]
    var confidence: [UInt8]
    /// fx, fy, cx, cy, already scaled to the depth-map resolution.
    var calibration: SIMD4<Float>
    var cameraTransform: simd_float4x4
    var timestamp: TimeInterval
}

struct SceneDepthSurface: Sendable {
    var positions: [SIMD3<Float>]
    var triangles: [UInt32]
    var rejectedSamples: Int
    var rejectedDiscontinuities: Int
    var rejectedSupportTriangles: Int
}

enum SceneDepthMesher {
    enum Policy: Sendable { case paper, stableEquipment }
    static let maximumAge: TimeInterval = 0.12

    static func isFresh(timestamp: TimeInterval, latestFrameTimestamp: TimeInterval,
                        secondsSinceReceived: TimeInterval) -> Bool {
        let age = latestFrameTimestamp - timestamp
        return age.isFinite && age >= -0.001 && age <= maximumAge &&
            secondsSinceReceived.isFinite && secondsSinceReceived >= 0 && secondsSinceReceived <= maximumAge
    }

    static func build(_ snapshot: SceneDepthSnapshot, supportPlaneY: Float?, pixelStep: Int = 2,
                      policy: Policy = .paper) -> SceneDepthSurface {
        var result = SceneDepthSurface(positions: [], triangles: [], rejectedSamples: 0,
                                       rejectedDiscontinuities: 0, rejectedSupportTriangles: 0)
        let width = snapshot.width, height = snapshot.height
        let k = snapshot.calibration
        guard width >= 2, height >= 2, width <= 4096, height <= 4096,
              snapshot.depths.count == width * height, snapshot.confidence.count == width * height,
              k.x.isFinite, k.y.isFinite, k.z.isFinite, k.w.isFinite, k.x > 0, k.y > 0,
              (0..<4).allSatisfy({ column in (0..<4).allSatisfy { snapshot.cameraTransform[column][$0].isFinite } }) else { return result }
        let step = max(1, pixelStep)
        let xs = Array(stride(from: 0, to: width, by: step))
        let ys = Array(stride(from: 0, to: height, by: step))
        guard xs.count >= 2, ys.count >= 2 else { return result }
        result.positions.reserveCapacity(xs.count * ys.count)
        var valid = [Bool](), measuredDepth = [Float]()
        valid.reserveCapacity(xs.count * ys.count); measuredDepth.reserveCapacity(xs.count * ys.count)
        result.triangles.reserveCapacity((xs.count - 1) * (ys.count - 1) * 6)
        for y in ys {
            for x in xs {
                let index = y * width + x, d = snapshot.depths[index]
                let accepted = d.isFinite && d >= 0.12 && d <= 3.0 &&
                    (snapshot.confidence[index] == 1 || snapshot.confidence[index] == 2)
                valid.append(accepted); measuredDepth.append(accepted ? d : 0)
                if accepted {
                    // The paper policy retracts the surface slightly to avoid
                    // depth noise cutting into coplanar paper.
                    // Equipment contact has a small foreground tolerance to
                    // avoid alternating depth ownership at a hand/model edge.
                    // Paper keeps its original conservative, retracted depth.
                    let biased = policy == .paper ? d + max(0.004, min(0.012, d * 0.005))
                        : d - max(0.008, min(0.015, d * 0.012))
                    // ARKit image coordinates are right/down/forward; its camera
                    // coordinates are right/up/back. No UI-orientation rotation
                    // is needed: RealityKit projects these world-space points.
                    result.positions.append([(Float(x) - k.z) / k.x * biased,
                                             -(Float(y) - k.w) / k.y * biased, -biased])
                } else {
                    result.positions.append(.zero); result.rejectedSamples += 1
                }
            }
        }
        func add(_ a: Int, _ b: Int, _ c: Int) {
            guard valid[a] && valid[b] && valid[c] else { return }
            let low = min(measuredDepth[a], measuredDepth[b], measuredDepth[c])
            let high = max(measuredDepth[a], measuredDepth[b], measuredDepth[c])
            // Do not stretch a foreground sample across a background pixel.
            // Both confidence and an edge-depth threshold must pass.
            guard high - low <= max(0.025, low * 0.035) else {
                result.rejectedDiscontinuities += 1; return
            }
            if let supportPlaneY, supportPlaneY.isFinite {
                func world(_ i: Int) -> SIMD3<Float> {
                    let point = snapshot.cameraTransform * SIMD4<Float>(result.positions[i], 1)
                    return [point.x, point.y, point.z]
                }
                let pa = world(a), pb = world(b), pc = world(c)
                let n = simd_cross(pb - pa, pc - pa), magnitude = simd_length(n)
                let centerY = (pa.y + pb.y + pc.y) / 3
                // Ignore only nearly horizontal triangles in a narrow band at
                // the detected table. Raised hands and vertical objects remain.
                let supportTolerance: Float = policy == .paper ? 0.010 : 0.020
                if magnitude > 1e-10 && abs(n.y / magnitude) > 0.90 && abs(centerY - supportPlaneY) < supportTolerance {
                    result.rejectedSupportTriangles += 1; return
                }
            }
            result.triangles.append(UInt32(a)); result.triangles.append(UInt32(b)); result.triangles.append(UInt32(c))
        }
        for y in 0..<(ys.count - 1) {
            for x in 0..<(xs.count - 1) {
                let a = y * xs.count + x, b = a + 1, c = a + xs.count, d = c + 1
                // Camera-facing winding, also correct on iOS 17 where culling
                // cannot be customized on OcclusionMaterial.
                add(a, c, b); add(b, c, d)
            }
        }
        return result
    }
}
