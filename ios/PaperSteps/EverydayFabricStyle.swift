import Foundation

/// Scan scale is measured in metres, matching undeformed fabric UVs.
/// Keep this metadata shared by live RealityKit and offline catalogue art.
enum EverydayFabricStyle: String, CaseIterable {
    case terry, jersey, linen

    static func fabric(forPartID id: String) -> Self? {
        if id.hasPrefix("towel_") { return .terry }
        if id.hasPrefix("shirt_") { return .jersey }
        if id.hasPrefix("sheet_") { return .linen }
        // A fine woven surface on the teaching ribbons, retaining their colour
        // identity. Cords and the collar are not reclassified as flat cloth.
        if id.hasPrefix("tie-"), !id.hasPrefix("tie-collar-") { return .linen }
        return nil
    }

    var resourcePrefix: String { "fabric-\(rawValue)" }
    var tileSizeMetres: SIMD2<Float> {
        switch self {
        case .terry: return [0.367054, 0.363200]
        case .jersey: return [0.263603, 0.263800]
        case .linen: return [0.270708139, 0.271299988]
        }
    }
    var sheen: Float { self == .terry ? 0.12 : 0.06 }

    static func trimTint(forPartID id: String) -> Float {
        if id == "shirt_collar" { return 0.97 }
        if id.contains("_hem") || id == "shirt_cuffs" { return 0.98 }
        return 1
    }

    static func tint(forPartID id: String, colorIndex: Int) -> SIMD3<Float> {
        if id.hasPrefix("tie-"), !id.hasPrefix("tie-collar-") {
            return EverydaySurfaceStyle.color(index: colorIndex)
        }
        return SIMD3(repeating: trimTint(forPartID: id))
    }
}
