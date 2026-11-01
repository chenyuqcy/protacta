import ARKit
import AVFoundation
import RealityKit
import UIKit
import Combine

/// Authored metres are scaled as one unit; the mesh and step offsets stay intact.
struct TutorialTabletopLayout {
    let scale: Float
    let offset: SIMD3<Float>
    init?(minimum: SIMD3<Float>, maximum: SIMD3<Float>, span: Float = 0.55) {
        let extent = maximum - minimum
        guard (0..<3).allSatisfy({ minimum[$0].isFinite && maximum[$0].isFinite && extent[$0].isFinite && extent[$0] >= 0 }),
              span.isFinite, span > 0 else { return nil }
        let longest = max(extent.x, max(extent.y, extent.z))
        guard longest > 0.0001 else { return nil }
        scale = span / longest
        guard scale.isFinite, scale > 0 else { return nil }
        let center = (minimum + maximum) * 0.5
        offset = [-center.x, -minimum.y + 0.01 / scale, -center.z]
    }
}

/// Requires consecutive fresh frames and a short normal-tracking interval.
/// A missing committed anchor cannot be replaced by a newly detected surface.
struct TutorialTabletopTracking {
    private var lastTimestamp: TimeInterval?
    private var normalSince: TimeInterval?
    mutating func reset() { lastTimestamp = nil; normalSince = nil }
    mutating func observe(timestamp: TimeInterval, normal: Bool, anchorPresent: Bool) -> Bool {
        let fresh = timestamp.isFinite && lastTimestamp.map { timestamp > $0 && timestamp - $0 < 0.25 } == true
        lastTimestamp = timestamp.isFinite ? timestamp : nil
        guard fresh, normal else { normalSince = nil; return false }
        if normalSince == nil { normalSince = timestamp }
        return anchorPresent && timestamp - (normalSince ?? timestamp) >= 0.4
    }
}

/// Borrows the existing studio ARView and model. Placement is a virtual tabletop
/// reference, not registration with a real motor or aircraft engine.
@MainActor
final class TutorialTabletopARController: NSObject, ObservableObject, ARSessionDelegate, UIGestureRecognizerDelegate {
    @Published private(set) var status = "Move slowly to find a table."
    @Published private(set) var canPlace = false
    @Published private(set) var placed = false
    @Published private(set) var trackingReady = false
    @Published private(set) var isRequestingCamera = false
    @Published private(set) var isLayoutPreview = false
    @Published private(set) var error: String?
    @Published private(set) var occlusionMode: EquipmentOcclusionMode
    @Published private(set) var handEdgeNotice: String?
    private let occlusionCapabilities: EquipmentOcclusionCapabilities
    private let handDepth = SceneDepthOcclusion(profile: .stableEquipment)
    private var depthSessionStartedAt: TimeInterval = 0
    private var lastDepthObservedAt: TimeInterval?
    private var lastDiagnosticWrite: TimeInterval = 0
    private(set) weak var view: ARView?
    private var content: Entity?
    private var layout: TutorialTabletopLayout?
    private var placementAnchor: AnchorEntity?
    private var worldAnchor: ARAnchor?
    private var movable: Entity?
    private var gestures: [UIGestureRecognizer] = []
    private var permissionTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var generation = 0
    private var backgrounded = false
    private var pendingStart = false
    private var gate = TutorialTabletopTracking()
    private var lastFrame: TimeInterval?
    private var initialYaw: Float = 0
    private var placedYaw: Float = 0
    private var scaleFactor: Float = 1
    private var pinchStart: Float = 1
    private var rotationStart: Float = 0
    private var panOffset = SIMD3<Float>.zero
    var onEntityTap: ((Entity?) -> Void)?
    var ready: Bool { placed && trackingReady && error == nil && !backgrounded }
    var supportsStableEdges: Bool { occlusionCapabilities.stableDepth }

    override init() {
        let capabilities = EquipmentOcclusionCapabilities.current
        occlusionCapabilities = capabilities
        _occlusionMode = Published(initialValue: EquipmentOcclusionConfiguration.effective(.stableEdges, capabilities: capabilities))
        super.init()
    }

    static var supportsAR: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return ARWorldTrackingConfiguration.isSupported
        #endif
    }

    static var layoutPreviewRequested: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--equipment-ar-layout-fixture")
        #else
        return false
        #endif
    }

    func startLayoutPreview() {
        #if DEBUG && targetEnvironment(simulator)
        guard Self.layoutPreviewRequested else { return }
        isLayoutPreview = true; placed = true; trackingReady = true
        setStatus("AR LAYOUT PREVIEW · NO LIVE CAMERA")
        #endif
    }

    func start(view: ARView, content: Entity, layout: TutorialTabletopLayout, initialYaw: Float) {
        stop()
        self.view = view; self.content = content; self.layout = layout; self.initialYaw = initialYaw
        backgrounded = false; error = nil
        view.cameraMode = .ar; view.automaticallyConfigureSession = false
        view.environment.background = .cameraFeed()
        view.environment.lighting.resource = nil
        view.environment.lighting.intensityExponent = 0
        view.environment.sceneUnderstanding.options = []
        view.renderOptions = EquipmentOcclusionConfiguration.renderOptions(mode: occlusionMode, capabilities: occlusionCapabilities)
        view.session.delegate = self; view.session.delegateQueue = .main
        let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.maximumNumberOfTouches = 1; pan.delegate = self
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        pinch.delegate = self
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(rotate(_:)))
        rotate.delegate = self
        tap.require(toFail: pan)
        gestures = [tap, pan, pinch, rotate]
        for gesture in gestures { view.addGestureRecognizer(gesture) }
        requestCamera()
    }

    private func requestCamera() {
        generation += 1
        let revision = generation
        isRequestingCamera = true; setStatus("Starting camera…")
        permissionTask?.cancel()
        permissionTask = Task { @MainActor [weak self] in
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
            default: allowed = false
            }
            guard let self, !Task.isCancelled, revision == self.generation, self.view != nil else { return }
            self.isRequestingCamera = false
            guard allowed else {
                self.error = "Camera access is off. Enable it in Settings, or return to the 3D view."
                self.setStatus(self.error!); return
            }
            guard !self.backgrounded else { return }
            if UIApplication.shared.applicationState == .active { self.runSession() }
            else { self.pendingStart = true }
        }
    }

    private func runSession() {
        guard Self.supportsAR, let view, !backgrounded,
              UIApplication.shared.applicationState == .active,
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        removePlacement(); gate.reset(); lastFrame = nil
        pendingStart = false; error = nil
        let config = EquipmentOcclusionConfiguration.make(mode: occlusionMode, capabilities: occlusionCapabilities)
        configureHandDepth()
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        setStatus("Move slowly. Aim at a clear, well-lit table.")
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, self.view?.session.delegate === self else { return }
                if let last = self.lastFrame, CACurrentMediaTime() - last > 0.3 {
                    self.gate.reset(); self.setReady(false); self.setCanPlace(false)
                    self.placementAnchor?.isEnabled = false
                    self.setStatus("Tracking paused. Keep the table in view, or scan again.")
                }
            }
        }
    }

    /// Change only the depth provider. No anchor-removal or tracking-reset
    /// options are passed; authored pose and the existing placement survive.
    func setOcclusionMode(_ requested: EquipmentOcclusionMode) {
        let selected = EquipmentOcclusionConfiguration.effective(requested, capabilities: occlusionCapabilities)
        guard selected != occlusionMode else { return }
        occlusionMode = selected; handEdgeNotice = nil
        guard let view, view.session.delegate === self, !backgrounded else { return }
        configureHandDepth()
        if view.session.configuration != nil {
            gate.reset(); setReady(false); setCanPlace(false); placementAnchor?.isEnabled = false
            view.session.run(EquipmentOcclusionConfiguration.make(mode: selected, capabilities: occlusionCapabilities))
        }
        recordDiagnostic(force: true)
    }

    private func configureHandDepth() {
        guard let view else { return }
        handDepth.reset()
        view.renderOptions = EquipmentOcclusionConfiguration.renderOptions(mode: occlusionMode, capabilities: occlusionCapabilities)
        view.environment.sceneUnderstanding.options = []
        depthSessionStartedAt = CACurrentMediaTime(); lastDepthObservedAt = nil
        if EquipmentOcclusionConfiguration.usesObjectDepth(mode: occlusionMode, capabilities: occlusionCapabilities) {
            handDepth.configure(in: view, excludingNativePeople: EquipmentOcclusionConfiguration.usesNativeHands(mode: occlusionMode, capabilities: occlusionCapabilities))
        }
    }

    func place(at point: CGPoint? = nil) {
        guard !isLayoutPreview, !placed, canPlace, trackingReady, let view,
              let content, let layout, let frame = freshFrame(),
              let hit = surfaceHit(at: point ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY)) else { return }
        var transform = matrix_identity_float4x4
        transform.columns.3 = hit.worldTransform.columns.3
        let realAnchor = ARAnchor(name: "Protacta_Virtual_Equipment", transform: transform)
        let anchor = AnchorEntity(.anchor(identifier: realAnchor.identifier))
        let container = Entity(); container.name = "Tabletop manipulation"
        let offset = Entity(); offset.position = layout.offset
        offset.addChild(content); container.addChild(offset)
        let camera = frame.camera.transform.columns.3, position = transform.columns.3
        placedYaw = atan2(camera.x - position.x, camera.z - position.z) - initialYaw
        scaleFactor = 1
        container.scale = SIMD3(repeating: layout.scale)
        container.orientation = simd_quatf(angle: placedYaw, axis: [0, 1, 0])
        anchor.addChild(container)
        let light = DirectionalLight(); light.light.intensity = 1100
        light.look(at: .zero, from: [-0.6, 1, 0.8], relativeTo: nil)
        anchor.addChild(light)
        view.session.add(anchor: realAnchor); view.scene.addAnchor(anchor)
        placementAnchor = anchor; worldAnchor = realAnchor; movable = container
        placed = true; setCanPlace(false)
        setStatus("Drag to move · Pinch to resize · Twist to rotate")
    }

    func resetPlacement() {
        guard !isLayoutPreview else { return }
        removePlacement(); gate.reset(); setReady(false); setCanPlace(false)
        setStatus("Aim at the table, then place the virtual model again.")
    }

    func resetManipulation() {
        guard ready, let layout, let movable else { return }
        scaleFactor = 1; movable.scale = SIMD3(repeating: layout.scale)
        movable.orientation = simd_quatf(angle: placedYaw, axis: [0, 1, 0])
    }

    func handleInactive() {
        if isRequestingCamera && UIApplication.shared.applicationState != .background { return }
        guard !isLayoutPreview else { return }
        backgrounded = true; pendingStart = false
        generation += 1; permissionTask?.cancel(); isRequestingCamera = false
        watchdog?.cancel(); view?.session.pause()
        handDepth.reset()
        setReady(false); setCanPlace(false); placementAnchor?.isEnabled = false
        setStatus("Session paused. Return and scan the table again.")
    }

    func handleActive() {
        guard !isLayoutPreview, view != nil, error == nil else { return }
        guard UIApplication.shared.applicationState == .active else { pendingStart = true; return }
        if backgrounded || pendingStart {
            backgrounded = false
            if AVCaptureDevice.authorizationStatus(for: .video) == .authorized { runSession() }
            else { requestCamera() }
        }
    }

    func stop() {
        generation += 1; permissionTask?.cancel(); permissionTask = nil
        watchdog?.cancel(); watchdog = nil
        handDepth.reset()
        if let view, view.session.delegate === self { view.session.pause(); view.session.delegate = nil }
        removePlacement()
        for gesture in gestures { gesture.view?.removeGestureRecognizer(gesture) }
        gestures.removeAll(); content?.removeFromParent(); content = nil; view = nil
        setReady(false); setCanPlace(false); placed = false; isRequestingCamera = false
        pendingStart = false; backgrounded = false; isLayoutPreview = false; error = nil
        handEdgeNotice = nil
    }

    private func removePlacement() {
        placementAnchor?.removeFromParent(); placementAnchor = nil
        if let worldAnchor, let view, view.session.delegate === self { view.session.remove(anchor: worldAnchor) }
        worldAnchor = nil; movable = nil; placed = false
        content?.removeFromParent()
    }

    private func freshFrame() -> ARFrame? {
        guard !backgrounded, error == nil, let frame = view?.session.currentFrame,
              case .normal = frame.camera.trackingState,
              CACurrentMediaTime() - frame.timestamp < 0.25 else { return nil }
        return frame
    }
    private func surfaceHit(at point: CGPoint) -> ARRaycastResult? {
        guard let view else { return nil }
        return view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal).first
            ?? view.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal).first
    }
    private func setStatus(_ value: String) { if status != value { status = value } }
    private func setReady(_ value: Bool) { if trackingReady != value { trackingReady = value } }
    private func setCanPlace(_ value: Bool) { if canPlace != value { canPlace = value } }

    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        guard let view else { return }
        if !placed { place(at: gesture.location(in: view)); return }
        guard ready, freshFrame() != nil else { return }
        onEntityTap?(view.entity(at: gesture.location(in: view)))
    }
    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        guard ready, freshFrame() != nil, let view, let movable,
              let hit = surfaceHit(at: gesture.location(in: view)) else { return }
        let world = SIMD3<Float>(hit.worldTransform.columns.3.x, hit.worldTransform.columns.3.y, hit.worldTransform.columns.3.z)
        if gesture.state == .began { panOffset = movable.position(relativeTo: nil) - world }
        if gesture.state == .began || gesture.state == .changed { movable.setPosition(world + panOffset, relativeTo: nil) }
    }
    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        guard ready, freshFrame() != nil, let movable, let layout else { return }
        if gesture.state == .began { pinchStart = scaleFactor }
        scaleFactor = min(3, max(0.25, pinchStart * Float(gesture.scale)))
        movable.scale = SIMD3(repeating: layout.scale * scaleFactor)
    }
    @objc private func rotate(_ gesture: UIRotationGestureRecognizer) {
        guard ready, freshFrame() != nil, let movable else { return }
        if gesture.state == .began { rotationStart = movable.orientation.angle * (movable.orientation.axis.y < 0 ? -1 : 1) }
        movable.orientation = simd_quatf(angle: rotationStart - Float(gesture.rotation), axis: [0, 1, 0])
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIRotationGestureRecognizer)
            || (gestureRecognizer is UIRotationGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer)
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        MainActor.assumeIsolated { assess(frame) }
    }
    private func assess(_ frame: ARFrame) {
        guard view?.session.delegate === self, !backgrounded else { return }
        let normal: Bool
        if case .normal = frame.camera.trackingState { normal = true } else { normal = false }
        if EquipmentOcclusionConfiguration.usesObjectDepth(mode: occlusionMode, capabilities: occlusionCapabilities) {
            handDepth.update(frame: frame, supportPlaneY: movable?.position(relativeTo: nil).y,
                             target: placed ? content : nil)
            if !normal {
                depthSessionStartedAt = CACurrentMediaTime(); lastDepthObservedAt = nil
            } else if let accepted = handDepth.lastAppliedDepthTimestamp, frame.timestamp - accepted < 0.15 {
                lastDepthObservedAt = CACurrentMediaTime()
            }
            let missingFor = CACurrentMediaTime() - (lastDepthObservedAt ?? depthSessionStartedAt)
            if normal, missingFor > (lastDepthObservedAt == nil ? 2 : 0.75) {
                setOcclusionMode(.nativeHands)
                handEdgeNotice = "Object depth is paused. Native hands is active."
            }
        }
        defer { recordDiagnostic() }
        lastFrame = frame.timestamp
        let present = worldAnchor.map { anchor in frame.anchors.contains { $0.identifier == anchor.identifier } } ?? true
        let stable = gate.observe(timestamp: frame.timestamp, normal: normal, anchorPresent: present)
        setReady(stable)
        if placed {
            placementAnchor?.isEnabled = stable; setCanPlace(false)
            setStatus(stable ? "Drag to move · Pinch to resize · Twist to rotate" : "Tracking is recovering. Keep the same table in view, or scan again.")
        } else {
            let found = stable && view.map { surfaceHit(at: CGPoint(x: $0.bounds.midX, y: $0.bounds.midY)) != nil } == true
            setCanPlace(found)
            setStatus(found ? "Surface found. Tap the table or choose Place here." : "Move slowly. Aim at a clear, well-lit table.")
        }
    }

    private func recordDiagnostic(force: Bool = false) {
        let now = CACurrentMediaTime()
        guard force || now - lastDiagnosticWrite >= 1 else { return }
        lastDiagnosticWrite = now
        let depth = handDepth.diagnostics
        let values: [String: Any] = [
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "mode": occlusionMode.rawValue, "supportsStableDepth": supportsStableEdges,
            "nativePersonOcclusionDisabled": view?.renderOptions.contains(.disablePersonOcclusion) ?? false,
            "groundingShadowsDisabled": view?.renderOptions.contains(.disableGroundingShadows) ?? false,
            "placed": placed, "trackingReady": trackingReady,
            "depthSource": depth.depthSource, "depthStatus": depth.status,
            "nativePersonExclusion": depth.nativePersonExclusion,
            "excludedPersonPixels": depth.excludedPersonPixels,
            "lastAppliedDepthTimestamp": depth.appliedFrameTimestamp ?? -1,
            "depthWidth": depth.depthWidth, "depthHeight": depth.depthHeight,
            "sourceDepthWidth": depth.sourceWidth, "sourceDepthHeight": depth.sourceHeight,
            "depthPixelStep": depth.pixelStep, "depthCropX": depth.cropX, "depthCropY": depth.cropY,
            "depthSamplingReason": depth.samplingReason, "depthProjectedTargetArea": depth.projectedTargetArea,
            "rejectedDepthSamples": depth.rejectedSamples,
            "rejectedDepthEdges": depth.rejectedDiscontinuities,
            "rejectedTableTriangles": depth.rejectedSupportTriangles,
            "triangles": depth.triangleCount, "meshBuildMilliseconds": depth.buildMilliseconds,
            "meshAgeMilliseconds": depth.meshAgeMilliseconds ?? -1,
            "displayedDepthFrames": depth.displayedFrames, "expiredDepthBuilds": depth.expiredBuilds,
            "expiredDisplayedMeshes": depth.expiredDisplays, "emptyForegroundBuilds": depth.emptyForegroundBuilds,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("equipment-ar-diagnostic.json"), options: .atomic)
        }
    }
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        MainActor.assumeIsolated { handleInactive() }
    }
    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        MainActor.assumeIsolated { handleActive() }
    }
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            self.error = "The AR session stopped. Return to 3D and open AR again."
            setStatus(self.error!); setReady(false); setCanPlace(false); placementAnchor?.isEnabled = false
        }
    }
}
