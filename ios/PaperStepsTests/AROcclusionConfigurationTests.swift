import ARKit
import RealityKit
import XCTest
@testable import Protacta

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

                    XCTAssertEqual(configuration.frameSemantics.contains(.personSegmentationWithDepth), personDepth && !sceneDepth, context)
                    XCTAssertEqual(configuration.frameSemantics.contains(.sceneDepth), sceneDepth, context)
                    XCTAssertFalse(configuration.frameSemantics.contains(.smoothedSceneDepth), context)
                    XCTAssertEqual(configuration.sceneReconstruction, [], context)
                    XCTAssertFalse(options.contains(.occlusion), context)
                    XCTAssertFalse(options.contains(.receivesLighting), "Real objects must not receive dark virtual contact patches: \(context)")
                }
            }
        }
    }

    @MainActor
    func testStablePaperUsesOneSmoothedDepthOwnerWithConservativePaperGeometry() {
        let supported = AROcclusionCapabilities(personDepth: true, sceneDepth: true, sceneMesh: true, smoothedDepth: true)
        let config = AROcclusionConfiguration.make(mode: .automatic, capabilities: supported)
        XCTAssertTrue(config.frameSemantics.contains(.sceneDepth))
        XCTAssertTrue(config.frameSemantics.contains(.smoothedSceneDepth))
        XCTAssertFalse(config.frameSemantics.contains(.personSegmentationWithDepth))
        XCTAssertEqual(config.sceneReconstruction, [])
        let stable = AROcclusionConfiguration.renderOptions(isAR: true, mode: .automatic, capabilities: supported)
        XCTAssertTrue(stable.contains(.disablePersonOcclusion))
        XCTAssertTrue(stable.contains(.disableGroundingShadows))
        let native = AROcclusionConfiguration.renderOptions(isAR: true, mode: .peopleOnly, capabilities: supported)
        XCTAssertFalse(native.contains(.disablePersonOcclusion))
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
                    XCTAssertFalse(options.contains(.receivesLighting), context)
                }
            }
        }
    }

    @MainActor
    func testCameraRenderingRemovesContactDarkeningAndRetainsPersonOcclusion() {
        let cameraOptions = AROcclusionConfiguration.renderOptions(isAR: true)
        XCTAssertTrue(cameraOptions.contains(.disableGroundingShadows))
        XCTAssertFalse(cameraOptions.contains(.disablePersonOcclusion), "Removing contact darkening must not expose the model through a hand")
        XCTAssertFalse(cameraOptions.contains(.disableAREnvironmentLighting), "Paper shading still uses real scene lighting")
        let studioOptions = AROcclusionConfiguration.renderOptions(isAR: false)
        XCTAssertFalse(studioOptions.contains(.disableGroundingShadows), "Returning to the studio restores its normal fold shading")
    }

    @MainActor
    func testPaperLightingSwitchPreservesPartialFoldAndMeshAcrossARAndStudio() throws {
        guard #available(iOS 18.0, *) else { throw XCTSkip("Per-entity grounding components require iOS 18") }
        let paper = PaperModel()
        paper.setPose(lesson: .dart, step: 3, progress: 0.4)
        let originalFrame = paper.frame
        let front = try XCTUnwrap(paper.root.findEntity(named: "Paper front") as? ModelEntity)
        let mesh = try XCTUnwrap(front.model?.mesh)
        paper.resetDiagnostics()

        // Repeat the AR setting to cover session recovery and mode changes,
        // then restore the studio without rebuilding/advancing the fold.
        for enabled in [false, false, true] {
            paper.setGroundingShadowsEnabled(enabled)
            for name in ["Paper front", "Paper reverse", "Moving flap front", "Moving flap reverse"] {
                let entity = try XCTUnwrap(paper.root.findEntity(named: name))
                let shadow = try XCTUnwrap(entity.components[GroundingShadowComponent.self])
                XCTAssertEqual(shadow.castsShadow, enabled, name)
                XCTAssertEqual(shadow.receivesShadow, enabled, name)
            }
            for name in ["Paper edges", "Moving flap outline", "Crease guide", "Fold direction"] {
                let entity = try XCTUnwrap(paper.root.findEntity(named: name))
                let shadow = try XCTUnwrap(entity.components[GroundingShadowComponent.self])
                XCTAssertFalse(shadow.castsShadow, name)
                XCTAssertFalse(shadow.receivesShadow, name)
            }
            XCTAssertTrue(front.model?.mesh === mesh)
            XCTAssertEqual(paper.frame.bounds.minimum, originalFrame.bounds.minimum)
            XCTAssertEqual(paper.frame.bounds.maximum, originalFrame.bounds.maximum)
            XCTAssertEqual(paper.diagnostics.poseEvaluations, 0)
            XCTAssertEqual(paper.diagnostics.meshGenerationCalls, 0)
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
