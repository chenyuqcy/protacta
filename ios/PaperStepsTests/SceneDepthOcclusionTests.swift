import RealityKit
import XCTest
@testable import Protacta

/// These scene-lifecycle checks intentionally use a non-AR view. They do not
/// stand in for a real-camera depth/hand-occlusion acceptance test.
@MainActor
final class SceneDepthOcclusionTests: XCTestCase {
    func testEquipmentProfileStartsWithoutAClaimedDepthSurfaceAndResetsCleanly() {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        let occlusion = SceneDepthOcclusion(profile: .stableEquipment)
        occlusion.configure(in: view)
        XCTAssertEqual(occlusion.diagnostics.status, "Waiting for smoothed hand depth")
        XCTAssertFalse(occlusion.diagnostics.isActive)
        XCTAssertNil(occlusion.lastAcceptedDepthTimestamp)
        occlusion.reset()
        XCTAssertTrue(view.scene.anchors.isEmpty)
        XCTAssertEqual(occlusion.diagnostics.depthSource, "None")
        XCTAssertEqual(occlusion.diagnostics.expiredDisplays, 0)
        XCTAssertEqual(occlusion.diagnostics.emptyForegroundBuilds, 0)
    }
    func testConfigureRestoresRemovedDepthAnchorWithoutDuplicatingIt() throws {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        let occlusion = SceneDepthOcclusion()
        defer { occlusion.reset() }

        occlusion.configure(in: view)
        XCTAssertEqual(view.scene.anchors.count, 1)
        let depthAnchor = try XCTUnwrap(view.scene.anchors.first)
        XCTAssertNil(depthAnchor.synchronization)
        XCTAssertNil(try XCTUnwrap(depthAnchor.children.first).synchronization)
        XCTAssertTrue(occlusion.diagnostics.hasScene)

        view.scene.anchors.removeAll()
        XCTAssertFalse(occlusion.diagnostics.hasScene)
        occlusion.configure(in: view)
        XCTAssertEqual(view.scene.anchors.count, 1)
        XCTAssertTrue(view.scene.anchors.first === depthAnchor)
        XCTAssertTrue(occlusion.diagnostics.hasScene)

        occlusion.configure(in: view)
        XCTAssertEqual(view.scene.anchors.count, 1, "Reconfiguration must not duplicate the depth anchor")
        XCTAssertFalse(occlusion.diagnostics.isActive, "Attaching an anchor is not evidence of a displayed depth surface")
        XCTAssertEqual(occlusion.diagnostics.displayedFrames, 0)
    }

    func testResetPreservesUnrelatedSceneAndCanConfigureAgain() {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        let unrelated = AnchorEntity(world: [1, 0, 0])
        view.scene.addAnchor(unrelated)
        let occlusion = SceneDepthOcclusion()
        defer { occlusion.reset() }

        occlusion.configure(in: view)
        XCTAssertEqual(view.scene.anchors.count, 2)
        occlusion.reset()
        XCTAssertEqual(view.scene.anchors.count, 1)
        XCTAssertTrue(view.scene.anchors.first === unrelated)
        let reset = occlusion.diagnostics
        XCTAssertFalse(reset.hasScene)
        XCTAssertFalse(reset.isActive)
        XCTAssertEqual(reset.status, "Not active")
        XCTAssertNil(reset.meshAgeMilliseconds)
        XCTAssertEqual(reset.triangleCount, 0)

        occlusion.configure(in: view)
        XCTAssertEqual(view.scene.anchors.count, 2)
        XCTAssertTrue(occlusion.diagnostics.hasScene)
        XCTAssertEqual(occlusion.diagnostics.status, "Waiting for raw scene depth")
    }
}
