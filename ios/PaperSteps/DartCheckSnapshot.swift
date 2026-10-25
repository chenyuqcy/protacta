import CoreGraphics
import CoreFoundation
import Foundation

/// Ephemeral image and comparison geometry from one accepted camera frame.
/// This value never saves a photo or claims that a fold was verified. Its raw
/// raster starts at the top-left; the frozen display transform is applied once
/// by the presentation layer, without reordering semantic paper corners.
struct DartCheckSnapshot: Identifiable {
    let id: UUID
    let cgImage: CGImage
    let action: Int
    let result: DartOutlineCheckResult
    let capturedUptime: TimeInterval
    let rawSheetQuadrilateral: PaperQuadrilateral?
    let displayTransform: CGAffineTransform
    let viewportSize: CGSize
    let isSynthetic: Bool
    let outlineViewportPoints: [CGPoint]
    let mismatchViewportPoints: [CGPoint]

    private let registration: PaperRegistration?

    init?(image: PaperLuminanceImage, result: DartOutlineCheckResult,
          rawSheetQuadrilateral: PaperQuadrilateral?, displayTransform: CGAffineTransform,
          viewportSize: CGSize, isSynthetic: Bool,
          now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard (1...10).contains(result.referenceState),
              result.timestamp.isFinite, now.isFinite, result.timestamp >= 0,
              now >= result.timestamp,
              now - result.timestamp <= PaperGuideSession.maximumObservationAge,
              image.width >= 64, image.height >= 64, image.width <= 4096, image.height <= 4096,
              image.pixels.count == image.width * image.height,
              viewportSize.width.isFinite, viewportSize.height.isFinite,
              viewportSize.width > 0, viewportSize.height > 0,
              [displayTransform.a, displayTransform.b, displayTransform.c,
               displayTransform.d, displayTransform.tx, displayTransform.ty].allSatisfy(\.isFinite),
              !result.checkpointID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              result.checkpointID.utf8.count <= 512,
              !result.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              result.message.utf8.count <= 4_000,
              result.mismatchedPoints.count <= 64,
              result.mismatchedPoints.allSatisfy(Self.unitPoint),
              DartPracticeCourse.supportsOutlineCheck(state: result.referenceState) || result.outcome == .cannotJudge else { return nil }
        let determinant = displayTransform.a * displayTransform.d - displayTransform.b * displayTransform.c
        guard determinant.isFinite, abs(determinant) > 1e-12 else { return nil }

        let registration: PaperRegistration?
        if let quad = rawSheetQuadrilateral {
            guard quad.isValid, quad.points.allSatisfy(Self.unitPoint),
                  let candidate = PaperRegistration(quadrilateral: quad) else { return nil }
            registration = candidate
        } else {
            guard result.outcome == .cannotJudge, result.mismatchedPoints.isEmpty else { return nil }
            registration = nil
        }

        let outline = DartOutlineChecker.outline(state: result.referenceState) ?? []
        let outlineViewport: [CGPoint]
        let mismatchViewport: [CGPoint]
        if let registration {
            // The same frozen raw-frame mapping is used for both target outline
            // and mismatch points. Do not clamp a genuinely cropped guide.
            let mappedOutline = outline.compactMap {
                Self.viewportPoint($0, registration: registration, transform: displayTransform)
            }
            let mappedMismatches = result.mismatchedPoints.compactMap {
                Self.viewportPoint($0, registration: registration, transform: displayTransform)
            }
            guard mappedOutline.count == outline.count,
                  mappedMismatches.count == result.mismatchedPoints.count else { return nil }
            outlineViewport = mappedOutline
            mismatchViewport = mappedMismatches
        } else {
            outlineViewport = []
            mismatchViewport = []
        }

        // Data owns one copy of the input bytes. The CGImage's retained provider
        // owns that data; no second luma array or CVPixelBuffer is kept here.
        let pixels = Data(image.pixels)
        guard let provider = CGDataProvider(data: pixels as CFData),
              let cgImage = CGImage(width: image.width, height: image.height,
                                    bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: image.width,
                                    space: CGColorSpaceCreateDeviceGray(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false,
                                    intent: .defaultIntent) else { return nil }
        id = UUID()
        self.cgImage = cgImage
        action = result.referenceState
        self.result = result
        capturedUptime = result.timestamp
        self.rawSheetQuadrilateral = rawSheetQuadrilateral
        self.displayTransform = displayTransform
        self.viewportSize = viewportSize
        self.isSynthetic = isSynthetic
        self.registration = registration
        outlineViewportPoints = outlineViewport
        mismatchViewportPoints = mismatchViewport
    }

    /// Normalized frozen viewport coordinates, not pixels in a resized sheet.
    func viewportPoint(forSheetPoint point: CGPoint) -> CGPoint? {
        guard let registration else { return nil }
        return Self.viewportPoint(point, registration: registration, transform: displayTransform)
    }

    private static func unitPoint(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite && (0...1).contains(point.x) && (0...1).contains(point.y)
    }

    private static func viewportPoint(_ point: CGPoint, registration: PaperRegistration,
                                      transform: CGAffineTransform) -> CGPoint? {
        guard unitPoint(point), let raw = registration.map(point) else { return nil }
        let displayed = raw.applying(transform)
        let tolerance: CGFloat = 0.000001
        guard displayed.x.isFinite, displayed.y.isFinite,
              (-tolerance...(1 + tolerance)).contains(displayed.x),
              (-tolerance...(1 + tolerance)).contains(displayed.y) else { return nil }
        // Only floating-point residue at a viewport boundary is clamped.
        return CGPoint(x: min(1, max(0, displayed.x)), y: min(1, max(0, displayed.y)))
    }
}
