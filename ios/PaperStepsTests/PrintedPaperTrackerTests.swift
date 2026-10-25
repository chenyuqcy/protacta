import CoreGraphics
import CoreImage
import CoreVideo
import ImageIO
import XCTest
@testable import Protacta

final class PrintedPaperTrackerTests: XCTestCase {
    func testNativeBarcodeRevisionAndRasterDiagnostics() throws {
        let synthetic = try practiceImage()
        let pdf = try bundledPracticePDFImage()
        let configurations: [(String, PrintedPaperBarcodeRevision, Bool)] = [
            ("default-automatic", .frameworkDefault, false),
            ("default-cpu", .frameworkDefault, true),
            ("revision3-cpu", .revision3, true),
            ("revision1-cpu", .revision1, true)
        ]
        var detectedACompleteSheet = false
        for (name, fixture) in [("synthetic", synthetic), ("bundled-pdf", pdf)] {
            attachPNG(fixture.image, name: "\(name)-source")
            let normalized = try normalizedRaster(fixture.image)
            attachPNG(normalized, name: "\(name)-bgra-normalized")
            for (configuration, revision, cpu) in configurations {
                let scan = PrintedPaperTracker.markerAnalysis(cgImage: fixture.image,
                                                              revision: revision, preferSupportedCPU: cpu)
                let payloads = scan.markers.map(\.payload).sorted()
                print("BARCODE_DIAGNOSTIC \(name) \(configuration): \(scan.diagnostic), payloads=\(payloads), failure=\(scan.failure ?? "none")")
                if scan.markers.count == 4 && Set(payloads) == Set(PrintedPaperRegistration.markerIDs) {
                    let registration = PrintedPaperRegistration(markers: Dictionary(uniqueKeysWithValues:
                        scan.markers.map { ($0.payload, $0.quadrilateral) }))
                    print("BARCODE_DIAGNOSTIC \(name) \(configuration): physical geometry valid=\(registration != nil)")
                    detectedACompleteSheet = detectedACompleteSheet || registration != nil
                }
            }
        }
        XCTAssertTrue(detectedACompleteSheet, "At least one supported native QR configuration must decode a complete, geometrically valid printed sheet")
    }

    func testBundledPrintLayoutMatchesTrackerGeometryExactly() throws {
        let layout = try XCTUnwrap(DartPracticePaperLayout.bundled,
                                   "The printable layout JSON must be bundled with the app")
        XCTAssertEqual(layout.schemaVersion, 1)
        XCTAssertEqual(layout.sheetSizeMM.width, 210, accuracy: 1e-10)
        XCTAssertEqual(layout.sheetSizeMM.height, 297, accuracy: 1e-10)
        XCTAssertEqual(layout.codeSideMM, 14, accuracy: 1e-10)
        XCTAssertEqual(layout.quietZoneMM, 3, accuracy: 1e-10)
        XCTAssertEqual(layout.markers.map(\.payload), PrintedPaperRegistration.markerIDs)
        for marker in layout.markers {
            let center = try XCTUnwrap(PrintedPaperRegistration.markerCenters[marker.payload])
            XCTAssertEqual(marker.center.x, Double(center.x), accuracy: 1e-10)
            XCTAssertEqual(marker.center.y, Double(center.y), accuracy: 1e-10)
        }
        XCTAssertEqual(layout.codeSideMM / layout.sheetSizeMM.width,
                       Double(PrintedPaperRegistration.codeSize.width), accuracy: 1e-10)
        XCTAssertEqual(layout.codeSideMM / layout.sheetSizeMM.height,
                       Double(PrintedPaperRegistration.codeSize.height), accuracy: 1e-10)
    }

    func testPerspectiveRegistrationUsesKnownIDsAndIndependentMarkerCorners() throws {
        let markers = markerQuads(mapping: perspective)
        let registration = try XCTUnwrap(PrintedPaperRegistration(markers: markers))
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1),
                      CGPoint(x: 0.38, y: 0.19), CGPoint(x: 0.78, y: 0.57)] {
            assertPoint(registration.map(sheetPoint: point), equals: perspective(point))
        }
        for (actual, expected) in zip(registration.quadrilateral.points,
                                      PaperQuadrilateral.unit.points.map(perspective)) {
            assertPoint(actual, equals: expected)
        }
        XCTAssertFalse(markers["PTC1A"]!.isValid,
                       "A small marker must use its own geometry validation, not the full-sheet minimum area")
    }

    func testCyclicMarkerCornerStartsDoNotChangePrintedDirection() throws {
        var markers = markerQuads(mapping: perspective)
        for (index, id) in PrintedPaperRegistration.markerIDs.enumerated() {
            markers[id] = markers[id]!.rotated(by: index)
        }
        let registration = try XCTUnwrap(PrintedPaperRegistration(markers: markers))
        assertPoint(registration.map(sheetPoint: CGPoint(x: 0.2, y: 0.3)),
                    equals: perspective(CGPoint(x: 0.2, y: 0.3)))
    }

    func testFourCentersAloneCannotAcceptWrongCodeSizeOrDistortedMarker() {
        var markers = markerQuads(mapping: perspective)
        let original = markers["PTC1B"]!
        // Scaling about the diagonal intersection preserves the measured
        // center, so a center-only homography would incorrectly accept it.
        let center = perspective(PrintedPaperRegistration.markerCenters["PTC1B"]!)
        let enlarged = original.points.map {
            CGPoint(x: center.x + ($0.x - center.x) * 1.8,
                    y: center.y + ($0.y - center.y) * 1.8)
        }
        markers["PTC1B"] = quad(enlarged)
        XCTAssertNil(PrintedPaperRegistration(markers: markers))
        markers = markerQuads(mapping: perspective)
        markers["PTC1B"] = quad([original.topLeft, original.bottomRight,
                                  original.topRight, original.bottomLeft])
        XCTAssertNil(PrintedPaperRegistration(markers: markers), "Crossed marker corners are invalid")
    }

    func testMissingDuplicatedWrongAndReflectedMarkersAreRejected() {
        let complete = markerQuads(mapping: perspective)
        var missing = complete
        missing.removeValue(forKey: "PTC1D")
        XCTAssertNil(PrintedPaperRegistration(markers: missing))
        var wrongIDs = complete
        wrongIDs["PTC1A"] = complete["PTC1B"]
        wrongIDs["PTC1B"] = complete["PTC1A"]
        XCTAssertNil(PrintedPaperRegistration(markers: wrongIDs))
        var reflected = complete
        let marker = complete["PTC1A"]!
        reflected["PTC1A"] = quad([marker.topLeft, marker.bottomLeft, marker.bottomRight, marker.topRight])
        XCTAssertNil(PrintedPaperRegistration(markers: reflected))

        var observations = markerObservations(complete)
        observations.append(observations[0])
        XCTAssertNil(PrintedPaperTracker.makePose(detection: detection(observations), timestamp: 10))
        let unsupported = observations.map {
            PrintedPaperMarkerObservation(payload: "OTHER", quadrilateral: $0.quadrilateral)
        }
        XCTAssertNil(PrintedPaperTracker.makePose(detection: detection(unsupported), timestamp: 10))
    }

    func testRecognizedOrUncertainHandOcclusionCannotProducePose() throws {
        let markers = markerObservations(markerQuads(mapping: perspective))
        let visible = try XCTUnwrap(PrintedPaperTracker.makePose(detection: detection(markers), timestamp: 10))
        XCTAssertEqual(visible.timestamp, 10)
        XCTAssertEqual(Set(visible.markerQuads.keys), Set(PrintedPaperRegistration.markerIDs))
        let hand = perspective(CGPoint(x: 0.4, y: 0.3))
        XCTAssertNil(PrintedPaperTracker.makePose(detection: detection(markers, hands: [hand]), timestamp: 10))
        XCTAssertNil(PrintedPaperTracker.makePose(detection: detection(markers, uncertain: true), timestamp: 10))
        XCTAssertNotNil(PrintedPaperTracker.makePose(detection: detection(markers, hands: [.zero]), timestamp: 10))
        XCTAssertNil(PrintedPaperTracker.makePose(detection: detection(markers), timestamp: .nan))
        var failed = detection(markers)
        failed.failure = "A required analysis stage failed."
        XCTAssertNil(PrintedPaperTracker.makePose(detection: failed, timestamp: 10),
                     "Known corners cannot override a failed analysis stage")
    }

    func testProcessingTimingAndFailureBelongToTheAdmittedFrame() throws {
        let buffer = try makeBuffer()
        let completed = expectation(description: "timed unknown frame")
        let tracker = PrintedPaperTracker(minimumInterval: 0) { _ in
            PrintedPaperDetection(markers: [], handPoints: [], hasUncertainHand: false,
                                  luminance: nil, failure: "Synthetic failure")
        }
        tracker.reset(generation: 4)
        let before = ProcessInfo.processInfo.systemUptime
        XCTAssertTrue(tracker.submit(pixelBuffer: buffer, timestamp: before, generation: 4) { frame in
            XCTAssertEqual(frame.timestamp, before)
            XCTAssertGreaterThanOrEqual(frame.processingStartedUptime, before)
            XCTAssertGreaterThanOrEqual(frame.processedUptime, frame.processingStartedUptime)
            XCTAssertLessThanOrEqual(frame.processedUptime, ProcessInfo.processInfo.systemUptime)
            XCTAssertEqual(frame.processingFailure, "Synthetic failure")
            XCTAssertNil(frame.pose)
            completed.fulfill()
        })
        XCTAssertFalse(tracker.submit(pixelBuffer: buffer, timestamp: before, generation: 3) { _ in XCTFail("Wrong generation") })
        wait(for: [completed], timeout: 5)
    }

    func testBGRAAndCGImageLuminanceKeepTopLeftRowsAndFullImageExtent() throws {
        let image = try bandImage(width: 8, height: 4, top: 230, bottom: 40)
        let decoded = try XCTUnwrap(PrintedPaperTracker.luminanceImage(cgImage: image, maximumDimension: 4))
        XCTAssertEqual(decoded.width, 4)
        XCTAssertEqual(decoded.height, 2)
        XCTAssertEqual(Array(decoded.pixels.prefix(4)), [230, 230, 230, 230],
                       "The top row must remain the raw image top, not be vertically flipped")
        XCTAssertEqual(Array(decoded.pixels.suffix(4)), [40, 40, 40, 40])

        let buffer = try makeBuffer(width: 8, height: 4)
        CVPixelBufferLockBaseAddress(buffer, [])
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<4 {
            for x in 0..<8 {
                let offset = y * stride + 4 * x
                let value: UInt8 = y < 2 ? 230 : 40
                bytes[offset] = value; bytes[offset + 1] = value; bytes[offset + 2] = value; bytes[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let camera = try XCTUnwrap(PrintedPaperTracker.luminanceImage(pixelBuffer: buffer, maximumDimension: 4))
        XCTAssertEqual(camera.pixels, decoded.pixels)
    }

    func testBoundedWorkerDropsFramesWhileBusyAndReturnsMatchingMetadata() throws {
        let buffer = try makeBuffer()
        let began = expectation(description: "one printed-paper frame began")
        let completed = expectation(description: "one matching result")
        let release = DispatchSemaphore(value: 0)
        let calls = LockedCount()
        let known = detection(markerObservations(markerQuads(mapping: perspective)))
        let tracker = PrintedPaperTracker(minimumInterval: 0) { _ in
            XCTAssertFalse(Thread.isMainThread)
            calls.increment()
            began.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            return known
        }
        tracker.reset(generation: 5)
        tracker.submit(pixelBuffer: buffer, timestamp: 10, generation: 5) { result in
            XCTAssertEqual(result.generation, 5)
            XCTAssertEqual(result.timestamp, 10)
            XCTAssertEqual(result.pose?.timestamp, 10)
            completed.fulfill()
        }
        wait(for: [began], timeout: 5)
        for timestamp in 11...100 {
            tracker.submit(pixelBuffer: buffer, timestamp: Double(timestamp), generation: 5) { _ in
                XCTFail("Busy worker must not enqueue more retained buffers")
            }
        }
        release.signal()
        wait(for: [completed], timeout: 5)
        XCTAssertEqual(calls.value, 1)
    }

    func testResetInvalidatesInFlightComputationAndSameGenerationRevision() throws {
        let buffer = try makeBuffer()
        let began = expectation(description: "old request began")
        let stale = expectation(description: "old revision cannot return")
        stale.isInverted = true
        let release = DispatchSemaphore(value: 0)
        let empty = detection([])
        let tracker = PrintedPaperTracker(minimumInterval: 0) { _ in
            began.fulfill()
            _ = release.wait(timeout: .now() + 5)
            return empty
        }
        tracker.reset(generation: 3)
        tracker.submit(pixelBuffer: buffer, timestamp: 1, generation: 3) { _ in stale.fulfill() }
        wait(for: [began], timeout: 5)
        tracker.reset(generation: 3)
        tracker.reset(generation: 4)
        tracker.submit(pixelBuffer: buffer, timestamp: 2, generation: 4) { _ in
            XCTFail("Reset must keep the slot occupied until old work releases its buffer")
        }
        release.signal()
        wait(for: [stale], timeout: 0.35)
    }

    func testFourHzAdmissionRejectsWrongGenerationOldAndInvalidTimes() throws {
        let buffer = try makeBuffer()
        let first = expectation(description: "first result")
        let second = expectation(description: "four Hz result")
        let calls = LockedCount()
        let empty = detection([])
        let tracker = PrintedPaperTracker(minimumInterval: 0.25) { _ in calls.increment(); return empty }
        tracker.reset(generation: 2)
        tracker.submit(pixelBuffer: buffer, timestamp: 1, generation: 2) { _ in first.fulfill() }
        wait(for: [first], timeout: 5)
        for timestamp in [Double.nan, -Double.infinity, -1, 0.9, 1, 1.1, 1.249] {
            tracker.submit(pixelBuffer: buffer, timestamp: timestamp, generation: 2) { _ in XCTFail("Ineligible frame") }
        }
        tracker.submit(pixelBuffer: buffer, timestamp: 1.25, generation: 1) { _ in XCTFail("Wrong generation") }
        tracker.submit(pixelBuffer: buffer, timestamp: 1.25, generation: 2) { result in
            XCTAssertEqual(result.timestamp, 1.25)
            XCTAssertNil(result.pose)
            second.fulfill()
        }
        wait(for: [second], timeout: 5)
        XCTAssertEqual(calls.value, 2)
    }

    func testRealVisionDecodesFourSyntheticPracticeCodesAndMatchesRawImagePose() throws {
        let fixture = try practiceImage()
        let tracker = PrintedPaperTracker()
        let completed = expectation(description: "real Vision synthetic QR fixture")
        tracker.reset(generation: 8)
        tracker.submit(cgImage: fixture.image, timestamp: 4, generation: 8) { frame in
            guard let pose = frame.pose else {
                let analysis = PrintedPaperTracker.analysis(cgImage: fixture.image)
                XCTFail("Real Vision must decode and geometrically validate all four printed practice codes. \(self.diagnostics(analysis))")
                completed.fulfill()
                return
            }
            XCTAssertEqual(Set(pose.markerQuads.keys), Set(PrintedPaperRegistration.markerIDs))
            for (actual, expected) in zip(pose.quadrilateral.points, fixture.sheet.points) {
                XCTAssertEqual(actual.x, expected.x, accuracy: 0.015)
                XCTAssertEqual(actual.y, expected.y, accuracy: 0.015)
            }
            XCTAssertEqual(frame.luminance?.width, 272)
            XCTAssertEqual(frame.luminance?.height, 320)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 30)
    }

    func testBundledPrintablePDFRendersIntoFourValidNativeVisionCodes() throws {
        let fixture = try bundledPracticePDFImage()
        let tracker = PrintedPaperTracker()
        let completed = expectation(description: "actual bundled PDF through native Vision")
        tracker.reset(generation: 10)
        tracker.submit(cgImage: fixture.image, timestamp: 5, generation: 10) { frame in
            guard let pose = frame.pose else {
                let analysis = PrintedPaperTracker.analysis(cgImage: fixture.image)
                XCTFail("The actual bundled practice PDF must decode and validate, not only a separately generated fixture. \(self.diagnostics(analysis))")
                completed.fulfill()
                return
            }
            XCTAssertEqual(Set(pose.markerQuads.keys), Set(PrintedPaperRegistration.markerIDs))
            for (actual, expected) in zip(pose.quadrilateral.points, fixture.sheet.points) {
                XCTAssertEqual(actual.x, expected.x, accuracy: 0.015)
                XCTAssertEqual(actual.y, expected.y, accuracy: 0.015)
            }
            completed.fulfill()
        }
        wait(for: [completed], timeout: 30)
    }

    func testNativeQRDecoderAndPhysicalRegistrationAcceptActualBundledPDF() throws {
        let fixture = try bundledPracticePDFImage()
        let scan = PrintedPaperTracker.markerAnalysis(cgImage: fixture.image)
        XCTAssertNil(scan.failure, "QR-only native stage: \(scan.failure ?? "none")")
        XCTAssertEqual(scan.markers.count, 4)
        XCTAssertEqual(Set(scan.markers.map(\.payload)), Set(PrintedPaperRegistration.markerIDs))
        guard scan.markers.count == 4, Set(scan.markers.map(\.payload)).count == 4 else { return }
        let registration = try XCTUnwrap(PrintedPaperRegistration(markers: Dictionary(uniqueKeysWithValues:
            scan.markers.map { ($0.payload, $0.quadrilateral) })), "Native QR geometry from the actual PDF must validate")
        for (actual, expected) in zip(registration.quadrilateral.points, fixture.sheet.points) {
            XCTAssertEqual(actual.x, expected.x, accuracy: 0.015)
            XCTAssertEqual(actual.y, expected.y, accuracy: 0.015)
        }
        // QR-only results intentionally have no hand-clear verdict and cannot
        // be passed off as production pose approval by this test.
    }

    func testRealVisionBlankAndMissingCodeFramesCannotReturnPose() throws {
        let blank = try bandImage(width: 640, height: 480, top: 25, bottom: 25)
        let missing = try practiceImage(including: ["PTC1A", "PTC1B", "PTC1C"])
        let tracker = PrintedPaperTracker()
        tracker.reset(generation: 9)
        let blankResult = expectation(description: "blank image has no printed pose")
        tracker.submit(cgImage: blank, timestamp: 1, generation: 9) { frame in
            XCTAssertNil(frame.pose)
            XCTAssertNotNil(frame.luminance)
            blankResult.fulfill()
        }
        wait(for: [blankResult], timeout: 30)
        let missingResult = expectation(description: "three real QR codes cannot make a four-code pose")
        tracker.submit(cgImage: missing.image, timestamp: 2, generation: 9) { frame in
            XCTAssertNil(frame.pose)
            XCTAssertNotNil(frame.luminance)
            missingResult.fulfill()
        }
        wait(for: [missingResult], timeout: 30)
    }

    private func perspective(_ point: CGPoint) -> CGPoint {
        let denominator = 1 + 0.10 * point.x + 0.06 * point.y
        return CGPoint(x: (0.18 + 0.64 * point.x + 0.03 * point.y) / denominator,
                       y: (0.06 + 0.04 * point.x + 0.84 * point.y) / denominator)
    }

    private func markerQuads(mapping: (CGPoint) -> CGPoint) -> [String: PaperQuadrilateral] {
        let half = CGSize(width: PrintedPaperRegistration.codeSize.width / 2,
                          height: PrintedPaperRegistration.codeSize.height / 2)
        return Dictionary(uniqueKeysWithValues: PrintedPaperRegistration.markerIDs.map { id in
            let center = PrintedPaperRegistration.markerCenters[id]!
            let points = [CGPoint(x: center.x - half.width, y: center.y - half.height),
                          CGPoint(x: center.x + half.width, y: center.y - half.height),
                          CGPoint(x: center.x + half.width, y: center.y + half.height),
                          CGPoint(x: center.x - half.width, y: center.y + half.height)].map(mapping)
            return (id, quad(points))
        })
    }

    private func markerObservations(_ markers: [String: PaperQuadrilateral]) -> [PrintedPaperMarkerObservation] {
        markers.map { PrintedPaperMarkerObservation(payload: $0.key, quadrilateral: $0.value) }
    }

    private func detection(_ markers: [PrintedPaperMarkerObservation], hands: [CGPoint] = [],
                            uncertain: Bool = false) -> PrintedPaperDetection {
        PrintedPaperDetection(markers: markers, handPoints: hands,
                              hasUncertainHand: uncertain, luminance: nil)
    }

    private func quad(_ points: [CGPoint]) -> PaperQuadrilateral {
        PaperQuadrilateral(topLeft: points[0], topRight: points[1],
                           bottomRight: points[2], bottomLeft: points[3])
    }

    private func assertPoint(_ actual: CGPoint?, equals expected: CGPoint,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else { XCTFail("Missing mapped point", file: file, line: line); return }
        XCTAssertEqual(actual.x, expected.x, accuracy: 1e-7, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 1e-7, file: file, line: line)
    }

    private func makeBuffer(width: Int = 8, height: Int = 4) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                           nil, &buffer), kCVReturnSuccess)
        return try XCTUnwrap(buffer)
    }

    private func bandImage(width: Int, height: Int, top: UInt8, bottom: UInt8) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let value = y < height / 2 ? top : bottom
                bytes[offset] = value; bytes[offset + 1] = value; bytes[offset + 2] = value
            }
        }
        return try image(bytes: bytes, width: width, height: height)
    }

    private func practiceImage(including markerIDs: [String] = PrintedPaperRegistration.markerIDs) throws -> (image: CGImage, sheet: PaperQuadrilateral) {
        let width = 1700, height = 2000
        let paperX = 220, paperY = 70, paperWidth = 1260, paperHeight = 1782
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value: UInt8 = (paperX..<(paperX + paperWidth)).contains(x) &&
                    (paperY..<(paperY + paperHeight)).contains(y) ? 245 : 25
                let offset = (y * width + x) * 4
                bytes[offset] = value; bytes[offset + 1] = value; bytes[offset + 2] = value
            }
        }
        let context = CIContext(options: [.useSoftwareRenderer: true])
        for id in markerIDs {
            let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
            filter.setValue(Data(id.utf8), forKey: "inputMessage")
            filter.setValue("M", forKey: "inputCorrectionLevel")
            let output = try XCTUnwrap(filter.outputImage)
            let code = try XCTUnwrap(context.createCGImage(output, from: output.extent))
            var codePixels = [UInt8](repeating: 255, count: code.width * code.height)
            let drawn = codePixels.withUnsafeMutableBytes { storage -> Bool in
                guard let bitmap = CGContext(data: storage.baseAddress, width: code.width, height: code.height,
                                              bitsPerComponent: 8, bytesPerRow: code.width,
                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                bitmap.draw(code, in: CGRect(x: 0, y: 0, width: code.width, height: code.height))
                return true
            }
            XCTAssertTrue(drawn)
            let codeSide = 84 // 14 mm × 6 px/mm; 21 QR modules × 4 px/module.
            let center = PrintedPaperRegistration.markerCenters[id]!
            let left = Int((Double(paperX) + Double(center.x) * Double(paperWidth) - Double(codeSide) / 2).rounded())
            let top = Int((Double(paperY) + Double(center.y) * Double(paperHeight) - Double(codeSide) / 2).rounded())
            for y in 0..<codeSide {
                for x in 0..<codeSide {
                    let sourceX = x * code.width / codeSide, sourceY = y * code.height / codeSide
                    let value = codePixels[sourceY * code.width + sourceX]
                    let offset = ((top + y) * width + left + x) * 4
                    bytes[offset] = value; bytes[offset + 1] = value; bytes[offset + 2] = value
                }
            }
        }
        let sheet = PaperQuadrilateral(
            topLeft: CGPoint(x: Double(paperX) / Double(width), y: Double(paperY) / Double(height)),
            topRight: CGPoint(x: Double(paperX + paperWidth) / Double(width), y: Double(paperY) / Double(height)),
            bottomRight: CGPoint(x: Double(paperX + paperWidth) / Double(width), y: Double(paperY + paperHeight) / Double(height)),
            bottomLeft: CGPoint(x: Double(paperX) / Double(width), y: Double(paperY + paperHeight) / Double(height)))
        return (try image(bytes: bytes, width: width, height: height), sheet)
    }

    private func bundledPracticePDFImage() throws -> (image: CGImage, sheet: PaperQuadrilateral) {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Protacta_Dart_Practice_A4", withExtension: "pdf"))
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(document.numberOfPages, 1)
        let page = try XCTUnwrap(document.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        XCTAssertEqual(box.width / box.height, 210.0 / 297, accuracy: 0.0001)
        let width = 1700, height = 2000
        let paper = CGRect(x: 220, y: 70, width: 1260, height: 1782)
        var bytes = [UInt8](repeating: 25, count: width * height * 4)
        for alpha in stride(from: 3, to: bytes.count, by: 4) { bytes[alpha] = 255 }
        let rendered = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                                           bitsPerComponent: 8, bytesPerRow: width * 4,
                                           space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue |
                                               CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
            // The bitmap CGContext already uses a bottom-left drawing origin.
            // Place the page's bottom at the raster's inverted bottom edge and
            // keep positive PDF scale. A second y flip mirrored the QR matrices
            // and moved both code rows to the top of the rendered practice page.
            context.translateBy(x: paper.minX, y: CGFloat(height) - paper.maxY)
            context.scaleBy(x: paper.width / box.width, y: paper.height / box.height)
            context.translateBy(x: -box.minX, y: -box.minY)
            context.drawPDFPage(page)
            return true
        }
        XCTAssertTrue(rendered)
        let sheet = PaperQuadrilateral(topLeft: CGPoint(x: paper.minX / CGFloat(width), y: paper.minY / CGFloat(height)),
                                       topRight: CGPoint(x: paper.maxX / CGFloat(width), y: paper.minY / CGFloat(height)),
                                       bottomRight: CGPoint(x: paper.maxX / CGFloat(width), y: paper.maxY / CGFloat(height)),
                                       bottomLeft: CGPoint(x: paper.minX / CGFloat(width), y: paper.maxY / CGFloat(height)))
        return (try image(bytes: bytes, width: width, height: height), sheet)
    }

    private func diagnostics(_ detection: PrintedPaperDetection) -> String {
        let markers = detection.markers.map { marker -> String in
            let points = marker.quadrilateral.points.map { String(format: "(%.4f,%.4f)", Double($0.x), Double($0.y)) }.joined(separator: ",")
            let a = marker.quadrilateral.topLeft, b = marker.quadrilateral.topRight, c = marker.quadrilateral.bottomRight
            let turn = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            return "\(marker.payload):[\(points)] winding=\(turn)"
        }.sorted().joined(separator: "; ")
        return "markers=\(detection.markers.count) {\(markers)}; hands=\(detection.handPoints.count), uncertainHand=\(detection.hasUncertainHand), failure=\(detection.failure ?? "none")"
    }

    private func normalizedRaster(_ source: CGImage) throws -> CGImage {
        let buffer = try XCTUnwrap(PrintedPaperTracker.pixelBuffer(cgImage: source))
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<(width * 4) { bytes[row * width * 4 + column] = base[row * stride + column] }
        }
        return try image(bytes: bytes, width: width, height: height)
    }

    private func attachPNG(_ image: CGImage, name: String) {
        guard let data = CFDataCreateMutable(kCFAllocatorDefault, 0),
              let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            XCTFail("Unable to attach diagnostic raster")
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { XCTFail("Unable to encode diagnostic PNG"); return }
        let attachment = XCTAttachment(data: data as Data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func image(bytes: [UInt8], width: Int, height: Int) throws -> CGImage {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue |
                                        CGBitmapInfo.byteOrder32Little.rawValue), provider: provider,
                                    decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private final class LockedCount: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
        func increment() { lock.lock(); count += 1; lock.unlock() }
    }
}
