import CoreGraphics
import CoreImage
import CoreVideo
import CryptoKit
import Foundation
import ImageIO

/// One explicitly requested local validation record. Human labels, annotations,
/// speech, device names and unique device identifiers are deliberately absent.
struct PracticeValidationSample: Codable {
    enum Source: String, Codable { case physicalCamera = "physical_camera", syntheticFixture = "synthetic_fixture" }
    enum Split: String, Codable { case development, evaluation }
    enum FrameDisposition: String, Codable { case fresh, expired }

    struct Point: Codable, Equatable {
        let x: Double
        let y: Double
        init(_ point: CGPoint) { x = Double(point.x); y = Double(point.y) }
        var cgPoint: CGPoint { CGPoint(x: x, y: y) }
    }

    struct Quadrilateral: Codable {
        let topLeft: Point
        let topRight: Point
        let bottomRight: Point
        let bottomLeft: Point
        init(_ quad: PaperQuadrilateral) {
            topLeft = Point(quad.topLeft); topRight = Point(quad.topRight)
            bottomRight = Point(quad.bottomRight); bottomLeft = Point(quad.bottomLeft)
        }
        var cgQuadrilateral: PaperQuadrilateral {
            PaperQuadrilateral(topLeft: topLeft.cgPoint, topRight: topRight.cgPoint,
                               bottomRight: bottomRight.cgPoint, bottomLeft: bottomLeft.cgPoint)
        }
    }

    struct Affine: Codable {
        let a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double
        init(_ transform: CGAffineTransform) {
            a = Double(transform.a); b = Double(transform.b); c = Double(transform.c)
            d = Double(transform.d); tx = Double(transform.tx); ty = Double(transform.ty)
        }
        var values: [Double] { [a, b, c, d, tx, ty] }
    }

    struct Image: Codable {
        let path: String
        let sha256: String?
        let width: Int
        let height: Int
        let orientation: String
    }

    struct Viewport: Codable {
        let width: Double
        let height: Double
        let orientation: String
        let rawToViewport: Affine
    }

    struct RegistrationPoint: Codable {
        let id: String
        let sheet: Point
    }

    struct Result: Codable {
        let outcome: PaperCheckOutcome
        let message: String
        let mismatchedPoints: [Point]
        let support: String
        let timestamp: TimeInterval
    }

    let schemaVersion: Int
    let id: String
    let source: Source
    let split: Split
    let sessionID: String
    let operatorID: String
    let sheetID: String
    let attemptID: String
    let originID: String
    /// Canonical original frame identity, including when derivatives are made.
    /// The actual file within this record is always image.path == "image.png".
    let sourceBasename: String
    let tutorialID: String
    let courseRevision: String
    let checkpointID: String
    let referenceState: Int
    let appVersion: String
    let appBuild: String
    let deviceModel: String?
    let osVersion: String?
    let capturedUptime: TimeInterval
    let processedUptime: TimeInterval
    let processingFailure: String?
    /// Explicit algorithm interval only; never inferred from frame age.
    let processingMs: Double?
    /// Capture-to-result/delivery age, which can include queueing time.
    let frameAgeMs: Double?
    let frameDisposition: FrameDisposition
    let image: Image
    let viewport: Viewport
    let rawSheetQuadrilateral: Quadrilateral?
    let markerQuadrilaterals: [String: Quadrilateral]
    let registrationPoints: [RegistrationPoint]
    let result: Result

    init(id: String = UUID().uuidString.lowercased(), source: Source, split: Split,
         sessionID: String, operatorID: String, sheetID: String, attemptID: String,
         originID: String, sourceBasename: String? = nil,
         tutorialID: String = "classic-dart", courseRevision: String,
         appVersion: String, appBuild: String, deviceModel: String? = nil, osVersion: String? = nil,
         capturedUptime: TimeInterval, processedUptime: TimeInterval,
         processingFailure: String? = nil,
         processingMs: Double? = nil, frameAgeMs: Double? = nil,
         frameDisposition: FrameDisposition = .fresh,
         imageWidth: Int, imageHeight: Int, viewportSize: CGSize, viewportOrientation: String,
         rawToViewport: CGAffineTransform, rawSheetQuadrilateral: PaperQuadrilateral?,
         markerQuadrilaterals: [String: PaperQuadrilateral], result: DartOutlineCheckResult) {
        schemaVersion = 1
        self.id = id
        self.source = source; self.split = split
        self.sessionID = sessionID; self.operatorID = operatorID; self.sheetID = sheetID
        self.attemptID = attemptID; self.originID = originID
        self.sourceBasename = sourceBasename ?? "\(id).png"
        self.tutorialID = tutorialID; self.courseRevision = courseRevision
        checkpointID = result.checkpointID; referenceState = result.referenceState
        self.appVersion = appVersion; self.appBuild = appBuild
        self.deviceModel = deviceModel; self.osVersion = osVersion
        self.capturedUptime = capturedUptime; self.processedUptime = processedUptime
        self.processingFailure = processingFailure
        self.processingMs = processingMs; self.frameAgeMs = frameAgeMs
        self.frameDisposition = frameDisposition
        image = Image(path: "image.png", sha256: nil, width: imageWidth, height: imageHeight,
                      orientation: "raw_top_left")
        viewport = Viewport(width: Double(viewportSize.width), height: Double(viewportSize.height),
                            orientation: viewportOrientation, rawToViewport: Affine(rawToViewport))
        self.rawSheetQuadrilateral = rawSheetQuadrilateral.map(Quadrilateral.init)
        self.markerQuadrilaterals = markerQuadrilaterals.mapValues(Quadrilateral.init)
        registrationPoints = Self.printedRegistrationPoints
        self.result = Result(outcome: result.outcome, message: result.message,
                             mismatchedPoints: result.mismatchedPoints.map(Point.init),
                             support: "visible_outline_only", timestamp: result.timestamp)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, source, split, sessionID, operatorID, sheetID, attemptID, originID, sourceBasename
        case tutorialID, courseRevision, checkpointID, referenceState, appVersion, appBuild, deviceModel, osVersion
        case capturedUptime, processedUptime, processingFailure, processingMs, frameAgeMs, frameDisposition, image, viewport
        case rawSheetQuadrilateral, markerQuadrilaterals, registrationPoints, result
    }

    func encode(to encoder: Swift.Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion); try values.encode(id, forKey: .id)
        try values.encode(source, forKey: .source); try values.encode(split, forKey: .split)
        try values.encode(sessionID, forKey: .sessionID); try values.encode(operatorID, forKey: .operatorID)
        try values.encode(sheetID, forKey: .sheetID); try values.encode(attemptID, forKey: .attemptID)
        try values.encode(originID, forKey: .originID); try values.encode(sourceBasename, forKey: .sourceBasename)
        try values.encode(tutorialID, forKey: .tutorialID); try values.encode(courseRevision, forKey: .courseRevision)
        try values.encode(checkpointID, forKey: .checkpointID); try values.encode(referenceState, forKey: .referenceState)
        try values.encode(appVersion, forKey: .appVersion); try values.encode(appBuild, forKey: .appBuild)
        try values.encodeIfPresent(deviceModel, forKey: .deviceModel); try values.encodeIfPresent(osVersion, forKey: .osVersion)
        try values.encode(capturedUptime, forKey: .capturedUptime); try values.encode(processedUptime, forKey: .processedUptime)
        try values.encodeIfPresent(processingFailure, forKey: .processingFailure)
        try values.encodeIfPresent(processingMs, forKey: .processingMs); try values.encodeIfPresent(frameAgeMs, forKey: .frameAgeMs)
        try values.encode(frameDisposition, forKey: .frameDisposition); try values.encode(image, forKey: .image)
        try values.encode(viewport, forKey: .viewport); try values.encode(rawSheetQuadrilateral, forKey: .rawSheetQuadrilateral)
        try values.encode(markerQuadrilaterals, forKey: .markerQuadrilaterals)
        try values.encode(registrationPoints, forKey: .registrationPoints); try values.encode(result, forKey: .result)
    }

    /// A new immutable record with the digest of the exact bytes written.
    fileprivate func withImageDigest(_ digest: String) throws -> PracticeValidationSample {
        // The type's synthesized Codable is the schema authority. Replacing the
        // digest through a local value avoids an enormous, divergent copy init.
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(self)
        var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
        var imageObject = object["image"] as? [String: Any] ?? [:]
        imageObject["sha256"] = digest
        object["image"] = imageObject
        return try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: object))
    }

    static var printedRegistrationPoints: [RegistrationPoint] {
        var points: [RegistrationPoint] = []
        let halfWidth = PrintedPaperRegistration.codeSize.width / 2
        let halfHeight = PrintedPaperRegistration.codeSize.height / 2
        for id in PrintedPaperRegistration.markerIDs {
            guard let center = PrintedPaperRegistration.markerCenters[id] else { continue }
            points.append(RegistrationPoint(id: "\(id).center", sheet: Point(center)))
            for (name, dx, dy) in [("topLeft", -halfWidth, -halfHeight),
                                   ("topRight", halfWidth, -halfHeight),
                                   ("bottomRight", halfWidth, halfHeight),
                                   ("bottomLeft", -halfWidth, halfHeight)] {
                points.append(RegistrationPoint(id: "\(id).\(name)",
                                                sheet: Point(CGPoint(x: center.x + dx, y: center.y + dy))))
            }
        }
        return points
    }

    fileprivate var isValidForExport: Bool {
        let ids = [sessionID, operatorID, sheetID, attemptID, originID]
        let allowedID = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        func identifier(_ value: String) -> Bool {
            !value.isEmpty && value != "." && value != ".." && value.utf8.count <= 80 && value.unicodeScalars.allSatisfy(allowedID.contains)
        }
        func shortText(_ value: String) -> Bool {
            !value.isEmpty && value.utf8.count <= 160 && !value.contains("\n") && !value.contains("\r")
        }
        guard schemaVersion == 1, UUID(uuidString: id) != nil,
              ids.allSatisfy(identifier), tutorialID == "classic-dart", shortText(courseRevision),
              shortText(checkpointID), (0...10).contains(referenceState),
              shortText(appVersion), shortText(appBuild),
              deviceModel.map(shortText) ?? true, osVersion.map(shortText) ?? true,
              sourceBasename.hasSuffix(".png"), sourceBasename.lowercased() != "image.png",
              sourceBasename.utf8.count <= 164,
              !sourceBasename.dropLast(4).isEmpty,
              sourceBasename.dropLast(4) != ".", sourceBasename.dropLast(4) != "..",
              sourceBasename.dropLast(4).unicodeScalars.allSatisfy(allowedID.contains),
              image.path == "image.png", image.orientation == "raw_top_left",
              image.width > 0, image.height > 0, image.width <= 16384, image.height <= 16384,
              viewport.width.isFinite, viewport.height.isFinite, viewport.width > 0, viewport.height > 0,
              ["portrait", "portraitUpsideDown", "landscapeLeft", "landscapeRight", "unknown"].contains(viewport.orientation),
              viewport.rawToViewport.values.allSatisfy(\.isFinite),
              capturedUptime.isFinite, processedUptime.isFinite, capturedUptime >= 0,
              processedUptime >= capturedUptime, result.timestamp == capturedUptime,
              result.support == "visible_outline_only", !result.message.isEmpty, result.message.utf8.count <= 4000,
              result.mismatchedPoints.count <= 64,
              result.mismatchedPoints.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { return false }
        let ageMs = (processedUptime - capturedUptime) * 1000
        if let processingMs, !processingMs.isFinite || processingMs < 0 || processingMs > ageMs + 0.001 { return false }
        if let frameAgeMs, !frameAgeMs.isFinite || frameAgeMs < ageMs - 0.001 { return false }
        if frameDisposition == .fresh && ageMs > PaperGuideSession.maximumObservationAge * 1000 + 0.001 { return false }
        if let frameAgeMs, frameDisposition == .fresh && frameAgeMs > PaperGuideSession.maximumObservationAge * 1000 + 0.001 { return false }
        if frameDisposition == .expired && result.outcome != .cannotJudge { return false }
        if let processingFailure, processingFailure.isEmpty || processingFailure.utf8.count > 2000 || result.outcome != .cannotJudge { return false }
        if !DartPracticeCourse.supportsOutlineCheck(state: referenceState) && result.outcome != .cannotJudge { return false }
        if rawSheetQuadrilateral == nil && result.outcome != .cannotJudge { return false }
        if let quad = rawSheetQuadrilateral, !quad.cgQuadrilateral.isValid { return false }
        let knownMarkers = Set(PrintedPaperRegistration.markerIDs)
        guard markerQuadrilaterals.keys.allSatisfy(knownMarkers.contains),
              markerQuadrilaterals.values.allSatisfy({ quad in
                  quad.cgQuadrilateral.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }
              }), registrationPoints.count == 20,
              registrationPoints.map(\.id) == Self.printedRegistrationPoints.map(\.id),
              zip(registrationPoints, Self.printedRegistrationPoints).allSatisfy({ $0.0.sheet == $0.1.sheet }) else { return false }
        let determinant = viewport.rawToViewport.a * viewport.rawToViewport.d - viewport.rawToViewport.b * viewport.rawToViewport.c
        return determinant.isFinite && abs(determinant) > 1e-12
    }
}

/// Explicit local save only. This service never starts a camera, takes a photo
/// by itself, uploads, shares or invents human labels. Completion runs on its
/// serial worker; the UI must apply its own generation/context checks.
final class PracticeValidationCapture: @unchecked Sendable {
    enum CaptureError: Error, Equatable, LocalizedError {
        case sourceNotAllowed, invalidSample, mismatchedFrame, imageConversionFailed
        case imageEncodingFailed, cancelled, outputAlreadyExists, fileWriteFailed
        var errorDescription: String? {
            switch self {
            case .sourceNotAllowed: return "This source cannot be saved as a physical camera sample."
            case .invalidSample: return "The validation metadata is incomplete or invalid."
            case .mismatchedFrame: return "The image does not match the processed frame."
            case .imageConversionFailed, .imageEncodingFailed: return "The local sample image could not be encoded."
            case .cancelled: return "The sample request was cancelled."
            case .outputAlreadyExists: return "This sample already exists."
            case .fileWriteFailed: return "The local sample could not be saved."
            }
        }
    }

    typealias Encoder = (CGImage) throws -> Data
    private let rootDirectory: URL?
    private let encoder: Encoder
    private let hasInjectedEncoder: Bool
    private let queue = DispatchQueue(label: "org.realitycore.protacta.validation-capture", qos: .utility)
    private let lock = NSLock()
    private var generation = 0
    private var revision: UInt64 = 0
    private var inFlight = false
    private lazy var imageContext = CIContext(options: [.cacheIntermediates: false])

    init(rootDirectory: URL? = nil, imageEncoder: Encoder? = nil) {
        self.rootDirectory = rootDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("ProtactaValidation", isDirectory: true)
        encoder = imageEncoder ?? Self.encodePNG
        hasInjectedEncoder = imageEncoder != nil
    }

    func reset(generation: Int) {
        lock.lock()
        self.generation = generation
        revision &+= 1
        // A cancelled request keeps its slot until its retained buffer is freed.
        lock.unlock()
    }

    /// False means busy/wrong generation and completion is not called. An
    /// admitted request completes once, including invalid metadata or denial.
    @discardableResult
    func save(pixelBuffer: CVPixelBuffer, sample: PracticeValidationSample,
              frameTimestamp: TimeInterval, generation: Int,
              completion: @escaping (Swift.Result<URL, Error>) -> Void) -> Bool {
        enqueue(sample: sample, frameTimestamp: frameTimestamp, generation: generation,
                dimensions: CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer)),
                physicalBuffer: true, makeImage: { [weak self] in
            guard let self else { return nil }
            let input = CIImage(cvPixelBuffer: pixelBuffer)
            return self.imageContext.createCGImage(input, from: input.extent,
                                                  format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        }, completion: completion)
    }

    /// Synthetic fixtures only. Physical exports must use the exact processed
    /// camera pixel buffer, never a substituted CGImage or UI screenshot.
    @discardableResult
    func save(cgImage: CGImage, sample: PracticeValidationSample,
              frameTimestamp: TimeInterval, generation: Int,
              completion: @escaping (Swift.Result<URL, Error>) -> Void) -> Bool {
        enqueue(sample: sample, frameTimestamp: frameTimestamp, generation: generation,
                dimensions: CGSize(width: cgImage.width, height: cgImage.height),
                physicalBuffer: false, makeImage: { cgImage }, completion: completion)
    }

    private func enqueue(sample: PracticeValidationSample, frameTimestamp: TimeInterval, generation: Int,
                         dimensions: CGSize, physicalBuffer: Bool, makeImage: @escaping () -> CGImage?,
                         completion: @escaping (Swift.Result<URL, Error>) -> Void) -> Bool {
        lock.lock()
        guard generation == self.generation, !inFlight else { lock.unlock(); return false }
        inFlight = true
        let submittedRevision = revision
        lock.unlock()
        queue.async { [self] in
            let result: Swift.Result<URL, Error>
            do {
                guard sample.source != .physicalCamera || (physicalBuffer && !hasInjectedEncoder && Self.physicalCameraSourceAllowed) else { throw CaptureError.sourceNotAllowed }
                guard sample.isValidForExport else { throw CaptureError.invalidSample }
                guard frameTimestamp.isFinite, sample.capturedUptime == frameTimestamp,
                      dimensions.width == CGFloat(sample.image.width), dimensions.height == CGFloat(sample.image.height) else { throw CaptureError.mismatchedFrame }
                try checkCurrent(generation: generation, revision: submittedRevision)
                guard let image = autoreleasepool(invoking: makeImage),
                      image.width == sample.image.width, image.height == sample.image.height else { throw CaptureError.imageConversionFailed }
                let png = try autoreleasepool { try encoder(image) }
                // An injected/test encoder must still produce a full-size PNG.
                guard let source = CGImageSourceCreateWithData(png as CFData, nil),
                      CGImageSourceGetType(source) as String? == "public.png",
                      let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
                      decoded.width == sample.image.width, decoded.height == sample.image.height else { throw CaptureError.imageEncodingFailed }
                let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
                let finalized = try sample.withImageDigest(digest)
                result = .success(try write(png: png, sample: finalized, generation: generation, revision: submittedRevision))
            } catch { result = .failure(error) }
            lock.lock(); inFlight = false; lock.unlock()
            completion(result)
        }
        return true
    }

    private func checkCurrent(generation: Int, revision: UInt64) throws {
        lock.lock(); defer { lock.unlock() }
        guard generation == self.generation, revision == self.revision else { throw CaptureError.cancelled }
    }

    private func write(png: Data, sample: PracticeValidationSample, generation: Int, revision: UInt64) throws -> URL {
        guard let rootDirectory, rootDirectory.isFileURL else { throw CaptureError.fileWriteFailed }
        let files = FileManager.default
        let final = rootDirectory.appendingPathComponent(sample.id, isDirectory: true)
        let staging = rootDirectory.appendingPathComponent(".capture-\(sample.id)-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: staging) }
        do {
            try checkCurrent(generation: generation, revision: revision)
            try files.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            try files.createDirectory(at: staging, withIntermediateDirectories: false)
            var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
            var directory = staging; try? directory.setResourceValues(excluded)
            try png.write(to: staging.appendingPathComponent("image.png"), options: .atomic)
            let json = JSONEncoder(); json.outputFormatting = [.prettyPrinted, .sortedKeys]
            try json.encode(sample).write(to: staging.appendingPathComponent("sample.json"), options: .atomic)
            // Hold the generation lock only around the final same-volume rename.
            // A reset cannot leave a newly committed record after cancellation.
            lock.lock(); defer { lock.unlock() }
            guard generation == self.generation, revision == self.revision else { throw CaptureError.cancelled }
            guard !files.fileExists(atPath: final.path) else { throw CaptureError.outputAlreadyExists }
            try files.moveItem(at: staging, to: final)
            return final
        } catch let error as CaptureError { throw error }
        catch { throw CaptureError.fileWriteFailed }
    }

    static var physicalCameraSourceAllowed: Bool {
        #if DEBUG && !targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--practice-validation") && !arguments.contains("--ui-testing") &&
            !arguments.contains("--paper-guide-fixture")
        #else
        return false
        #endif
    }

    static func encodePNG(_ image: CGImage) throws -> Data {
        guard let data = CFDataCreateMutable(kCFAllocatorDefault, 0),
              let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { throw CaptureError.imageEncodingFailed }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CaptureError.imageEncodingFailed }
        return data as Data
    }
}
