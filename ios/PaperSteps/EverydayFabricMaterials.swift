import RealityKit
import UIKit
import Metal
import OSLog

/// Reuse the same GPU textures while the procedural meshes change each frame.
/// Texture failures leave the teaching lesson usable, and are surfaced to logs.
@MainActor
enum EverydayFabricMaterials {
    private static var cache: [EverydayFabricStyle: PhysicallyBasedMaterial] = [:]
    private static var unavailable: Set<EverydayFabricStyle> = []
    private static let logger = Logger(subsystem: "org.realitycore.protacta", category: "Fabric")

    static func material(for style: EverydayFabricStyle) -> PhysicallyBasedMaterial? {
        if let existing = cache[style] { return existing }
        guard !unavailable.contains(style) else { return nil }
        do {
            let material = try load(style)
            cache[style] = material
            return material
        } catch {
            unavailable.insert(style)
            logger.error("Fabric maps unavailable: \(style.rawValue, privacy: .public), \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func load(_ style: EverydayFabricStyle, bundle: Bundle = .main) throws -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .white, texture: try texture(style, suffix: "white-basecolor", ext: "jpg", semantic: .color, bundle: bundle))
        material.normal = .init(texture: try texture(style, suffix: "normal-gl", ext: "png", semantic: .normal, bundle: bundle))
        material.roughness = .init(scale: 1, texture: try texture(style, suffix: "roughness", ext: "png", semantic: .scalar, bundle: bundle))
        material.metallic = 0.0
        material.specular = 0.2
        material.sheen = .init(tint: UIColor(white: CGFloat(style.sheen), alpha: 1))
        material.textureCoordinateTransform = .init(scale: SIMD2<Float>(repeating: 1) / style.tileSizeMetres)
        return material
    }

    private static func texture(_ style: EverydayFabricStyle, suffix: String, ext: String,
                                semantic: TextureResource.Semantic, bundle: Bundle) throws -> MaterialParameters.Texture {
        let filename = "\(style.resourcePrefix)-\(suffix)"
        guard let url = bundle.url(forResource: filename, withExtension: ext) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(filename).\(ext)"])
        }
        let resource = try TextureResource.load(contentsOf: url, options: .init(semantic: semantic, mipmapsMode: .allocateAndGenerateAll))
        let sampler = MTLSamplerDescriptor()
        sampler.sAddressMode = .repeat
        sampler.tAddressMode = .repeat
        sampler.minFilter = .linear
        sampler.magFilter = .linear
        sampler.mipFilter = .linear
        sampler.maxAnisotropy = 8
        return MaterialParameters.Texture(resource, sampler: .init(sampler))
    }
}
