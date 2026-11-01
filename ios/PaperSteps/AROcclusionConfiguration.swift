import ARKit
import RealityKit

enum AROcclusionMode: String, CaseIterable, Identifiable {
    case automatic, peopleOnly

    var id: String { rawValue }
    var title: String { self == .automatic ? "Refined edges" : "Native hands" }
    var explanation: String {
        self == .automatic
            ? "Apple's refined hand outline, with supported LiDAR depth for other objects."
            : "Use Apple's hand occlusion. Other objects may stay behind the model."
    }
}

struct AROcclusionCapabilities: Equatable {
    let personDepth: Bool
    let sceneDepth: Bool
    let sceneMesh: Bool
    let smoothedDepth: Bool
    let combinedPersonAndSceneDepth: Bool

    /// Existing synthetic callers can omit the combination result. Runtime
    /// capabilities always supply the device's check of the complete option set.
    init(personDepth: Bool, sceneDepth: Bool, sceneMesh: Bool, smoothedDepth: Bool = false,
         combinedPersonAndSceneDepth: Bool? = nil) {
        self.personDepth = personDepth; self.sceneDepth = sceneDepth
        self.sceneMesh = sceneMesh; self.smoothedDepth = smoothedDepth
        self.combinedPersonAndSceneDepth = combinedPersonAndSceneDepth ?? (personDepth && sceneDepth)
    }

    static var current: Self {
        let person = ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth)
        let depth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        let smooth = depth && ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth])
        var combined: ARConfiguration.FrameSemantics = [.personSegmentationWithDepth, .sceneDepth]
        if smooth { combined.insert(.smoothedSceneDepth) }
        return Self(personDepth: person, sceneDepth: depth,
                    sceneMesh: ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification),
                    smoothedDepth: smooth,
                    combinedPersonAndSceneDepth: person && depth && ARWorldTrackingConfiguration.supportsFrameSemantics(combined))
    }
}

enum AROcclusionConfiguration {
    /// Custom depth is for non-person objects only. When native hands also run,
    /// the renderer must exclude their current segmentation region and its edge
    /// margin after filtering; missing segmentation must hide the custom mask.
    static func usesObjectDepth(mode: AROcclusionMode, capabilities: AROcclusionCapabilities) -> Bool {
        mode == .automatic && capabilities.sceneDepth &&
            (!capabilities.personDepth || capabilities.combinedPersonAndSceneDepth)
    }

    static func usesNativeHands(mode: AROcclusionMode, capabilities: AROcclusionCapabilities) -> Bool {
        capabilities.personDepth
    }

    static func renderOptions(isAR: Bool, mode: AROcclusionMode? = nil,
                              capabilities: AROcclusionCapabilities? = nil) -> ARView.RenderOptions {
        var options: ARView.RenderOptions = [.disableMotionBlur, .disableDepthOfField]
        // Native matting owns hand silhouettes. Do not disable it when custom
        // non-person depth is enabled; that mask must exclude the hand region.
        // Grounding at a real-paper/hand/table intersection can add a dark patch.
        if isAR { options.insert(.disableGroundingShadows) }
        return options
    }

    static func make(mode: AROcclusionMode, capabilities: AROcclusionCapabilities) -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic
        configuration.isLightEstimationEnabled = true
        if usesNativeHands(mode: mode, capabilities: capabilities) {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
        }
        if usesObjectDepth(mode: mode, capabilities: capabilities) {
            configuration.frameSemantics.insert(.sceneDepth)
            if capabilities.smoothedDepth { configuration.frameSemantics.insert(.smoothedSceneDepth) }
        }
        // No reconstructed scene mesh adds a second owner at the hand boundary.
        return configuration
    }

    static func sceneOptions(mode: AROcclusionMode, capabilities: AROcclusionCapabilities) -> ARView.Environment.SceneUnderstanding.Options {
        []
    }
}
