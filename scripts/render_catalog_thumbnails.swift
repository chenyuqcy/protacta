import AppKit
import SceneKit
import Metal

// Render the bundled, licensed teaching assets, rather than invented artwork.
// Compile with ios/PaperSteps/PaperGeometry.swift, then pass source.usdz (or
// --dart) and destination.png. Run generate_studio_environment.py first.
@main
enum CatalogThumbnailRenderer {
static func main() throws {
guard CommandLine.arguments.count == 3,
      let device = MTLCreateSystemDefaultDevice() else { fatalError("source.usdz destination.png") }
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
let scene: SCNScene
if source.lastPathComponent == "--dart" {
    scene = SCNScene()
    let frame = PaperGeometry.frame(step: PaperGeometry.lastStep, progress: 1)
    for face in frame.faces where face.vertices.count >= 3 {
        let vertices = face.vertices.map { vertex in
            let p = vertex.position + vertex.separation + face.normal * 0.000015
            return SCNVector3(p.x, p.y, p.z)
        }
        let indices = (1..<(vertices.count - 1)).flatMap { [Int32(0), Int32($0), Int32($0 + 1)] }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)],
                                  elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let material = SCNMaterial(); material.lightingModel = .physicallyBased
        material.diffuse.contents = NSColor(white: 0.94, alpha: 1)
        material.roughness.contents = 0.78; material.isDoubleSided = true
        geometry.materials = [material]; scene.rootNode.addChildNode(SCNNode(geometry: geometry))
    }
} else { scene = try SCNScene(url: source, options: [.checkConsistency: true]) }
let (low, high) = scene.rootNode.boundingBox
let center = SCNVector3((low.x + high.x) / 2, (low.y + high.y) / 2, (low.z + high.z) / 2)
let extent = max(high.x - low.x, max(high.y - low.y, high.z - low.z))
guard extent.isFinite, extent > 0 else { fatalError("Model has no bounds") }
let camera = SCNNode(); camera.camera = SCNCamera()
camera.camera!.usesOrthographicProjection = true
camera.camera!.orthographicScale = Double(extent * 0.64)
camera.camera!.zNear = Double(extent / 1000)
camera.camera!.zFar = Double(extent * 20)
camera.position = SCNVector3(center.x + extent * 2, center.y + extent * 1.4, center.z + extent * 2.5)
if source.lastPathComponent == "turbofan-structure.usdz" {
    // X increases from the front fan toward the exhaust in this source asset.
    camera.position = SCNVector3(center.x - extent * 2.5, center.y + extent, center.z + extent * 2)
}
camera.look(at: center); scene.rootNode.addChildNode(camera)
let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light!.type = .ambient
ambient.light!.intensity = 180; scene.rootNode.addChildNode(ambient)
let key = SCNNode(); key.light = SCNLight(); key.light!.type = .directional
key.light!.intensity = 1100; key.position = camera.position
key.look(at: center); scene.rootNode.addChildNode(key)
scene.background.contents = NSColor.clear
let environment = source.deletingLastPathComponent().appendingPathComponent("studio-lighting.png")
if let image = NSImage(contentsOf: environment) {
    scene.lightingEnvironment.contents = image; scene.lightingEnvironment.intensity = 1.0
}
camera.camera!.wantsHDR = true; camera.camera!.wantsExposureAdaptation = false
let renderer = SCNRenderer(device: device, options: nil)
renderer.scene = scene; renderer.pointOfView = camera
let image = renderer.snapshot(atTime: 0, with: CGSize(width: 800, height: 800), antialiasingMode: .multisampling4X)
guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG export failed") }
try png.write(to: destination)
print("Rendered \(source.lastPathComponent): \(png.count) bytes")

}
}
