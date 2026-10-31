import RealityKit
import SwiftUI
import Combine

/// Runtime adapter: the same renderer and part/pose logic can host qualified
/// equipment assets. It never changes the file or infers a disassembly order.
@MainActor
final class AssemblySceneController: ObservableObject {
    let tutorial: AssemblyTutorial
    let root = Entity()
    let renderer = Tutorial3DRenderer()
    let tabletop = TutorialTabletopARController()
    @Published private(set) var isLoaded = false
    @Published private(set) var failure: String?
    @Published private(set) var stepIndex = 0
    @Published private(set) var progress: Double = 0
    @Published private(set) var selectedPartID: String?
    @Published private(set) var isExploded = false
    @Published private(set) var isPartFocused = false
    @Published private(set) var isAR = false
    @Published private(set) var arEntryError: String?
    var canAnimate: Bool { !isAR || tabletop.ready }
    private(set) var framing = Tutorial3DRenderer.Framing(center: .zero, radius: 0.5)
    private var overviewFraming = Tutorial3DRenderer.Framing(center: .zero, radius: 0.5)
    private var parts: [String: Entity] = [:]
    private var origins: [String: Transform] = [:]
    private let selectionFrame = Entity()
    private let frameEdgeMesh = MeshResource.generateBox(size: 1)
    private var loadGeneration = 0
    private let sharedView: ARView?
    private var tabletopLayout: TutorialTabletopLayout?
    private var tabletopObservation: AnyCancellable?

    init(tutorial: AssemblyTutorial, sharedView: ARView? = nil) {
        self.tutorial = tutorial; self.sharedView = sharedView; root.synchronization = nil
        selectionFrame.name = "__ProtactaPartHighlight"; selectionFrame.synchronization = nil
        tabletopObservation = tabletop.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        tabletop.onEntityTap = { [weak self] in self?.select(entity: $0) }
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

        clearSelectionFrame()
        for child in Array(root.children) { child.removeFromParent() }
        root.addChild(entity)
        parts = resolved
        origins = resolved.mapValues(\.transform)
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
        overviewFraming = framing; isPartFocused = false
        tabletopLayout = TutorialTabletopLayout(minimum: minimum, maximum: maximum)
        stepIndex = 0; progress = 0; isExploded = false; failure = nil; isLoaded = true
        select(tutorial.steps[0].focusID)
        applyPose()
    }

    func setStep(_ index: Int) {
        guard tutorial.steps.indices.contains(index) else { return }
        stepIndex = index; progress = 0; isExploded = false
        isPartFocused = false; framing = overviewFraming
        select(step.focusID); applyPose()
    }

    func setProgress(_ value: Double) {
        progress = value.isFinite ? min(1, max(0, value)) : 0
        applyPose()
    }

    func setExploded(_ exploded: Bool) {
        if exploded { isPartFocused = false; framing = overviewFraming }
        isExploded = exploded; applyPose()
    }

    func select(_ id: String?) {
        clearSelectionFrame()
        selectedPartID = id.flatMap { parts[$0] == nil ? nil : $0 }
        guard let id = selectedPartID, let part = parts[id] else {
            isPartFocused = false; framing = overviewFraming; return
        }
        // Never replace imported materials. RealityKit's rendered USD material
        // can retain an earlier replacement even after CPU values are restored.
        // An independent frame preserves textures and disappears as one entity.
        let bounds = part.visualBounds(relativeTo: part)
        let longest = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
        let thickness = min(0.025, max(0.001, longest * 0.012))
        let extent = bounds.extents + SIMD3<Float>(repeating: thickness * 2)
        let color = UnlitMaterial(color: UIColor(red: 0.95, green: 0.62, blue: 0.23, alpha: 1))
        for axis in 0..<3 {
            let others = (0..<3).filter { $0 != axis }
            for a: Float in [-1, 1] { for b: Float in [-1, 1] {
                let edge = ModelEntity(mesh: frameEdgeMesh, materials: [color])
                edge.name = "__ProtactaHighlightEdge"; edge.synchronization = nil
                var size = SIMD3<Float>(repeating: thickness); size[axis] = extent[axis]
                var center = bounds.center
                center[others[0]] += a * extent[others[0]] * 0.5
                center[others[1]] += b * extent[others[1]] * 0.5
                edge.scale = size; edge.position = center; selectionFrame.addChild(edge)
            } }
        }
        part.addChild(selectionFrame)
        updateFocusFraming()
    }

    func focusSelectedPart() {
        guard !isAR, selectedPart != nil else { return }
        isPartFocused = true; updateFocusFraming()
        renderer.setContent(root, framing: framing); renderer.resetView()
    }

    func resetCameraView() {
        if isAR { tabletop.resetManipulation(); return }
        isPartFocused = false; framing = overviewFraming
        renderer.setContent(root, framing: framing); renderer.resetView()
    }

    @discardableResult
    func enterAR() -> Bool {
        guard isLoaded, !isAR else { return false }
        arEntryError = nil
        if TutorialTabletopARController.layoutPreviewRequested {
            tabletop.startLayoutPreview(); isAR = true; return true
        }
        guard TutorialTabletopARController.supportsAR else {
            arEntryError = "Tabletop AR needs a supported iPhone or iPad. The 3D view remains available."
            return false
        }
        guard let tabletopLayout else { return false }
        _ = makeView()
        guard let view = renderer.handToAR() else { return false }
        isPartFocused = false; framing = overviewFraming
        tabletop.start(view: view, content: root, layout: tabletopLayout, initialYaw: tutorial.initialYaw)
        isAR = true
        return true
    }

    func exitAR() {
        guard isAR else { return }
        tabletop.stop(); renderer.restoreStudio(); isAR = false
        renderer.setContent(root, framing: framing)
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
        tabletop.stop()
        clearSelectionFrame(); renderer.shutdown()
        for child in Array(root.children) { child.removeFromParent() }
        parts.removeAll(); origins.removeAll()
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
        updateFocusFraming()
    }

    private func applyOffsets(_ offsets: [String: SIMD3<Float>]) {
        for (id, entity) in parts {
            guard var transform = origins[id] else { continue }
            let offset = offsets[id] ?? .zero
            if let parent = entity.parent { transform.translation += parent.convert(direction: offset, from: root) }
            else { transform.translation += offset }
            entity.transform = transform
        }
    }

    private func clearSelectionFrame() {
        selectionFrame.removeFromParent()
        for child in Array(selectionFrame.children) { child.removeFromParent() }
    }

    private func updateFocusFraming() {
        guard isPartFocused, let id = selectedPartID, let part = parts[id] else { return }
        let bounds = part.visualBounds(relativeTo: nil)
        framing = .init(center: bounds.center, radius: max(0.02, simd_length(bounds.extents) * 0.5),
                        initialYaw: tutorial.initialYaw, initialPitch: tutorial.initialPitch)
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
        guard viewport.superview === self else { return }
        viewport.frame = bounds
        renderer?.updateLayout()
    }
}
