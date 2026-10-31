import ARKit
import RealityKit

enum AROcclusionMode: String, CaseIterable, Identifiable {
    case automatic, peopleOnly

    var id: String { rawValue }
    var title: String { self == .automatic ? "Stable edges" : "Native hands" }
    var explanation: String {
        self == .automatic
            ? "Steadier hand and object edges on supported LiDAR devices."
            : "Use Apple's hand occlusion. Other objects may stay behind the model."
    }
}

struct AROcclusionCapabilities: Equatable {
    let personDepth: Bool
    let sceneDepth: Bool
    let sceneMesh: Bool
    let smoothedDepth: Bool

    init(personDepth: Bool, sceneDepth: Bool, sceneMesh: Bool, smoothedDepth: Bool = false) {
        self.personDepth = personDepth; self.sceneDepth = sceneDepth
        self.sceneMesh = sceneMesh; self.smoothedDepth = smoothedDepth
    }

    static var current: Self {
        Self(personDepth: ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth),
             sceneDepth: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
             sceneMesh: ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification),
             smoothedDepth: ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth))
    }
}

enum AROcclusionConfiguration {
    static func renderOptions(isAR: Bool, mode: AROcclusionMode? = nil,
                              capabilities: AROcclusionCapabilities? = nil) -> ARView.RenderOptions {
        var options: ARView.RenderOptions = [.disableMotionBlur, .disableDepthOfField]
        // A teaching model can intersect real paper, hands and the table.
        // Grounding adds ambient occlusion/contact shadows at that intersection;
        // keep the camera image visible there instead of drawing a dark patch.
        if isAR { options.insert(.disableGroundingShadows) }
        if isAR, mode == .automatic, capabilities?.sceneDepth == true {
            options.insert(.disablePersonOcclusion)
        }
        return options
    }

    static func make(mode: AROcclusionMode, capabilities: AROcclusionCapabilities) -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic
        configuration.isLightEstimationEnabled = true
        if mode == .automatic && capabilities.sceneDepth {
            configuration.frameSemantics.insert(.sceneDepth)
            if capabilities.smoothedDepth { configuration.frameSemantics.insert(.smoothedSceneDepth) }
        } else if capabilities.personDepth {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
        }
        // Use one depth owner. Native silhouettes and a reconstructed mesh
        // must not independently alternate at the moving hand's boundary.
        return configuration
    }

    static func sceneOptions(mode: AROcclusionMode, capabilities: AROcclusionCapabilities) -> ARView.Environment.SceneUnderstanding.Options {
        []
    }
}
