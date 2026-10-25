import SwiftUI
import RealityKit
import ARKit
import Combine

enum ProductAsset {
    @MainActor static func load(from url: URL) async throws -> Entity {
        if #available(iOS 18.0, *) { return try await Entity(contentsOf: url) }
        for try await entity in Entity.loadAsync(contentsOf: url).values { return entity }
        throw CocoaError(.fileReadUnknown)
    }
}

// SwiftUI updates do not replace the renderer or an established AR anchor.
@MainActor
final class ProductSceneController: NSObject, ObservableObject {
    @Published var isLoaded = false
    @Published var failure: String?
    @Published var pose: ProductPose = .assembled
    @Published var partName = "Every part, explained."
    @Published var partDetail = "Drag to rotate. Pinch to zoom."
    @Published var releasePressed = false
    @Published var isAnimating = false
    @Published var hotspot: CGPoint?
    @Published var callout = ""
    private(set) var view: ARView?
    private var model: Entity?
    private var partEntities: [String: Entity] = [:]
    private var origins: [String: Transform] = [:]
    private let camera = PerspectiveCamera()
    private var target = SIMD3<Float>(0, 0.25, 0)
    private var yaw: Float = 0.50
    private var pitch: Float = 0.28
    private var distance: Float = 1.10
    private var initialYaw: Float = 0
    private var initialPitch: Float = 0
    private var initialDistance: Float = 1
    private var loadTask: Task<Void, Never>?
    private var replayTask: Task<Void, Never>?
    private var animationTask: Task<Void, Never>?
    private var updateSubscription: Cancellable?
    private var pointer: InstructionPointer?
    private var releaseOrigin: Transform?
    private var activeStep: ManualStep?
    private var lastProjection: TimeInterval = 0
    private var studioConfigured = false
    private var loadGeneration = 0

    func makeView() -> ARView {
        if studioConfigured, let view { return view }
        // One renderer is shared with AR. A second RealityKit view behind a
        // full-screen cover can leave the live camera background black.
        let v = view ?? ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view = v
        guard UIApplication.shared.applicationState != .background else { return v }
        studioConfigured = true
        failure = nil
        v.session.pause(); v.session.delegate = nil
        v.cameraMode = .nonAR; v.automaticallyConfigureSession = false
        v.environment.sceneUnderstanding.options = []
        v.scene.anchors.removeAll()
        for gesture in v.gestureRecognizers ?? [] { v.removeGestureRecognizer(gesture) }
        v.environment.background = .color(UIColor(red: 0.91, green: 0.94, blue: 0.88, alpha: 1))
        v.renderOptions = [.disableMotionBlur, .disableDepthOfField]
        if let environment = try? EnvironmentResource.load(named: "studio") {
            v.environment.lighting.resource = environment
            v.environment.lighting.intensityExponent = 0.70
        }
        v.accessibilityIdentifier = "productViewport"
        let anchor = AnchorEntity(world: .zero)
        v.scene.addAnchor(anchor)
        camera.camera.fieldOfViewInDegrees = 35
        anchor.addChild(camera)
        let key = DirectionalLight()
        key.light.color = .init(red: 1, green: 0.96, blue: 0.89, alpha: 1)
        key.light.intensity = 650
        key.look(at: [0, 0.2, 0], from: [-0.5, 1, 0.7], relativeTo: nil)
        anchor.addChild(key)
        let fill = PointLight(); fill.light.intensity = 220; fill.position = [0.6, 0.6, -0.5]; anchor.addChild(fill)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:))); v.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(zoom(_:))); v.addGestureRecognizer(pinch)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapModel(_:))); v.addGestureRecognizer(tap)
        view = v; updateCamera()
        loadGeneration += 1
        let generation = loadGeneration
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let url = Bundle.main.url(forResource: "aeris-one", withExtension: "usdz") else { throw CocoaError(.fileNoSuchFile) }
                let entity = try await ProductAsset.load(from: url)
                guard !Task.isCancelled, generation == self.loadGeneration, self.studioConfigured else { return }
                anchor.addChild(entity)
                self.model = entity
                for name in ["Rear_Cover", "Filter_Cartridge", "Top_Assembly", "Base_Assembly"] {
                    guard let part = entity.findEntity(named: name) else { throw NSError(domain: "AerisModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing model component: \(name)"]) }
                    self.partEntities[name] = part; self.origins[name] = part.transform
                }
                self.isLoaded = true
                self.releaseOrigin = entity.findEntity(named: "Cover_Release_Button")?.transform
                self.pointer = InstructionPointer(model: entity, space: anchor)
                self.updateSubscription = v.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
                    guard let self else { return }
                    self.pointer?.refreshPosition()
                    let now = CACurrentMediaTime()
                    if now - self.lastProjection > 0.05 {
                        self.lastProjection = now
                        let projected = self.pointer?.worldPoint.flatMap { self.view?.project($0) }
                        if let projected {
                            if self.hotspot.map({ hypot($0.x - projected.x, $0.y - projected.y) > 0.5 }) ?? true {
                                self.hotspot = projected
                            }
                        } else if self.hotspot != nil { self.hotspot = nil }
                    }
                }
                let extent = entity.visualBounds(relativeTo: nil).extents
                NSLog("AERIS_MODEL_LOADED parts=%d extent=%@", self.partEntities.count, String(describing: extent))
                self.setPose(.assembled, animated: false)
            } catch {
                guard !Task.isCancelled, generation == self.loadGeneration, self.studioConfigured else { return }
                self.failure = "The model could not be loaded. Close and reopen this guide."
                NSLog("AERIS_LOAD_ERROR %@", error.localizedDescription)
            }
        }
        return v
    }

    func prepareForAR() {
        loadGeneration += 1
        loadTask?.cancel(); replayTask?.cancel(); animationTask?.cancel()
        updateSubscription?.cancel(); updateSubscription = nil
        pointer?.clear(); pointer = nil
        model?.stopAllAnimations(recursive: true)
        // The AR screen borrows this view after studio teardown. A delayed
        // studio disappearance must never remove that screen's anchors/gestures.
        if view?.cameraMode == .nonAR {
            view?.session.pause(); view?.session.delegate = nil
            view?.scene.anchors.removeAll()
            for gesture in view?.gestureRecognizers ?? [] { view?.removeGestureRecognizer(gesture) }
        }
        model = nil; partEntities.removeAll(); origins.removeAll()
        camera.removeFromParent()
        studioConfigured = false; isLoaded = false; isAnimating = false; hotspot = nil
    }

    func shutdown() { prepareForAR() }

    func setPose(_ pose: ProductPose, animated: Bool = true) {
        replayTask?.cancel(); animationTask?.cancel(); self.pose = pose
        pointer?.clear(); callout = ""; hotspot = nil; releasePressed = false
        if let releaseOrigin { model?.findEntity(named: "Cover_Release_Button")?.transform = releaseOrigin }
        let duration: TimeInterval = animated && !UIAccessibility.isReduceMotionEnabled ? 0.85 : 0
        isAnimating = duration > 0
        for (name, entity) in partEntities {
            guard var transform = origins[name] else { continue }
            let offset: SIMD3<Float>
            switch (pose, name) {
            case (.cover, "Rear_Cover"): offset = [0, 0, -0.22]
            case (.filter, "Rear_Cover"), (.exploded, "Rear_Cover"): offset = [0, 0, -0.43]
            case (.insert, "Rear_Cover"): offset = [0, 0, -0.43]
            case (.filter, "Filter_Cartridge"), (.exploded, "Filter_Cartridge"): offset = [0, 0, -0.24]
            case (.exploded, "Top_Assembly"): offset = [0, 0.10, 0]
            case (.exploded, "Base_Assembly"): offset = [0, -0.045, 0]
            default: offset = .zero
            }
            // Blender's USD exporter wraps the file in a Z-up -> Y-up root.
            // Convert intended world/Y-up displacement to the actual parent frame.
            if let parent = entity.parent { transform.translation += parent.convert(direction: offset, from: nil) }
            else { transform.translation += offset }
            entity.stopAllAnimations(recursive: false)
            if duration == 0 { entity.transform = transform }
            else { entity.move(to: transform, relativeTo: entity.parent, duration: duration, timingFunction: .easeInOut) }
        }
        switch pose {
        case .assembled: target = [0, 0.25, 0]; yaw = 0.5; pitch = 0.43; distance = 1.13
        case .release, .cover, .filter, .insert, .closedRear: target = [0, 0.25, -0.16]; yaw = 2.4; pitch = 0.36; distance = 1.48
        case .exploded: target = [0, 0.25, -0.16]; yaw = 2.35; pitch = 0.40; distance = 1.48
        case .controls: target = [0, 0.34, 0]; yaw = 0.2; pitch = 0.96; distance = 0.87
        }
        updateCamera()
        inspect(pose == .cover || pose == .release || pose == .closedRear ? "Rear cover" : pose == .filter || pose == .exploded || pose == .insert ? "Filter cartridge" : pose == .controls ? "Top controls" : "Housing")
        animationTask = Task { [weak self] in
            if duration > 0 { try? await Task.sleep(for: .milliseconds(900)) }
            guard !Task.isCancelled else { return }; self?.isAnimating = false
        }
    }
    func guide(_ step: ManualStep, replay: Bool = false, animated: Bool = true) {
        activeStep = step
        if replay {
            let before: ProductPose = step.pose == .cover ? .release : step.pose == .filter ? .cover : step.pose == .insert ? .filter : step.pose == .closedRear ? .insert : .assembled
            setPose(before, animated: false)
            isAnimating = true
            replayTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }; self?.guide(step)
            }
            return
        }
        setPose(step.pose, animated: animated)
        pointer?.show(step.focus); callout = step.callout
    }
    func pressRelease() {
        guard pose == .release, !releasePressed, !isAnimating,
              let button = model?.findEntity(named: "Cover_Release_Button"), let parent = button.parent,
              var transform = releaseOrigin else { return }
        transform.translation += parent.convert(direction: [0, 0, 0.003], from: nil)
        button.move(to: transform, relativeTo: parent, duration: 0.2, timingFunction: .easeInOut)
        releasePressed = true; pointer?.markPressed(); callout = "RELEASED — NEXT STEP"
        isAnimating = true
        animationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(230))
            guard !Task.isCancelled else { return }; self?.isAnimating = false
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    @objc private func tapModel(_ gesture: UITapGestureRecognizer) {
        guard let hotspot, pose == .release else { return }
        let point = gesture.location(in: view)
        if hypot(point.x - hotspot.x, point.y - hotspot.y) < 48 { pressRelease() }
    }
    func replay(_ pose: ProductPose) {
        let from: ProductPose = pose == .assembled ? .filter : .assembled
        setPose(from, animated: false)
        replayTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.setPose(pose)
        }
    }
    func inspect(_ part: String) {
        partName = part
        switch part {
        case "Housing": partDetail = "A warm white shell with air inlets and a rear service opening."
        case "Rear cover": partDetail = "Release the small tab above the handle, then pull outward."
        case "Filter cartridge": partDetail = "Pleated media, two seals and a pull loop form one removable cartridge."
        case "Top controls": partDetail = "Power, mode and filter controls inside the air outlet grille."
        default: partDetail = "A rubber foot ring supports the housing."
        }
    }
    private func updateCamera() {
        let position = target + SIMD3<Float>(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
        camera.look(at: target, from: position, relativeTo: nil)
    }
    @objc private func drag(_ g: UIPanGestureRecognizer) {
        if g.state == .began { initialYaw = yaw; initialPitch = pitch }
        let t = g.translation(in: g.view)
        yaw = initialYaw - Float(t.x) * 0.008
        pitch = min(1.35, max(-0.08, initialPitch + Float(t.y) * 0.005))
        updateCamera()
    }
    @objc private func zoom(_ g: UIPinchGestureRecognizer) {
        if g.state == .began { initialDistance = distance }
        distance = min(2.6, max(0.60, initialDistance / Float(g.scale))); updateCamera()
    }
}

struct ProductSceneView: UIViewRepresentable {
    let controller: ProductSceneController
    func makeUIView(context: Context) -> ARView { controller.makeView() }
    func updateUIView(_ uiView: ARView, context: Context) {}
}
