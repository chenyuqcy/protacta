import ARKit
import AVFoundation
import RealityKit
import XCTest
import simd
@testable import Protacta

/// Runtime mesh/session checks. They exercise the actual RealityKit scene, not
/// a camera recording, physical fabric movement or real-object registration.
@MainActor
final class EverydaySceneControllerTests: XCTestCase {
    func testEveryCourseDrawsActualMeshesAtTheStartMiddleAndTargetOfEveryAction() throws {
        for course in EverydayTutorialID.allCases {
            let controller = EverydaySceneController(courseID: course)
            defer { controller.shutdown() }
            let view = controller.makeView()
            let reference = try teachingReference(in: view)
            for action in EverydayTutorialCourse.course(course).actions.indices {
                for progress in [0.0, 0.5, 1.0] {
                    controller.select(actionIndex: action, progress: progress)
                    XCTAssertNil(controller.failure, "\(course), action \(action), progress \(progress)")
                    XCTAssertTrue(reference.isEnabled)
                    let rendered = try meshSnapshot(in: reference)
                    XCTAssertFalse(rendered.isEmpty, "\(course) must draw surfaces rather than only a caption")
                    let bounds = reference.visualBounds(relativeTo: reference)
                    XCTAssertTrue((0..<3).allSatisfy { bounds.extents[$0].isFinite && bounds.extents[$0] > 0 })
                }
            }
        }
    }

    func testChangingAndReplayingPosesUpdatesTheMeshInsideOnePersistentView() throws {
        let controller = EverydaySceneController(courseID: .towel)
        defer { controller.shutdown() }
        let view = controller.makeView()
        let reference = try teachingReference(in: view)
        let initial = try meshSnapshot(in: reference)
        let identities = descendants(of: reference).compactMap { $0 as? ModelEntity }.map(ObjectIdentifier.init)
        controller.seek(0.5)
        let middle = try meshSnapshot(in: reference)
        XCTAssertNotEqual(initial, middle, "The rendered vertices must move when the playback pose changes")
        XCTAssertTrue(controller.makeView() === view)
        XCTAssertTrue(try teachingReference(in: view) === reference)
        XCTAssertEqual(descendants(of: reference).compactMap { $0 as? ModelEntity }.map(ObjectIdentifier.init), identities,
                       "A pose update must preserve the existing visible entities")
        controller.select(actionIndex: 2, progress: 1)
        XCTAssertNotEqual(try meshSnapshot(in: reference), initial)
        controller.select(actionIndex: 0, progress: 0.5)
        XCTAssertEqual(try meshSnapshot(in: reference), middle, "Replay returns to the same authored intermediate pose")
        XCTAssertTrue(controller.makeView() === view)
        XCTAssertEqual(view.scene.anchors.count, 1)
    }

    func testUnsupportedSimulatorARPreservesTheExactPoseAndDoesNotRequestCameraAccess() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This exercises the unsupported Simulator fallback, not physical AR placement")
        #endif
        guard !TutorialTabletopARController.layoutPreviewRequested else {
            throw XCTSkip("A layout fixture intentionally takes a separate AR entry path")
        }
        guard !TutorialTabletopARController.supportsAR else {
            throw XCTSkip("Requires a device/runtime without world-tracking support")
        }
        let permission = AVCaptureDevice.authorizationStatus(for: .video)
        let controller = EverydaySceneController(courseID: .fourInHand)
        defer { controller.shutdown() }
        let view = controller.makeView()
        controller.select(actionIndex: 3, progress: 0.43, autoplay: true)
        let reference = try teachingReference(in: view)
        let pose = try meshSnapshot(in: reference)
        XCTAssertFalse(controller.enterAR())
        XCTAssertFalse(controller.isAR)
        XCTAssertFalse(controller.motion.isPlaying)
        XCTAssertEqual(controller.motion.actionIndex, 3)
        XCTAssertEqual(controller.motion.progress, 0.43)
        XCTAssertEqual(try meshSnapshot(in: reference), pose)
        XCTAssertTrue(view.cameraMode == .nonAR)
        XCTAssertTrue(controller.makeView() === view)
        XCTAssertNotNil(controller.arEntryError)
        XCTAssertNil(view.session.configuration, "Unsupported AR must not start a camera session")
        XCTAssertFalse(controller.tabletop.isRequestingCamera)
        XCTAssertEqual(AVCaptureDevice.authorizationStatus(for: .video), permission)
    }

    func testInactiveAndActiveRoundTripKeepsThePausedMeshUntilTheUserPlaysAgain() throws {
        let controller = EverydaySceneController(courseID: .tShirt)
        defer { controller.shutdown() }
        let view = controller.makeView()
        controller.select(actionIndex: 2, progress: 0.37, autoplay: true)
        let reference = try teachingReference(in: view)
        let pose = try meshSnapshot(in: reference)
        let progress = controller.motion.progress
        XCTAssertTrue(controller.motion.isPlaying)
        controller.handleInactive()
        XCTAssertFalse(controller.motion.isPlaying)
        XCTAssertEqual(controller.motion.progress, progress)
        XCTAssertEqual(try meshSnapshot(in: reference), pose)
        XCTAssertTrue(view.scene.anchors.isEmpty, "The suspended studio should detach its scene")
        controller.tick(elapsed: 0.12, allowed: true)
        controller.handleActive()
        controller.tick(elapsed: 0.12, allowed: true)
        XCTAssertFalse(controller.motion.isPlaying, "Activation must not silently resume a hands-on lesson")
        XCTAssertEqual(controller.motion.progress, progress)
        XCTAssertEqual(try meshSnapshot(in: reference), pose)
        XCTAssertTrue(try teachingReference(in: view) === reference)
        XCTAssertTrue(controller.makeView() === view)
        controller.play()
        controller.tick(elapsed: 0.12, allowed: true)
        XCTAssertGreaterThan(controller.motion.progress, progress)
        XCTAssertNotEqual(try meshSnapshot(in: reference), pose, "Explicit Play must resume actual geometry movement")
    }

    private func teachingReference(in view: ARView, file: StaticString = #filePath, line: UInt = #line) throws -> Entity {
        let entities = view.scene.anchors.flatMap { descendants(of: $0) }
        return try XCTUnwrap(entities.first { $0.name == "Everyday spatial teaching reference" },
                             "The visible studio must contain its teaching model", file: file, line: line)
    }

    private func descendants(of entity: Entity) -> [Entity] {
        [entity] + entity.children.flatMap { descendants(of: $0) }
    }

    private func meshSnapshot(in root: Entity, file: StaticString = #filePath, line: UInt = #line) throws -> [String: [SIMD3<Float>]] {
        var result: [String: [SIMD3<Float>]] = [:]
        let models = descendants(of: root).compactMap { $0 as? ModelEntity }
        XCTAssertFalse(models.isEmpty, file: file, line: line)
        for entity in models {
            let component = try XCTUnwrap(entity.model, entity.name, file: file, line: line)
            let parts = component.mesh.contents.models.flatMap { Array($0.parts) }
            XCTAssertFalse(parts.isEmpty, entity.name, file: file, line: line)
            let positions = parts.flatMap { $0.positions.elements }
            XCTAssertFalse(positions.isEmpty, entity.name, file: file, line: line)
            XCTAssertTrue(positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }, entity.name, file: file, line: line)
            XCTAssertTrue(parts.allSatisfy { ($0.triangleIndices?.elements.count ?? 0) >= 3 }, entity.name, file: file, line: line)
            XCTAssertFalse(component.materials.isEmpty, entity.name, file: file, line: line)
            XCTAssertNil(result.updateValue(positions, forKey: entity.name), "Mesh IDs must be unique", file: file, line: line)
        }
        return result
    }
}
