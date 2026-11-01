import ARKit
import RealityKit

enum AROcclusionMode: String, CaseIterable, Identifiable {
    case handsFirst, automatic, peopleOnly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .handsFirst: return "Hands first"
        case .automatic: return "Refined depth"
        case .peopleOnly: return "Native depth"
        }
    }
    var accessibilityIdentifier: String {
        switch self {
        case .handsFirst: return "modeHandsFirst"
        case .automatic: return "modeAutomatic"
        case .peopleOnly: return "modePeopleOnly"
        }
    }
    var explanation: String {
        switch self {
        case .handsFirst: return "Keep hands in front of the paper, including when they cross it. Recommended for folding."
        case .automatic: return "Use depth to place hands and other objects in front of or behind the paper."
        case .peopleOnly: return "Use Apple's depth ordering for hands, without additional object depth."
        }
    }
}

struct AROcclusionCapabilities: Equatable {
    let personMask: Bool
    let personDepth: Bool
    let sceneDepth: Bool
    let sceneMesh: Bool
    let smoothedDepth: Bool
    let combinedPersonAndSceneDepth: Bool

    /// Existing synthetic callers can omit the combination result. Runtime
    /// capabilities always supply the device's check of the complete option set.
    init(personDepth: Bool, sceneDepth: Bool, sceneMesh: Bool, smoothedDepth: Bool = false,
         combinedPersonAndSceneDepth: Bool? = nil, personMask: Bool? = nil) {
        self.personMask = personMask ?? personDepth
        self.personDepth = personDepth; self.sceneDepth = sceneDepth
        self.sceneMesh = sceneMesh; self.smoothedDepth = smoothedDepth
        self.combinedPersonAndSceneDepth = combinedPersonAndSceneDepth ?? (personDepth && sceneDepth)
    }

    static var current: Self {
        let mask = ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentation)
        let person = ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth)
        let depth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        let smooth = depth && ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth])
        var combined: ARConfiguration.FrameSemantics = [.personSegmentationWithDepth, .sceneDepth]
        if smooth { combined.insert(.smoothedSceneDepth) }
        return Self(personDepth: person, sceneDepth: depth,
                    sceneMesh: ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification),
                    smoothedDepth: smooth,
                    combinedPersonAndSceneDepth: person && depth && ARWorldTrackingConfiguration.supportsFrameSemantics(combined),
                    personMask: mask)
    }
}

enum AROcclusionConfiguration {
    /// A folding guide prioritises visible hands rather than an uncertain depth
    /// comparison at the exact point where a hand crosses the virtual sheet.
    static func recommendedMode(capabilities: AROcclusionCapabilities) -> AROcclusionMode {
        capabilities.personMask ? .handsFirst : .automatic
    }

    static func effectiveMode(_ requested: AROcclusionMode, capabilities: AROcclusionCapabilities) -> AROcclusionMode {
        guard requested == .handsFirst, !capabilities.personMask else { return requested }
        return capabilities.personDepth ? .peopleOnly : .automatic
    }

    /// Custom depth is for non-person objects only. When native hands also run,
    /// the renderer must exclude their current segmentation region and its edge
    /// margin after filtering; missing segmentation must hide the custom mask.
    static func usesObjectDepth(mode: AROcclusionMode, capabilities: AROcclusionCapabilities) -> Bool {
        effectiveMode(mode, capabilities: capabilities) == .automatic && capabilities.sceneDepth &&
            (!capabilities.personDepth || capabilities.combinedPersonAndSceneDepth)
    }

    static func usesNativeHands(mode: AROcclusionMode, capabilities: AROcclusionCapabilities) -> Bool {
        effectiveMode(mode, capabilities: capabilities) == .handsFirst ? capabilities.personMask : capabilities.personDepth
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
            if effectiveMode(mode, capabilities: capabilities) == .handsFirst {
                configuration.frameSemantics.insert(.personSegmentation)
            } else { configuration.frameSemantics.insert(.personSegmentationWithDepth) }
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
