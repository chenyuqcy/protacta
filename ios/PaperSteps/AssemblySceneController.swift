import RealityKit
import SwiftUI

/// Runtime adapter: the same renderer and part/pose logic can host qualified
/// equipment assets. It never changes the file or infers a disassembly order.
@MainActor
final class AssemblySceneController: ObservableObject {
    let tutorial: AssemblyTutorial
    let root = Entity()
    let renderer = Tutorial3DRenderer()
    @Published private(set) var isLoaded = false
    @Published private(set) var failure: String?
    @Published private(set) var stepIndex = 0
    @Published private(set) var progress: Double = 0
    @Published private(set) var selectedPartID: String?
    @Published private(set) var isExploded = false
    private(set) var framing = Tutorial3DRenderer.Framing(center: .zero, radius: 0.5)
    private var parts: [String: Entity] = [:]
    private var origins: [String: Transform] = [:]
    private var materialRecords: [(ModelEntity, [any RealityKit.Material])] = []
    private var loadGeneration = 0
    private let sharedView: ARView?

    init(tutorial: AssemblyTutorial, sharedView: ARView? = nil) {
        self.tutorial = tutorial; self.sharedView = sharedView; root.synchronization = nil
    }
    var step: AssemblyTutorial.Step { tutorial.steps[stepIndex] }
    var selectedPart: AssemblyTutorial.Part? { tutorial.parts.first { $0.id == selectedPartID } }

    func load() async {
        guard !isLoaded else { return }
        loadGeneration += 1
        let generation = loadGeneration
        do {
            try tutorial.validate()
            guard let url = Bundle.main.url(forResource: tutorial.assetName, withExtension: "usdz") else { throw CocoaError(.fileNoSuchFile) }
            let entity = try await ProductAsset.load(from: url)
            guard !Task.isCancelled, generation == loadGeneration else { return }
            try bind(entity)
        } catch {
            guard !Task.isCancelled, generation == loadGeneration else { return }
            failure = error.localizedDescription
        }
    }

    /// All required names must resolve exactly once, and independent animated
    /// groups cannot be ancestors of each other. Reject before mutating a scene.
    func bind(_ entity: Entity) throws {
        try tutorial.validate()
        let all = descendants(entity)
        var resolved: [String: Entity] = [:]
        for part in tutorial.parts {
            let matches = all.filter { $0.name == part.entityName }
            guard matches.count == 1, let match = matches.first else { throw AssemblyTutorialError.missingOrAmbiguousPart(part.entityName) }
            guard descendants(match).contains(where: { ($0 as? ModelEntity)?.model != nil }) else { throw AssemblyTutorialError.emptyPart(part.entityName) }
            resolved[part.id] = match
        }
        let identities = Set(resolved.values.map(ObjectIdentifier.init))
        for part in resolved.values {
            var parent = part.parent
            while let candidate = parent {
                guard !identities.contains(ObjectIdentifier(candidate)) else { throw AssemblyTutorialError.nestedParts }
                parent = candidate.parent
            }
        }
        let bounds = entity.visualBounds(relativeTo: nil)
        let extent = bounds.extents
        guard extent.x.isFinite, extent.y.isFinite, extent.z.isFinite, simd_length(extent) > 0.0001 else { throw AssemblyTutorialError.emptyModel }

        restoreMaterials()
        for child in Array(root.children) { child.removeFromParent() }
        root.addChild(entity)
        parts = resolved
        origins = resolved.mapValues(\.transform)
        materialRecords = all.compactMap { entity in
            guard let model = entity as? ModelEntity, let component = model.model else { return nil }
            return (model, component.materials)
        }
        for part in resolved.values { part.generateCollisionShapes(recursive: true) }
        // Fit the actual authored poses, instead of adding the same arbitrary
        // margin to every model. Linear motions remain inside this union.
        var minimum = bounds.min, maximum = bounds.max
        let exploded = Dictionary(uniqueKeysWithValues: tutorial.parts.map { ($0.id, $0.explodedOffset) })
        for offsets in tutorial.steps.map(\.offsets) + [exploded] {
            applyOffsets(offsets)
            let moved = entity.visualBounds(relativeTo: nil)
            minimum = simd_min(minimum, moved.min); maximum = simd_max(maximum, moved.max)
        }
        applyOffsets([:])
        framing = .init(center: (minimum + maximum) * 0.5, radius: simd_length(maximum - minimum) * 0.5,
                        initialYaw: tutorial.initialYaw, initialPitch: tutorial.initialPitch)
        stepIndex = 0; progress = 0; isExploded = false; failure = nil; isLoaded = true
        select(tutorial.steps[0].focusID)
        applyPose()
    }

    func setStep(_ index: Int) {
        guard tutorial.steps.indices.contains(index) else { return }
        stepIndex = index; progress = 0; isExploded = false
        select(step.focusID); applyPose()
    }

    func setProgress(_ value: Double) {
        progress = value.isFinite ? min(1, max(0, value)) : 0
        applyPose()
    }

    func setExploded(_ exploded: Bool) { isExploded = exploded; applyPose() }

    func select(_ id: String?) {
        restoreMaterials()
        selectedPartID = id.flatMap { parts[$0] == nil ? nil : $0 }
        guard let id = selectedPartID, let part = parts[id] else { return }
        let highlight = SimpleMaterial(color: UIColor(red: 0.94, green: 0.65, blue: 0.35, alpha: 1), roughness: 0.7, isMetallic: false)
        for case let model as ModelEntity in descendants(part) {
            guard var component = model.model else { continue }
            component.materials = Array(repeating: highlight, count: max(1, component.materials.count))
            model.model = component
        }
    }

    func select(entity: Entity?) {
        var current = entity
        while let candidate = current {
            if let id = parts.first(where: { $0.value === candidate })?.key { select(id); return }
            current = candidate.parent
        }
        select(nil)
    }

    func makeView() -> ARView {
        renderer.onEntityTap = { [weak self] in self?.select(entity: $0) }
        let view = renderer.makeView(content: root, framing: framing, sharedView: sharedView)
        view.accessibilityIdentifier = "assembly3DViewport"
        return view
    }

    func shutdown() {
        loadGeneration += 1
        restoreMaterials(); renderer.shutdown()
        for child in Array(root.children) { child.removeFromParent() }
        parts.removeAll(); origins.removeAll(); materialRecords.removeAll()
        isLoaded = false
    }

    private func applyPose() {
        let start = stepIndex == 0 ? [:] : tutorial.steps[stepIndex - 1].offsets
        let amount = Float(progress)
        // Smooth endpoints while allowing precise scrubbing and deterministic replay.
        let blend = amount * amount * (3 - 2 * amount)
        var offsets: [String: SIMD3<Float>] = [:]
        for part in tutorial.parts {
            let from = start[part.id] ?? .zero
            let to = step.offsets[part.id] ?? .zero
            offsets[part.id] = isExploded ? part.explodedOffset : from + (to - from) * blend
        }
        applyOffsets(offsets)
    }

    private func applyOffsets(_ offsets: [String: SIMD3<Float>]) {
        for (id, entity) in parts {
            guard var transform = origins[id] else { continue }
            let offset = offsets[id] ?? .zero
            if let parent = entity.parent { transform.translation += parent.convert(direction: offset, from: nil) }
            else { transform.translation += offset }
            entity.transform = transform
        }
    }

    private func restoreMaterials() {
        for (entity, materials) in materialRecords {
            guard var component = entity.model else { continue }
            component.materials = materials; entity.model = component
        }
    }

    private func descendants(_ entity: Entity) -> [Entity] {
        [entity] + entity.children.flatMap { descendants($0) }
    }
}

struct AssemblySceneView: UIViewRepresentable {
    @ObservedObject var controller: AssemblySceneController
    let isActive: Bool
    func makeUIView(context: Context) -> AssemblyViewportContainer {
        AssemblyViewportContainer(renderer: controller.renderer, view: controller.makeView())
    }
    func updateUIView(_ uiView: AssemblyViewportContainer, context: Context) {
        controller.renderer.setContent(controller.root, framing: controller.framing)
        controller.renderer.setActive(isActive)
        controller.renderer.updateLayout()
    }
}

/// The borrowed ARView may come from another module, so resize it through a
/// container instead of relying on a particular ARView subclass.
final class AssemblyViewportContainer: UIView {
    private weak var renderer: Tutorial3DRenderer?
    private let viewport: ARView
    init(renderer: Tutorial3DRenderer, view: ARView) {
        self.renderer = renderer; viewport = view
        super.init(frame: .zero)
        clipsToBounds = true; addSubview(view)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layoutSubviews() {
        super.layoutSubviews()
        viewport.frame = bounds
        renderer?.updateLayout()
    }
}
