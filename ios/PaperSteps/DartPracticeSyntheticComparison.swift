#if DEBUG && targetEnvironment(simulator)
import CoreGraphics
import Foundation

/// Generated simulator pixels for UI plumbing, never a camera observation or
/// physical-fold acceptance. The actual outline checker still makes the result.
struct DartPracticeSyntheticComparison {
    let result: DartOutlineCheckResult
    let snapshot: DartCheckSnapshot?

    static func make(action: Int, sheetVisible: Bool, viewportSize: CGSize,
                     timestamp: TimeInterval, now: TimeInterval? = nil) -> DartPracticeSyntheticComparison {
        func unknown(_ message: String) -> DartPracticeSyntheticComparison {
            DartPracticeSyntheticComparison(result: DartOutlineCheckResult(
                checkpointID: "dart-synthetic-outline-\(action)-v1", referenceState: action,
                outcome: .cannotJudge, message: "Synthetic comparison. \(message)",
                mismatchedPoints: [], timestamp: timestamp), snapshot: nil)
        }
        func isFresh(_ current: TimeInterval) -> Bool {
            timestamp.isFinite && timestamp >= 0 && current.isFinite && current >= timestamp &&
                current - timestamp <= PaperGuideSession.maximumObservationAge
        }
        guard isFresh(now ?? ProcessInfo.processInfo.systemUptime) else {
            return unknown("This sample is not a current comparison frame. Check again.")
        }
        guard (1...10).contains(action), DartPracticeCourse.supportsOutlineCheck(state: action) else {
            return unknown("Use the 3D reference for this action. An outline cannot verify lifted paper or hidden layers.")
        }

        let viewport: CGSize
        if viewportSize.width.isFinite, viewportSize.height.isFinite,
           viewportSize.width > 0, viewportSize.height > 0 {
            viewport = viewportSize
        } else { viewport = CGSize(width: 390, height: 500) }
        guard viewport.width >= 64, viewport.height >= 64 else {
            return unknown("The comparison viewport is too small. Expand the window and check again.")
        }
        let scale = 320 / max(viewport.width, viewport.height)
        let width = Int((viewport.width * scale).rounded())
        let height = Int((viewport.height * scale).rounded())
        guard width >= 64, height >= 64, width <= 320, height <= 320 else {
            return unknown("The comparison viewport is too narrow. Expand the window and check again.")
        }

        let quad = PaperQuadrilateral(topLeft: CGPoint(x: 0.22, y: 0.12),
                                      topRight: CGPoint(x: 0.78, y: 0.12),
                                      bottomRight: CGPoint(x: 0.78, y: 0.88),
                                      bottomLeft: CGPoint(x: 0.22, y: 0.88))
        // Action 2's reopened boundary is identical to an untouched flat sheet.
        // Actions 3–6 deliberately show the prior shape, exercising adjustment
        // feedback instead of approving every visible simulator sample.
        let renderedState = action == 2 ? 0 : action - 1
        guard let outline = DartOutlineChecker.outline(state: renderedState),
              let registration = PaperRegistration(quadrilateral: quad) else {
            return unknown("This generated paper state is unavailable. Use the 3D reference.")
        }
        let projected = outline.compactMap(registration.map)
        guard projected.count == outline.count else { return unknown("This generated paper outline cannot be projected.") }
        var pixels = [UInt8](repeating: 25, count: width * height)
        if sheetVisible {
            for row in 0..<height {
                for column in 0..<width {
                    // Same edge-coordinate convention as camera grayscale and
                    // the checker: pixel (i,j) has center ((i+.5)/W,(j+.5)/H).
                    let point = CGPoint(x: (Double(column) + 0.5) / Double(width),
                                        y: (Double(row) + 0.5) / Double(height))
                    if contains(point, polygon: projected) { pixels[row * width + column] = 245 }
                }
            }
        }
        let image = PaperLuminanceImage(width: width, height: height, pixels: pixels)
        let pose = sheetVisible ? quad : nil
        let checked = DartOutlineChecker.evaluate(image: image, pose: pose, state: action, timestamp: timestamp)
        let finishedAt = now ?? ProcessInfo.processInfo.systemUptime
        guard isFresh(finishedAt) else {
            return unknown("This generated comparison took too long. Check again.")
        }
        let scoped = DartOutlineCheckResult(checkpointID: checked.checkpointID,
                                            referenceState: checked.referenceState, outcome: checked.outcome,
                                            message: "Synthetic comparison. \(checked.message)",
                                            mismatchedPoints: checked.mismatchedPoints, timestamp: checked.timestamp)
        let snapshot = DartCheckSnapshot(image: image, result: scoped, rawSheetQuadrilateral: pose,
                                         displayTransform: .identity, viewportSize: viewport,
                                         isSynthetic: true, now: finishedAt)
        return DartPracticeSyntheticComparison(result: scoped, snapshot: snapshot)
    }

    /// Rasterization uses an independent ray crossing test; it does not copy
    /// the checker's convex inside/outside implementation or invent outcomes.
    private static func contains(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        var inside = false
        var previous = polygon.count - 1
        for index in polygon.indices {
            let a = polygon[index], b = polygon[previous]
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            previous = index
        }
        return inside
    }
}
#endif
