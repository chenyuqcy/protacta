import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Vision

struct PrintedPaperPose {
    /// The original A4 sheet, in raw image top-left normalized coordinates.
    /// Corner identity comes from the printed IDs; never sort these by screen.
    let quadrilateral: PaperQuadrilateral
    let markerQuads: [String: PaperQuadrilateral]
    let timestamp: TimeInterval
}

struct PrintedPaperFrame {
    let generation: Int
    let timestamp: TimeInterval
    let pose: PrintedPaperPose?
    /// Same full-image coordinates as the pose, with no rotation or crop.
    let luminance: PaperLuminanceImage?
}

struct PrintedPaperMarkerObservation {
    let payload: String
    let quadrilateral: PaperQuadrilateral
}

/// QR decoding alone is not a hands-clear paper pose. Tests can independently
/// verify the printable artifact without bypassing the production hand gate.
struct PrintedPaperMarkerScan {
    let markers: [PrintedPaperMarkerObservation]
    let failure: String?
    var diagnostic: String = ""
}

enum PrintedPaperBarcodeRevision {
    case production, frameworkDefault, revision3, revision1
}

/// Intermediate results also support deterministic admission/cancellation tests.
struct PrintedPaperDetection {
    let markers: [PrintedPaperMarkerObservation]
    let handPoints: [CGPoint]
    let hasUncertainHand: Bool
    let luminance: PaperLuminanceImage?
    var failure: String? = nil
}

/// Registration for a specific printed practice sheet, not arbitrary paper.
/// Four marker centers establish a homography; their independently measured
/// corners must also agree with the projected 14 mm code squares.
struct PrintedPaperRegistration {
    static let markerIDs = ["PTC1A", "PTC1B", "PTC1C", "PTC1D"]
    static let markerCenters: [String: CGPoint] = [
        "PTC1A": CGPoint(x: 0.16, y: 0.72), "PTC1B": CGPoint(x: 0.84, y: 0.72),
        "PTC1C": CGPoint(x: 0.84, y: 0.94), "PTC1D": CGPoint(x: 0.16, y: 0.94)
    ]
    static let codeSize = CGSize(width: 14.0 / 210, height: 14.0 / 297)

    let quadrilateral: PaperQuadrilateral
    private let centerRegistration: PaperRegistration

    init?(markers: [String: PaperQuadrilateral]) {
        guard Set(markers.keys) == Set(Self.markerIDs) else { return nil }
        var centers: [CGPoint] = []
        for id in Self.markerIDs {
            guard let marker = markers[id], Self.isValidMarker(marker),
                  let center = Self.projectiveCenter(marker) else { return nil }
            centers.append(center)
        }
        let centerQuad = PaperQuadrilateral(topLeft: centers[0], topRight: centers[1],
                                            bottomRight: centers[2], bottomLeft: centers[3])
        guard let registration = PaperRegistration(quadrilateral: centerQuad) else { return nil }
        centerRegistration = registration
        let corners = PaperQuadrilateral.unit.points.compactMap { sheetPoint -> CGPoint? in
            registration.map(Self.centerCoordinates(sheetPoint))
        }
        guard corners.count == 4 else { return nil }
        let sheet = PaperQuadrilateral(topLeft: corners[0], topRight: corners[1],
                                       bottomRight: corners[2], bottomLeft: corners[3])
        guard sheet.isValid else { return nil }

        for id in Self.markerIDs {
            guard let center = Self.markerCenters[id], let marker = markers[id] else { return nil }
            let halfWidth = Self.codeSize.width / 2, halfHeight = Self.codeSize.height / 2
            let local = [CGPoint(x: center.x - halfWidth, y: center.y - halfHeight),
                         CGPoint(x: center.x + halfWidth, y: center.y - halfHeight),
                         CGPoint(x: center.x + halfWidth, y: center.y + halfHeight),
                         CGPoint(x: center.x - halfWidth, y: center.y + halfHeight)]
            let expected = local.compactMap { registration.map(Self.centerCoordinates($0)) }
            guard expected.count == 4, Self.matchesMeasuredCorners(marker.points, expected: expected) else { return nil }
        }
        quadrilateral = sheet
    }

    func map(sheetPoint: CGPoint) -> CGPoint? {
        centerRegistration.map(Self.centerCoordinates(sheetPoint))
    }

    private static func centerCoordinates(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - 0.16) / 0.68, y: (point.y - 0.72) / 0.22)
    }

    /// Generic PaperQuadrilateral rejects very small viewport targets, which is
    /// appropriate for a sheet but too restrictive for a 14 mm printed marker.
    private static func isValidMarker(_ marker: PaperQuadrilateral) -> Bool {
        let points = marker.points
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite &&
            (0...1).contains($0.x) && (0...1).contains($0.y) }) else { return false }
        var twiceArea: CGFloat = 0
        for index in 0..<4 {
            let a = points[index], b = points[(index + 1) % 4], c = points[(index + 2) % 4]
            let first = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let second = CGPoint(x: c.x - b.x, y: c.y - b.y)
            // Clockwise in top-left image coordinates. Reversed winding is a
            // reflection, not a permitted cyclic QR corner correspondence.
            guard hypot(first.x, first.y) > 0.001,
                  first.x * second.y - first.y * second.x > 1e-7 else { return false }
            twiceArea += a.x * b.y - b.x * a.y
        }
        return twiceArea > 2e-6
    }

    /// A projective image does not preserve the arithmetic mean of corners.
    /// Diagonal intersection does preserve the actual printed square's center.
    private static func projectiveCenter(_ marker: PaperQuadrilateral) -> CGPoint? {
        let p = marker.topLeft, q = marker.topRight
        let r = CGPoint(x: marker.bottomRight.x - p.x, y: marker.bottomRight.y - p.y)
        let s = CGPoint(x: marker.bottomLeft.x - q.x, y: marker.bottomLeft.y - q.y)
        let delta = CGPoint(x: q.x - p.x, y: q.y - p.y)
        let denominator = r.x * s.y - r.y * s.x
        guard denominator.isFinite, abs(denominator) > 1e-9 else { return nil }
        let t = (delta.x * s.y - delta.y * s.x) / denominator
        let u = (delta.x * r.y - delta.y * r.x) / denominator
        guard (0...1).contains(t), (0...1).contains(u) else { return nil }
        return CGPoint(x: p.x + t * r.x, y: p.y + t * r.y)
    }

    private static func matchesMeasuredCorners(_ measured: [CGPoint], expected: [CGPoint]) -> Bool {
        let expectedEdges = (0..<4).map { distance(expected[$0], expected[($0 + 1) % 4]) }
        let meanEdge = expectedEdges.reduce(0, +) / 4
        guard meanEdge.isFinite, meanEdge > 0.001 else { return false }
        // Vision may start at a different corner when the QR rotates. It must
        // still preserve the cyclic winding and the physical code dimensions.
        return (0..<4).contains { shift in
            let cycle = (0..<4).map { measured[($0 + shift) % 4] }
            let errors = zip(cycle, expected).map { distance($0.0, $0.1) }
            let rms = sqrt(errors.reduce(0) { $0 + $1 * $1 } / 4)
            guard rms <= meanEdge * 0.22, errors.allSatisfy({ $0 <= meanEdge * 0.35 }) else { return false }
            return (0..<4).allSatisfy { index in
                let ratio = distance(cycle[index], cycle[(index + 1) % 4]) / expectedEdges[index]
                return ratio.isFinite && (0.70...1.30).contains(ratio)
            }
        }
    }

    private static func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }
}

/// On-device QR-assisted practice paper tracking. At most one camera buffer is
/// retained for work, with accepted submissions at most four times per second.
final class PrintedPaperTracker: @unchecked Sendable {
    typealias Processor = (CVPixelBuffer) -> PrintedPaperDetection
    private let queue = DispatchQueue(label: "org.realitycore.protacta.printed-paper", qos: .userInitiated)
    private let lock = NSLock()
    private let minimumInterval: TimeInterval
    private let processor: Processor
    private var generation = 0
    private var revision: UInt64 = 0
    private var inFlight = false
    private var lastTimestamp = -TimeInterval.infinity

    init() {
        minimumInterval = 0.25
        processor = Self.detect
    }

    init(minimumInterval: TimeInterval, processor: @escaping Processor) {
        self.minimumInterval = max(0, minimumInterval)
        self.processor = processor
    }

    func reset(generation: Int) {
        lock.lock()
        self.generation = generation
        revision &+= 1
        lastTimestamp = -.infinity
        // Old work retains its slot until it finishes; resets cannot accumulate
        // additional camera buffers or admit an old result into a new session.
        lock.unlock()
    }

    func submit(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval, generation: Int,
                completion: @escaping (PrintedPaperFrame) -> Void) {
        let process = processor
        enqueue(timestamp: timestamp, generation: generation,
                process: { process(pixelBuffer) }, completion: completion)
    }

    /// Real Vision integration on generated fixtures, without a camera session.
    func submit(cgImage: CGImage, timestamp: TimeInterval, generation: Int,
                completion: @escaping (PrintedPaperFrame) -> Void) {
        enqueue(timestamp: timestamp, generation: generation,
                process: { Self.detect(cgImage) }, completion: completion)
    }

    private func enqueue(timestamp: TimeInterval, generation: Int,
                         process: @escaping () -> PrintedPaperDetection,
                         completion: @escaping (PrintedPaperFrame) -> Void) {
        guard timestamp.isFinite, timestamp >= 0 else { return }
        lock.lock()
        guard generation == self.generation, !inFlight,
              timestamp - lastTimestamp >= minimumInterval else { lock.unlock(); return }
        inFlight = true
        lastTimestamp = timestamp
        let submittedRevision = revision
        lock.unlock()
        queue.async { [weak self] in
            let detection = autoreleasepool { process() }
            guard let self else { return }
            self.lock.lock()
            self.inFlight = false
            let current = generation == self.generation && submittedRevision == self.revision
            self.lock.unlock()
            guard current else { return }
            let pose = Self.makePose(detection: detection, timestamp: timestamp)
            completion(PrintedPaperFrame(generation: generation, timestamp: timestamp,
                                         pose: pose, luminance: detection.luminance))
        }
    }

    static func makePose(detection: PrintedPaperDetection, timestamp: TimeInterval) -> PrintedPaperPose? {
        guard timestamp.isFinite, timestamp >= 0, !detection.hasUncertainHand else { return nil }
        var markers: [String: PaperQuadrilateral] = [:]
        let known = Set(PrintedPaperRegistration.markerIDs)
        for marker in detection.markers where known.contains(marker.payload) {
            guard markers[marker.payload] == nil else { return nil }
            markers[marker.payload] = marker.quadrilateral
        }
        guard let registration = PrintedPaperRegistration(markers: markers),
              !detection.handPoints.contains(where: { insideOrNear($0, quad: registration.quadrilateral) }) else { return nil }
        return PrintedPaperPose(quadrilateral: registration.quadrilateral,
                                markerQuads: markers, timestamp: timestamp)
    }

    private static func detect(_ buffer: CVPixelBuffer) -> PrintedPaperDetection {
        detect(handler: VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:]),
               luminance: luminanceImage(pixelBuffer: buffer))
    }

    private static func detect(_ image: CGImage) -> PrintedPaperDetection {
        // Use the same input format and request path as the live camera, rather
        // than relying on different CGImage inference/color-conversion behavior.
        guard let buffer = pixelBuffer(cgImage: image) else {
            return PrintedPaperDetection(markers: [], handPoints: [], hasUncertainHand: true,
                                          luminance: nil, failure: "CGImage normalization failed")
        }
        return detect(buffer)
    }

    /// On-device diagnostics for native image fixtures. No pixels or diagnostic
    /// data are uploaded or persisted by the tracker.
    static func analysis(cgImage: CGImage) -> PrintedPaperDetection { detect(cgImage) }

    static func markerAnalysis(cgImage: CGImage,
                               revision: PrintedPaperBarcodeRevision = .production,
                               preferSupportedCPU: Bool? = nil) -> PrintedPaperMarkerScan {
        guard let buffer = pixelBuffer(cgImage: cgImage) else {
            return PrintedPaperMarkerScan(markers: [], failure: "CGImage normalization failed")
        }
        return scanMarkers(handler: VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:]),
                            revision: revision, preferSupportedCPU: preferSupportedCPU)
    }

    private static func detect(handler: VNImageRequestHandler,
                               luminance: PaperLuminanceImage?) -> PrintedPaperDetection {
        let scan = scanMarkers(handler: handler)
        guard scan.failure == nil else {
            return PrintedPaperDetection(markers: scan.markers, handPoints: [],
                                          hasUncertainHand: true, luminance: luminance, failure: scan.failure)
        }
        let hands = VNDetectHumanHandPoseRequest()
        hands.maximumHandCount = 2
        do {
            // Separate calls identify the failing inference stage. A working QR
            // decoder never implies that hand assessment is available or clear.
            try handler.perform([hands])
            var handPoints: [CGPoint] = []
            var uncertain = false
            for hand in hands.results ?? [] {
                let joints = try hand.recognizedPoints(.all).values.filter { $0.confidence >= 0.3 }
                if joints.isEmpty { uncertain = true }
                handPoints += joints.map { CGPoint(x: $0.location.x, y: 1 - $0.location.y) }
            }
            return PrintedPaperDetection(markers: scan.markers, handPoints: handPoints,
                                          hasUncertainHand: uncertain, luminance: luminance)
        } catch {
            let error = error as NSError
            return PrintedPaperDetection(markers: scan.markers, handPoints: [],
                                          hasUncertainHand: true, luminance: luminance,
                                          failure: "Hand assessment failed [\(error.domain):\(error.code)]: \(error.localizedDescription)")
        }
    }

    private static func scanMarkers(handler: VNImageRequestHandler,
                                     revision: PrintedPaperBarcodeRevision = .production,
                                     preferSupportedCPU: Bool? = nil) -> PrintedPaperMarkerScan {
        let codes = VNDetectBarcodesRequest()
        switch revision {
        case .production:
            #if targetEnvironment(simulator)
            // On the tested iOS simulator, revisions 4 and 3 decoded none of
            // the independently rendered valid QR fixtures; revision 1 decoded
            // all four and passed physical marker validation. This is a
            // simulator compatibility algorithm, not device-accuracy evidence.
            codes.revision = VNDetectBarcodesRequestRevision1
            #endif
        case .frameworkDefault: break
        case .revision3: codes.revision = VNDetectBarcodesRequestRevision3
        case .revision1: codes.revision = VNDetectBarcodesRequestRevision1
        }
        codes.symbologies = [.qr]
        let computeDetails: String
        #if targetEnvironment(simulator)
        // Choose only a CPU reported as supported by the configured request.
        // Device builds keep Apple's default barcode revision and automatic
        // hardware selection; simulator acceptance does not validate that path.
        let selectCPU = preferSupportedCPU ?? true
        #else
        let selectCPU = preferSupportedCPU ?? false
        #endif
        if selectCPU || preferSupportedCPU != nil {
            do {
                let devices = try codes.supportedComputeStageDevices
                let main = devices[.main] ?? []
                let cpu = main.first { device in
                    if case .cpu = device { return true }
                    return false
                }
                if selectCPU, let cpu { codes.setComputeDevice(cpu, for: .main) }
                computeDetails = "main devices=\(main.map { String(describing: $0) }.joined(separator: ",")); selected supported CPU=\(selectCPU && cpu != nil)"
            } catch {
                computeDetails = "compute-device query failed: \(error.localizedDescription)"
            }
        } else {
            computeDetails = "device automatic compute selection"
        }
        do {
            try handler.perform([codes])
            let markers = (codes.results ?? []).compactMap { observation -> PrintedPaperMarkerObservation? in
                guard let payload = observation.payloadStringValue else { return nil }
                func topLeft(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: 1 - point.y) }
                return PrintedPaperMarkerObservation(payload: payload, quadrilateral: PaperQuadrilateral(
                    topLeft: topLeft(observation.topLeft), topRight: topLeft(observation.topRight),
                    bottomRight: topLeft(observation.bottomRight), bottomLeft: topLeft(observation.bottomLeft)))
            }
            return PrintedPaperMarkerScan(markers: markers, failure: nil,
                                           diagnostic: "revision=\(codes.revision); \(computeDetails)")
        } catch {
            let error = error as NSError
            return PrintedPaperMarkerScan(markers: [],
                                           failure: "QR detection revision \(codes.revision) failed [\(error.domain):\(error.code)]: \(error.localizedDescription); \(computeDetails)")
        }
    }

    /// Direct camera row copying avoids introducing a second orientation change.
    static func luminanceImage(pixelBuffer: CVPixelBuffer, maximumDimension: Int = 320) -> PaperLuminanceImage? {
        let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0, maximumDimension > 0 else { return nil }
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let base: UnsafeMutableRawPointer
        let stride: Int
        let components: Int
        let videoRange: Bool
        switch format {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 1,
                  let address = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
            base = address; stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0); components = 1
            videoRange = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        case kCVPixelFormatType_OneComponent8:
            guard let address = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
            base = address; stride = CVPixelBufferGetBytesPerRow(pixelBuffer); components = 1; videoRange = false
        case kCVPixelFormatType_32BGRA:
            guard let address = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
            base = address; stride = CVPixelBufferGetBytesPerRow(pixelBuffer); components = 4; videoRange = false
        default: return nil
        }
        let scale = min(1, Double(maximumDimension) / Double(max(width, height)))
        let targetWidth = max(1, Int((Double(width) * scale).rounded()))
        let targetHeight = max(1, Int((Double(height) * scale).rounded()))
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var pixels = [UInt8](repeating: 0, count: targetWidth * targetHeight)
        for y in 0..<targetHeight {
            let sourceY = min(height - 1, Int((Double(y) + 0.5) * Double(height) / Double(targetHeight)))
            for x in 0..<targetWidth {
                let sourceX = min(width - 1, Int((Double(x) + 0.5) * Double(width) / Double(targetWidth)))
                let offset = sourceY * stride + sourceX * components
                let value: Int
                if components == 4 {
                    value = (77 * Int(bytes[offset + 2]) + 150 * Int(bytes[offset + 1]) + 29 * Int(bytes[offset])) >> 8
                } else if videoRange {
                    value = max(0, min(255, (Int(bytes[offset]) - 16) * 255 / 219))
                } else { value = Int(bytes[offset]) }
                pixels[y * targetWidth + x] = UInt8(value)
            }
        }
        return PaperLuminanceImage(width: targetWidth, height: targetHeight, pixels: pixels)
    }

    static func luminanceImage(cgImage: CGImage, maximumDimension: Int = 320) -> PaperLuminanceImage? {
        guard maximumDimension > 0, let buffer = pixelBuffer(cgImage: cgImage) else { return nil }
        return luminanceImage(pixelBuffer: buffer, maximumDimension: maximumDimension)
    }

    static func pixelBuffer(cgImage: CGImage) -> CVPixelBuffer? {
        guard cgImage.width > 0, cgImage.height > 0 else { return nil }
        // Normalize arbitrary CGImage color formats into explicit top-to-bottom
        // BGRA rows, then use the exact camera downsampling path above.
        var optional: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, cgImage.width, cgImage.height,
                                  kCVPixelFormatType_32BGRA,
                                  [kCVPixelBufferCGImageCompatibilityKey: true,
                                   kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
                                  &optional) == kCVReturnSuccess, let buffer = optional else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(data: base, width: cgImage.width, height: cgImage.height,
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return nil
        }
        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    private static func insideOrNear(_ point: CGPoint, quad: PaperQuadrilateral) -> Bool {
        guard point.x.isFinite, point.y.isFinite else { return true }
        var positive = false, negative = false
        let points = quad.points
        for index in 0..<4 {
            let a = points[index], b = points[(index + 1) % 4]
            let dx = b.x - a.x, dy = b.y - a.y
            let cross = dx * (point.y - a.y) - dy * (point.x - a.x)
            let margin = CGFloat(0.025) * hypot(dx, dy)
            if cross > margin { positive = true }
            if cross < -margin { negative = true }
        }
        return !(positive && negative)
    }
}
