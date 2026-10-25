import ARKit
import RealityKit
import XCTest
@testable import Foliafold

/// These tests validate configuration and lesson-state contracts only. They do
/// not run a camera session or establish physical hand/object occlusion quality.
final class AROcclusionConfigurationTests: XCTestCase {
    @MainActor
    func testAutomaticModeEnablesOnlySupportedOcclusionFeatures() {
        for personDepth in [false, true] {
            for sceneDepth in [false, true] {
                for sceneMesh in [false, true] {
                    let capabilities = AROcclusionCapabilities(
                        personDepth: personDepth, sceneDepth: sceneDepth, sceneMesh: sceneMesh
                    )
                    let configuration = AROcclusionConfiguration.make(mode: .automatic, capabilities: capabilities)
                    let options = AROcclusionConfiguration.sceneOptions(mode: .automatic, capabilities: capabilities)
                    let context = "personDepth=\(personDepth), sceneDepth=\(sceneDepth), sceneMesh=\(sceneMesh)"

                    XCTAssertEqual(configuration.frameSemantics.contains(.personSegmentationWithDepth), personDepth, context)
                    XCTAssertEqual(configuration.frameSemantics.contains(.sceneDepth), sceneDepth, context)
                    XCTAssertFalse(configuration.frameSemantics.contains(.smoothedSceneDepth), context)
                    XCTAssertEqual(configuration.sceneReconstruction, sceneMesh ? .meshWithClassification : [], context)
                    XCTAssertEqual(options.contains(.occlusion), sceneMesh, context)
                }
            }
        }
    }

    @MainActor
    func testPeopleOnlyModeRetainsSupportedNativeOcclusionWithoutSceneDepthOrMesh() {
        for personDepth in [false, true] {
            for sceneDepth in [false, true] {
                for sceneMesh in [false, true] {
                    let capabilities = AROcclusionCapabilities(
                        personDepth: personDepth, sceneDepth: sceneDepth, sceneMesh: sceneMesh
                    )
                    let configuration = AROcclusionConfiguration.make(mode: .peopleOnly, capabilities: capabilities)
                    let options = AROcclusionConfiguration.sceneOptions(mode: .peopleOnly, capabilities: capabilities)
                    let context = "personDepth=\(personDepth), sceneDepth=\(sceneDepth), sceneMesh=\(sceneMesh)"

                    XCTAssertEqual(configuration.frameSemantics.contains(.personSegmentationWithDepth), personDepth, context)
                    XCTAssertFalse(configuration.frameSemantics.contains(.sceneDepth), context)
                    XCTAssertFalse(configuration.frameSemantics.contains(.smoothedSceneDepth), context)
                    XCTAssertEqual(configuration.sceneReconstruction, [], context)
                    XCTAssertFalse(options.contains(.occlusion), context)
                }
            }
        }
    }

    @MainActor
    func testModeChangesKeepAPartialFoldAndInjectedPlacementWithoutCreatingARView() {
        let controller = LessonController()
        controller.selectLesson(.dart)
        controller.begin()
        controller.goToStep(3)
        controller.scrub(to: 0.4)
        // Inject controller flags, not a fake camera frame or physical anchor.
        controller.isAR = true
        controller.placed = true
        controller.trackingReady = true

        for mode in [AROcclusionMode.peopleOnly, .automatic] {
            controller.setOcclusionMode(mode)
            XCTAssertEqual(controller.lesson, .dart)
            XCTAssertTrue(controller.started)
            XCTAssertEqual(controller.stepIndex, 3)
            XCTAssertEqual(controller.progress, 0.4, accuracy: 0.0001)
            XCTAssertFalse(controller.completed)
            XCTAssertTrue(controller.placed)
            XCTAssertTrue(controller.isAR)
            XCTAssertFalse(controller.isPlaying)
            XCTAssertNil(controller.arView, "Changing a preference must not create or request a camera renderer")
        }
    }

    @MainActor
    func testModeChangesKeepACompletedLessonWithoutCreatingARView() {
        let controller = LessonController()
        controller.selectLesson(.dart)
        controller.begin()
        controller.goToStep(controller.lastStep)
        controller.scrub(to: 1)
        controller.next()
        XCTAssertTrue(controller.completed)
        controller.isAR = true
        controller.placed = true
        controller.trackingReady = true

        for mode in [AROcclusionMode.peopleOnly, .automatic] {
            controller.setOcclusionMode(mode)
            XCTAssertEqual(controller.lesson, .dart)
            XCTAssertTrue(controller.started)
            XCTAssertEqual(controller.stepIndex, controller.lastStep)
            XCTAssertEqual(controller.progress, 1, accuracy: 0.0001)
            XCTAssertTrue(controller.completed)
            XCTAssertTrue(controller.placed)
            XCTAssertTrue(controller.isAR)
            XCTAssertFalse(controller.isPlaying)
            XCTAssertNil(controller.arView)
        }
    }
}
