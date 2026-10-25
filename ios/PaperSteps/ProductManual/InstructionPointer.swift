import RealityKit
import UIKit

/// Shared instructional geometry for the native viewer and real AR placement.
@MainActor
final class InstructionPointer {
    private let model: Entity
    private let space: Entity
    private var arrow: Entity?
    private var originalMaterials: [(ModelEntity, [any Material])] = []
    private(set) var focusEntity: Entity?
    private(set) var focusName = ""
    private var arrowTarget: SIMD3<Float> = .zero
    init(model: Entity, space: Entity) { self.model = model; self.space = space }

    func clear() {
        for (entity, materials) in originalMaterials { entity.model?.materials = materials }
        originalMaterials.removeAll(); arrow?.removeFromParent(); arrow = nil; focusEntity = nil
    }
    func show(_ name: String) {
        clear(); focusName = name
        guard let target = model.findEntity(named: name) else { return }
        focusEntity = target
        // Highlight the actual operative component, not a screen-space proxy.
        if name != "Main_Housing" { recolor(target, color: .systemRed, record: true) }
        var point = target.visualBounds(relativeTo: space).center
        if name == "Main_Housing" { point = [0.09, 0.17, 0.10] }
        arrowTarget = point
        let offset: SIMD3<Float> = name == "Power_symbol_arc" || name == "Filter_reset_label" || name == "Filter_TOP_mark" ? [0.055, 0.065, 0.01] : [0.04, 0.065, -0.055]
        let start = point + offset
        let direction = simd_normalize(point - start)
        let length = simd_length(offset)
        let root = Entity(); root.name = "Instruction_Arrow"; root.position = start
        root.orientation = simd_quatf(from: [0, 1, 0], to: direction)
        let red = UnlitMaterial(color: .systemRed)
        let headLength: Float = 0.019
        let shaft = ModelEntity(mesh: .generateBox(size: [0.0044, length - headLength, 0.0044], cornerRadius: 0.001), materials: [red])
        shaft.position.y = (length - headLength) / 2
        var descriptor = MeshDescriptor(name: "InstructionArrowHead")
        let r: Float = 0.008, h = headLength / 2
        descriptor.positions = MeshBuffers.Positions([[-r,-h,-r],[r,-h,-r],[r,-h,r],[-r,-h,r],[0,h,0]])
        descriptor.primitives = .triangles([0,4,1,1,4,2,2,4,3,3,4,0,0,1,2,0,2,3])
        guard let arrowMesh = try? MeshResource.generate(from: [descriptor]) else { return }
        let head = ModelEntity(mesh: arrowMesh, materials: [red])
        head.position.y = length - headLength / 2
        root.addChild(shaft); root.addChild(head); space.addChild(root); arrow = root
    }
    func refreshPosition() {
        guard let target = focusEntity, focusName != "Main_Housing", let arrow else { return }
        let point = target.visualBounds(relativeTo: space).center
        arrow.position += point - arrowTarget; arrowTarget = point
    }
    func markPressed() {
        guard let focusEntity else { return }
        recolor(focusEntity, color: .systemGreen, record: false)
        arrow?.removeFromParent(); arrow = nil
    }
    var worldPoint: SIMD3<Float>? {
        guard let focusEntity else { return nil }
        return focusEntity.visualBounds(relativeTo: nil).center
    }
    private func recolor(_ entity: Entity, color: UIColor, record: Bool) {
        if let m = entity as? ModelEntity, let component = m.model {
            if record { originalMaterials.append((m, component.materials)) }
            m.model?.materials = component.materials.map { _ in UnlitMaterial(color: color) }
        }
        for child in entity.children { recolor(child, color: color, record: record) }
    }
}
