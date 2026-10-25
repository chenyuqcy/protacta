import ARKit
import RealityKit

enum AROcclusionMode: String, CaseIterable, Identifiable {
    case automatic, peopleOnly

    var id: String { rawValue }
    var title: String { self == .automatic ? "Hands and objects" : "Hands only" }
    var explanation: String {
        self == .automatic
            ? "Use Apple's hand occlusion and add live object depth when this device supports it."
            : "Use Apple's native hand occlusion on its own. Try this if your hand is still covered. Other objects may not hide the paper."
    }
}

struct AROcclusionCapabilities: Equatable {
    let personDepth: Bool
    let sceneDepth: Bool
    let sceneMesh: Bool

    static var current: Self {
        Self(personDepth: ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth),
             sceneDepth: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
             sceneMesh: ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification))
    }
}

enum AROcclusionConfiguration {
    static func make(mode: AROcclusionMode, capabilities: AROcclusionCapabilities) -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic
        configuration.isLightEstimationEnabled = true
        if capabilities.personDepth { configuration.frameSemantics.insert(.personSegmentationWithDepth) }
        if mode == .automatic {
            if capabilities.sceneDepth { configuration.frameSemantics.insert(.sceneDepth) }
            if capabilities.sceneMesh { configuration.sceneReconstruction = .meshWithClassification }
        }
        // The extra mesh uses current depth, not a second temporally-smoothed
        // stream. Native people occlusion remains enabled in both modes.
        return configuration
    }

    static func sceneOptions(mode: AROcclusionMode, capabilities: AROcclusionCapabilities) -> ARView.Environment.SceneUnderstanding.Options {
        mode == .automatic && capabilities.sceneMesh ? [.occlusion, .receivesLighting] : []
    }
}
