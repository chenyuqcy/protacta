import AppKit
import SceneKit
import Metal
import MetalKit
import simd

/// Static catalogue art rendered from the exact procedural teaching geometry.
/// Run render_everyday_catalog_thumbnails.sh; no live 3D views are needed in the
/// scrolling home screen. Poses are illustrative, not saved learner progress.
@main
enum EverydayCatalogThumbnailRenderer {
    struct Pose {
        let course: EverydayTutorialID
        let filename: String
        let action: Int
        let progress: Double
        let eye: SIMD3<Float>
    }

    struct Receipt: Codable {
        let course: String
        let filename: String
        let actionIndex: Int
        let progress: Double
        let vertices: Int
        let triangles: Int
        let bytes: Int
        let texturedParts: Int
        let textureResources: [String]
    }

    static let poses = [
        Pose(course: .towel, filename: "everyday-towel-preview.png", action: 2, progress: 0.30, eye: [0.5, 2.4, 2.1]),
        Pose(course: .tShirt, filename: "everyday-t-shirt-preview.png", action: 0, progress: 0.24, eye: [0.35, 3.0, 1.7]),
        Pose(course: .flatBedsheet, filename: "everyday-bedsheet-preview.png", action: 1, progress: 0.38, eye: [0.55, 2.5, 2.0]),
        Pose(course: .squareKnot, filename: "everyday-square-knot-preview.png", action: 4, progress: 1, eye: [0.3, 4.0, 1.8]),
        Pose(course: .fourInHand, filename: "everyday-necktie-preview.png", action: 6, progress: 1, eye: [0.2, 4.0, 1.8])
    ]

    static func main() throws {
        guard CommandLine.arguments.count == 3, let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Usage: renderer Resources-directory receipt.json (Metal required)")
        }
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let receiptURL = URL(fileURLWithPath: CommandLine.arguments[2])
        var receipts: [Receipt] = []
        for pose in poses {
            receipts.append(try render(pose, device: device, destination: destination))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(receipts).write(to: receiptURL)
    }

    static func render(_ pose: Pose, device: MTLDevice, destination: URL) throws -> Receipt {
        let scene = SCNScene()
        let parts = EverydayMeshGeometry.parts(courseID: pose.course, actionIndex: pose.action, progress: pose.progress)
        var allPositions: [SIMD3<Float>] = []
        var triangleCount = 0
        var texturedPartCount = 0
        var materialCache: [String: SCNMaterial] = [:]
        var textureResources = Set<String>()
        let textureLoader = MTKTextureLoader(device: device)
        for part in parts {
            let surface = try EverydaySurfaceMesh.make(part: part)
            allPositions += surface.positions
            triangleCount += surface.triangles.count / 3
            let geometry = SCNGeometry(
                sources: [SCNGeometrySource(vertices: surface.positions.map { SCNVector3($0.x, $0.y, $0.z) }),
                          SCNGeometrySource(normals: surface.normals.map { SCNVector3($0.x, $0.y, $0.z) }),
                          SCNGeometrySource(textureCoordinates: surface.textureCoordinates.map {
                              CGPoint(x: CGFloat($0.x), y: CGFloat($0.y))
                          })],
                elements: [SCNGeometryElement(indices: surface.triangles, primitiveType: .triangles)])
            // Part identity matters: the shirt and the first rope share a
            // palette index but must never share a textile material.
            let fabric = EverydayFabricStyle.fabric(forPartID: part.id)
            let trimTint = EverydayFabricStyle.trimTint(forPartID: part.id)
            let cacheKey = fabric.map { "\($0.resourcePrefix)-\(trimTint)" } ?? "solid-\(part.colorIndex)"
            let material: SCNMaterial
            if let cached = materialCache[cacheKey] {
                material = cached
            } else {
                material = SCNMaterial()
                material.lightingModel = .physicallyBased
                material.metalness.contents = 0
                if let fabric {
                    material.diffuse.contents = NSColor.white
                    material.multiply.contents = NSColor(white: CGFloat(trimTint), alpha: 1)
                    let maps: [(SCNMaterialProperty, String, Bool)] = [
                        (material.diffuse, "white-basecolor.jpg", true),
                        (material.normal, "normal-gl.png", false),
                        (material.roughness, "roughness.png", false)
                    ]
                    for (property, suffix, isColor) in maps {
                        let filename = "\(fabric.resourcePrefix)-\(suffix)"
                        // Explicit GPU formats keep normal/roughness out of
                        // sRGB decoding. SceneKit accepts MTLTexture contents.
                        property.contents = try textureLoader.newTexture(
                            URL: destination.appendingPathComponent(filename),
                            options: [.SRGB: NSNumber(value: isColor),
                                      .generateMipmaps: NSNumber(value: true)])
                        property.mappingChannel = 0
                        property.wrapS = .repeat
                        property.wrapT = .repeat
                        property.minificationFilter = .linear
                        property.magnificationFilter = .linear
                        property.mipFilter = .linear
                        property.maxAnisotropy = 8
                        property.contentsTransform = SCNMatrix4(simd_float4x4(diagonal: [
                            1 / fabric.tileSizeMetres.x, 1 / fabric.tileSizeMetres.y, 1, 1
                        ]))
                        textureResources.insert(filename)
                    }
                } else {
                    let color = EverydaySurfaceStyle.color(index: part.colorIndex)
                    material.diffuse.contents = NSColor(srgbRed: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: 1)
                    material.roughness.contents = EverydaySurfaceStyle.roughness
                }
                materialCache[cacheKey] = material
            }
            if fabric != nil { texturedPartCount += 1 }
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry); node.name = part.id
            scene.rootNode.addChildNode(node)
        }
        guard !allPositions.isEmpty else { fatalError("No teaching geometry for \(pose.course)") }
        let minimum = allPositions.reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude), simd_min)
        let maximum = allPositions.reduce(SIMD3<Float>(repeating: -.greatestFiniteMagnitude), simd_max)
        let center = (minimum + maximum) / 2
        let extent = simd_reduce_max(maximum - minimum)
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera!.usesOrthographicProjection = true
        camera.camera!.zNear = Double(extent / 1000)
        camera.camera!.zFar = Double(extent * 20)
        camera.simdPosition = center + pose.eye * extent
        camera.look(at: SCNVector3(center.x, center.y, center.z))
        scene.rootNode.addChildNode(camera)

        // Fit projected geometry, rather than world bounds: all five shapes
        // occupy the same visual scale despite very different aspect ratios.
        let view = camera.simdWorldTransform.inverse
        let projected = allPositions.map { view * SIMD4<Float>($0, 1) }
        let projectedMin = projected.reduce(SIMD4<Float>(repeating: .greatestFiniteMagnitude), simd_min)
        let projectedMax = projected.reduce(SIMD4<Float>(repeating: -.greatestFiniteMagnitude), simd_max)
        let projectedSpan = max(projectedMax.x - projectedMin.x, projectedMax.y - projectedMin.y)
        camera.camera!.orthographicScale = Double(projectedSpan * 0.64)
        let projectedCenter = (projectedMin + projectedMax) / 2
        let cameraTransform = camera.simdWorldTransform
        let right = SIMD3<Float>(cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z)
        let up = SIMD3<Float>(cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z)
        camera.simdPosition += right * projectedCenter.x + up * projectedCenter.y

        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light!.type = .ambient
        ambient.light!.intensity = 160; scene.rootNode.addChildNode(ambient)
        let key = SCNNode(); key.light = SCNLight(); key.light!.type = .directional
        key.light!.intensity = 1000
        key.simdPosition = center + SIMD3<Float>(-2, 4, 3) * extent
        key.look(at: SCNVector3(center.x, center.y, center.z)); scene.rootNode.addChildNode(key)
        if let environment = NSImage(contentsOf: destination.appendingPathComponent("studio-lighting.png")) {
            scene.lightingEnvironment.contents = environment
            scene.lightingEnvironment.intensity = 0.8
        }
        scene.background.contents = NSColor.clear
        camera.camera!.wantsHDR = true
        camera.camera!.wantsExposureAdaptation = false
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene; renderer.pointOfView = camera
        let rendered = renderer.snapshot(atTime: 0, with: CGSize(width: 800, height: 800), antialiasingMode: .multisampling4X)
        guard let tiff = rendered.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG export failed") }
        try png.write(to: destination.appendingPathComponent(pose.filename))
        print("Rendered \(pose.filename): \(allPositions.count) vertices, \(triangleCount) triangles, \(png.count) bytes")
        return Receipt(course: pose.course.rawValue, filename: pose.filename, actionIndex: pose.action,
                       progress: pose.progress, vertices: allPositions.count, triangles: triangleCount, bytes: png.count,
                       texturedParts: texturedPartCount, textureResources: textureResources.sorted())
    }
}
