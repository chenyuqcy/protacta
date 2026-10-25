import CoreGraphics
import CoreVideo
import CryptoKit
import Foundation
import ImageIO
import XCTest
@testable import Protacta

final class PracticeValidationCaptureTests: XCTestCase {
    private var output: URL!

    override func setUpWithError() throws {
        output = FileManager.default.temporaryDirectory.appendingPathComponent("protacta-validation-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let output { try? FileManager.default.removeItem(at: output) }
    }

    func testConstructionDoesNotCreateOrCaptureAnything() {
        _ = PracticeValidationCapture(rootDirectory: output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testCodableSchemaPreservesSemanticCornersAndSeparatesMachineResultFromHumanLabels() throws {
        let sample = fixtureSample(quad: .unit.rotated(by: 1))
        let data = try JSONEncoder().encode(sample)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["source"] as? String, "synthetic_fixture")
        XCTAssertEqual(object["split"] as? String, "development")
        XCTAssertEqual(object["paperLayoutID"] as? String, "protacta-dart-a4-ptc2")
        XCTAssertEqual(object["paperLayoutRevision"] as? Int, 2)
        XCTAssertNil(object["humanLabel"])
        XCTAssertNil(object["reviewed"])
        XCTAssertNil(object["deviceName"])
        XCTAssertNil(object["deviceIdentifier"])
        let image = try XCTUnwrap(object["image"] as? [String: Any])
        XCTAssertEqual(image["path"] as? String, "image.png")
        XCTAssertEqual(image["orientation"] as? String, "raw_top_left")
        XCTAssertEqual(image["width"] as? Int, 4)
        let quad = try XCTUnwrap(object["rawSheetQuadrilateral"] as? [String: Any])
        let topLeft = try XCTUnwrap(quad["topLeft"] as? [String: Double])
        XCTAssertEqual(topLeft["x"], 1)
        XCTAssertEqual(topLeft["y"], 0, "Semantic top-left must not be sorted back to screen top-left")
        let decoded = try JSONDecoder().decode(PracticeValidationSample.self, from: data)
        XCTAssertEqual(decoded.rawSheetQuadrilateral?.cgQuadrilateral, .unit.rotated(by: 1))
        XCTAssertEqual(decoded.registrationPoints.count, 20)
        XCTAssertEqual(Set(decoded.registrationPoints.map(\.id)).count, 20)
        XCTAssertEqual(decoded.result.timestamp, decoded.capturedUptime)
        XCTAssertEqual(decoded.result.support, "visible_outline_only")
        XCTAssertNotEqual(decoded.sourceBasename, "image.png")
    }

    func testSaveCreatesOneAtomicRecordWithFullSizePNGAndVerifiedDigest() throws {
        let capture = PracticeValidationCapture(rootDirectory: output)
        let image = try fixtureImage()
        let sample = fixtureSample()
        let directory = try save(capture, image: image, sample: sample).get()
        XCTAssertEqual(directory.lastPathComponent, sample.id)
        XCTAssertEqual(directory.deletingLastPathComponent(), output)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), ["image.png", "sample.json"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), [sample.id])
        let png = try Data(contentsOf: directory.appendingPathComponent("image.png"))
        let decoded = try JSONDecoder().decode(PracticeValidationSample.self,
                                              from: Data(contentsOf: directory.appendingPathComponent("sample.json")))
        XCTAssertEqual(decoded.image.sha256, SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(decoded.image.path, "image.png")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.png")
        let written = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(written.width, 4); XCTAssertEqual(written.height, 2)
        XCTAssertNil(sample.image.sha256, "Finalizing a digest must not mutate the caller's immutable sample")
        // Preserve exact exported bytes for the independent Python schema and
        // integrity contract check. These remain explicitly synthetic data.
        let imageAttachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        imageAttachment.name = "Synthetic_capture_contract_image"; imageAttachment.lifetime = .keepAlways
        add(imageAttachment)
        let metadataAttachment = XCTAttachment(data: try Data(contentsOf: directory.appendingPathComponent("sample.json")),
                                               uniformTypeIdentifier: "public.json")
        metadataAttachment.name = "Synthetic_capture_contract_metadata"; metadataAttachment.lifetime = .keepAlways
        add(metadataAttachment)
    }

    func testStableOriginalFrameIdentityAllowsCollectorTimestampDots() throws {
        let capture = PracticeValidationCapture(rootDirectory: output)
        let origin = "32b7a45c-7890-4ffe-9876-123456789abc_frame_12345.123456789"
        let sample = fixtureSample(originID: origin, sourceBasename: "\(origin).png")
        let directory = try save(capture, image: fixtureImage(), sample: sample).get()
        let decoded = try JSONDecoder().decode(PracticeValidationSample.self,
                                              from: Data(contentsOf: directory.appendingPathComponent("sample.json")))
        XCTAssertEqual(decoded.originID, origin)
        XCTAssertEqual(decoded.sourceBasename, "\(origin).png")
    }

    func testObsoleteOrMislabeledPaperLayoutCannotBeExportedAsCurrent() throws {
        let capture = PracticeValidationCapture(rootDirectory: output)
        let image = try fixtureImage()
        for change: (inout [String: Any]) -> Void in [
            { $0["paperLayoutID"] = "protacta-dart-a4-ptc1" },
            { $0["paperLayoutRevision"] = 1 }
        ] {
            let invalid = try mutated(fixtureSample(), change)
            XCTAssertEqual(error(in: try save(capture, image: image, sample: invalid)), .invalidSample)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testPixelBufferExportKeepsRawTopLeftRowsAndPrimaryColors() throws {
        let capture = PracticeValidationCapture(rootDirectory: output)
        let buffer = try fixtureBuffer()
        let completed = expectation(description: "raw camera-format fixture saved")
        var saved: Swift.Result<URL, Error>?
        XCTAssertTrue(capture.save(pixelBuffer: buffer, sample: fixtureSample(), frameTimestamp: 100, generation: 0) {
            saved = $0; completed.fulfill()
        })
        wait(for: [completed], timeout: 10)
        let directory = try XCTUnwrap(saved).get()
        let png = try Data(contentsOf: directory.appendingPathComponent("image.png"))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let decoded = try XCTUnwrap(PrintedPaperTracker.pixelBuffer(cgImage: image))
        let actual = try packedPixels(decoded)
        let expected = fixturePixels
        XCTAssertEqual(actual.count, expected.count)
        for index in expected.indices {
            XCTAssertLessThanOrEqual(abs(Int(actual[index]) - Int(expected[index])), 1,
                                     "Raw row/color mismatch at byte \(index); the PNG must not be rotated or mirrored")
        }
    }

    func testMissingPoseAndExpiredFrameExportOnlyAsCannotJudge() throws {
        let capture = PracticeValidationCapture(rootDirectory: output)
        let sample = fixtureSample(outcome: .cannotJudge, quad: nil,
                                   processed: 100.8, disposition: .expired, failure: "QR assessment unavailable")
        let directory = try save(capture, image: fixtureImage(), sample: sample).get()
        let data = try Data(contentsOf: directory.appendingPathComponent("sample.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(object["rawSheetQuadrilateral"] is NSNull)
        XCTAssertEqual(object["frameDisposition"] as? String, "expired")
        let decoded = try JSONDecoder().decode(PracticeValidationSample.self, from: data)
        XCTAssertNil(decoded.rawSheetQuadrilateral)
        XCTAssertEqual(decoded.result.outcome, .cannotJudge)
        XCTAssertEqual(decoded.processingFailure, "QR assessment unavailable")
        XCTAssertEqual(decoded.processingMs, 20)
        XCTAssertEqual(decoded.frameAgeMs!, 800, accuracy: 0.001)
    }

    func testTimestampDimensionsAndExpiredApprovalCannotBeMislabeled() throws {
        let capture = PracticeValidationCapture(rootDirectory: output)
        let image = try fixtureImage()
        let wrongTimestamp = try save(capture, image: image, sample: fixtureSample(), frameTimestamp: 99)
        XCTAssertEqual(error(in: wrongTimestamp), .mismatchedFrame)
        let wrongSize = try save(capture, image: image, sample: fixtureSample(width: 5))
        XCTAssertEqual(error(in: wrongSize), .mismatchedFrame)
        let expiredMatch = try save(capture, image: image,
                                   sample: fixtureSample(processed: 100.8, disposition: .expired))
        XCTAssertEqual(error(in: expiredMatch), .invalidSample)
        let wrongCheck = try mutated(fixtureSample()) { object in
            var result = object["result"] as! [String: Any]
            result["timestamp"] = 99.0
            object["result"] = result
        }
        XCTAssertEqual(error(in: try save(capture, image: image, sample: wrongCheck)), .invalidSample)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testUnprovidedPseudonymsPathTraversalAndInventedProcessingIntervalAreRejected() throws {
        let image = try fixtureImage()
        let capture = PracticeValidationCapture(rootDirectory: output)
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["operatorID"] = "" },
            { $0["sheetID"] = "../other" },
            { $0["id"] = "../outside" },
            { $0["sourceBasename"] = "image.png" },
            { $0["processingMs"] = 2000.0 },
            { $0["frameAgeMs"] = 1.0 },
            { $0["frameAgeMs"] = 900.0 },
            { $0["processingFailure"] = "Failure cannot accompany approval" }
        ]
        for change in changes {
            let invalid = try mutated(fixtureSample(), change)
            XCTAssertEqual(error(in: try save(capture, image: image, sample: invalid)), .invalidSample)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testCGImageCannotBePresentedAsPhysicalCameraEvidence() throws {
        let capture = PracticeValidationCapture(rootDirectory: output)
        let result = try save(capture, image: fixtureImage(), sample: fixtureSample(source: .physicalCamera))
        XCTAssertEqual(error(in: result), .sourceNotAllowed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        #if targetEnvironment(simulator)
        XCTAssertFalse(PracticeValidationCapture.physicalCameraSourceAllowed)
        #endif
    }

    func testConcurrentSaveIsRejectedWithoutQueuingAnotherImage() throws {
        let began = expectation(description: "one encoder began")
        let completed = expectation(description: "one encoder completed")
        let release = DispatchSemaphore(value: 0)
        let capture = PracticeValidationCapture(rootDirectory: output, imageEncoder: { image in
            began.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            return try PracticeValidationCapture.encodePNG(image)
        })
        let image = try fixtureImage()
        XCTAssertTrue(capture.save(cgImage: image, sample: fixtureSample(), frameTimestamp: 100, generation: 0) { result in
            if case .failure(let error) = result { XCTFail("Expected one successful capture: \(error)") }
            completed.fulfill()
        })
        wait(for: [began], timeout: 5)
        XCTAssertFalse(capture.save(cgImage: image, sample: fixtureSample(), frameTimestamp: 100, generation: 0) { _ in
            XCTFail("A busy capture service must not admit a second image")
        })
        release.signal()
        wait(for: [completed], timeout: 10)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path).count, 1)
    }

    func testGenerationResetCancelsBeforeCommitAndDoesNotReleaseBusySlotEarly() throws {
        let began = expectation(description: "old encoder began")
        let cancelled = expectation(description: "old encoder cancelled")
        let release = DispatchSemaphore(value: 0)
        let capture = PracticeValidationCapture(rootDirectory: output, imageEncoder: { image in
            began.fulfill()
            _ = release.wait(timeout: .now() + 5)
            return try PracticeValidationCapture.encodePNG(image)
        })
        let image = try fixtureImage()
        capture.reset(generation: 1)
        XCTAssertTrue(capture.save(cgImage: image, sample: fixtureSample(), frameTimestamp: 100, generation: 1) { result in
            XCTAssertEqual(self.error(in: result), .cancelled); cancelled.fulfill()
        })
        wait(for: [began], timeout: 5)
        capture.reset(generation: 2)
        XCTAssertFalse(capture.save(cgImage: image, sample: fixtureSample(), frameTimestamp: 100, generation: 2) { _ in XCTFail("Busy after reset") })
        release.signal()
        wait(for: [cancelled], timeout: 10)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testDuplicateIDNeverOverwritesExistingRecordOrLeavesStagingFiles() throws {
        let capture = PracticeValidationCapture(rootDirectory: output)
        let sample = fixtureSample(), image = try fixtureImage()
        let first = try save(capture, image: image, sample: sample).get()
        let original = try Data(contentsOf: first.appendingPathComponent("sample.json"))
        XCTAssertEqual(error(in: try save(capture, image: image, sample: sample)), .outputAlreadyExists)
        XCTAssertEqual(try Data(contentsOf: first.appendingPathComponent("sample.json")), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), [sample.id])
    }

    func testInvalidEncoderCannotWriteArbitraryBytesAsPNG() throws {
        let capture = PracticeValidationCapture(rootDirectory: output, imageEncoder: { _ in Data("not a PNG".utf8) })
        XCTAssertEqual(error(in: try save(capture, image: fixtureImage(), sample: fixtureSample())), .imageEncodingFailed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    private func fixtureSample(source: PracticeValidationSample.Source = .syntheticFixture,
                                outcome: PaperCheckOutcome = .visibleMatch, quad: PaperQuadrilateral? = .unit,
                                processed: TimeInterval = 100.05,
                                disposition: PracticeValidationSample.FrameDisposition = .fresh,
                                failure: String? = nil, width: Int = 4,
                                originID: String = "origin-test-01", sourceBasename: String? = nil) -> PracticeValidationSample {
        PracticeValidationSample(source: source, split: .development,
                                 sessionID: "session-test-01", operatorID: "operator-test-01",
                                 sheetID: "sheet-test-01", attemptID: "attempt-test-01", originID: originID, sourceBasename: sourceBasename,
                                 courseRevision: DartPracticeCourse.revision,
                                 appVersion: "0.1.0", appBuild: "test", deviceModel: "synthetic", osVersion: "test",
                                 capturedUptime: 100, processedUptime: processed, processingFailure: failure,
                                 processingMs: 20, frameAgeMs: (processed - 100) * 1000, frameDisposition: disposition,
                                 imageWidth: width, imageHeight: 2, viewportSize: CGSize(width: 390, height: 500),
                                 viewportOrientation: "portrait", rawToViewport: .identity,
                                 rawSheetQuadrilateral: quad, markerQuadrilaterals: [:],
                                 result: DartOutlineCheckResult(checkpointID: "dart-visible-outline-2-v1", referenceState: 2,
                                                              outcome: outcome, message: "Synthetic fixture: visible outline only.",
                                                              mismatchedPoints: [], timestamp: 100))
    }

    private func save(_ capture: PracticeValidationCapture, image: CGImage, sample: PracticeValidationSample,
                       frameTimestamp: TimeInterval = 100) throws -> Swift.Result<URL, Error> {
        let completed = expectation(description: "one explicit fixture save")
        var result: Swift.Result<URL, Error>?
        XCTAssertTrue(capture.save(cgImage: image, sample: sample, frameTimestamp: frameTimestamp, generation: 0) {
            result = $0; completed.fulfill()
        })
        wait(for: [completed], timeout: 10)
        return try XCTUnwrap(result)
    }

    private func error(in result: Swift.Result<URL, Error>) -> PracticeValidationCapture.CaptureError? {
        if case .failure(let error) = result { return error as? PracticeValidationCapture.CaptureError }
        XCTFail("Expected capture rejection")
        return nil
    }

    private func mutated(_ sample: PracticeValidationSample,
                          _ mutation: (inout [String: Any]) -> Void) throws -> PracticeValidationSample {
        let data = try JSONEncoder().encode(sample)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        mutation(&object)
        return try JSONDecoder().decode(PracticeValidationSample.self, from: JSONSerialization.data(withJSONObject: object))
    }

    /// BGRA: the first row is red/green/blue/white; the second row differs at
    /// every position so a vertical flip or channel swap cannot pass by symmetry.
    private var fixturePixels: [UInt8] {
        [0, 0, 255, 255, 0, 255, 0, 255, 255, 0, 0, 255, 255, 255, 255, 255,
         255, 255, 0, 255, 255, 0, 255, 255, 0, 255, 255, 255, 0, 0, 0, 255]
    }

    private func fixtureImage() throws -> CGImage {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(fixturePixels) as CFData))
        return try XCTUnwrap(CGImage(width: 4, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func fixtureBuffer() throws -> CVPixelBuffer {
        let buffer = try XCTUnwrap(PrintedPaperTracker.pixelBuffer(cgImage: fixtureImage()))
        return buffer
    }

    private func packedPixels(_ buffer: CVPixelBuffer) throws -> [UInt8] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var values: [UInt8] = []
        for row in 0..<CVPixelBufferGetHeight(buffer) {
            values += Array(UnsafeBufferPointer(start: bytes + row * stride, count: CVPixelBufferGetWidth(buffer) * 4))
        }
        return values
    }
}
