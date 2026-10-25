import CoreGraphics
import CoreVideo
import XCTest
@testable import Protacta

final class PaperVisionTrackerTests: XCTestCase {
    private let sheet = PaperVisionObservation(
        corners: [CGPoint(x: 0.2, y: 0.85), CGPoint(x: 0.8, y: 0.85),
                  CGPoint(x: 0.8, y: 0.15), CGPoint(x: 0.2, y: 0.15)], confidence: 0.95)

    func testOneClearCandidateKeepsRawVisionCornerCoordinates() {
        let selected = PaperVisionTracker.selectObservation(candidates: [sheet], handPoints: [])
        XCTAssertEqual(selected, sheet)
        XCTAssertGreaterThan(selected!.corners[0].y, selected!.corners[3].y,
                             "The viewport conversion must happen in the caller, not twice")
    }

    func testAmbiguousSecondSheetAndRecognizedHandOverlapHideTheGuide() {
        let second = PaperVisionObservation(
            corners: sheet.corners.map { CGPoint(x: $0.x - 0.05, y: $0.y) }, confidence: 0.98)
        XCTAssertNil(PaperVisionTracker.selectObservation(candidates: [sheet, second], handPoints: []))
        XCTAssertNil(PaperVisionTracker.selectObservation(candidates: [sheet],
                                                          handPoints: [CGPoint(x: 0.5, y: 0.5)]))
        XCTAssertNil(PaperVisionTracker.selectObservation(candidates: [sheet],
                                                          handPoints: [CGPoint(x: 0.19, y: 0.5)]))
        XCTAssertNotNil(PaperVisionTracker.selectObservation(candidates: [sheet],
                                                             handPoints: [CGPoint(x: 0.05, y: 0.5)]))
    }

    func testInvalidOrCroppedQuadrilateralsAreRejected() {
        let crossed = [sheet.corners[0], sheet.corners[2], sheet.corners[1], sheet.corners[3]]
        let cases = [
            PaperVisionObservation(corners: sheet.corners, confidence: 0.4),
            PaperVisionObservation(corners: crossed, confidence: 1),
            PaperVisionObservation(corners: Array(repeating: .zero, count: 4), confidence: 1),
            PaperVisionObservation(corners: [CGPoint(x: .nan, y: 0.2)] + Array(sheet.corners.dropFirst()), confidence: 1),
            PaperVisionObservation(corners: sheet.corners.map { CGPoint(x: $0.x - 0.3, y: $0.y) }, confidence: 1)
        ]
        for candidate in cases {
            XCTAssertNil(PaperVisionTracker.selectObservation(candidates: [candidate], handPoints: []))
        }
    }

    func testBusyWorkerDropsFramesInsteadOfRetainingAnUnboundedQueue() throws {
        let buffer = try makeBuffer()
        let began = expectation(description: "first frame began")
        let completed = expectation(description: "one frame completed")
        let release = DispatchSemaphore(value: 0)
        let counter = LockedCounter()
        let tracker = PaperVisionTracker(minimumInterval: 0) { _ in
            counter.increment()
            XCTAssertFalse(Thread.isMainThread)
            began.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            return self.sheet
        }
        tracker.reset(generation: 7)
        tracker.submit(pixelBuffer: buffer, timestamp: 1, generation: 7) { result in
            XCTAssertEqual(result.generation, 7)
            XCTAssertEqual(result.timestamp, 1)
            completed.fulfill()
        }
        wait(for: [began], timeout: 5)
        for frame in 2...100 {
            tracker.submit(pixelBuffer: buffer, timestamp: TimeInterval(frame), generation: 7) { _ in
                XCTFail("A busy worker must not queue another frame")
            }
        }
        release.signal()
        wait(for: [completed], timeout: 5)
        XCTAssertEqual(counter.value, 1)
    }

    func testResetCancelsAnAlreadyRunningGeneration() throws {
        let buffer = try makeBuffer()
        let began = expectation(description: "old frame began")
        let oldCallback = expectation(description: "old callback must be discarded")
        oldCallback.isInverted = true
        let release = DispatchSemaphore(value: 0)
        let tracker = PaperVisionTracker(minimumInterval: 0) { _ in
            began.fulfill()
            _ = release.wait(timeout: .now() + 5)
            return self.sheet
        }
        tracker.reset(generation: 1)
        tracker.submit(pixelBuffer: buffer, timestamp: 1, generation: 1) { _ in oldCallback.fulfill() }
        wait(for: [began], timeout: 5)
        tracker.reset(generation: 2)
        release.signal()
        wait(for: [oldCallback], timeout: 0.3)
    }

    func testRateLimitAndOutOfOrderFramesDoNotRunDetection() throws {
        let buffer = try makeBuffer()
        let first = expectation(description: "first frame")
        let last = expectation(description: "next eligible frame")
        let counter = LockedCounter()
        let tracker = PaperVisionTracker(minimumInterval: 0.125) { _ in
            counter.increment()
            return nil
        }
        tracker.reset(generation: 3)
        tracker.submit(pixelBuffer: buffer, timestamp: 1, generation: 3) { _ in first.fulfill() }
        wait(for: [first], timeout: 5)
        for timestamp in [0.9, 1, 1.05, 1.124] {
            tracker.submit(pixelBuffer: buffer, timestamp: timestamp, generation: 3) { _ in
                XCTFail("Out-of-order or rate-limited frame was accepted")
            }
        }
        tracker.submit(pixelBuffer: buffer, timestamp: 1.25, generation: 3) { result in
            XCTAssertNil(result.observation, "A no-detection result must not reuse a previous rectangle")
            last.fulfill()
        }
        wait(for: [last], timeout: 5)
        XCTAssertEqual(counter.value, 2)
    }

    func testWrongGenerationAndInvalidTimestampDoNotRunDetection() throws {
        let buffer = try makeBuffer()
        let completed = expectation(description: "valid submission")
        let counter = LockedCounter()
        let tracker = PaperVisionTracker(minimumInterval: 0) { _ in counter.increment(); return nil }
        tracker.reset(generation: 4)
        tracker.submit(pixelBuffer: buffer, timestamp: 0, generation: 3) { _ in XCTFail("Wrong generation") }
        tracker.submit(pixelBuffer: buffer, timestamp: .nan, generation: 4) { _ in XCTFail("NaN timestamp") }
        tracker.submit(pixelBuffer: buffer, timestamp: -1, generation: 4) { _ in XCTFail("Negative timestamp") }
        tracker.submit(pixelBuffer: buffer, timestamp: 0, generation: 4) { _ in completed.fulfill() }
        wait(for: [completed], timeout: 5)
        XCTAssertEqual(counter.value, 1)
    }

    func testBlankImageHasNoRectangleObservation() throws {
        let tracker = PaperVisionTracker()
        let completed = expectation(description: "blank Vision frame")
        tracker.reset(generation: 1)
        tracker.submit(pixelBuffer: try makeBuffer(), timestamp: 1, generation: 1) { result in
            XCTAssertNil(result.observation)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 15)
    }

    func testSyntheticFlatSheetProducesFreshRawImageCorners() throws {
        let buffer = try makeBuffer()
        CVPixelBufferLockBaseAddress(buffer, [])
        let memory = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        // A 240 × 336 light sheet on a dark 640 × 480 image. This exercises
        // Vision detection and raw corner output, not real-world AR acceptance.
        for y in 72..<408 {
            for x in 200..<440 {
                let pixel = memory + y * stride + x * 4
                pixel[0] = 255; pixel[1] = 255; pixel[2] = 255; pixel[3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let tracker = PaperVisionTracker()
        let completed = expectation(description: "synthetic sheet Vision frame")
        tracker.reset(generation: 1)
        tracker.submit(pixelBuffer: buffer, timestamp: 2, generation: 1) { result in
            if let observation = result.observation {
                XCTAssertEqual(observation.corners.count, 4)
                XCTAssertEqual(observation.corners[0].x, 200.0 / 640, accuracy: 0.03)
                XCTAssertEqual(observation.corners[0].y, 408.0 / 480, accuracy: 0.03)
                XCTAssertEqual(observation.corners[2].x, 440.0 / 640, accuracy: 0.03)
                XCTAssertEqual(observation.corners[2].y, 72.0 / 480, accuracy: 0.03)
            } else {
                XCTFail("The live Vision pipeline must detect a clear synthetic sheet, not only reject blanks")
            }
            completed.fulfill()
        }
        wait(for: [completed], timeout: 15)
    }

    private func makeBuffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(kCFAllocatorDefault, 640, 480, kCVPixelFormatType_32BGRA,
                                        [kCVPixelBufferCGImageCompatibilityKey: true,
                                         kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
                                        &buffer)
        XCTAssertEqual(result, kCVReturnSuccess)
        let image = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(image, [])
        defer { CVPixelBufferUnlockBaseAddress(image, []) }
        let memory = try XCTUnwrap(CVPixelBufferGetBaseAddress(image))
        memset(memory, 0, CVPixelBufferGetBytesPerRow(image) * CVPixelBufferGetHeight(image))
        let pixels = memory.assumingMemoryBound(to: UInt8.self)
        for y in 0..<CVPixelBufferGetHeight(image) {
            for x in 0..<CVPixelBufferGetWidth(image) {
                pixels[y * CVPixelBufferGetBytesPerRow(image) + x * 4 + 3] = 255
            }
        }
        return image
    }
}

private final class LockedCounter {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
