import RealityKit
import SwiftUI
import Combine

@MainActor
private final class EverydayTeachingModel {
    let root = Entity()
    private var entities: [String: ModelEntity] = [:]
    private var previous: [String: EverydayMeshPart] = [:]
    private var seeThrough = false

    private func material(for part: EverydayMeshPart) -> PhysicallyBasedMaterial {
        var material: PhysicallyBasedMaterial
        if let fabric = EverydayFabricStyle.fabric(forPartID: part.id),
           let textured = EverydayFabricMaterials.material(for: fabric) {
            material = textured
            material.baseColor.tint = UIColor(white: CGFloat(EverydayFabricStyle.trimTint(forPartID: part.id)), alpha: 1)
        } else {
            material = PhysicallyBasedMaterial()
            let color = EverydayFabricStyle.fabric(forPartID: part.id) != nil
                ? SIMD3<Float>(repeating: 0.91) : EverydaySurfaceStyle.color(index: part.colorIndex)
            material.baseColor = .init(tint: UIColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: 1))
            material.roughness = .init(floatLiteral: EverydaySurfaceStyle.roughness)
        }
        material.blending = seeThrough ? .transparent(opacity: .init(floatLiteral: 0.46)) : .opaque
        return material
    }

    func setSeeThrough(_ enabled: Bool) {
        guard enabled != seeThrough else { return }
        seeThrough = enabled
        for (id, entity) in entities {
            guard let part = previous[id] else { continue }
            entity.model?.materials = [material(for: part)]
        }
    }
    init() { root.name = "Everyday spatial teaching reference"; root.synchronization = nil }

    func update(_ parts: [EverydayMeshPart]) throws {
        let live = Set(parts.map(\.id))
        for id in Array(entities.keys) where !live.contains(id) {
            entities.removeValue(forKey: id)?.removeFromParent(); previous.removeValue(forKey: id)
        }
        for part in parts {
            if previous[part.id] == part { continue }
            let surface = try EverydaySurfaceMesh.make(part: part)
            var descriptor = MeshDescriptor(name: part.id)
            descriptor.positions = MeshBuffers.Positions(surface.positions)
            descriptor.normals = MeshBuffers.Normals(surface.normals)
            descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(surface.textureCoordinates)
            descriptor.primitives = .triangles(surface.triangles)
            let mesh = try MeshResource.generate(from: [descriptor])
            let entity = entities[part.id] ?? ModelEntity()
            entity.name = part.id; entity.synchronization = nil
            entity.model = ModelComponent(mesh: mesh, materials: [material(for: part)])
            if entities[part.id] == nil { root.addChild(entity); entities[part.id] = entity }
            previous[part.id] = part
        }
    }
}

/// One model and one ARView survive studio/AR and fullscreen transitions.
/// Animation never declares that the learner has completed a real action.
@MainActor
final class EverydaySceneController: ObservableObject {
    enum FramingMode: String { case action, detail, complete }
    let courseID: EverydayTutorialID
    let tabletop = TutorialTabletopARController()
    let renderer: Tutorial3DRenderer
    private let model = EverydayTeachingModel()
    @Published private(set) var motion = EverydayMotionPlayback()
    @Published private(set) var isAR = false
    @Published private(set) var arEntryError: String?
    @Published private(set) var failure: String?
    @Published private(set) var seeThroughGuide = true
    @Published private(set) var framing: Tutorial3DRenderer.Framing
    @Published private(set) var framingMode: FramingMode = .action
    private var actionFrames: [Int: EverydayStepFraming.Frame] = [:]
    private let tabletopLayout: TutorialTabletopLayout?
    private var tabletopObservation: AnyCancellable?
    private var alignmentObservation: AnyCancellable?
    private var dimensionObservation: AnyCancellable?
    private var objectScale = SIMD3<Float>(repeating: 1)
    var canAnimate: Bool { failure == nil && (!isAR || tabletop.ready) }
    let objectGuide: EverydayObjectGuide?

    init(courseID: EverydayTutorialID) {
        self.courseID = courseID
        renderer = Tutorial3DRenderer(orbitTouchCount: 1, hasStudioSurface: [.towel, .tShirt, .flatBedsheet].contains(courseID))
        objectGuide = EverydayObjectGuide.course(courseID)
        let bounds = EverydayMeshGeometry.envelope(courseID: courseID)
        let first = EverydayStepFraming.action(courseID: courseID, actionIndex: 0)
        framing = .init(center: first.center, radius: first.radius, initialYaw: 0.12, initialPitch: 1.0)
        actionFrames[0] = first
        tabletopLayout = TutorialTabletopLayout(minimum: bounds.minimum, maximum: bounds.maximum, span: 0.52)
        tabletopObservation = tabletop.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        dimensionObservation = tabletop.$objectAlignmentScale.sink { [weak self] scale in
            guard let self, self.objectScale != scale else { return }
            self.objectScale = scale
            self.actionFrames.removeAll()
            self.refreshStudioFraming(resetZoom: true)
            self.applyPose()
        }
        alignmentObservation = tabletop.$isObjectAligned.sink { [weak self] aligned in
            guard let self else { return }
            self.model.setSeeThrough(self.isAR && aligned && self.seeThroughGuide)
            if aligned && self.isAR {
                // Calibration uses the flat starting item. Show that same pose
                // without overwriting the learner's saved confirmations.
                self.motion.select(actionIndex: 0, progress: 0)
                self.framingMode = .action
                self.refreshStudioFraming(resetZoom: true)
                self.applyPose()
            }
        }
        renderer.onCameraChange = { [weak self] in
            // Gesture changes do not otherwise publish scene state. Dispatch
            // avoids publishing during UIViewRepresentable's layout update.
            Task { @MainActor [weak self] in self?.objectWillChange.send() }
        }
        applyPose()
    }

    func makeView() -> ARView {
        let view = renderer.makeView(content: model.root, framing: framing)
        view.accessibilityIdentifier = "everyday3DViewport"
        return view
    }
    func select(actionIndex: Int, progress: Double = 0, autoplay: Bool = false, completed: Bool = false) {
        guard canAnimate else { pause(); return }
        let last = EverydayTutorialCourse.course(courseID).actions.count - 1
        motion.select(actionIndex: min(last, max(0, actionIndex)), progress: progress,
                      autoplay: autoplay && canAnimate)
        framingMode = completed ? .complete : .action
        refreshStudioFraming(resetZoom: true)
        applyPose()
    }
    func play() { guard canAnimate else { return }; restoreActionFraming(); motion.play(); applyPose() }
    func pause() { if motion.isPlaying { motion.pause() } }
    func replay() { guard canAnimate else { return }; restoreActionFraming(); motion.replay(); applyPose() }
    func seek(_ progress: Double) {
        guard canAnimate else { pause(); return }
        if framingMode != .complete || progress < 1 { restoreActionFraming() }
        motion.seek(to: progress); applyPose()
    }
    func setSlow(_ slow: Bool) { motion.setSlow(slow) }
    func tick(elapsed: TimeInterval, allowed: Bool) {
        guard motion.isPlaying else { return }
        let old = motion.progress
        motion.advance(elapsed: elapsed, allowed: allowed && canAnimate)
        if old != motion.progress { applyPose() }
    }
    func resetView() {
        if isAR { tabletop.resetManipulation() }
        else { refreshStudioFraming(resetZoom: true); renderer.resetView() }
    }

    func focusCurrentStep() {
        guard !isAR, failure == nil else { return }
        pause()
        if framingMode != .complete { framingMode = framingMode == .detail ? .action : .detail }
        refreshStudioFraming(resetZoom: true)
        renderer.resetView()
    }

    var focusDiagnostics: String {
        String(format: "mode=%@;center=%.6f,%.6f,%.6f;radius=%.6f;zoom=%.6f",
               framingMode.rawValue, framing.center.x, framing.center.y, framing.center.z,
               framing.radius, renderer.cameraZoom)
    }

    private func restoreActionFraming() {
        guard framingMode != .action else { return }
        framingMode = .action
        refreshStudioFraming(resetZoom: true)
    }

    private func refreshStudioFraming(resetZoom: Bool) {
        let frame: EverydayStepFraming.Frame
        switch framingMode {
        case .action:
            if let cached = actionFrames[motion.actionIndex] { frame = cached }
            else {
                frame = EverydayStepFraming.action(courseID: courseID, actionIndex: motion.actionIndex, objectScale: objectScale)
                actionFrames[motion.actionIndex] = frame
            }
        case .detail:
            frame = EverydayStepFraming.pose(courseID: courseID, actionIndex: motion.actionIndex, progress: motion.progress, objectScale: objectScale)
        case .complete:
            frame = EverydayStepFraming.completed(courseID: courseID, objectScale: objectScale)
        }
        framing = .init(center: frame.center, radius: frame.radius, initialYaw: 0.12, initialPitch: 1.0)
        renderer.setFraming(framing, resetZoom: resetZoom)
    }

    func beginObjectAlignment() {
        guard isAR, let guide = objectGuide else { return }
        pause()
        _ = tabletop.beginObjectAlignment(footprint: guide.footprint)
    }

    func toggleSeeThroughGuide() {
        seeThroughGuide.toggle()
        model.setSeeThrough(isAR && tabletop.isObjectAligned && seeThroughGuide)
    }

    @discardableResult
    func enterAR() -> Bool {
        guard !isAR, failure == nil else { return false }
        pause(); arEntryError = nil
        if TutorialTabletopARController.layoutPreviewRequested {
            tabletop.startLayoutPreview(); isAR = true; return true
        }
        guard TutorialTabletopARController.supportsAR else {
            arEntryError = "Tabletop AR needs a supported iPhone or iPad. You can keep using 3D here."
            return false
        }
        guard let tabletopLayout else { return false }
        _ = makeView()
        guard let view = renderer.handToAR() else { return false }
        tabletop.start(view: view, content: model.root, layout: tabletopLayout, initialYaw: 0)
        isAR = true; return true
    }
    func exitAR() {
        guard isAR else { return }
        pause(); tabletop.stop(); renderer.restoreStudio(); isAR = false
        model.setSeeThrough(false)
        renderer.setContent(model.root, framing: framing)
    }
    func handleActive() {
        if isAR { tabletop.handleActive() } else { renderer.setActive(true) }
    }
    func handleInactive() {
        pause()
        if isAR { tabletop.handleInactive() } else { renderer.setActive(false) }
    }
    func shutdown() {
        pause(); tabletop.stop(); renderer.shutdown()
    }
    private func applyPose() {
        do {
            try model.update(EverydayMeshGeometry.parts(courseID: courseID, actionIndex: motion.actionIndex,
                                                       progress: motion.progress, objectScale: objectScale))
            model.root.isEnabled = true
            if failure != nil { failure = nil }
        } catch {
            model.root.isEnabled = false
            motion.pause(); failure = "The 3D reference could not be drawn. Close this tutorial and try again."
        }
    }
}

struct EverydaySceneView: UIViewRepresentable {
    @ObservedObject var controller: EverydaySceneController
    let isActive: Bool
    func makeUIView(context: Context) -> AssemblyViewportContainer {
        AssemblyViewportContainer(renderer: controller.renderer, view: controller.makeView())
    }
    func updateUIView(_ view: AssemblyViewportContainer, context: Context) {
        if !controller.isAR { controller.renderer.setActive(isActive) }
        controller.renderer.updateLayout()
    }
    // The controller owns shutdown. The container resizes the SAME ARView on
    // rotation; changing studio/AR chrome must not detach or pause that session.
}
