import ARKit
import RealityKit

enum EquipmentOcclusionMode: String, CaseIterable, Identifiable {
    case stableEdges, nativeHands
    var id: String { rawValue }
    var title: String { self == .stableEdges ? "Stable edges" : "Native hands" }
}

struct EquipmentOcclusionCapabilities {
    let stableDepth: Bool
    let personDepth: Bool
    static var current: Self {
        Self(stableDepth: ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth]),
             personDepth: ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth))
    }
}

enum EquipmentOcclusionConfiguration {
    static func effective(_ requested: EquipmentOcclusionMode, capabilities: EquipmentOcclusionCapabilities) -> EquipmentOcclusionMode {
        requested == .stableEdges && capabilities.stableDepth ? .stableEdges : .nativeHands
    }
    static func make(mode: EquipmentOcclusionMode, capabilities: EquipmentOcclusionCapabilities) -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        config.isLightEstimationEnabled = true
        if effective(mode, capabilities: capabilities) == .stableEdges {
            config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        } else if capabilities.personDepth {
            config.frameSemantics = [.personSegmentationWithDepth]
        }
        return config
    }
    static func renderOptions(mode: EquipmentOcclusionMode, capabilities: EquipmentOcclusionCapabilities) -> ARView.RenderOptions {
        var options = AROcclusionConfiguration.renderOptions(isAR: true)
        // The stable mode has one owner of depth rejection: the calibrated
        // LiDAR occluder. A second native silhouette must not flicker over it.
        if effective(mode, capabilities: capabilities) == .stableEdges { options.insert(.disablePersonOcclusion) }
        return options
    }
}
