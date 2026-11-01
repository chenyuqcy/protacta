import ARKit
import RealityKit
import XCTest
@testable import Protacta

/// These tests validate configuration and lesson-state contracts only. They do
/// not run a camera session or establish physical hand/object occlusion quality.
final class AROcclusionConfigurationTests: XCTestCase {
    @MainActor
    func testHandsFirstUsesAMatteWithoutAnyCompetingDepthOrderingOrSceneMesh() {
        let supported = AROcclusionCapabilities(personDepth: true, sceneDepth: true, sceneMesh: true,
                                               smoothedDepth: true, personMask: true)
        let config = AROcclusionConfiguration.make(mode: .handsFirst, capabilities: supported)
        XCTAssertEqual(config.frameSemantics, [.personSegmentation],
                       "At contact, hand visibility must not alternate on an estimated-depth comparison")
        XCTAssertEqual(config.sceneReconstruction, [])
        XCTAssertFalse(AROcclusionConfiguration.usesObjectDepth(mode: .handsFirst, capabilities: supported))
        XCTAssertTrue(AROcclusionConfiguration.usesNativeHands(mode: .handsFirst, capabilities: supported))
        XCTAssertEqual(AROcclusionConfiguration.sceneOptions(mode: .handsFirst, capabilities: supported), [])
        let render = AROcclusionConfiguration.renderOptions(isAR: true, mode: .handsFirst, capabilities: supported)
        XCTAssertFalse(render.contains(.disablePersonOcclusion))
        XCTAssertTrue(render.contains(.disableGroundingShadows))
    }

    @MainActor
    func testHandsFirstWorksOnAPersonMaskOnlyDeviceWithoutRequestingPersonDepth() {
        let maskOnly = AROcclusionCapabilities(personDepth: false, sceneDepth: false, sceneMesh: false, personMask: true)
        XCTAssertEqual(AROcclusionConfiguration.recommendedMode(capabilities: maskOnly), .handsFirst)
        XCTAssertEqual(AROcclusionConfiguration.make(mode: .handsFirst, capabilities: maskOnly).frameSemantics,
                       [.personSegmentation])
        XCTAssertTrue(AROcclusionConfiguration.usesNativeHands(mode: .handsFirst, capabilities: maskOnly))
    }

    @MainActor
    func testUnsupportedHandsFirstFallsBackWithoutRequestingUnsupportedSegmentation() {
        for depth in [false, true] {
            for scene in [false, true] {
                let unsupported = AROcclusionCapabilities(personDepth: depth, sceneDepth: scene,
                                                          sceneMesh: true, personMask: false)
                let expected: AROcclusionMode = depth ? .peopleOnly : .automatic
                XCTAssertEqual(AROcclusionConfiguration.effectiveMode(.handsFirst, capabilities: unsupported), expected)
                XCTAssertEqual(AROcclusionConfiguration.recommendedMode(capabilities: unsupported), .automatic)
                let config = AROcclusionConfiguration.make(mode: .handsFirst, capabilities: unsupported)
                // personSegmentationWithDepth includes the segmentation bit;
                // compare the exact request rather than treating them as
                // independent flags on synthetic capability combinations.
                let expectedSemantics: ARConfiguration.FrameSemantics = depth ? [.personSegmentationWithDepth]
                    : scene ? [.sceneDepth] : []
                XCTAssertEqual(config.frameSemantics, expectedSemantics)
                XCTAssertEqual(config.frameSemantics.contains(.personSegmentationWithDepth), depth)
                XCTAssertEqual(config.frameSemantics.contains(.sceneDepth), !depth && scene)
            }
        }
    }

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
                    XCTAssertEqual(configuration.sceneReconstruction, [], context)
                    XCTAssertFalse(options.contains(.occlusion), context)
                    XCTAssertFalse(options.contains(.receivesLighting), "Real objects must not receive dark virtual contact patches: \(context)")
                }
            }
        }
    }

    @MainActor
    func testRefinedModeKeepsNativeHandMattingAndOnlyAddsObjectDepthWhenCombinedSemanticsWork() {
        for person in [false, true] {
            for depth in [false, true] {
                for smoothed in [false, true] {
                    for combined in [false, true] {
                        let supported = AROcclusionCapabilities(personDepth: person, sceneDepth: depth, sceneMesh: true,
                                                               smoothedDepth: smoothed, combinedPersonAndSceneDepth: combined)
                        let config = AROcclusionConfiguration.make(mode: .automatic, capabilities: supported)
                        let objectDepth = depth && (!person || combined)
                        let context = "person=\(person), depth=\(depth), smoothed=\(smoothed), combined=\(combined)"
                        XCTAssertEqual(AROcclusionConfiguration.usesObjectDepth(mode: .automatic, capabilities: supported), objectDepth, context)
                        XCTAssertEqual(AROcclusionConfiguration.usesNativeHands(mode: .automatic, capabilities: supported), person, context)
                        XCTAssertEqual(config.frameSemantics.contains(.sceneDepth), objectDepth, context)
                        XCTAssertEqual(config.frameSemantics.contains(.smoothedSceneDepth), objectDepth && smoothed, context)
                        XCTAssertEqual(config.frameSemantics.contains(.personSegmentationWithDepth), person, context)
                        XCTAssertEqual(config.sceneReconstruction, [], context)
                        let render = AROcclusionConfiguration.renderOptions(isAR: true, mode: .automatic, capabilities: supported)
                        XCTAssertFalse(render.contains(.disablePersonOcclusion), "The custom non-person mask must not turn off hand matting: \(context)")
                        XCTAssertTrue(render.contains(.disableGroundingShadows), context)
                        XCTAssertFalse(AROcclusionConfiguration.sceneOptions(mode: .automatic, capabilities: supported).contains(.occlusion),
                                       "A reconstructed scene mesh must not add another hand silhouette owner")
                    }
                }
            }
        }
    }

    @MainActor
    func testUnsupportedCombinedSetFallsBackToNativeHandsInsteadOfRequestingIndividualUnsupportedUnion() {
        let separateOnly = AROcclusionCapabilities(personDepth: true, sceneDepth: true, sceneMesh: true,
                                                  smoothedDepth: true, combinedPersonAndSceneDepth: false)
        let config = AROcclusionConfiguration.make(mode: .automatic, capabilities: separateOnly)
        XCTAssertEqual(config.frameSemantics, [.personSegmentationWithDepth])
        XCTAssertFalse(AROcclusionConfiguration.usesObjectDepth(mode: .automatic, capabilities: separateOnly))
        XCTAssertTrue(AROcclusionConfiguration.usesNativeHands(mode: .automatic, capabilities: separateOnly))
    }

    func testSyntheticInitializerPreservesExistingCallersAndModeRawValues() {
        let both = AROcclusionCapabilities(personDepth: true, sceneDepth: true, sceneMesh: false)
        XCTAssertTrue(both.combinedPersonAndSceneDepth)
        XCTAssertFalse(AROcclusionCapabilities(personDepth: false, sceneDepth: true, sceneMesh: false).combinedPersonAndSceneDepth)
        XCTAssertEqual(AROcclusionMode.automatic.rawValue, "automatic")
        XCTAssertEqual(AROcclusionMode.peopleOnly.rawValue, "peopleOnly")
        XCTAssertEqual(AROcclusionMode.automatic.title, "Refined depth")
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
                    XCTAssertFalse(AROcclusionConfiguration.usesObjectDepth(mode: .peopleOnly, capabilities: capabilities), context)
                    XCTAssertEqual(AROcclusionConfiguration.usesNativeHands(mode: .peopleOnly, capabilities: capabilities), personDepth, context)
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

        for mode in [AROcclusionMode.peopleOnly, .automatic, .handsFirst] {
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

        for mode in [AROcclusionMode.peopleOnly, .automatic, .handsFirst] {
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
