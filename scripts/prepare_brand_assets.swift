import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Mechanical preparation of the supplied artwork: crop, fit and composite only.
// Run from the repository root with `swift scripts/prepare_brand_assets.swift`.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("docs/design/brand/ProtactaLogoSource.png")
let assetRoot = root.appendingPathComponent("ios/PaperSteps/Assets.xcassets")
let outputRoot = root.appendingPathComponent("output/intro-timeline-build25-2026-11-03/branding")
let fm = FileManager.default
try fm.createDirectory(at: outputRoot, withIntermediateDirectories: true)
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Cannot read supplied logo") }
let width = artwork.width, height = artwork.height
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                       bytesPerRow: width * 4, space: space,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
bitmap.draw(artwork, in: CGRect(x: 0, y: 0, width: width, height: height))
let bytes = bitmap.data!.assumingMemoryBound(to: UInt8.self)
func visible(_ x: Int, _ y: Int) -> Bool { bytes[(y * width + x) * 4 + 3] > 8 }
let occupied = (0..<width).map { x in (0..<height).contains { visible(x, $0) } }
var gaps: [Range<Int>] = []
var start: Int?
for x in 0...width {
    if x < width && !occupied[x] { if start == nil { start = x } }
    else if let low = start { gaps.append(low..<x); start = nil }
}
guard let gap = gaps.filter({ $0.count >= 40 && $0.lowerBound > width / 5 && $0.upperBound < width * 3 / 4 })
    .max(by: { $0.count < $1.count }) else { fatalError("No clear gap separates mark and wordmark") }
func bounds(xLimit: Int) -> CGRect {
    var minX = width, minY = height, maxX = -1, maxY = -1
    for y in 0..<height { for x in 0..<xLimit where visible(x, y) {
        minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
    } }
    precondition(maxX >= minX && maxY >= minY)
    return CGRect(x: max(0, minX - 2), y: max(0, minY - 2),
                  width: min(width - max(0, minX - 2), maxX - minX + 5),
                  height: min(height - max(0, minY - 2), maxY - minY + 5))
}
let markBounds = bounds(xLimit: gap.lowerBound)
let logoBounds = bounds(xLimit: width)
guard let mark = artwork.cropping(to: markBounds), let logo = artwork.cropping(to: logoBounds) else { fatalError("Crop failed") }

func context(_ w: Int, _ h: Int, opaque: Bool) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
              space: space, bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)!
}
func png(_ image: CGImage, _ url: URL) throws {
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("PNG export failed") }
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
}
func fit(_ image: CGImage, width targetWidth: Int) -> CGImage {
    let targetHeight = Int((Double(image.height) * Double(targetWidth) / Double(image.width)).rounded())
    let canvas = context(targetWidth, targetHeight, opaque: false)
    canvas.interpolationQuality = .high
    canvas.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    return canvas.makeImage()!
}
func imageSet(_ name: String, image: CGImage) throws {
    let folder = assetRoot.appendingPathComponent(name + ".imageset")
    try png(image, folder.appendingPathComponent("Logo.png"))
    let manifest: [String: Any] = ["images": [["filename": "Logo.png", "idiom": "universal"]],
                                   "info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        .write(to: folder.appendingPathComponent("Contents.json"))
}
try imageSet("ProtactaLogo", image: fit(logo, width: 1600))
try imageSet("ProtactaMark", image: fit(mark, width: 1024))
let icon = context(1024, 1024, opaque: true)
icon.setFillColor(CGColor(colorSpace: space, components: [0.97, 0.975, 0.975, 1])!)
icon.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
let scale = min(820 / Double(mark.width), 820 / Double(mark.height))
let iconWidth = Double(mark.width) * scale, iconHeight = Double(mark.height) * scale
icon.interpolationQuality = .high
icon.draw(mark, in: CGRect(x: (1024 - iconWidth) / 2, y: (1024 - iconHeight) / 2,
                          width: iconWidth, height: iconHeight))
let iconImage = icon.makeImage()!
try png(iconImage, assetRoot.appendingPathComponent("AppIcon.appiconset/AppIcon.png"))
try png(fit(iconImage, width: 256), outputRoot.appendingPathComponent("icon-preview.png"))
try png(fit(logo, width: 1000), outputRoot.appendingPathComponent("logo-preview.png"))
try png(fit(mark, width: 400), outputRoot.appendingPathComponent("mark-preview.png"))
let record: [String: Any] = [
    "source": "docs/design/brand/ProtactaLogoSource.png", "sourceSize": [width, height],
    "clearGapColumns": [gap.lowerBound, gap.upperBound],
    "markCrop": [markBounds.minX, markBounds.minY, markBounds.width, markBounds.height],
    "fullLogoCrop": [logoBounds.minX, logoBounds.minY, logoBounds.width, logoBounds.height],
    "iconSize": [1024, 1024], "iconHasAlpha": false,
    "iconArtworkRect": [(1024 - iconWidth) / 2, (1024 - iconHeight) / 2, iconWidth, iconHeight],
    "operation": "Exact supplied pixels, cropped at transparent gap, proportional resampling; opaque offwhite icon composite. No artwork redrawing."
]
try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
    .write(to: outputRoot.appendingPathComponent("asset-preparation.json"))
print(String(data: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), encoding: .utf8)!)
