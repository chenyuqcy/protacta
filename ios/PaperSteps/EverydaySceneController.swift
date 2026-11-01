import RealityKit
import SwiftUI
import Combine

@MainActor
private final class EverydayTeachingModel {
    let root = Entity()
    private var entities: [String: ModelEntity] = [:]
    private var previous: [String: EverydayMeshPart] = [:]
    private let materials: [SimpleMaterial] = [
        SimpleMaterial(color: UIColor(red: 0.40, green: 0.65, blue: 0.62, alpha: 1), roughness: 0.92, isMetallic: false),
        SimpleMaterial(color: UIColor(red: 0.20, green: 0.46, blue: 0.69, alpha: 1), roughness: 0.75, isMetallic: false),
        SimpleMaterial(color: UIColor(red: 0.82, green: 0.37, blue: 0.17, alpha: 1), roughness: 0.75, isMetallic: false),
        SimpleMaterial(color: UIColor(red: 0.90, green: 0.88, blue: 0.80, alpha: 1), roughness: 0.92, isMetallic: false),
        SimpleMaterial(color: UIColor(red: 0.16, green: 0.23, blue: 0.29, alpha: 1), roughness: 0.85, isMetallic: false)
    ]
    private enum MeshError: Error { case invalidGeometry }
    init() { root.name = "Everyday spatial teaching reference"; root.synchronization = nil }

    func update(_ parts: [EverydayMeshPart]) throws {
        let live = Set(parts.map(\.id))
        for id in Array(entities.keys) where !live.contains(id) {
            entities.removeValue(forKey: id)?.removeFromParent(); previous.removeValue(forKey: id)
        }
        for part in parts {
            guard !part.positions.isEmpty, part.triangles.count >= 3, part.triangles.count % 3 == 0,
                  part.positions.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { throw MeshError.invalidGeometry }
            if previous[part.id] == part { continue }
            var normals = Array(repeating: SIMD3<Float>.zero, count: part.positions.count)
            var front: [UInt32] = []
            for index in stride(from: 0, to: part.triangles.count - 2, by: 3) {
                let a = Int(part.triangles[index]), b = Int(part.triangles[index + 1]), c = Int(part.triangles[index + 2])
                guard a < part.positions.count, b < part.positions.count, c < part.positions.count else { throw MeshError.invalidGeometry }
                let cross = simd_cross(part.positions[b] - part.positions[a], part.positions[c] - part.positions[a])
                guard simd_length_squared(cross) > 1e-15 else { continue }
                normals[a] += cross; normals[b] += cross; normals[c] += cross
                front += [UInt32(a), UInt32(b), UInt32(c)]
            }
            guard !front.isEmpty else { throw MeshError.invalidGeometry }
            normals = normals.map { simd_length_squared($0) > 1e-15 ? simd_normalize($0) : [0, 1, 0] }
            let count = UInt32(part.positions.count)
            let skin: Float = 0.00025
            let positions = zip(part.positions, normals).map { $0.0 + $0.1 * skin }
                + zip(part.positions, normals).map { $0.0 - $0.1 * skin }
            var triangles = front
            for index in stride(from: 0, to: front.count, by: 3) {
                triangles += [front[index + 2] + count, front[index + 1] + count, front[index] + count]
            }
            var descriptor = MeshDescriptor(name: part.id)
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.normals = MeshBuffers.Normals(normals + normals.map { -$0 })
            descriptor.primitives = .triangles(triangles)
            let mesh = try MeshResource.generate(from: [descriptor])
            let entity = entities[part.id] ?? ModelEntity()
            entity.name = part.id; entity.synchronization = nil
            entity.model = ModelComponent(mesh: mesh, materials: [materials[min(materials.count - 1, max(0, part.colorIndex))]])
            if entities[part.id] == nil { root.addChild(entity); entities[part.id] = entity }
            previous[part.id] = part
        }
    }
}

/// One model and one ARView survive studio/AR and fullscreen transitions.
/// Animation never declares that the learner has completed a real action.
@MainActor
final class EverydaySceneController: ObservableObject {
    let courseID: EverydayTutorialID
    let tabletop = TutorialTabletopARController()
    let renderer = Tutorial3DRenderer(orbitTouchCount: 1)
    private let model = EverydayTeachingModel()
    @Published private(set) var motion = EverydayMotionPlayback()
    @Published private(set) var isAR = false
    @Published private(set) var arEntryError: String?
    @Published private(set) var failure: String?
    let framing: Tutorial3DRenderer.Framing
    private let tabletopLayout: TutorialTabletopLayout?
    private var tabletopObservation: AnyCancellable?
    var canAnimate: Bool { failure == nil && (!isAR || tabletop.ready) }

    init(courseID: EverydayTutorialID) {
        self.courseID = courseID
        let bounds = EverydayMeshGeometry.envelope(courseID: courseID)
        let center = (bounds.minimum + bounds.maximum) * 0.5
        let radius = max(0.15, simd_length(bounds.maximum - bounds.minimum) * 0.5)
        framing = .init(center: center, radius: radius, initialYaw: 0.12, initialPitch: 1.0)
        tabletopLayout = TutorialTabletopLayout(minimum: bounds.minimum, maximum: bounds.maximum, span: 0.52)
        tabletopObservation = tabletop.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        applyPose()
    }

    func makeView() -> ARView {
        let view = renderer.makeView(content: model.root, framing: framing)
        view.accessibilityIdentifier = "everyday3DViewport"
        return view
    }
    func select(actionIndex: Int, progress: Double = 0, autoplay: Bool = false) {
        guard canAnimate else { pause(); return }
        let last = EverydayTutorialCourse.course(courseID).actions.count - 1
        motion.select(actionIndex: min(last, max(0, actionIndex)), progress: progress,
                      autoplay: autoplay && canAnimate)
        applyPose()
    }
    func play() { guard canAnimate else { return }; motion.play(); applyPose() }
    func pause() { if motion.isPlaying { motion.pause() } }
    func replay() { guard canAnimate else { return }; motion.replay(); applyPose() }
    func seek(_ progress: Double) { guard canAnimate else { pause(); return }; motion.seek(to: progress); applyPose() }
    func setSlow(_ slow: Bool) { motion.setSlow(slow) }
    func tick(elapsed: TimeInterval, allowed: Bool) {
        guard motion.isPlaying else { return }
        let old = motion.progress
        motion.advance(elapsed: elapsed, allowed: allowed && canAnimate)
        if old != motion.progress { applyPose() }
    }
    func resetView() {
        if isAR { tabletop.resetManipulation() }
        else { renderer.resetView() }
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
            try model.update(EverydayMeshGeometry.parts(courseID: courseID, actionIndex: motion.actionIndex, progress: motion.progress))
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
