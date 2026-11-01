import Foundation

/// An owned, sensor-oriented segmentation buffer. Any nonzero label belongs to
/// native person occlusion; this utility only removes competing LiDAR samples.
/// It never draws a silhouette, rotates a buffer, or retains a previous mask.
struct SceneDepthPersonMask: Sendable {
    let width: Int
    let height: Int
    let values: [UInt8]

    /// Pixel-centred normalized resampling with conservative footprint coverage
    /// prevents a thin person label disappearing during downsampling. Dilation
    /// is a square margin measured in DEPTH pixels, clamped at image edges.
    /// Work is O(mask pixels + depth pixels), independent of the radius.
    func exclusionMask(depthWidth: Int, depthHeight: Int, radius: Int = 4) -> [Bool]? {
        guard validSize(width, height), validSize(depthWidth, depthHeight),
              values.count == width * height,
              compatibleAspect(depthWidth: depthWidth, depthHeight: depthHeight) else { return nil }
        let count = depthWidth * depthHeight
        guard values.contains(where: { $0 != 0 }) else { return Array(repeating: false, count: count) }

        // UInt32 is sufficient for the largest accepted 4096 x 4096 buffer.
        // Release this source-resolution table before allocating dilation work.
        let stride = width + 1
        var integral = Array(repeating: UInt32(0), count: stride * (height + 1))
        for y in 0..<height {
            var row: UInt32 = 0
            let input = y * width, previous = y * stride, output = (y + 1) * stride
            for x in 0..<width {
                if values[input + x] != 0 { row += 1 }
                integral[output + x + 1] = integral[previous + x + 1] + row
            }
        }
        var covered = Array(repeating: UInt8(0), count: count)
        for y in 0..<depthHeight {
            // These exact integer edges are the footprint around normalized
            // centre (x + 0.5, y + 0.5); no UI-orientation transform is applied.
            let y0 = y * height / depthHeight
            let y1 = ((y + 1) * height + depthHeight - 1) / depthHeight
            for x in 0..<depthWidth {
                let x0 = x * width / depthWidth
                let x1 = ((x + 1) * width + depthWidth - 1) / depthWidth
                let enclosed = integral[y1 * stride + x1] + integral[y0 * stride + x0]
                    - integral[y0 * stride + x1] - integral[y1 * stride + x0]
                if enclosed != 0 { covered[y * depthWidth + x] = 1 }
            }
        }
        integral.removeAll(keepingCapacity: false)

        let margin = min(max(0, radius), max(depthWidth, depthHeight))
        guard margin > 0 else { return covered.map { $0 != 0 } }
        var horizontal = Array(repeating: UInt8(0), count: count)
        for y in 0..<depthHeight {
            let row = y * depthWidth
            var present = 0
            for x in 0...min(margin, depthWidth - 1) { present += Int(covered[row + x]) }
            for x in 0..<depthWidth {
                horizontal[row + x] = present > 0 ? 1 : 0
                let outgoing = x - margin, incoming = x + margin + 1
                if outgoing >= 0 { present -= Int(covered[row + outgoing]) }
                if incoming < depthWidth { present += Int(covered[row + incoming]) }
            }
        }
        covered.removeAll(keepingCapacity: false)
        var result = Array(repeating: false, count: count)
        for x in 0..<depthWidth {
            var present = 0
            for y in 0...min(margin, depthHeight - 1) { present += Int(horizontal[y * depthWidth + x]) }
            for y in 0..<depthHeight {
                result[y * depthWidth + x] = present > 0
                let outgoing = y - margin, incoming = y + margin + 1
                if outgoing >= 0 { present -= Int(horizontal[outgoing * depthWidth + x]) }
                if incoming < depthHeight { present += Int(horizontal[incoming * depthWidth + x]) }
            }
        }
        return result
    }

    /// Exclusion happens after depth filtering so a spatial/temporal filter
    /// cannot refill these holes. excludedPixels measures mask coverage,
    /// including locations whose original depth was already invalid.
    func excludingPeople(from snapshot: SceneDepthSnapshot, radius: Int = 4)
        -> (snapshot: SceneDepthSnapshot, excludedPixels: Int)? {
        guard validSize(snapshot.width, snapshot.height),
              snapshot.depths.count == snapshot.width * snapshot.height,
              snapshot.confidence.count == snapshot.depths.count,
              let excluded = exclusionMask(depthWidth: snapshot.width, depthHeight: snapshot.height, radius: radius) else { return nil }
        var output = snapshot, excludedPixels = 0
        for index in excluded.indices where excluded[index] {
            output.depths[index] = 0
            output.confidence[index] = 0
            excludedPixels += 1
        }
        return (output, excludedPixels)
    }

    /// A stale mesh is safe only when its baked exclusion still protects
    /// every currently required person pixel inside that mesh's sensor ROI.
    /// Shrinking or moving outside the ROI does not add competing coverage.
    static func coversPersonRegion(protected protectedMask: [Bool], required requiredMask: [Bool],
                                   width: Int, region: SceneDepthRegion) -> Bool {
        guard (1...4096).contains(width), !protectedMask.isEmpty,
              protectedMask.count == requiredMask.count,
              protectedMask.count % width == 0 else { return false }
        let height = protectedMask.count / width
        guard (1...4096).contains(height),
              region.x >= 0, region.x < width, region.y >= 0, region.y < height,
              region.width > 0, region.width <= width - region.x,
              region.height > 0, region.height <= height - region.y else { return false }
        for y in region.y..<(region.y + region.height) {
            let start = y * width + region.x
            for index in start..<(start + region.width) {
                if requiredMask[index] && !protectedMask[index] { return false }
            }
        }
        return true
    }

    private func validSize(_ width: Int, _ height: Int) -> Bool {
        (1...4096).contains(width) && (1...4096).contains(height)
    }

    private func compatibleAspect(depthWidth: Int, depthHeight: Int) -> Bool {
        let a = Double(width) * Double(depthHeight), b = Double(height) * Double(depthWidth)
        let error = abs(a - b) / max(a, b)
        // Permit sensor-resolution rounding, while capping the tolerance for
        // tiny synthetic buffers. A rotated or substantially cropped layout
        // must be rejected rather than silently reinterpreted.
        let rounding = 0.5 * (1 / Double(width) + 1 / Double(height)
            + 1 / Double(depthWidth) + 1 / Double(depthHeight))
        return error <= max(0.02, min(0.125, rounding))
    }
}
