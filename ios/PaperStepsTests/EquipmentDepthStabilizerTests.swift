import XCTest
import ARKit
import RealityKit
@testable import Protacta

/// Synthetic numerical contracts; physical edge quality is a separate gate.
final class EquipmentDepthStabilizerTests: XCTestCase {
    private func plane(_ depth: Float = 0.5, time: Double = 1) -> SceneDepthSnapshot {
        SceneDepthSnapshot(width: 5, height: 5, depths: Array(repeating: depth, count: 25),
            confidence: Array(repeating: 2, count: 25), calibration: [100, 100, 2, 2],
            cameraTransform: matrix_identity_float4x4, timestamp: time)
    }
    func testSmallStationaryNoiseDoesNotAlternateTheFilteredDepth() {
        var filter = EquipmentDepthStabilizer()
        _ = filter.filter(plane())
        for index in 1...12 {
            let input = plane(index.isMultiple(of: 2) ? 0.503 : 0.497, time: 1 + Double(index) / 30)
            let result = filter.filter(input)
            XCTAssertTrue(result.depths.allSatisfy { abs($0 - 0.5) < 0.000001 })
        }
    }
    func testRealForegroundOrBackgroundChangeBypassesHistoryImmediately() {
        var filter = EquipmentDepthStabilizer()
        _ = filter.filter(plane())
        XCTAssertEqual(filter.filter(plane(1.2, time: 1.033)).depths[12], 1.2)
        XCTAssertEqual(filter.filter(plane(0.3, time: 1.066)).depths[12], 0.3)
    }
    func testCurrentRawExposureClearsAWithdrawnHandDespiteSmoothedLag() {
        var filter = EquipmentDepthStabilizer()
        _ = filter.filter(plane())
        let lagging = plane(0.5, time: 1.033), clear = plane(1.2, time: 1.033)
        let result = filter.filter(lagging, current: clear)
        XCTAssertTrue(result.depths.allSatisfy { $0 == 1.2 }, "Current background must replace the old hand in the same exposure")
        let arriving = filter.filter(plane(1.2, time: 1.066), current: plane(0.3, time: 1.066))
        XCTAssertTrue(arriving.depths.allSatisfy { $0 == 0.3 })
    }
    func testCoherentRawMotionDoesNotReenterTheTemporalDeadbandAfterReprojection() {
        var filter = EquipmentDepthStabilizer(); _ = filter.filter(plane())
        var smoothed = plane(0.49, time: 1.033)
        smoothed.cameraTransform.columns.3.z = 0.002
        var current = smoothed; current.depths = Array(repeating: 0.515, count: 25)
        XCTAssertEqual(filter.filter(smoothed, current: current).depths[12], 0.515,
                       "Accepted same-exposure raw motion must bypass our own hold/blend as well")
    }
    func testRawMotionCheckRejectsAnotherExposureOrCalibration() {
        var filter = EquipmentDepthStabilizer()
        let input = plane()
        XCTAssertEqual(filter.filter(input, current: plane(1.2, time: 0.9)).depths[12], 0.5)
        var wrongCamera = plane(1.2); wrongCamera.cameraTransform.columns.3.x = 0.1
        filter.reset()
        XCTAssertEqual(filter.filter(input, current: wrongCamera).depths[12], 0.5)
        var invalid = plane(1.2); invalid.confidence = Array(repeating: 0, count: 25)
        filter.reset()
        XCTAssertEqual(filter.filter(input, current: invalid).depths[12], 0.5)
    }
    func testIsolatedRawOutlierDoesNotPunchAHoleInAStableHand() {
        var filter = EquipmentDepthStabilizer()
        _ = filter.filter(plane())
        var raw = plane(time: 1.033); raw.depths[12] = 1.2
        XCTAssertEqual(filter.filter(plane(time: 1.033), current: raw).depths[12], 0.5)
        XCTAssertEqual(filter.filter(plane(time: 1.066), current: plane(1.2, time: 1.066)).depths[12], 1.2,
                       "A coherent background must still clear the hand immediately")
    }
    func testSupportedConfidenceHoleHasABoundAndRawWithdrawalClearsItImmediately() {
        var filter = EquipmentDepthStabilizer()
        _ = filter.filter(plane())
        var hole = plane(); hole.confidence = Array(repeating: 0, count: 25)
        for i in [6, 7, 8, 11] { hole.confidence[i] = 2 }
        for i in [13, 16] { hole.confidence[i] = 2; hole.depths[i] = 1.2 }
        for frame in 1...2 {
            hole.timestamp = 1 + Double(frame) / 30
            XCTAssertEqual(filter.filter(hole).confidence[12], 1)
        }
        hole.timestamp = 1.1
        XCTAssertEqual(filter.filter(hole).confidence[12], 0, "Support cannot retain an invalid pixel indefinitely")
        filter.reset(); _ = filter.filter(plane())
        hole.timestamp = 1.033; _ = filter.filter(hole)
        hole.timestamp = 1.066
        XCTAssertEqual(filter.filter(hole, current: plane(1.2, time: 1.066)).depths[12], 1.2)
    }
    func testLargerStationaryNoiseIsHeldWithoutHoldingRealMotion() {
        var filter = EquipmentDepthStabilizer()
        _ = filter.filter(plane())
        for frame in 1...10 {
            let input = plane(frame.isMultiple(of: 2) ? 0.508 : 0.492, time: 1 + Double(frame) / 30)
            XCTAssertEqual(filter.filter(input).depths[12], 0.5)
        }
        XCTAssertEqual(filter.filter(plane(0.65, time: 1.367)).depths[12], 0.65)
    }
    func testCameraMovementAndLongFrameGapCannotReuseDepthHistory() {
        var filter = EquipmentDepthStabilizer()
        _ = filter.filter(plane())
        var moving = plane(0.505, time: 1.033)
        moving.cameraTransform.columns.3.x = 0.02
        XCTAssertEqual(filter.filter(moving).depths[12], 0.505)
        XCTAssertEqual(filter.filter(plane(0.501, time: 2)).depths[12], 0.501)
    }
    func testInteriorHoleMayFillButAnUnsupportedOrEdgePixelDoesNotGrow() {
        var filter = EquipmentDepthStabilizer()
        var hole = plane(); hole.confidence[12] = 0
        XCTAssertEqual(filter.filter(hole).depths[12], 0.5)
        var invalid = plane(time: 1.033); invalid.confidence = Array(repeating: 0, count: 25)
        XCTAssertTrue(filter.filter(invalid).confidence.allSatisfy { $0 == 0 })
        var boundary = plane()
        for y in 0..<5 { for x in 3..<5 { boundary.depths[y * 5 + x] = 1.2 } }
        boundary.confidence[12] = 0
        filter.reset()
        XCTAssertEqual(filter.filter(boundary).confidence[12], 0)
    }
    func testEquipmentDepthToleranceDoesNotChangeThePaperPolicy() {
        let input = plane()
        let paper = SceneDepthMesher.build(input, supportPlaneY: nil, pixelStep: 1)
        let equipment = SceneDepthMesher.build(input, supportPlaneY: nil, pixelStep: 1, policy: .stableEquipment)
        XCTAssertLessThan(paper.positions[12].z, -0.5)
        XCTAssertEqual(equipment.positions[12].z, -0.492, accuracy: 0.000001)
        XCTAssertEqual(equipment.triangles.count, paper.triangles.count)
    }
    func testSparseFilterMatchesDenseFilterAtEveryMesherVertex() {
        var dense = EquipmentDepthStabilizer(), sparse = EquipmentDepthStabilizer()
        for frame in 0..<8 {
            var input = plane(frame.isMultiple(of: 2) ? 0.5 : 0.503, time: 1 + Double(frame) / 30)
            input.confidence[12] = 0
            for y in 0..<5 { input.depths[y * 5 + 4] = 1.2 }
            let full = dense.filter(input), sampled = sparse.filter(input, pixelStep: 2)
            for y in stride(from: 0, to: 5, by: 2) {
                for x in stride(from: 0, to: 5, by: 2) {
                    let index = y * 5 + x
                    XCTAssertEqual(sampled.depths[index], full.depths[index])
                    XCTAssertEqual(sampled.confidence[index], full.confidence[index])
                }
            }
        }
    }
    func testSmallCameraTranslationAlignsTheForegroundBeforeTheDeadband() {
        var old = SceneDepthSnapshot(width: 9, height: 5, depths: Array(repeating: 1.2, count: 45),
            confidence: Array(repeating: 2, count: 45), calibration: [200, 200, 4, 2],
            cameraTransform: matrix_identity_float4x4, timestamp: 1)
        for y in 0..<5 { for x in 3...5 { old.depths[y * 9 + x] = 0.25 } }
        var current = old
        current.timestamp = 1.033; current.cameraTransform.columns.3.x = 0.0025
        current.depths = Array(repeating: 1.2, count: 45)
        for y in 0..<5 { for x in 1...3 { current.depths[y * 9 + x] = 0.253 } }
        var filter = EquipmentDepthStabilizer(); _ = filter.filter(old)
        let result = filter.filter(current)
        XCTAssertEqual(result.depths[2 * 9 + 2], 0.25, accuracy: 0.000001,
                       "The stable near surface moved two pixels; the old screen pixel held background")
        XCTAssertEqual(result.depths[2 * 9 + 5], 1.2, accuracy: 0.000001,
                       "The old foreground screen pixel must clear immediately")
    }

    private func supportedHole(centerX: Int = 2, principalX: Float = 2, time: Double) -> SceneDepthSnapshot {
        var hole = plane(time: time)
        hole.calibration.z = principalX
        hole.confidence = Array(repeating: 0, count: 25)
        for (dx, dy) in [(-1, -1), (0, -1), (1, -1), (-1, 0)] {
            hole.confidence[(2 + dy) * 5 + centerX + dx] = 2
        }
        for (dx, dy) in [(1, 0), (-1, 1)] {
            let index = (2 + dy) * 5 + centerX + dx
            hole.confidence[index] = 2; hole.depths[index] = 1.2
        }
        return hole
    }

    func testCropShiftTransportsTheTwoFrameHoleLimit() {
        var filter = EquipmentDepthStabilizer(); _ = filter.filter(plane())
        XCTAssertEqual(filter.filter(supportedHole(time: 1.033)).confidence[12], 1)
        let shifted = supportedHole(centerX: 1, principalX: 1, time: 1.066)
        XCTAssertEqual(filter.filter(shifted).confidence[11], 1)
        var third = shifted; third.timestamp = 1.099
        XCTAssertEqual(filter.filter(third).confidence[11], 0,
                       "A shifted crop must not reset a retained pixel's hold counter")
    }

    func testHeldPixelCannotAccumulateMoreThan120MillisecondsAcrossShortFrameGaps() {
        var filter = EquipmentDepthStabilizer(); _ = filter.filter(plane())
        XCTAssertEqual(filter.filter(supportedHole(time: 1.08)).confidence[12], 1)
        XCTAssertEqual(filter.filter(supportedHole(time: 1.15)).confidence[12], 0,
                       "The latest frame is 70ms old, but the retained center was last seen 150ms ago")
    }

    func testDuplicateAndBackwardsFramesDoNotBecomeANewHistorySource() {
        for staleTime in [0.99, 1.0] {
            var filter = EquipmentDepthStabilizer(); _ = filter.filter(plane())
            XCTAssertEqual(filter.filter(plane(0.7, time: staleTime)).depths[12], 0.7)
            XCTAssertEqual(filter.filter(plane(0.705, time: 1.033)).depths[12], 0.705,
                           "An out-of-order exposure must not become the next deadband reference")
        }
    }

    func testExcludedHandIsNotPersistedOrResurrectedWhenTheMaskDisappears() {
        var filter = EquipmentDepthStabilizer(); _ = filter.filter(plane())
        let mask = Array(repeating: true, count: 25)
        let masked = filter.filter(plane(time: 1.033), current: plane(time: 1.033), pixelStep: 2, excluding: mask)
        XCTAssertTrue(masked.depths.allSatisfy { $0 == 0 })
        XCTAssertTrue(masked.confidence.allSatisfy { $0 == 0 }, "Even unsampled person pixels must be cleared")
        var unknown = plane(time: 1.066)
        unknown.confidence = Array(repeating: 0, count: 25)
        let cleared = filter.filter(unknown, current: unknown)
        XCTAssertTrue(cleared.confidence.allSatisfy { $0 == 0 }, "A native-person region cannot return as a custom ghost")
    }

    func testExcludedCurrentAndRawNeighborsCannotFillAnUnmaskedHole() {
        var input = plane(time: 1.033), raw = input
        input.confidence = Array(repeating: 0, count: 25)
        raw.confidence = Array(repeating: 0, count: 25)
        var mask = Array(repeating: false, count: 25)
        for index in [6, 7, 8, 11, 13] {
            input.confidence[index] = 2; raw.confidence[index] = 2; mask[index] = true
        }
        var filter = EquipmentDepthStabilizer()
        let result = filter.filter(input, current: raw, excluding: mask)
        XCTAssertEqual(result.confidence[12], 0)
        XCTAssertTrue(result.confidence.allSatisfy { $0 == 0 })
    }

    func testMalformedExclusionFailsClosedAndClearsHistory() {
        var filter = EquipmentDepthStabilizer(); _ = filter.filter(plane())
        let result = filter.filter(plane(time: 1.033), excluding: [true])
        XCTAssertTrue(result.depths.allSatisfy { $0 == 0 })
        XCTAssertTrue(result.confidence.allSatisfy { $0 == 0 })
        XCTAssertEqual(filter.filter(plane(0.505, time: 1.066)).depths[12], 0.505)
    }

    func testDuplicateFrameStillHonorsTheCurrentExclusion() {
        var filter = EquipmentDepthStabilizer(); _ = filter.filter(plane())
        var mask = Array(repeating: false, count: 25); mask[12] = true
        XCTAssertEqual(filter.filter(plane(), excluding: mask).confidence[12], 0)
        var unknown = plane(time: 1.033); unknown.confidence = Array(repeating: 0, count: 25)
        XCTAssertTrue(filter.filter(unknown).confidence.allSatisfy { $0 == 0 })
    }

    @MainActor
    func testRefinedEquipmentUsesNativeHandsPlusOnlySupportedNonPersonDepthWithoutSceneMesh() {
        for depth in [false, true] {
            for person in [false, true] {
                for combined in [false, true] {
                    let capabilities = EquipmentOcclusionCapabilities(stableDepth: depth, personDepth: person,
                                                                     combinedPersonAndSceneDepth: combined)
                    let config = EquipmentOcclusionConfiguration.make(mode: .stableEdges, capabilities: capabilities)
                    let objectDepth = depth && (!person || combined)
                    let context = "depth=\(depth), person=\(person), combined=\(combined)"
                    XCTAssertEqual(EquipmentOcclusionConfiguration.usesObjectDepth(mode: .stableEdges, capabilities: capabilities), objectDepth, context)
                    XCTAssertEqual(EquipmentOcclusionConfiguration.usesNativeHands(mode: .stableEdges, capabilities: capabilities), person, context)
                    XCTAssertEqual(EquipmentOcclusionConfiguration.effective(.stableEdges, capabilities: capabilities), objectDepth ? .stableEdges : .nativeHands, context)
                    XCTAssertEqual(config.frameSemantics.contains(.sceneDepth), objectDepth, context)
                    XCTAssertEqual(config.frameSemantics.contains(.smoothedSceneDepth), objectDepth, context)
                    XCTAssertEqual(config.frameSemantics.contains(.personSegmentationWithDepth), person, context)
                    XCTAssertEqual(config.sceneReconstruction, [], context)
                    let options = EquipmentOcclusionConfiguration.renderOptions(mode: .stableEdges, capabilities: capabilities)
                    XCTAssertFalse(options.contains(.disablePersonOcclusion), "Native matting must remain the only hand-boundary owner: \(context)")
                    XCTAssertTrue(options.contains(.disableGroundingShadows), context)
                }
            }
        }
    }

    @MainActor
    func testUnsupportedEquipmentCombinationFallsBackToNativeOnlyWhileDepthOnlyDevicesRemainUsable() {
        let separateOnly = EquipmentOcclusionCapabilities(stableDepth: true, personDepth: true, combinedPersonAndSceneDepth: false)
        let fallback = EquipmentOcclusionConfiguration.make(mode: .stableEdges, capabilities: separateOnly)
        XCTAssertEqual(fallback.frameSemantics, [.personSegmentationWithDepth])
        XCTAssertEqual(EquipmentOcclusionConfiguration.effective(.stableEdges, capabilities: separateOnly), .nativeHands)
        let depthOnly = EquipmentOcclusionCapabilities(stableDepth: true, personDepth: false, combinedPersonAndSceneDepth: false)
        let depth = EquipmentOcclusionConfiguration.make(mode: .stableEdges, capabilities: depthOnly)
        XCTAssertEqual(depth.frameSemantics, [.sceneDepth, .smoothedSceneDepth])
        XCTAssertTrue(EquipmentOcclusionConfiguration.usesObjectDepth(mode: .stableEdges, capabilities: depthOnly))
        XCTAssertFalse(EquipmentOcclusionConfiguration.usesNativeHands(mode: .stableEdges, capabilities: depthOnly))
    }

    @MainActor
    func testEquipmentNativePreferenceNeverRequestsObjectDepthAndKeepsPersistedModeValues() {
        let capabilities = EquipmentOcclusionCapabilities(stableDepth: true, personDepth: true)
        let config = EquipmentOcclusionConfiguration.make(mode: .nativeHands, capabilities: capabilities)
        XCTAssertEqual(config.frameSemantics, [.personSegmentationWithDepth])
        XCTAssertFalse(EquipmentOcclusionConfiguration.usesObjectDepth(mode: .nativeHands, capabilities: capabilities))
        XCTAssertTrue(EquipmentOcclusionConfiguration.usesNativeHands(mode: .nativeHands, capabilities: capabilities))
        XCTAssertFalse(EquipmentOcclusionConfiguration.renderOptions(mode: .nativeHands, capabilities: capabilities).contains(.disablePersonOcclusion))
        XCTAssertTrue(capabilities.combinedPersonAndSceneDepth)
        XCTAssertFalse(EquipmentOcclusionCapabilities(stableDepth: true, personDepth: false).combinedPersonAndSceneDepth)
        XCTAssertEqual(EquipmentOcclusionMode.stableEdges.rawValue, "stableEdges")
        XCTAssertEqual(EquipmentOcclusionMode.nativeHands.rawValue, "nativeHands")
        XCTAssertEqual(EquipmentOcclusionMode.stableEdges.title, "Refined edges")
    }
}
