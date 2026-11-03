import XCTest
import RealityKit
import UIKit
@testable import Protacta

final class TutorialTabletopARTests: XCTestCase {
    @MainActor
    func testPlacementStartsLockedAndCannotBeUnlockedBeforeItIsReady() {
        let controller = TutorialTabletopARController()
        XCTAssertTrue(controller.positionLocked)
        XCTAssertFalse(controller.placementGesturesEnabled)
        controller.togglePositionLock()
        XCTAssertTrue(controller.positionLocked)
        XCTAssertFalse(controller.placed)
        XCTAssertNil(controller.view, "A lock request must not start an AR session")
        controller.resetPlacement()
        XCTAssertTrue(controller.positionLocked)
        XCTAssertFalse(controller.placementGesturesEnabled)
        controller.stop()
    }

    func testTransformChangesRequireTheirOwnFreshGestureBegin() {
        var gate = TutorialPlacementGestureGate()
        for kind in [TutorialPlacementGestureGate.Kind.pan, .pinch, .rotation] {
            XCTAssertFalse(gate.allows(kind, phase: .changed, enabled: true))
            XCTAssertTrue(gate.allows(kind, phase: .began, enabled: true))
            XCTAssertTrue(gate.allows(kind, phase: .changed, enabled: true))
            XCTAssertFalse(gate.allows(kind, phase: .ended, enabled: true))
            XCTAssertFalse(gate.allows(kind, phase: .changed, enabled: true))
        }
    }

    func testLockOrTrackingLossRequiresNewBeginsAfterRecovery() {
        var gate = TutorialPlacementGestureGate()
        for kind in [TutorialPlacementGestureGate.Kind.pan, .pinch, .rotation] {
            XCTAssertTrue(gate.allows(kind, phase: .began, enabled: true))
            XCTAssertFalse(gate.allows(kind, phase: .changed, enabled: false))
            XCTAssertFalse(gate.allows(kind, phase: .changed, enabled: true), "Cached transforms cannot resume after invalidation")
            XCTAssertTrue(gate.allows(kind, phase: .began, enabled: true))
        }
        gate.cancelAll()
        for kind in [TutorialPlacementGestureGate.Kind.pan, .pinch, .rotation] {
            XCTAssertFalse(gate.allows(kind, phase: .changed, enabled: true))
        }
    }

    func testSimultaneousPinchAndRotationKeepIndependentBeginState() {
        var gate = TutorialPlacementGestureGate()
        XCTAssertTrue(gate.allows(.pinch, phase: .began, enabled: true))
        XCTAssertTrue(gate.allows(.rotation, phase: .began, enabled: true))
        gate.cancel(.pinch)
        XCTAssertFalse(gate.allows(.pinch, phase: .changed, enabled: true))
        XCTAssertTrue(gate.allows(.rotation, phase: .changed, enabled: true))
        XCTAssertFalse(gate.allows(.rotation, phase: .cancelled, enabled: true))
        XCTAssertFalse(gate.allows(.rotation, phase: .changed, enabled: true))
        XCTAssertFalse(gate.allows(.rotation, phase: .began, enabled: false))
    }

    func testTabletopSizingUsesWholeAnimationEnvelopeAndLeavesTableClear() throws {
        let minimum = SIMD3<Float>(-4, -2, -1)
        let maximum = SIMD3<Float>(4, 3, 1)
        let layout = try XCTUnwrap(TutorialTabletopLayout(minimum: minimum, maximum: maximum))
        XCTAssertEqual(layout.scale * 8, 0.55, accuracy: 0.000001)
        XCTAssertEqual((minimum.y + layout.offset.y) * layout.scale, 0.01, accuracy: 0.000001)
        XCTAssertEqual(layout.offset.x, 0)
        XCTAssertEqual(layout.offset.z, 0)
    }

    func testInvalidBoundsCannotCreateAnInvisibleOrNonfinitePlacement() {
        XCTAssertNil(TutorialTabletopLayout(minimum: .zero, maximum: .zero))
        XCTAssertNil(TutorialTabletopLayout(minimum: .zero, maximum: [-1, 1, 1]))
        XCTAssertNil(TutorialTabletopLayout(minimum: .zero, maximum: [.nan, 1, 1]))
        XCTAssertNil(TutorialTabletopLayout(minimum: [-Float.greatestFiniteMagnitude, 0, 0],
                                            maximum: [.greatestFiniteMagnitude, 1, 1]))
    }

    func testTrackingNeedsFreshStableFramesAndTheSameAnchor() {
        var gate = TutorialTabletopTracking()
        XCTAssertFalse(gate.observe(timestamp: 1, normal: true, anchorPresent: true))
        XCTAssertFalse(gate.observe(timestamp: 1.1, normal: true, anchorPresent: true))
        for time in [1.2, 1.3, 1.4, 1.5, 1.6] { _ = gate.observe(timestamp: time, normal: true, anchorPresent: true) }
        XCTAssertTrue(gate.observe(timestamp: 1.7, normal: true, anchorPresent: true))
        XCTAssertFalse(gate.observe(timestamp: 1.8, normal: true, anchorPresent: false))
        XCTAssertTrue(gate.observe(timestamp: 1.9, normal: true, anchorPresent: true))
        XCTAssertFalse(gate.observe(timestamp: 2, normal: false, anchorPresent: true))
        XCTAssertFalse(gate.observe(timestamp: 2.1, normal: true, anchorPresent: true))
        XCTAssertFalse(gate.observe(timestamp: 4, normal: true, anchorPresent: true))
        XCTAssertFalse(gate.observe(timestamp: 3, normal: true, anchorPresent: true))
    }

    @MainActor
    func testStudioHandoffReusesViewAndRestoresOwnModelAndGestures() throws {
        let renderer = Tutorial3DRenderer()
        let model = ModelEntity(mesh: .generateBox(size: 0.2))
        let view = renderer.makeView(content: model, framing: .init(center: .zero, radius: 0.3))
        let originalGestures = (view.gestureRecognizers ?? []).map(ObjectIdentifier.init)
        XCTAssertTrue(renderer.handToAR() === view)
        XCTAssertNil(model.parent)
        XCTAssertTrue(view.scene.anchors.isEmpty)
        renderer.setActive(true)
        XCTAssertTrue(view.scene.anchors.isEmpty, "Late studio updates must not reclaim the AR view")
        let carrier = Entity(); carrier.addChild(model)
        renderer.restoreStudio()
        XCTAssertFalse(renderer.isHandedToAR)
        XCTAssertEqual(view.scene.anchors.count, 1)
        XCTAssertFalse(model.parent === carrier)
        XCTAssertEqual((view.gestureRecognizers ?? []).map(ObjectIdentifier.init), originalGestures)
        renderer.shutdown()
    }

    @MainActor
    func testAuthoredMotionFollowsScaledRotatedPlacementInsteadOfWorldAxes() throws {
        let controller = AssemblySceneController(tutorial: .aeris)
        let asset = Entity()
        for part in AssemblyTutorial.aeris.parts {
            let node = ModelEntity(mesh: .generateBox(size: 0.1))
            node.name = part.entityName; asset.addChild(node)
        }
        try controller.bind(asset)
        let carrier = Entity()
        carrier.scale = [0.1, 0.1, 0.1]
        carrier.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        carrier.addChild(controller.root)
        let filter = try XCTUnwrap(asset.findEntity(named: "Filter_Cartridge"))
        controller.setStep(1); controller.setProgress(1)
        XCTAssertLessThan(simd_distance(filter.position(relativeTo: controller.root), [0, 0, -0.24]), 0.00001)
        XCTAssertLessThan(simd_distance(filter.position(relativeTo: nil), [-0.024, 0, 0]), 0.00001)
        controller.setStep(2); controller.setProgress(1)
        XCTAssertLessThan(simd_length(filter.position(relativeTo: controller.root)), 0.00001)
        controller.shutdown()
    }
}
