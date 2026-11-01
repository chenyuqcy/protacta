import Foundation
import simd

/// Used by stabilized equipment and virtual-paper occluders. Historical samples
/// are reprojected to this exposure; unsupported or stale observations expire.
struct EquipmentDepthStabilizer: Sendable {
    private var previous: SceneDepthSnapshot?
    private var heldFrames: [UInt8] = []
    private var lastObservedAt: [TimeInterval] = []
    mutating func reset() { previous = nil; heldFrames.removeAll(); lastObservedAt.removeAll() }

    mutating func filter(_ input: SceneDepthSnapshot, current raw: SceneDepthSnapshot? = nil,
                         pixelStep: Int = 1, excluding excluded: [Bool]? = nil) -> SceneDepthSnapshot {
        guard SceneDepthTemporalAlignment.validSnapshot(input) else { reset(); return input }
        let count = input.depths.count
        if let excluded, excluded.count != count {
            // The custom surface must not become an unmasked person occluder
            // just because its exclusion bitmap has malformed dimensions.
            reset()
            var empty = input
            empty.depths = Array(repeating: 0, count: count)
            empty.confidence = Array(repeating: 0, count: count)
            return empty
        }
        var output = input
        if let excluded {
            for index in excluded.indices where excluded[index] {
                output.depths[index] = 0; output.confidence[index] = 0
            }
        }
        if let previous, input.timestamp <= previous.timestamp {
            // Never install an out-of-order or duplicate frame as the new
            // history source. The next normal exposure starts afresh.
            reset(); return output
        }
        // Only the same camera exposure can disprove smoothed history. Never
        // compare depth in different pixel coordinates after camera movement.
        let reference = raw.flatMap { value -> SceneDepthSnapshot? in
            guard value.width == input.width, value.height == input.height,
                  value.depths.count == count, value.confidence.count == count,
                  abs(value.timestamp - input.timestamp) < 0.001,
                  value.calibration == input.calibration,
                  (0..<4).allSatisfy({ value.cameraTransform[$0] == input.cameraTransform[$0] }) else { return nil }
            return value
        }
        func reading(_ index: Int) -> (depth: Float, confidence: UInt8, bypassesHistory: Bool) {
            guard excluded?[index] != true else { return (0, 0, false) }
            let smooth = input.depths[index], confidence = input.confidence[index]
            if let reference {
                let latest = reference.depths[index], reliability = reference.confidence[index]
                if latest.isFinite, (0.12...3).contains(latest), (1...2).contains(reliability),
                   !smooth.isFinite || confidence == 0 || abs(latest - smooth) > 0.020 {
                    // An isolated raw edge outlier must not punch a fresh hole
                    // through a stable silhouette. Coherent arrival/withdrawal
                    // is accepted in the same exposure, without a time delay.
                    let x = index % input.width, y = index / input.width
                    var support = 0, available = 0
                    for offset in 0..<5 {
                        let dx = offset == 1 ? -1 : offset == 2 ? 1 : 0
                        let dy = offset == 3 ? -1 : offset == 4 ? 1 : 0
                        let px = x + dx, py = y + dy
                        guard px >= 0, px < input.width, py >= 0, py < input.height else { continue }
                        let i = py * input.width + px
                        guard excluded?[i] != true else { continue }
                        available += 1
                        let d = reference.depths[i]
                        if d.isFinite, (0.12...3).contains(d), (1...2).contains(reference.confidence[i]),
                           abs(d - latest) <= 0.020 { support += 1 }
                    }
                    guard available >= 3, support >= min(3, available) else { return (smooth, confidence, false) }
                    // A hand arriving or withdrawing bypasses system smoothing
                    // as well as our own history in this exposure.
                    return (latest, reliability, true)
                }
            }
            return (smooth, confidence, false)
        }
        func valid(_ value: (depth: Float, confidence: UInt8, bypassesHistory: Bool)) -> Bool {
            value.depth.isFinite && (0.12...3).contains(value.depth) && (1...2).contains(value.confidence)
        }
        let old = previous.flatMap {
            SceneDepthTemporalAlignment.reproject($0, into: input, heldFrames: heldFrames,
                                                 lastObservedAt: lastObservedAt, excluding: excluded)
        }
        let previousHolds = old?.heldFrames ?? Array(repeating: 0, count: count)
        var nextHolds = Array(repeating: UInt8(0), count: count)
        var nextObservedAt = Array(repeating: input.timestamp, count: count)
        if let excluded {
            for index in excluded.indices where excluded[index] {
                nextObservedAt[index] = 0
            }
        }
        // Match the mesher's sampling grid. Read the full 3x3 neighborhood, but
        // avoid filtering vertices the mesh never uses or allocating per pixel.
        let step = max(1, pixelStep)
        var neighbors = Array(repeating: Float(0), count: 9)
        for y in stride(from: 0, to: input.height, by: step) {
            for x in stride(from: 0, to: input.width, by: step) {
                let index = y * input.width + x
                guard excluded?[index] != true else { continue }
                let current = reading(index)
                let currentValid = valid(current)
                var neighborCount = 0, oldSupport = 0
                for dy in -1...1 { for dx in -1...1 {
                    let px = x + dx, py = y + dy
                    guard px >= 0, py >= 0, px < input.width, py < input.height else { continue }
                    let neighbor = py * input.width + px
                    let sample = reading(neighbor)
                    if valid(sample) {
                        let depth = sample.depth
                        var insertion = neighborCount
                        while insertion > 0, neighbors[insertion - 1] > depth {
                            neighbors[insertion] = neighbors[insertion - 1]
                            insertion -= 1
                        }
                        neighbors[insertion] = depth; neighborCount += 1
                        if let old, old.confidence[index] >= 1, abs(depth - old.depths[index]) <= 0.012 { oldSupport += 1 }
                    }
                } }
                var measured: Float?
                if currentValid {
                    let current = current.depth
                    var first = 0, end = neighborCount
                    while first < end, neighbors[first] < current - 0.015 { first += 1 }
                    while end > first, neighbors[end - 1] > current + 0.015 { end -= 1 }
                    measured = end - first >= 3 ? neighbors[first + (end - first) / 2] : current
                } else if neighborCount >= 5, neighbors[neighborCount - 1] - neighbors[0] <= 0.015 {
                    // Fill only an interior confidence hole, never a silhouette
                    // that straddles the foreground and background.
                    measured = neighbors[neighborCount / 2]
                } else if let old, old.confidence[index] >= 1,
                          previousHolds[index] < 2,
                          oldSupport >= 3 {
                    measured = old.depths[index]; nextHolds[index] = previousHolds[index] + 1
                    nextObservedAt[index] = old.lastObservedAt[index]
                }
                guard var depth = measured else {
                    output.depths[index] = 0; output.confidence[index] = 0; nextObservedAt[index] = 0; continue
                }
                if !current.bypassesHistory, let old, old.confidence[index] >= 1 {
                    let difference = abs(depth - old.depths[index])
                    if difference <= 0.010 { depth = old.depths[index] }
                    else if difference <= 0.020 { depth = (depth + old.depths[index]) * 0.5 }
                    // A new foreground/background edge bypasses history now.
                }
                output.depths[index] = depth
                output.confidence[index] = currentValid ? current.confidence : 1
            }
        }
        previous = output; heldFrames = nextHolds; lastObservedAt = nextObservedAt
        return output
    }
}
