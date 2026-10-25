import ARKit
import RealityKit
import SwiftUI
import Combine
import AVFoundation

@MainActor
final class ProductARController: NSObject, ObservableObject, ARSessionDelegate {
    @Published var status = "Move slowly to find a table"
    @Published var canPlace = false
    @Published var placed = false
    @Published var trackingReady = false
    @Published var needsReset = false
    @Published var error: String?
    @Published var modelReady = false
    @Published var stability: Float = 0
    @Published var guideProgress = ManualProgress()
    @Published var isAnimating = false
    @Published var releasePressed = false
    static var supported: Bool { ARWorldTrackingConfiguration.isSupported }
    private(set) var view: ARView?
    private var model: Entity?
    private var anchor: AnchorEntity?
    private var committedID: UUID?
    private var candidate: simd_float4x4?
    private var lastTimestamp: TimeInterval?
    private var normalSince: TimeInterval?
    private var lastPublish: TimeInterval = 0
    private var transforms: [String: Transform] = [:]
    private var loadTask: Task<Void, Never>?
    private var stopped = false
    private var animationRoot: Entity?
    private var pointer: InstructionPointer?
    private var releaseOrigin: Transform?
    private var animationTask: Task<Void, Never>?
    private var lastDiagnosticWrite: TimeInterval = 0
    private var interactionRoot: ModelEntity?
    private var manipulationGestures: [UIGestureRecognizer] = []
    private var configured = false
    private var peopleOcclusionEnabled = false
    private var sceneReconstructionEnabled = false
    private var depthEnabled = false
    private var permissionTask: Task<Void, Never>?
    private var sessionRevision = 0
    private var backgrounded = false
    var isStopped: Bool { stopped }

    init(task: ManualTask = .filter, sharedView: ARView? = nil) {
        super.init()
        view = sharedView
        guideProgress.select(task)
    }

    private var canInteract: Bool {
        !stopped && !backgrounded && placed && trackingReady && !needsReset && error == nil && !isAnimating
    }

    func makeView() -> ARView {
        if configured, let view { return view }
        let v = view ?? ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        configured = true
        v.cameraMode = .ar; v.automaticallyConfigureSession = false
        v.environment.background = .cameraFeed()
        v.environment.lighting.resource = nil
        v.environment.lighting.intensityExponent = 0
        v.environment.sceneUnderstanding.options = [.occlusion, .receivesLighting]
        v.isMultipleTouchEnabled = true
        view = v; v.session.delegate = self; v.session.delegateQueue = .main
        v.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapModel(_:))))
        v.renderOptions = [.disableMotionBlur, .disableDepthOfField]
        loadModelIfNeeded()
        requestSessionStart()
        return v
    }

    private func loadModelIfNeeded() {
        guard view != nil, model == nil, !stopped, !backgrounded else { return }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let url = Bundle.main.url(forResource: "aeris-one", withExtension: "usdz") else { throw CocoaError(.fileNoSuchFile) }
                let entity = try await ProductAsset.load(from: url)
                guard !Task.isCancelled, !self.stopped, !self.backgrounded else { return }
                self.model = entity
                self.enableGroundingShadows(on: entity)
                for name in ["Rear_Cover", "Filter_Cartridge", "Top_Assembly", "Base_Assembly"] {
                    guard let part = entity.findEntity(named: name) else { throw CocoaError(.coderInvalidValue) }
                    self.transforms[name] = part.transform
                }
                self.modelReady = true
                self.releaseOrigin = entity.findEntity(named: "Cover_Release_Button")?.transform
                self.recordDiagnostic(force: true)
            } catch {
                guard !Task.isCancelled, !self.stopped, !self.backgrounded else { return }
                self.error = "Unable to load the model: \(error.localizedDescription)"
            }
        }
    }

    private func requestSessionStart() {
        guard Self.supported, view != nil, !stopped, !backgrounded, UIApplication.shared.applicationState != .background else { return }
        sessionRevision += 1
        let revision = sessionRevision
        permissionTask?.cancel()
        permissionTask = Task { [weak self] in
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
            default: allowed = false
            }
            guard let self, !Task.isCancelled, !self.stopped, !self.backgrounded,
                  revision == self.sessionRevision,
                  UIApplication.shared.applicationState != .background else { return }
            if allowed { self.runSession() }
            else { self.error = "Camera access is off. Enable it in Settings, or return to the 3D guide." }
        }
    }
    private func runSession() {
        guard Self.supported, let view, !stopped, !backgrounded,
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              UIApplication.shared.applicationState != .background else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        config.isLightEstimationEnabled = true
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            config.frameSemantics.insert(.personSegmentationWithDepth)
            peopleOcclusionEnabled = true
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
            depthEnabled = true
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
            sceneReconstructionEnabled = true
        }
        view.environment.background = .cameraFeed()
        // Tabletop placement uses world tracking, not recognition or
        // registration of a real appliance.
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        status = "Move slowly. Include the table and surrounding texture."
    }
    func reset() {
        guard !stopped else { return }
        backgrounded = false
        error = nil
        pointer?.clear(); pointer = nil; animationTask?.cancel(); guideProgress.select(guideProgress.task); releasePressed = false; isAnimating = false
        anchor?.removeFromParent(); anchor = nil; committedID = nil; animationRoot = nil
        candidate = nil; normalSince = nil; lastTimestamp = nil
        for gesture in manipulationGestures { view?.removeGestureRecognizer(gesture) }
        manipulationGestures.removeAll(); interactionRoot = nil
        placed = false; canPlace = false; needsReset = false; stability = 0; trackingReady = false
        model?.removeFromParent()
        model?.stopAllAnimations(recursive: true)
        for (name, t) in transforms { model?.findEntity(named: name)?.transform = t }
        if let releaseOrigin { model?.findEntity(named: "Cover_Release_Button")?.transform = releaseOrigin }
        loadModelIfNeeded()
        requestSessionStart()
    }
    func stop() {
        stopped = true; sessionRevision += 1
        permissionTask?.cancel(); loadTask?.cancel(); animationTask?.cancel()
        model?.stopAllAnimations(recursive: true)
        pointer?.clear(); pointer = nil
        anchor?.isEnabled = false
        trackingReady = false; canPlace = false; isAnimating = false
        // The view may already have returned to the studio. Only its current AR
        // owner can pause it or remove gestures during delayed cover teardown.
        if let view, view.session.delegate === self {
            view.session.pause(); view.session.delegate = nil
            view.scene.anchors.removeAll()
            for gesture in view.gestureRecognizers ?? [] { view.removeGestureRecognizer(gesture) }
        }
        manipulationGestures.removeAll()
    }
    func pauseForBackground() {
        guard !stopped else { return }
        backgrounded = true; sessionRevision += 1
        permissionTask?.cancel(); loadTask?.cancel(); animationTask?.cancel()
        model?.stopAllAnimations(recursive: true)
        isAnimating = false
        view?.session.pause(); anchor?.isEnabled = false; canPlace = false; trackingReady = false
        needsReset = true; status = "Session paused. Scan the table again to continue."
    }
    func place(at point: CGPoint? = nil) {
        guard !stopped, !backgrounded, modelReady, trackingReady, !placed, !needsReset,
              let model, let view, let frame = view.session.currentFrame,
              case .normal = frame.camera.trackingState,
              CACurrentMediaTime() - frame.timestamp < 0.2 else { return }
        // Confirm a fresh surface under the reticle at the moment the user taps.
        guard let hit = surfaceHit(at: point ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY)) else {
            canPlace = false; candidate = nil
            status = "Aim the centre at the table again."
            return
        }
        let transform = hit.worldTransform
        var worldTransform = matrix_identity_float4x4
        worldTransform.columns.3 = transform.columns.3
        let worldAnchor = ARAnchor(name: "Aeris_Tabletop", transform: worldTransform)
        let contentAnchor = AnchorEntity(.anchor(identifier: worldAnchor.identifier))
        let movable = ModelEntity(); movable.name = "User_Placement"
        let local = Entity(); local.name = "AnimationRoot"
        // Align the front to the person placing it while the world anchor stays fixed.
        let cam = frame.camera.transform.columns.3
        let pos = transform.columns.3
        let yaw = atan2(cam.x - pos.x, cam.z - pos.z)
        local.setOrientation(simd_quatf(angle: yaw, axis: [0, 1, 0]), relativeTo: nil)
        local.addChild(model)
        // Ground the actual imported mesh, independent of its file's origin.
        local.position.y = -model.visualBounds(relativeTo: local).min.y + 0.001
        movable.addChild(local); contentAnchor.addChild(movable)
        view.session.add(anchor: worldAnchor); view.scene.addAnchor(contentAnchor)
        anchor = contentAnchor; animationRoot = local; committedID = worldAnchor.identifier
        interactionRoot = movable
        updateInteractionBounds()
        manipulationGestures = view.installGestures([.translation, .rotation, .scale], for: movable).compactMap { $0 as? UIGestureRecognizer }
        for gesture in manipulationGestures { gesture.addTarget(self, action: #selector(manipulationChanged(_:))) }
        pointer = InstructionPointer(model: model, space: local)
        placed = true; canPlace = false; candidate = nil
        status = "Drag to move · Pinch to resize · Twist to rotate"
        NSLog("AERIS_AR_PLACED anchor=%@ writes=1", worldAnchor.identifier.uuidString)
        guideProgress.select(guideProgress.task)
        pointer?.show(guideProgress.current.focus)
        recordDiagnostic(force: true)
    }
    private func updateInteractionBounds() {
        guard let model, let interactionRoot else { return }
        let bounds = model.visualBounds(relativeTo: interactionRoot)
        let shape = ShapeResource.generateBox(size: bounds.extents + SIMD3<Float>(repeating: 0.015)).offsetBy(translation: bounds.center)
        interactionRoot.collision = CollisionComponent(shapes: [shape])
    }
    private func surfaceHit(at point: CGPoint) -> ARRaycastResult? {
        guard let view else { return nil }
        return view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal).first
            ?? view.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal).first
    }
    private func enableGroundingShadows(on entity: Entity) {
        if #available(iOS 18.0, *), entity.components.has(ModelComponent.self) {
            entity.components.set(GroundingShadowComponent(castsShadow: true, receivesShadow: true, fadeBehaviorNearPhysicalObjects: .constant))
        }
        for child in entity.children { enableGroundingShadows(on: child) }
    }
    @objc private func manipulationChanged(_ gesture: UIGestureRecognizer) {
        if gesture is EntityScaleGestureRecognizer, let interactionRoot {
            let size = min(max(interactionRoot.scale.x, 0.2), 2)
            interactionRoot.scale = SIMD3<Float>(repeating: size)
        }
        if gesture.state == .ended { recordDiagnostic(force: true) }
    }
    func show(_ pose: ProductPose) {
        guard placed, trackingReady, !needsReset, let model, let local = animationRoot else { return }
        for (name, origin) in transforms {
            guard let entity = model.findEntity(named: name), let parent = entity.parent else { continue }
            var t = origin
            let offset: SIMD3<Float>
            switch (pose, name) {
            case (.cover, "Rear_Cover"): offset = [0, 0, -0.22]
            case (.filter, "Rear_Cover"), (.exploded, "Rear_Cover"): offset = [0, 0, -0.43]
            case (.insert, "Rear_Cover"): offset = [0, 0, -0.43]
            case (.filter, "Filter_Cartridge"), (.exploded, "Filter_Cartridge"): offset = [0, 0, -0.24]
            case (.exploded, "Top_Assembly"): offset = [0, 0.10, 0]
            case (.exploded, "Base_Assembly"): offset = [0, 0.0, 0] // Keep support on the real table.
            default: offset = .zero
            }
            t.translation += parent.convert(direction: offset, from: local)
            entity.stopAllAnimations(recursive: false)
            entity.move(to: t, relativeTo: parent, duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.9, timingFunction: .easeInOut)
        }
    }
    func nextGuideStep() {
        guard canInteract, guideProgress.canAdvance || guideProgress.completed else { return }
        guideProgress.next(); applyGuide()
    }
    func previousGuideStep() {
        guard canInteract, guideProgress.index > 0 else { return }
        guideProgress.go(to: guideProgress.index - 1); applyGuide()
    }
    private func applyGuide() {
        animationTask?.cancel(); releasePressed = false
        if let releaseOrigin { model?.findEntity(named: "Cover_Release_Button")?.transform = releaseOrigin }
        pointer?.clear()
        show(guideProgress.completed ? .assembled : guideProgress.current.pose)
        if !guideProgress.completed { pointer?.show(guideProgress.current.focus) }
        isAnimating = true
        animationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(950))
            guard !Task.isCancelled else { return }; self?.updateInteractionBounds(); self?.isAnimating = false
        }
    }
    func replayGuide() {
        guard canInteract, !guideProgress.completed else { return }
        let pose = guideProgress.current.pose
        let before: ProductPose = pose == .cover ? .release : pose == .filter ? .cover : pose == .insert ? .filter : pose == .closedRear ? .insert : .assembled
        guideProgress.actionConfirmed = false; show(before); pointer?.clear(); isAnimating = true
        animationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled else { return }; self?.applyGuide()
        }
    }
    func pressRelease() {
        guard canInteract, !guideProgress.completed, guideProgress.current.requiresPress, !releasePressed,
              let button = model?.findEntity(named: "Cover_Release_Button"), let parent = button.parent,
              let local = animationRoot, var t = releaseOrigin else { return }
        t.translation += parent.convert(direction: [0, 0, 0.003], from: local)
        button.move(to: t, relativeTo: parent, duration: 0.2, timingFunction: .easeInOut)
        releasePressed = true; guideProgress.confirmAction(); pointer?.markPressed()
        isAnimating = true
        animationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(230))
            guard !Task.isCancelled else { return }; self?.isAnimating = false
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    @objc private func tapModel(_ gesture: UITapGestureRecognizer) {
        if !placed { place(at: gesture.location(in: view)); return }
        guard let world = pointer?.worldPoint, let projected = view?.project(world) else { return }
        let touch = gesture.location(in: view)
        if hypot(touch.x - projected.x, touch.y - projected.y) < 48 { pressRelease() }
    }
    // Main delegate queue keeps RealityKit and observable updates on the UI thread.
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        MainActor.assumeIsolated { assess(frame) }
    }
    private func assess(_ frame: ARFrame) {
        guard !stopped, view?.session.delegate === self else { return }
        defer { recordDiagnostic() }
        pointer?.refreshPosition()
        guard !stopped, !needsReset else { return }
        let now = frame.timestamp
        let fresh = lastTimestamp.map { now > $0 && now - $0 < 0.25 } ?? false
        lastTimestamp = now
        let normal: Bool
        if case .normal = frame.camera.trackingState { normal = true } else { normal = false }
        for gesture in manipulationGestures { gesture.isEnabled = normal && fresh }
        if !normal || !fresh {
            candidate = nil; normalSince = nil; canPlace = false; stability = 0
            trackingReady = false; anchor?.isEnabled = false
            status = placed ? "Tracking is unstable. The model is temporarily hidden." : "Move slowly to help the camera understand the space."
            return
        }
        if normalSince == nil { normalSince = now }
        if placed {
            let sameAnchor = frame.anchors.contains { $0.identifier == committedID }
            let recovered = now - (normalSince ?? now) >= 0.6
            trackingReady = sameAnchor && recovered
            anchor?.isEnabled = trackingReady
            status = trackingReady ? "Drag to move · Pinch to resize · Twist to rotate" : "Recovering the same position…"
            return
        }
        guard let view else { return }
        let point = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        guard let hit = surfaceHit(at: point) else {
            candidate = nil; canPlace = false; stability = 0
            status = modelReady ? "Move your phone to find a surface, then tap to place." : "Loading the product model…"
            return
        }
        // Native surface placement: no reference-image pose gate or jitter lock.
        candidate = hit.worldTransform
        canPlace = modelReady
        trackingReady = normal
        if now - lastPublish > 0.1 {
            lastPublish = now; stability = modelReady ? 1 : 0
            status = !modelReady ? "Surface found. Loading the product model…" : "Tap the surface or choose Place Here."
        }
    }
    private func recordDiagnostic(force: Bool = false) {
        let now = CACurrentMediaTime()
        guard force || now - lastDiagnosticWrite >= 1 else { return }
        lastDiagnosticWrite = now
        let frame = view?.session.currentFrame
        let values: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "status": status, "modelReady": modelReady, "surfaceDetected": candidate != nil,
            "canPlace": canPlace, "placed": placed, "trackingReady": trackingReady,
            "needsReset": needsReset, "step": guideProgress.index + 1,
            "completed": guideProgress.completed, "error": error ?? "",
            "nativeGestureCount": manipulationGestures.count,
            "modelScale": interactionRoot?.scale.x ?? 1,
            "cameraModeAR": view?.cameraMode == .ar,
            "cameraImageWidth": frame.map { CVPixelBufferGetWidth($0.capturedImage) } ?? 0,
            "cameraImageHeight": frame.map { CVPixelBufferGetHeight($0.capturedImage) } ?? 0,
            "peopleOcclusionEnabled": peopleOcclusionEnabled,
            "sceneReconstructionEnabled": sceneReconstructionEnabled,
            "sceneDepthEnabled": depthEnabled,
            "hasPersonMask": frame?.segmentationBuffer != nil,
            "hasPersonDepth": frame?.estimatedDepthData != nil,
            "hasSceneDepth": frame?.sceneDepth != nil,
            "sceneMeshCount": frame?.anchors.filter { $0 is ARMeshAnchor }.count ?? 0,
            "groundingShadowsEnabled": true
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        // Local status only. No camera images or world positions are stored.
        try? data.write(to: documents.appendingPathComponent("AerisManualARStatus.json"), options: .atomic)
    }
    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        MainActor.assumeIsolated {
            guard !stopped, view?.session === session, session.delegate === self else { return }
            if let id = committedID, anchors.contains(where: { $0.identifier == id }) {
                anchor?.isEnabled = false; needsReset = true; trackingReady = false; status = "The original position was lost. Scan the table again."
            }
        }
    }
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        MainActor.assumeIsolated {
            guard !stopped, view?.session === session, session.delegate === self else { return }
            pauseForBackground()
        }
    }
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated {
            guard !stopped, view?.session === session, session.delegate === self else { return }
            pauseForBackground()
            self.error = "AR session failed: \(message)"
        }
    }
}

struct NativeARView: UIViewRepresentable {
    let controller: ProductARController
    final class Coordinator {
        let controller: ProductARController
        init(controller: ProductARController) { self.controller = controller }
    }
    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }
    func makeUIView(context: Context) -> ARView { controller.makeView() }
    func updateUIView(_ uiView: ARView, context: Context) {}
    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) { coordinator.controller.stop() }
}

struct ProductARScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @StateObject private var controller: ProductARController
    @State private var previousIdleTimerDisabled = false
    private let green = Color(red: 0.15, green: 0.31, blue: 0.23)
    init(task: ManualTask = .filter, sharedView: ARView? = nil) {
        _controller = StateObject(wrappedValue: ProductARController(task: task, sharedView: sharedView))
    }
    var body: some View {
        ZStack {
            if ProductARController.supported {
                NativeARView(controller: controller).ignoresSafeArea()
                if !controller.placed && controller.error == nil {
                    Image(systemName: controller.canPlace ? "scope" : "plus").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(controller.canPlace ? Color.green : .white).shadow(radius: 3)
                }
            } else {
                Color(red: 0.93, green: 0.95, blue: 0.89).ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "arkit").font(.system(size: 60, weight: .ultraLight))
                    Text("AERIS, in your space.").font(.title3)
                    Text("Open this on an ARKit-capable iPhone or iPad.\nThe Simulator supports 3D viewing, but cannot detect a real table.").font(.subheadline).multilineTextAlignment(.center).lineSpacing(5)
                    Button("Return to 3D Guide") { dismiss() }.buttonStyle(.borderedProminent).tint(green).accessibilityIdentifier("returnTo3D")
                }.foregroundStyle(green).padding(25)
            }
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 3) { Text("AERIS / Spatial Guide").font(.system(size: 15, weight: .medium)); Text(controller.guideProgress.task.rawValue).font(.system(size: 11)) }
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).padding(12).background(.regularMaterial, in: Circle()) }.accessibilityIdentifier("closeAR").accessibilityLabel("Close AR")
                }.padding(20).background(.ultraThinMaterial)
                Spacer()
                if ProductARController.supported {
                    VStack(spacing: 14) {
                        Text(controller.error ?? controller.status).font(.system(size: 13, weight: .medium)).multilineTextAlignment(.center)
                        Text("Virtual concept model · Not aligned to a real appliance")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .accessibilityIdentifier("productARScope")
                        if controller.error != nil {
                            Button("Try camera again") { controller.reset() }
                                .buttonStyle(.bordered).tint(green)
                                .accessibilityIdentifier("retryProductAR")
                        }
                        if controller.error == nil {
                            if controller.needsReset { Button("Scan Table Again") { controller.reset() }.buttonStyle(.borderedProminent).tint(green) }
                            else if controller.placed {
                                Text(controller.guideProgress.completed ? "Guide complete" : "STEP \(controller.guideProgress.index + 1) / \(controller.guideProgress.task.steps.count) · \(controller.guideProgress.current.title)").font(.system(size: 16, weight: .semibold)).accessibilityIdentifier("arStepTitle")
                                if !controller.guideProgress.completed {
                                    Label(controller.releasePressed ? "RELEASED" : controller.guideProgress.current.callout, systemImage: controller.releasePressed ? "checkmark.circle.fill" : "arrow.up.right").font(.system(size: 12, weight: .bold)).foregroundStyle(controller.releasePressed ? green : .red)
                                    Text(controller.guideProgress.current.detail).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                    if controller.guideProgress.current.requiresPress && !controller.releasePressed {
                                        Button("Press the red release tab") { controller.pressRelease() }.tint(.red).buttonStyle(.bordered).disabled(!controller.trackingReady || controller.isAnimating).accessibilityIdentifier("arPressRelease")
                                    }
                                }
                                Button { controller.nextGuideStep() } label: { Label(controller.guideProgress.completed ? "Start Again" : controller.isAnimating ? "Playing action…" : "Next Step", systemImage: "arrow.right").foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 5) }.buttonStyle(.borderedProminent).tint(green).disabled(!controller.trackingReady || controller.isAnimating || (!controller.guideProgress.canAdvance && !controller.guideProgress.completed)).accessibilityIdentifier("arNextStep")
                                HStack {
                                    Button("Back") { controller.previousGuideStep() }.disabled(controller.guideProgress.index == 0).accessibilityIdentifier("arBack")
                                    Spacer()
                                    Button("Replay action") { controller.replayGuide() }.disabled(controller.guideProgress.completed).accessibilityIdentifier("arReplay")
                                    Spacer()
                                    Button("Place again") { controller.reset() }.accessibilityIdentifier("arPlaceAgain")
                                }.font(.system(size: 12)).disabled(controller.isAnimating || !controller.trackingReady)
                            } else {
                                if !controller.modelReady { ProgressView("Loading model…").font(.caption).tint(green) }
                                Button { controller.place() } label: { Label("Place Here", systemImage: "plus.viewfinder").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent).tint(green).disabled(!controller.canPlace).accessibilityIdentifier("arPlaceHere")
                            }
                        }
                        Text(controller.placed ? "Turn the model to reach the red tab. Keep following the steps here in AR." : "Place on a table or floor. Then drag, pinch and rotate the model.").font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22)).padding(16)
                }
            }.foregroundStyle(green)
        }
        .onAppear {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            controller.stop()
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        }
        .onChange(of: phase) { _, newValue in if newValue == .background { controller.pauseForBackground() } }
    }
}
