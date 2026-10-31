import Foundation
import simd

/// Applied only to the equipment occluder. Real motion and camera movement
/// reset history; invalid observations cannot grow or indefinitely retain a hand.
struct EquipmentDepthStabilizer: Sendable {
    private var previous: SceneDepthSnapshot?
    private var heldFrames: [UInt8] = []
    mutating func reset() { previous = nil; heldFrames.removeAll() }

    mutating func filter(_ input: SceneDepthSnapshot, pixelStep: Int = 1) -> SceneDepthSnapshot {
        guard input.width > 1, input.height > 1, input.width <= 4096, input.height <= 4096 else { reset(); return input }
        let count = input.width * input.height
        guard count == input.depths.count,
              count == input.confidence.count else { reset(); return input }
        func valid(_ index: Int) -> Bool {
            let depth = input.depths[index]
            return depth.isFinite && (0.12...3).contains(depth) && (1...2).contains(input.confidence[index])
        }
        var output = input
        let old = previous
        let compatible = old.map { value in
            guard value.width == input.width, value.height == input.height,
                  input.timestamp > value.timestamp, input.timestamp - value.timestamp < 0.12,
                  simd_length(SIMD3(input.cameraTransform.columns.3.x - value.cameraTransform.columns.3.x,
                                    input.cameraTransform.columns.3.y - value.cameraTransform.columns.3.y,
                                    input.cameraTransform.columns.3.z - value.cameraTransform.columns.3.z)) < 0.004 else { return false }
            let a = simd_quatf(input.cameraTransform), b = simd_quatf(value.cameraTransform)
            return abs(simd_dot(a.vector, b.vector)) > cos(Float(0.5 * Double.pi / 180 / 2))
                && input.calibration == value.calibration
        } ?? false
        let previousHolds = compatible && heldFrames.count == count ? heldFrames : Array(repeating: 0, count: count)
        var nextHolds = Array(repeating: UInt8(0), count: count)
        // Match the mesher's sampling grid. Read the full 3x3 neighborhood, but
        // avoid filtering vertices the mesh never uses or allocating per pixel.
        let step = max(1, pixelStep)
        var neighbors = Array(repeating: Float(0), count: 9)
        for y in stride(from: 0, to: input.height, by: step) {
            for x in stride(from: 0, to: input.width, by: step) {
                let index = y * input.width + x
                let currentValid = valid(index)
                var neighborCount = 0, oldSupport = 0
                for dy in -1...1 { for dx in -1...1 {
                    let px = x + dx, py = y + dy
                    guard px >= 0, py >= 0, px < input.width, py < input.height else { continue }
                    let neighbor = py * input.width + px
                    if valid(neighbor) {
                        let depth = input.depths[neighbor]
                        var insertion = neighborCount
                        while insertion > 0, neighbors[insertion - 1] > depth {
                            neighbors[insertion] = neighbors[insertion - 1]
                            insertion -= 1
                        }
                        neighbors[insertion] = depth; neighborCount += 1
                        if compatible, let old, abs(depth - old.depths[index]) <= 0.012 { oldSupport += 1 }
                    }
                } }
                var measured: Float?
                if currentValid {
                    let current = input.depths[index]
                    var first = 0, end = neighborCount
                    while first < end, neighbors[first] < current - 0.015 { first += 1 }
                    while end > first, neighbors[end - 1] > current + 0.015 { end -= 1 }
                    measured = end - first >= 3 ? neighbors[first + (end - first) / 2] : current
                } else if neighborCount >= 5, neighbors[neighborCount - 1] - neighbors[0] <= 0.015 {
                    // Fill only an interior confidence hole, never a silhouette
                    // that straddles the foreground and background.
                    measured = neighbors[neighborCount / 2]
                } else if compatible, let old, old.confidence[index] >= 1,
                          previousHolds[index] < 1,
                          oldSupport >= 3 {
                    measured = old.depths[index]; nextHolds[index] = 1
                }
                guard var depth = measured else {
                    output.depths[index] = 0; output.confidence[index] = 0; continue
                }
                if compatible, let old, old.confidence[index] >= 1 {
                    let difference = abs(depth - old.depths[index])
                    if difference <= 0.006 { depth = old.depths[index] }
                    else if difference <= 0.020 { depth = (depth + old.depths[index]) * 0.5 }
                    // A new foreground/background edge bypasses history now.
                }
                output.depths[index] = depth
                output.confidence[index] = currentValid ? input.confidence[index] : 1
            }
        }
        previous = output; heldFrames = nextHolds
        return output
    }
}
