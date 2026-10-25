import CryptoKit
import Foundation
import RealityKit
import XCTest
@testable import Protacta

final class AerisIntegrationTests: XCTestCase {
    func testAllThreeManualTasksKeepTheirAuthoredSequenceAndReleaseGate() throws {
        XCTAssertEqual(ManualTask.allCases, [.filter, .setup, .clean])
        XCTAssertEqual(ManualTask.filter.steps.count, 7)
        XCTAssertEqual(ManualTask.setup.steps.count, 5)
        XCTAssertEqual(ManualTask.clean.steps.count, 5)
        for task in ManualTask.allCases {
            XCTAssertEqual(task.steps.map(\.id), Array(task.steps.indices))
            XCTAssertEqual(task.steps.filter(\.requiresPress).count, 1)
            let release = try XCTUnwrap(task.steps.first(where: \.requiresPress))
            XCTAssertEqual(release.focus, "Cover_Release_Button")
            var progress = ManualProgress()
            progress.select(task)
            for _ in 0..<release.id { progress.next() }
            XCTAssertEqual(progress.index, release.id)
            XCTAssertFalse(progress.canAdvance)
            progress.next()
            XCTAssertEqual(progress.index, release.id, "Next must require the virtual release-tab action")
            progress.go(to: release.id + 1)
            XCTAssertEqual(progress.index, release.id, "Step navigation must not bypass the tab")
            progress.confirmAction()
            progress.next()
            XCTAssertEqual(progress.index, release.id + 1)
        }
    }

    func testCompletionRestartAndTaskSwitchResetInteractionEvidence() {
        var progress = ManualProgress()
        progress.go(to: 6)
        XCTAssertEqual(progress.index, 0)
        for _ in ManualTask.filter.steps {
            if progress.current.requiresPress { progress.confirmAction() }
            progress.next()
        }
        XCTAssertTrue(progress.completed)
        XCTAssertEqual(progress.index, 6)
        progress.next()
        XCTAssertEqual(progress.index, 0)
        XCTAssertEqual(progress.highestUnlocked, 0)
        XCTAssertFalse(progress.completed)
        XCTAssertFalse(progress.actionConfirmed)
        progress.next()
        progress.confirmAction()
        progress.select(.clean)
        XCTAssertEqual(progress.task, .clean)
        XCTAssertEqual(progress.index, 0)
        XCTAssertEqual(progress.highestUnlocked, 0)
        XCTAssertFalse(progress.actionConfirmed)
    }

    func testRevisitingReleaseStepRequiresANewVirtualPress() {
        var progress = ManualProgress()
        progress.next()
        progress.confirmAction()
        progress.next()
        progress.go(to: 1)
        XCTAssertFalse(progress.actionConfirmed)
        XCTAssertFalse(progress.canAdvance)
        progress.next()
        XCTAssertEqual(progress.index, 1)
    }

    @MainActor
    func testARProgressRequiresPlacementAndCurrentTracking() {
        let controller = ProductARController()
        controller.trackingReady = true
        controller.nextGuideStep()
        XCTAssertEqual(controller.guideProgress.index, 0)
        controller.placed = true
        controller.needsReset = true
        controller.nextGuideStep()
        XCTAssertEqual(controller.guideProgress.index, 0)
        controller.needsReset = false
        controller.error = "Session failed"
        controller.nextGuideStep()
        XCTAssertEqual(controller.guideProgress.index, 0)
        controller.stop()
    }

    @MainActor
    func testBackgroundAndFinalDismissalCancelInteractionUntilAnExplicitRescan() {
        let controller = ProductARController(task: .clean)
        controller.placed = true
        controller.trackingReady = true
        controller.isAnimating = true
        controller.pauseForBackground()
        XCTAssertFalse(controller.trackingReady)
        XCTAssertFalse(controller.isAnimating)
        XCTAssertTrue(controller.needsReset)
        controller.nextGuideStep()
        XCTAssertEqual(controller.guideProgress.index, 0)
        controller.reset()
        XCTAssertEqual(controller.guideProgress.task, .clean)
        XCTAssertFalse(controller.placed)
        XCTAssertFalse(controller.trackingReady)
        XCTAssertFalse(controller.needsReset)
        XCTAssertNil(controller.view, "Domain lifecycle checks must not create a renderer or request camera access")
        controller.stop()
        XCTAssertTrue(controller.isStopped)
        controller.placed = true
        controller.trackingReady = true
        controller.reset()
        controller.nextGuideStep()
        XCTAssertEqual(controller.guideProgress.index, 0, "A dismissed controller must remain stopped")
    }

    @MainActor
    func testStudioShutdownClearsPendingGuideAnimationWithoutCreatingAView() {
        let controller = ProductSceneController()
        controller.guide(ManualTask.filter.steps[1], replay: true)
        XCTAssertTrue(controller.isAnimating)
        controller.shutdown()
        XCTAssertFalse(controller.isAnimating)
        XCTAssertFalse(controller.isLoaded)
        XCTAssertNil(controller.hotspot)
        XCTAssertNil(controller.view)
    }

    @MainActor
    func testBundledConceptAssetMatchesSourceAndContainsEveryInstructionTarget() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "aeris-one", withExtension: "usdz"))
        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(bytes.count, 3_653_362)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "3b405825eaacb6eb7591251e7c3d2ef9bb0c31cc02dd97c63f5fa4d258f17f95")
        let model = try await ProductAsset.load(from: url)
        let requiredParts = Set(ManualTask.allCases.flatMap(\.steps).map(\.focus))
            .union(["Rear_Cover", "Filter_Cartridge", "Top_Assembly", "Base_Assembly"])
        for name in requiredParts {
            XCTAssertNotNil(model.findEntity(named: name), "Missing authored interaction target: \(name)")
        }
    }
}
