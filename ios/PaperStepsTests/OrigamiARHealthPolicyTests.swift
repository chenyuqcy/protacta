import Foundation
import XCTest
@testable import Protacta

/// Synthetic timing and controller-state contracts, not physical AR evidence.
final class OrigamiARHealthPolicyTests: XCTestCase {
    func testFrameFreshnessRejectsStallsMissingAndMalformedTimestamps() {
        XCTAssertTrue(OrigamiARFrameHealth.isFresh(timestamp: 10, now: 10.25))
        XCTAssertFalse(OrigamiARFrameHealth.isFresh(timestamp: 10, now: 10.251))
        XCTAssertFalse(OrigamiARFrameHealth.isFresh(timestamp: nil, now: 10))
        XCTAssertFalse(OrigamiARFrameHealth.isFresh(timestamp: .nan, now: 10))
        XCTAssertFalse(OrigamiARFrameHealth.isFresh(timestamp: 10, now: .infinity))
        XCTAssertFalse(OrigamiARFrameHealth.isFresh(timestamp: 11, now: 10))
        XCTAssertFalse(OrigamiARFrameHealth.isFresh(timestamp: -1, now: 0))
    }

    func testFreshnessDoesNotReplaceNormalTrackingOrTheCommittedAnchor() {
        XCTAssertTrue(OrigamiARFrameHealth.isUsable(timestamp: 10, now: 10.01, normal: true, anchorPresent: true))
        XCTAssertFalse(OrigamiARFrameHealth.isUsable(timestamp: 10, now: 10.01, normal: false, anchorPresent: true))
        XCTAssertFalse(OrigamiARFrameHealth.isUsable(timestamp: 10, now: 10.01, normal: true, anchorPresent: false))
    }

    func testMissingDepthHasTwoSecondStartupGrace() {
        var policy = OrigamiARDepthHealth()
        XCTAssertFalse(policy.shouldFallback(now: 10, frameTimestamp: 10, normal: true, appliedTimestamp: nil))
        XCTAssertFalse(policy.shouldFallback(now: 11.999, frameTimestamp: 11.999, normal: true, appliedTimestamp: nil))
        XCTAssertTrue(policy.shouldFallback(now: 12, frameTimestamp: 12, normal: true, appliedTimestamp: nil))
    }

    func testOnlyRecentlyAppliedDepthRenewsTheShortRunningWindow() {
        var policy = OrigamiARDepthHealth()
        XCTAssertFalse(policy.shouldFallback(now: 10, frameTimestamp: 10, normal: true, appliedTimestamp: 9.99))
        XCTAssertFalse(policy.shouldFallback(now: 10.749, frameTimestamp: 10.749, normal: true, appliedTimestamp: 9.99))
        XCTAssertTrue(policy.shouldFallback(now: 10.75, frameTimestamp: 10.75, normal: true, appliedTimestamp: 9.99))
        XCTAssertFalse(policy.shouldFallback(now: 10.8, frameTimestamp: 10.8, normal: true, appliedTimestamp: 10.79))
        XCTAssertFalse(policy.shouldFallback(now: 11.5, frameTimestamp: 11.5, normal: true, appliedTimestamp: nil))
    }

    func testOldFutureAndNonfiniteAppliedTimesCannotCertifyDepthHealth() {
        var policy = OrigamiARDepthHealth()
        XCTAssertFalse(policy.shouldFallback(now: 10, frameTimestamp: 10, normal: true, appliedTimestamp: 1))
        XCTAssertFalse(policy.shouldFallback(now: 11, frameTimestamp: 11, normal: true, appliedTimestamp: 20))
        XCTAssertTrue(policy.shouldFallback(now: 12, frameTimestamp: 12, normal: true, appliedTimestamp: .nan))
    }

    func testTrackingLossAndQueuedStaleFramesResetRatherThanTriggerFallback() {
        var policy = OrigamiARDepthHealth()
        XCTAssertFalse(policy.shouldFallback(now: 10, frameTimestamp: 10, normal: true, appliedTimestamp: nil))
        XCTAssertFalse(policy.shouldFallback(now: 20, frameTimestamp: 20, normal: false, appliedTimestamp: nil))
        XCTAssertFalse(policy.shouldFallback(now: 21, frameTimestamp: 10, normal: true, appliedTimestamp: 10))
        XCTAssertFalse(policy.shouldFallback(now: 22, frameTimestamp: 22, normal: true, appliedTimestamp: nil))
        XCTAssertFalse(policy.shouldFallback(now: 23, frameTimestamp: 23, normal: true, appliedTimestamp: nil))
        XCTAssertTrue(policy.shouldFallback(now: 24, frameTimestamp: 24, normal: true, appliedTimestamp: nil))
    }

    func testExplicitResetAndBackwardClockStartANewGraceWindow() {
        var policy = OrigamiARDepthHealth()
        XCTAssertFalse(policy.shouldFallback(now: 10, frameTimestamp: 10, normal: true, appliedTimestamp: 10))
        policy.reset()
        XCTAssertFalse(policy.shouldFallback(now: 20, frameTimestamp: 20, normal: true, appliedTimestamp: nil))
        XCTAssertFalse(policy.shouldFallback(now: 19, frameTimestamp: 19, normal: true, appliedTimestamp: nil))
        XCTAssertFalse(policy.shouldFallback(now: 20.9, frameTimestamp: 20.9, normal: true, appliedTimestamp: nil))
        XCTAssertTrue(policy.shouldFallback(now: 21, frameTimestamp: 21, normal: true, appliedTimestamp: nil))
    }
}

@MainActor
final class OrigamiARControllerHealthTests: XCTestCase {
    private func capabilities(mask: Bool = true, person: Bool = true) -> AROcclusionCapabilities {
        AROcclusionCapabilities(personDepth: person, sceneDepth: true, sceneMesh: false,
                                 smoothedDepth: true, combinedPersonAndSceneDepth: true, personMask: mask)
    }

    private func partialFold(capabilities: AROcclusionCapabilities? = nil) -> LessonController {
        let controller = LessonController(progressStore: LearningProgressStore(defaults: nil),
                                          occlusionCapabilities: capabilities ?? self.capabilities())
        controller.selectLesson(.dart); controller.begin(); controller.goToStep(3); controller.scrub(to: 0.4)
        return controller
    }

    private func injectPlacement(_ controller: LessonController) {
        // Flags only: no synthetic camera frame, anchor, or depth rendering.
        controller.isAR = true; controller.placed = true; controller.trackingReady = true
    }

    func testRecommendedDefaultAndUnsupportedHandsFirstNormalizationPreserveTheFold() {
        let preferred = partialFold()
        XCTAssertEqual(preferred.occlusionMode, .handsFirst)
        let controller = partialFold(capabilities: capabilities(mask: false))
        XCTAssertEqual(controller.occlusionMode, .automatic)
        injectPlacement(controller)
        controller.setOcclusionMode(.handsFirst)
        XCTAssertEqual(controller.occlusionMode, .peopleOnly)
        XCTAssertEqual(controller.stepIndex, 3); XCTAssertEqual(controller.progress, 0.4, accuracy: 0.0001)
        XCTAssertTrue(controller.placed); XCTAssertTrue(controller.trackingReady)
        XCTAssertFalse(controller.isPlaying); XCTAssertNil(controller.arView)
    }

    func testPausedStalledCameraDisablesPlacementWithoutChangingTheFoldOrRepeatedSaves() {
        let controller = partialFold(); injectPlacement(controller)
        controller.togglePositionLock()
        XCTAssertTrue(controller.placementGesturesEnabled)
        XCTAssertFalse(controller.isPlaying)
        controller.checkTabletopFrameHealth(timestamp: 10, now: 10.3, normal: true, anchorPresent: true)
        XCTAssertFalse(controller.trackingReady); XCTAssertFalse(controller.placementGesturesEnabled)
        XCTAssertFalse(controller.canAnimate); XCTAssertFalse(controller.isPlaying)
        XCTAssertTrue(controller.placed); XCTAssertEqual(controller.stepIndex, 3)
        XCTAssertEqual(controller.progress, 0.4, accuracy: 0.0001)
        let savedRevision = controller.savedProgressRevision
        controller.checkTabletopFrameHealth(timestamp: 10, now: 11, normal: true, anchorPresent: true)
        XCTAssertEqual(controller.savedProgressRevision, savedRevision)
        XCTAssertNil(controller.arView)
    }

    func testMissingAnchorStopsPlaybackAndStudioIsNotAffectedByTheCameraWatchdog() {
        let controller = partialFold(); injectPlacement(controller); controller.togglePlayback()
        XCTAssertTrue(controller.isPlaying)
        controller.checkTabletopFrameHealth(timestamp: 10, now: 10.01, normal: true, anchorPresent: false)
        XCTAssertFalse(controller.isPlaying); XCTAssertFalse(controller.trackingReady)
        XCTAssertEqual(controller.progress, 0.4, accuracy: 0.0001)
        let studio = partialFold(); studio.togglePlayback()
        studio.checkTabletopFrameHealth(timestamp: nil, now: 100, normal: false, anchorPresent: false)
        XCTAssertTrue(studio.isPlaying); XCTAssertFalse(studio.isAR)
    }

    func testDepthFailureFallsBackToForegroundHandsAndPreservesPlacementAndPartialFold() {
        let controller = partialFold(); injectPlacement(controller); controller.setOcclusionMode(.automatic)
        controller.checkObjectDepthHealth(now: 10, frameTimestamp: 10, normal: true, appliedTimestamp: nil)
        XCTAssertEqual(controller.occlusionMode, .automatic)
        controller.checkObjectDepthHealth(now: 12, frameTimestamp: 12, normal: true, appliedTimestamp: nil)
        XCTAssertEqual(controller.occlusionMode, .handsFirst)
        XCTAssertEqual(controller.occlusionHealthNotice, "Object depth is paused. Hands first is active.")
        XCTAssertTrue(controller.placed); XCTAssertTrue(controller.trackingReady)
        XCTAssertEqual(controller.stepIndex, 3); XCTAssertEqual(controller.progress, 0.4, accuracy: 0.0001)
        XCTAssertFalse(controller.completed); XCTAssertNil(controller.arView)
    }

    func testDepthFailureWithoutMaskFallsBackToNativeDepthHands() {
        let controller = partialFold(capabilities: capabilities(mask: false)); injectPlacement(controller)
        controller.checkObjectDepthHealth(now: 10, frameTimestamp: 10, normal: true, appliedTimestamp: 10)
        controller.checkObjectDepthHealth(now: 10.75, frameTimestamp: 10.75, normal: true, appliedTimestamp: nil)
        XCTAssertEqual(controller.occlusionMode, .peopleOnly)
        XCTAssertEqual(controller.occlusionHealthNotice, "Object depth is paused. Native hands is active.")
    }

    func testModeChangeAndBackgroundResetTheDepthHealthWindowAndNeverStartCamera() {
        let controller = partialFold(); injectPlacement(controller); controller.setOcclusionMode(.automatic)
        controller.checkObjectDepthHealth(now: 10, frameTimestamp: 10, normal: true, appliedTimestamp: 10)
        controller.setOcclusionMode(.handsFirst); controller.setOcclusionMode(.automatic)
        controller.checkObjectDepthHealth(now: 20, frameTimestamp: 20, normal: true, appliedTimestamp: nil)
        XCTAssertEqual(controller.occlusionMode, .automatic)
        controller.background()
        controller.checkObjectDepthHealth(now: 100, frameTimestamp: 100, normal: true, appliedTimestamp: nil)
        XCTAssertTrue(controller.needsRescan); XCTAssertEqual(controller.occlusionMode, .automatic)
        XCTAssertFalse(controller.isPlaying); XCTAssertFalse(controller.trackingReady)
        XCTAssertEqual(controller.progress, 0.4, accuracy: 0.0001)
        XCTAssertNil(controller.arView)
    }
}
