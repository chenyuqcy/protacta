import RealityKit
import UIKit

@MainActor
private final class TutorialStudioARView: ARView {
    var onViewportLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onViewportLayout?()
    }
}

/// Shared studio renderer for authored cloth diagrams and imported assemblies.
/// It owns no camera session, course progress, audio or real-object registration.
@MainActor
final class Tutorial3DRenderer: NSObject, UIGestureRecognizerDelegate {
    struct Framing {
        let center: SIMD3<Float>
        let radius: Float
        var initialYaw: Float = 0.40
        var initialPitch: Float = 0.90
    }

    private(set) var view: ARView?
    private(set) var isHandedToAR = false
    private let anchor = AnchorEntity(world: .zero)
    private let camera = PerspectiveCamera()
    private var framing = Framing(center: .zero, radius: 0.5)
    private var yaw: Float = 0.40
    private var pitch: Float = 0.90
    private var zoom: Float = 1
    private var dragStart = SIMD2<Float>.zero
    private var zoomStart: Float = 1
    private var lastSize = CGSize.zero
    private var content: Entity?
    private let orbitTouchCount: Int
    private var installedGestures: [UIGestureRecognizer] = []
    var onEntityTap: ((Entity?) -> Void)?

    init(orbitTouchCount: Int = 1) {
        self.orbitTouchCount = min(2, max(1, orbitTouchCount))
        super.init()
        anchor.name = "Tutorial studio"
        anchor.synchronization = nil
        camera.synchronization = nil
        camera.camera.fieldOfViewInDegrees = 43
        if #available(iOS 18.0, *) { camera.camera.fieldOfViewOrientation = .vertical }
        anchor.addChild(camera)
        let key = DirectionalLight()
        key.light.intensity = 1300
        key.look(at: .zero, from: [-0.6, 1, 0.5], relativeTo: nil)
        anchor.addChild(key)
        let fill = PointLight()
        fill.light.intensity = 180
        fill.light.attenuationRadius = 4
        fill.position = [0.6, 0.8, -0.6]
        anchor.addChild(fill)
    }

    func makeView(content: Entity, framing: Framing, sharedView: ARView? = nil) -> ARView {
        if let view { return view }
        let view = sharedView ?? TutorialStudioARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.session.pause(); view.session.delegate = nil
        view.cameraMode = .nonAR; view.automaticallyConfigureSession = false
        view.scene.anchors.removeAll()
        for gesture in view.gestureRecognizers ?? [] { view.removeGestureRecognizer(gesture) }
        view.accessibilityIdentifier = "tutorial3DViewport"
        (view as? TutorialStudioARView)?.onViewportLayout = { [weak self] in self?.updateLayout() }
        view.environment.background = .color(UIColor(red: 0.91, green: 0.94, blue: 0.92, alpha: 1))
        view.environment.sceneUnderstanding.options = []
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableGroundingShadows]
        view.isMultipleTouchEnabled = true
        self.view = view
        setContent(content, framing: framing)
        resetView()
        let pan = UIPanGestureRecognizer(target: self, action: #selector(orbit(_:)))
        pan.minimumNumberOfTouches = orbitTouchCount; pan.delegate = self
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        pinch.delegate = self
        let tap = UITapGestureRecognizer(target: self, action: #selector(selectEntity(_:)))
        view.addGestureRecognizer(pan); view.addGestureRecognizer(pinch); view.addGestureRecognizer(tap)
        installedGestures = [pan, pinch, tap]
        setActive(true)
        return view
    }

    func setContent(_ entity: Entity, framing: Framing) {
        if content !== entity {
            content?.removeFromParent()
            content = entity
            entity.synchronization = nil
            if !isHandedToAR { anchor.addChild(entity) }
        }
        self.framing = framing
        updateCamera()
    }

    func setActive(_ active: Bool) {
        guard let view, !isHandedToAR else { return }
        if active {
            if !view.scene.anchors.contains(where: { $0 === anchor }) { view.scene.addAnchor(anchor) }
            updateCamera()
        } else {
            view.session.pause()
            anchor.removeFromParent()
        }
    }

    func updateLayout() {
        guard !isHandedToAR, view?.bounds.size != lastSize else { return }
        updateCamera()
    }

    func resetView() {
        yaw = framing.initialYaw; pitch = framing.initialPitch; zoom = 1
        updateCamera()
    }

    func handToAR() -> ARView? {
        guard let view else { return nil }
        isHandedToAR = true
        view.session.pause(); anchor.removeFromParent(); content?.removeFromParent()
        for gesture in installedGestures { view.removeGestureRecognizer(gesture) }
        return view
    }

    func restoreStudio() {
        guard isHandedToAR, let view else { return }
        isHandedToAR = false
        view.session.pause(); view.session.delegate = nil
        view.cameraMode = .nonAR; view.automaticallyConfigureSession = false
        view.environment.background = .color(UIColor(red: 0.91, green: 0.94, blue: 0.92, alpha: 1))
        view.environment.lighting.resource = nil
        view.environment.lighting.intensityExponent = 0
        view.environment.sceneUnderstanding.options = []
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableGroundingShadows]
        if let content { anchor.addChild(content) }
        for gesture in installedGestures { view.addGestureRecognizer(gesture) }
        setActive(true)
    }

    func shutdown() {
        // A borrowed view may already have returned to its previous module.
        // Late cleanup must only touch this renderer's own scene and gestures.
        if view?.scene.anchors.contains(where: { $0 === anchor }) == true { view?.session.pause() }
        anchor.removeFromParent()
        content?.removeFromParent(); content = nil
        onEntityTap = nil
        for gesture in installedGestures { view?.removeGestureRecognizer(gesture) }
        installedGestures.removeAll()
        isHandedToAR = false
        view = nil
    }

    private func updateCamera() {
        guard !isHandedToAR, let size = view?.bounds.size, size.width > 1, size.height > 1 else { return }
        lastSize = size
        let verticalHalf = Float(43 * Double.pi / 360)
        let horizontalHalf = atan(tan(verticalHalf) * Float(size.width / size.height))
        let limitingHalf = min(verticalHalf, horizontalHalf)
        let distance = max(0.08, framing.radius / sin(limitingHalf) * 1.08) * zoom
        let offset = SIMD3<Float>(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
        camera.look(at: framing.center, from: framing.center + offset, relativeTo: nil)
    }

    @objc private func orbit(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { dragStart = [yaw, pitch] }
        let translation = gesture.translation(in: view)
        yaw = dragStart.x - Float(translation.x) * 0.006
        pitch = min(1.48, max(0.15, dragStart.y + Float(translation.y) * 0.005))
        updateCamera()
    }

    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { zoomStart = zoom }
        zoom = min(2.2, max(0.55, zoomStart / max(Float(gesture.scale), 0.01)))
        updateCamera()
    }

    @objc private func selectEntity(_ gesture: UITapGestureRecognizer) {
        guard let view else { return }
        onEntityTap?(view.entity(at: gesture.location(in: view)))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer.view === view && otherGestureRecognizer.view === view
    }
}
