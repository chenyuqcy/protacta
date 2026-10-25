import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Vision

/// Rectangle candidates only. These observations do not identify paper, its
/// semantic direction, its fold state, or whether an instruction was completed.
struct PaperVisionObservation: Equatable {
    /// Raw captured-image coordinates, normalized with a lower-left origin.
    /// The order is Vision's top-left, top-right, bottom-right, bottom-left.
    let corners: [CGPoint]
    let confidence: Float
}

struct PaperVisionResult {
    let generation: Int
    let timestamp: TimeInterval
    let observation: PaperVisionObservation?
}

/// Fresh detections are intentionally used instead of keeping an old rectangle
/// alive through occlusion. At most one frame is retained for work and accepted
/// submissions are at least 125 ms apart. Completion runs on the worker queue;
/// the caller must apply generation, step, freshness and display-transform checks.
final class PaperVisionTracker: @unchecked Sendable {
    typealias Processor = (CVPixelBuffer) -> PaperVisionObservation?

    private let queue = DispatchQueue(label: "org.realitycore.protacta.paper-vision", qos: .userInitiated)
    private let lock = NSLock()
    private let minimumInterval: TimeInterval
    private let processor: Processor
    private var generation = 0
    private var revision: UInt64 = 0
    private var inFlight = false
    private var lastTimestamp = -TimeInterval.infinity

    init() {
        minimumInterval = 1.0 / 8.0
        processor = Self.detect
    }

    /// A deterministic processor can exercise queue admission and cancellation
    /// without pretending a synthetic test is physical-camera acceptance.
    init(minimumInterval: TimeInterval, processor: @escaping Processor) {
        self.minimumInterval = max(0, minimumInterval)
        self.processor = processor
    }

    func reset(generation: Int) {
        lock.lock()
        self.generation = generation
        revision &+= 1
        lastTimestamp = -.infinity
        // Keep the slot occupied until the old computation actually finishes.
        // Otherwise repeated resets could queue many retained camera buffers.
        lock.unlock()
    }

    func submit(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval, generation: Int,
                completion: @escaping (PaperVisionResult) -> Void) {
        guard timestamp.isFinite, timestamp >= 0 else { return }
        lock.lock()
        guard generation == self.generation, !inFlight,
              timestamp - lastTimestamp >= minimumInterval else {
            lock.unlock()
            return
        }
        inFlight = true
        lastTimestamp = timestamp
        let submittedRevision = revision
        lock.unlock()

        let process = processor
        queue.async { [weak self] in
            let observation = autoreleasepool { process(pixelBuffer) }
            guard let self else { return }
            self.lock.lock()
            self.inFlight = false
            let current = generation == self.generation && submittedRevision == self.revision
            self.lock.unlock()
            guard current else { return }
            completion(PaperVisionResult(generation: generation, timestamp: timestamp,
                                         observation: observation))
        }
    }

    private static func detect(_ pixelBuffer: CVPixelBuffer) -> PaperVisionObservation? {
        let rectangles = VNDetectRectanglesRequest()
        rectangles.maximumObservations = 4
        rectangles.minimumConfidence = 0.8
        rectangles.minimumSize = 0.18
        rectangles.minimumAspectRatio = 0.35
        rectangles.maximumAspectRatio = 1
        rectangles.quadratureTolerance = 30

        let hands = VNDetectHumanHandPoseRequest()
        hands.maximumHandCount = 2
        // .up deliberately leaves raw sensor orientation unchanged. Applying
        // both EXIF rotation here and ARFrame.displayTransform later would rotate
        // the guide twice.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .up, options: [:])
        do {
            try handler.perform([rectangles, hands])
            let candidates = (rectangles.results ?? []).map {
                PaperVisionObservation(corners: [$0.topLeft, $0.topRight, $0.bottomRight, $0.bottomLeft],
                                       confidence: $0.confidence)
            }
            var handPoints: [CGPoint] = []
            for hand in hands.results ?? [] {
                // Failure to read a detected hand is uncertainty, not permission
                // to show a guide through an unmeasured occluder.
                let joints = try hand.recognizedPoints(.all)
                let reliable = joints.values.filter { $0.confidence >= 0.3 }
                guard !reliable.isEmpty else { return nil }
                handPoints += reliable.map(\.location)
            }
            return selectObservation(candidates: candidates, handPoints: handPoints)
        } catch {
            // Vision or its on-device models may be unavailable. No old cue is
            // returned as a substitute and no image leaves the device.
            return nil
        }
    }

    /// Conservative candidate selection shared by live Vision and deterministic
    /// geometry fixtures. Hand landmarks only reject recognized overlap; this is
    /// not a guarantee that every hand or other occluder has been detected.
    static func selectObservation(candidates: [PaperVisionObservation],
                                  handPoints: [CGPoint]) -> PaperVisionObservation? {
        let valid = candidates.compactMap { observation -> (PaperVisionObservation, CGFloat)? in
            guard observation.confidence.isFinite, observation.confidence >= 0.8,
                  let area = validArea(observation.corners) else { return nil }
            return (observation, area)
        }.sorted { $0.1 > $1.1 }
        guard let first = valid.first else { return nil }
        // Similar sheets, nested rectangles or a nearby screen are ambiguous.
        // Selecting a different candidate silently would transfer orientation.
        if valid.count > 1, valid[1].1 >= first.1 * 0.6 { return nil }
        if handPoints.contains(where: { insideOrNear($0, polygon: first.0.corners) }) { return nil }
        return first.0
    }

    private static func validArea(_ points: [CGPoint]) -> CGFloat? {
        guard points.count == 4,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite &&
                  (0.005...0.995).contains($0.x) && (0.005...0.995).contains($0.y) }) else { return nil }
        var twiceArea: CGFloat = 0
        var sign: CGFloat = 0
        for i in 0..<4 {
            let a = points[i], b = points[(i + 1) % 4], c = points[(i + 2) % 4]
            let dx = b.x - a.x, dy = b.y - a.y
            guard dx * dx + dy * dy > 0.0025 else { return nil }
            let turn = dx * (c.y - b.y) - dy * (c.x - b.x)
            guard abs(turn) > 0.0001 else { return nil }
            if sign == 0 { sign = turn }
            guard turn * sign > 0 else { return nil }
            twiceArea += a.x * b.y - b.x * a.y
        }
        let area = abs(twiceArea) / 2
        guard (0.035...0.88).contains(area) else { return nil }
        return area
    }

    private static func insideOrNear(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard point.x.isFinite, point.y.isFinite else { return true }
        var hasPositive = false, hasNegative = false
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let dx = b.x - a.x, dy = b.y - a.y
            let cross = dx * (point.y - a.y) - dy * (point.x - a.x)
            let tolerance = CGFloat(0.025) * sqrt(dx * dx + dy * dy)
            if cross > tolerance { hasPositive = true }
            if cross < -tolerance { hasNegative = true }
        }
        return !(hasPositive && hasNegative)
    }
}
