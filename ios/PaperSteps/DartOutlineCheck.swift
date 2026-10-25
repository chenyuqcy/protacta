import CoreGraphics
import Foundation

enum PaperCheckOutcome: String, Codable {
    case visibleMatch, needsAdjustment, cannotJudge
}

struct DartOutlineCheckResult {
    let checkpointID: String
    let referenceState: Int
    let outcome: PaperCheckOutcome
    let message: String
    /// Unit original-sheet coordinates; the caller projects through its pose.
    let mismatchedPoints: [CGPoint]
    let timestamp: TimeInterval
}

/// Row-major 8-bit grayscale for the entire raw camera image. Coordinates are
/// top-left normalized; resizing is permitted, cropping or rotation is not.
struct PaperLuminanceImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    /// Vision's normalized coordinates describe image edges. Pixel (x,y) is
    /// centered at ((x + 0.5)/width, (y + 0.5)/height), including after the
    /// tracker's full-frame downsampling. Clamp only the outer half-pixel to
    /// its edge sample; do not shift every interior point onto an endpoint grid.
    func sample(at point: CGPoint) -> Double? {
        guard width > 0, height > 0, width <= 4096, height <= 4096,
              pixels.count == width * height,
              point.x.isFinite, point.y.isFinite,
              point.x >= 0, point.y >= 0, point.x <= 1, point.y <= 1 else { return nil }
        let x = min(Double(width - 1), max(0, Double(point.x) * Double(width) - 0.5))
        let y = min(Double(height - 1), max(0, Double(point.y) * Double(height) - 0.5))
        let left = Int(x), top = Int(y)
        let right = min(width - 1, left + 1), bottom = min(height - 1, top + 1)
        let dx = x - Double(left), dy = y - Double(top)
        let a = Double(pixels[top * width + left])
        let b = Double(pixels[top * width + right])
        let c = Double(pixels[bottom * width + left])
        let d = Double(pixels[bottom * width + right])
        return (a * (1 - dx) + b * dx) * (1 - dy) + (c * (1 - dx) + d * dx) * dy
    }
}

/// The JSON is also the printing generator's source. Keep the matrix box distinct
/// from its white quiet zone: Vision QR corners describe the matrix itself.
struct DartPracticePaperLayout: Codable {
    struct Size: Codable { let width: Double; let height: Double }
    struct Point: Codable { let x: Double; let y: Double }
    struct Marker: Codable { let payload: String; let center: Point }
    let schemaVersion: Int
    let layoutID: String
    let layoutRevision: Int
    let sheetSizeMM: Size
    let codeSideMM: Double
    let quietZoneMM: Double
    let markers: [Marker]

    static var bundled: DartPracticePaperLayout? {
        guard let url = Bundle.main.url(forResource: "DartPracticePaper", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let layout = try? JSONDecoder().decode(Self.self, from: data),
              layout.schemaVersion == 1,
              layout.layoutID == PrintedPaperRegistration.layoutID,
              layout.layoutRevision == PrintedPaperRegistration.layoutRevision,
              layout.markers.map(\.payload) == PrintedPaperRegistration.markerIDs,
              abs(layout.sheetSizeMM.width - 210) < 0.001,
              abs(layout.sheetSizeMM.height - 297) < 0.001,
              abs(layout.codeSideMM - 14) < 0.001,
              abs(layout.quietZoneMM - 3) < 0.001,
              layout.markers.allSatisfy({ marker in
                  guard let center = PrintedPaperRegistration.markerCenters[marker.payload] else { return false }
                  return abs(marker.center.x - Double(center.x)) < 1e-10 &&
                      abs(marker.center.y - Double(center.y)) < 1e-10
              }) else { return nil }
        return layout
    }

    func isPrintedRegion(_ point: CGPoint) -> Bool {
        // An additional 1.5 mm keeps blur/edge antialiasing of printed ink out
        // of the silhouette test. It does not excuse arbitrary dark regions.
        let halfWidth = (codeSideMM / 2 + quietZoneMM + 1.5) / sheetSizeMM.width
        let halfHeight = (codeSideMM / 2 + quietZoneMM + 1.5) / sheetSizeMM.height
        return markers.contains {
            abs(Double(point.x) - $0.center.x) <= halfWidth &&
                abs(Double(point.y) - $0.center.y) <= halfHeight
        }
    }
}

/// Experimental, deliberately restricted visible-silhouette comparison. It
/// requires white practice paper on a dark plain mat, four-code registration,
/// no recognized hand overlap (enforced by the tracker), and a flat checkpoint.
/// Thresholds below are engineering starting points, not calibrated accuracy.
/// A white glove or hidden layer can be indistinguishable from white paper.
enum DartOutlineChecker {
    private struct Sample {
        let point: CGPoint
        let imagePoint: CGPoint
        let inside: Bool
        let edgeDistance: Double
        let luminance: Double
    }

    static func outline(state: Int) -> [CGPoint]? {
        guard [0, 2, 3, 4, 5, 6].contains(state) else { return nil }
        let vertices = PaperGeometry.frame(step: state, progress: 1).faces.flatMap(\.vertices)
        let points = vertices.map { vertex in
            CGPoint(x: Double(vertex.position.x / PaperGeometry.width + 0.5),
                    y: Double(vertex.position.z / PaperGeometry.height + 0.5))
        }
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite &&
            (-0.0001...1.0001).contains(Double($0.x)) &&
            (-0.0001...1.0001).contains(Double($0.y)) }) else { return nil }
        return convexHull(points.map { CGPoint(x: min(1, max(0, $0.x)), y: min(1, max(0, $0.y))) })
    }

    static func evaluate(image: PaperLuminanceImage, pose: PaperQuadrilateral?,
                         state: Int, timestamp: TimeInterval) -> DartOutlineCheckResult {
        func result(_ outcome: PaperCheckOutcome, _ message: String,
                    _ points: [CGPoint] = []) -> DartOutlineCheckResult {
            DartOutlineCheckResult(checkpointID: "dart-visible-outline-\(state)-v1", referenceState: state,
                                   outcome: outcome, message: message,
                                   mismatchedPoints: points, timestamp: timestamp)
        }
        guard let polygon = outline(state: state) else {
            return result(.cannotJudge, "Use the 3D reference for this step. This check does not judge lifted paper, wings or hidden layers.")
        }
        guard timestamp.isFinite, timestamp >= 0, image.width >= 64, image.height >= 64,
              image.width <= 4096, image.height <= 4096,
              image.pixels.count == image.width * image.height else {
            return result(.cannotJudge, "The camera image is not ready. Keep the paper flat and try again.")
        }
        guard let pose, pose.isValid, let registration = PaperRegistration(quadrilateral: pose) else {
            return result(.cannotJudge, "Scan all four printed codes on the practice paper and keep the sheet flat.")
        }
        guard let layout = DartPracticePaperLayout.bundled else {
            return result(.cannotJudge, "The practice-paper layout is unavailable. Use the 3D reference.")
        }

        // The whole original sheet coordinate frame plus a dark outer margin
        // must be in view. A partial frame must not be stretched into a pass.
        let marginCorners = [CGPoint(x: -0.04, y: -0.035), CGPoint(x: 1.04, y: -0.035),
                             CGPoint(x: 1.04, y: 1.035), CGPoint(x: -0.04, y: 1.035)]
        guard marginCorners.allSatisfy({ point in
            guard let p = registration.map(point) else { return false }
            return p.x >= 0.01 && p.y >= 0.01 && p.x <= 0.99 && p.y <= 0.99
        }) else {
            return result(.cannotJudge, "Move the camera back so the full practice sheet and a dark margin are visible.")
        }
        let pixelEdges = pose.points.indices.map { index -> Double in
            let a = pose.points[index], b = pose.points[(index + 1) % 4]
            return hypot(Double(b.x - a.x) * Double(image.width),
                         Double(b.y - a.y) * Double(image.height))
        }
        guard pixelEdges.allSatisfy({ $0 >= 48 }) else {
            return result(.cannotJudge, "Bring the camera closer while keeping the whole practice sheet in view.")
        }

        var samples: [Sample] = []
        var background: [Double] = []
        for row in 0..<77 {
            let y = -0.035 + Double(row) * 1.07 / 76
            for column in 0..<55 {
                let x = -0.04 + Double(column) * 1.08 / 54
                let point = CGPoint(x: x, y: y)
                guard !layout.isPrintedRegion(point),
                      let mapped = registration.map(point),
                      let luminance = image.sample(at: mapped) else { continue }
                let distance = distanceToEdges(point, polygon: polygon)
                // Boundary pixels, folds and anti-aliasing do not make reliable
                // inside/outside samples at this downsampled resolution.
                guard distance >= 0.014 else { continue }
                let inside = contains(point, polygon: polygon)
                samples.append(Sample(point: point, imagePoint: mapped, inside: inside,
                                      edgeDistance: distance, luminance: luminance))
                if x < -0.015 || x > 1.015 || y < -0.015 || y > 1.015 {
                    background.append(luminance)
                }
            }
        }
        let interior = samples.filter(\.inside)
        let exterior = samples.filter { !$0.inside }
        guard interior.count >= 100, exterior.count >= 60, background.count >= 40 else {
            return result(.cannotJudge, "There is not enough visible paper and background to compare this outline.")
        }
        let white = percentile(interior.map(\.luminance), 0.5)
        let dark = percentile(background, 0.85)
        let contrast = white - dark
        guard white >= 185, dark <= 110, contrast >= 90 else {
            return result(.cannotJudge, "Use white practice paper on a dark plain mat with even lighting, then try again.")
        }
        let whiteThreshold = white - max(25, contrast * 0.18)
        let darkThreshold = dark + max(20, contrast * 0.15)
        let ambiguous = interior.filter { $0.luminance > darkThreshold && $0.luminance < whiteThreshold }
        let ambiguousExterior = exterior.filter {
            $0.luminance > darkThreshold && $0.luminance < whiteThreshold &&
                !isBilinearBoundary(at: $0.imagePoint, in: image,
                                    darkThreshold: darkThreshold, whiteThreshold: whiteThreshold)
        }
        let bright = interior.filter { $0.luminance >= whiteThreshold }
        guard Double(bright.count) / Double(interior.count) >= 0.65,
              Double(ambiguous.count) / Double(interior.count) <= 0.06 else {
            return result(.cannotJudge, "The paper has shadows, an obstruction or unclear contrast. Clear your hands, improve the view and try again.")
        }
        // An expected-empty corner that looks gray is not evidence of dark
        // background. Otherwise shadowing an unfolded corner could erase both
        // the 'extra white paper' error and all ambiguity, falsely matching the
        // folded silhouette. The same 3.5% exterior allowance used for bright
        // mismatches bounds ignored noise; larger unclear regions are unknown.
        // Bilinear interpolation across a sharp paper/mat boundary is the one
        // exception: all four contributing native pixels must already be
        // settled white or dark, with both present. This excuses at most a
        // one-pixel interpolation footprint, not a gray/shadowed image region.
        guard Double(ambiguousExterior.count) / Double(exterior.count) <= 0.035 else {
            return result(.cannotJudge, "The outline's surrounding area is unclear or shadowed. Clear the sheet, use even lighting and a plain dark mat, then try again.")
        }
        let deepDark = interior.filter { $0.edgeDistance > 0.07 && $0.luminance <= darkThreshold }
        guard Double(deepDark.count) / Double(interior.count) <= 0.025 else {
            return result(.cannotJudge, "Part of the paper is obscured or unclear. Clear the sheet and compare its outline again.")
        }

        let missing = interior.filter { $0.luminance <= darkThreshold }
        let extra = exterior.filter { $0.luminance >= whiteThreshold }
        let missingRatio = Double(missing.count) / Double(interior.count)
        let extraRatio = Double(extra.count) / Double(exterior.count)
        if missingRatio <= 0.035 && extraRatio <= 0.035 {
            let message: String
            if state == 2 {
                message = "The visible outer outline matches. Check the center crease yourself; an outline cannot verify that crease or hidden layers."
            } else if state == 0 {
                message = "The visible outline matches a flat A4 sheet. This checks the outer shape only, not completed folds."
            } else {
                message = "The visible outline matches this reference. Check the crease and layers yourself before choosing the next step."
            }
            return result(.visibleMatch, message)
        }

        let mismatches = (missing + extra).map(\.point).filter {
            (0...1).contains($0.x) && (0...1).contains($0.y)
        }
        let stride = max(1, mismatches.count / 24)
        let highlights = mismatches.enumerated().compactMap { index, point in index % stride == 0 ? point : nil }
        let focus: String
        switch state {
        case 3: focus = "the upper-left edge"
        case 4: focus = "the two upper edges"
        case 5: focus = "the long left sloping edge"
        case 6: focus = "the two long sloping edges"
        default: focus = "the sheet's outer edges"
        }
        return result(.needsAdjustment,
                      "The visible outline differs near the highlighted points. Clear your hands, compare \(focus) with the 3D reference, and check again.",
                      Array(highlights.prefix(24)))
    }

    private static func isBilinearBoundary(at point: CGPoint, in image: PaperLuminanceImage,
                                           darkThreshold: Double, whiteThreshold: Double) -> Bool {
        // evaluate() has validated the image and mapped point before storing
        // a sample. Use the same edge-based pixel-center convention as sample.
        let x = min(Double(image.width - 1), max(0, Double(point.x) * Double(image.width) - 0.5))
        let y = min(Double(image.height - 1), max(0, Double(point.y) * Double(image.height) - 0.5))
        let left = Int(x), top = Int(y)
        let right = min(image.width - 1, left + 1), bottom = min(image.height - 1, top + 1)
        let values = [image.pixels[top * image.width + left], image.pixels[top * image.width + right],
                      image.pixels[bottom * image.width + left], image.pixels[bottom * image.width + right]].map(Double.init)
        return values.contains(where: { $0 <= darkThreshold }) &&
            values.contains(where: { $0 >= whiteThreshold }) &&
            values.allSatisfy { $0 <= darkThreshold || $0 >= whiteThreshold }
    }

    private static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * fraction)))]
    }

    private static func contains(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        var positive = false, negative = false
        for index in polygon.indices {
            let cross = turn(polygon[index], polygon[(index + 1) % polygon.count], point)
            if cross > 1e-10 { positive = true }
            if cross < -1e-10 { negative = true }
        }
        return !(positive && negative)
    }

    private static func distanceToEdges(_ point: CGPoint, polygon: [CGPoint]) -> Double {
        polygon.indices.map { index in
            let a = polygon[index], b = polygon[(index + 1) % polygon.count]
            let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
            let lengthSquared = dx * dx + dy * dy
            let amount = min(1, max(0, (Double(point.x - a.x) * dx + Double(point.y - a.y) * dy) / lengthSquared))
            return hypot(Double(point.x - a.x) - amount * dx, Double(point.y - a.y) - amount * dy)
        }.min() ?? 0
    }

    private static func turn(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
        Double(b.x - a.x) * Double(c.y - a.y) - Double(b.y - a.y) * Double(c.x - a.x)
    }

    private static func convexHull(_ points: [CGPoint]) -> [CGPoint]? {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        var unique: [CGPoint] = []
        for point in sorted where unique.last.map({ hypot(Double($0.x - point.x), Double($0.y - point.y)) > 1e-6 }) ?? true {
            unique.append(point)
        }
        guard unique.count >= 3 else { return nil }
        var lower: [CGPoint] = [], upper: [CGPoint] = []
        for point in unique {
            while lower.count >= 2 && redundantTurn(lower[lower.count - 2], lower[lower.count - 1], point) { lower.removeLast() }
            lower.append(point)
        }
        for point in unique.reversed() {
            while upper.count >= 2 && redundantTurn(upper[upper.count - 2], upper[upper.count - 1], point) { upper.removeLast() }
            upper.append(point)
        }
        lower.removeLast(); upper.removeLast()
        let hull = lower + upper
        return hull.count >= 3 ? hull : nil
    }

    private static func redundantTurn(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        // PaperGeometry uses Float rotations. At steps 5/6 a source crease
        // intersection is mathematically on the final sloping edge, but arrives
        // about 4e-8 sheet units off it. Remove collinear points using a distance
        // tolerance (1e-6 sheet units, under 0.0003 mm), not a fixed cross-product
        // threshold whose units depend on edge length. Genuine shape corners
        // remain many orders of magnitude larger than this numerical tolerance.
        let chord = hypot(Double(c.x - a.x), Double(c.y - a.y))
        return turn(a, b, c) <= 1e-6 * max(1e-6, chord)
    }
}
