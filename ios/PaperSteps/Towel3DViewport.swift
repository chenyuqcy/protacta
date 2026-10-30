import RealityKit
import SwiftUI

@MainActor
final class Towel3DModel {
    let root = Entity()
    private let panels = (0..<3).map { _ in ModelEntity() }
    private var lastAction: Int?
    private var lastProgress: Double?
    private var lastQuads: [Int: [[SIMD3<Float>]]] = [:]
    private let cloth = SimpleMaterial(color: UIColor(red: 0.45, green: 0.70, blue: 0.68, alpha: 1),
                                       roughness: 0.95, isMetallic: false)
    private let active = SimpleMaterial(color: UIColor(red: 0.93, green: 0.66, blue: 0.47, alpha: 1),
                                        roughness: 0.95, isMetallic: false)

    init() {
        root.name = "Towel fold teaching diagram"
        root.synchronization = nil
        for (index, panel) in panels.enumerated() {
            panel.name = ["Left third", "Middle third", "Right third"][index]
            panel.synchronization = nil
            root.addChild(panel)
        }
    }

    func update(actionIndex: Int, progress: Double) {
        let normalized = progress.isFinite ? min(1, max(0, progress)) : 0
        let action = min(2, max(0, actionIndex))
        guard lastAction != action || lastProgress != normalized else { return }
        let frame = Towel3DGeometry.panels(actionIndex: action, progress: normalized)
        for panel in frame {
            let entity = panels[panel.column]
            let material = panel.isMoving ? active : cloth
            if lastQuads[panel.column] == panel.quads, var model = entity.model {
                model.materials = [material]; entity.model = model
                continue
            }
            var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], triangles: [UInt32] = []
            for quad in panel.quads {
                let cross = simd_cross(quad[1] - quad[0], quad[2] - quad[0])
                guard simd_length_squared(cross) > 1e-12 else { continue }
                let normal = simd_normalize(cross)
                // A thin front/reverse surface remains visible while a flap
                // turns edge-on. Opposite winding gives the reverse its normal.
                for reverse in [false, true] {
                    let points = reverse ? Array(quad.reversed()) : quad
                    let n = reverse ? -normal : normal
                    let start = UInt32(positions.count)
                    positions += points.map { $0 + n * 0.0006 }
                    normals += Array(repeating: n, count: 4)
                    triangles += [start, start + 1, start + 2, start, start + 2, start + 3]
                }
            }
            var descriptor = MeshDescriptor(name: entity.name)
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.normals = MeshBuffers.Normals(normals)
            descriptor.primitives = .triangles(triangles)
            if let mesh = try? MeshResource.generate(from: [descriptor]) {
                entity.model = ModelComponent(mesh: mesh, materials: [material])
                lastQuads[panel.column] = panel.quads
            }
        }
        lastAction = action; lastProgress = normalized
    }
}

struct Towel3DViewport: UIViewRepresentable {
    let actionIndex: Int
    let progress: Double
    let isActive: Bool
    let resetToken: Int

    @MainActor
    final class Coordinator {
        let model = Towel3DModel()
        // One-finger swipes keep the enclosing lesson scrollable.
        let renderer = Tutorial3DRenderer(orbitTouchCount: 2)
        var resetToken = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        context.coordinator.model.update(actionIndex: actionIndex, progress: progress)
        let view = context.coordinator.renderer.makeView(content: context.coordinator.model.root,
            framing: .init(center: [0, 0.04, 0], radius: 0.55))
        view.accessibilityIdentifier = "towel3DViewport"
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        let coordinator = context.coordinator
        coordinator.model.update(actionIndex: actionIndex, progress: progress)
        coordinator.renderer.setActive(isActive)
        if coordinator.resetToken != resetToken {
            coordinator.resetToken = resetToken; coordinator.renderer.resetView()
        }
        coordinator.renderer.updateLayout()
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) { coordinator.renderer.shutdown() }
}
