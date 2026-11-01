import ARKit
import RealityKit

enum EquipmentOcclusionMode: String, CaseIterable, Identifiable {
    // Keep persisted raw values compatible with previous builds.
    case stableEdges, nativeHands
    var id: String { rawValue }
    var title: String { self == .stableEdges ? "Refined edges" : "Native hands" }
}

struct EquipmentOcclusionCapabilities: Equatable {
    let stableDepth: Bool
    let personDepth: Bool
    let combinedPersonAndSceneDepth: Bool

    init(stableDepth: Bool, personDepth: Bool, combinedPersonAndSceneDepth: Bool? = nil) {
        self.stableDepth = stableDepth; self.personDepth = personDepth
        self.combinedPersonAndSceneDepth = combinedPersonAndSceneDepth ?? (stableDepth && personDepth)
    }

    static var current: Self {
        let depth = ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth])
        let person = ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth)
        let combined: ARConfiguration.FrameSemantics = [.personSegmentationWithDepth, .sceneDepth, .smoothedSceneDepth]
        return Self(stableDepth: depth, personDepth: person,
                    combinedPersonAndSceneDepth: depth && person && ARWorldTrackingConfiguration.supportsFrameSemantics(combined))
    }
}

enum EquipmentOcclusionConfiguration {
    /// This path must mask out the current native-person region and its margin
    /// after temporal/spatial filtering, so only Apple's matte owns hand edges.
    static func usesObjectDepth(mode: EquipmentOcclusionMode, capabilities: EquipmentOcclusionCapabilities) -> Bool {
        mode == .stableEdges && capabilities.stableDepth &&
            (!capabilities.personDepth || capabilities.combinedPersonAndSceneDepth)
    }

    static func usesNativeHands(mode: EquipmentOcclusionMode, capabilities: EquipmentOcclusionCapabilities) -> Bool {
        capabilities.personDepth
    }

    static func effective(_ requested: EquipmentOcclusionMode, capabilities: EquipmentOcclusionCapabilities) -> EquipmentOcclusionMode {
        usesObjectDepth(mode: requested, capabilities: capabilities) ? .stableEdges : .nativeHands
    }

    static func make(mode: EquipmentOcclusionMode, capabilities: EquipmentOcclusionCapabilities) -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        config.isLightEstimationEnabled = true
        if usesNativeHands(mode: mode, capabilities: capabilities) {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        }
        if usesObjectDepth(mode: mode, capabilities: capabilities) {
            config.frameSemantics.formUnion([.sceneDepth, .smoothedSceneDepth])
        }
        return config
    }

    static func renderOptions(mode: EquipmentOcclusionMode, capabilities: EquipmentOcclusionCapabilities) -> ARView.RenderOptions {
        // Native hand matting remains active in both modes; the optional object
        // depth mask must never compete with it for person silhouette pixels.
        AROcclusionConfiguration.renderOptions(isAR: true)
    }
}
