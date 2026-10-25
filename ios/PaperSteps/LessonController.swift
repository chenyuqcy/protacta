import ARKit
import AVFoundation
import Combine
import RealityKit
import SwiftUI

/// One RealityKit view switches between studio and camera mode. Keeping two live
/// renderers behind a presentation caused a black camera in the earlier demo.
@MainActor
final class LessonController: NSObject, ObservableObject, ARSessionDelegate {
    @Published var lesson: OrigamiLesson = .crane
    @Published var started = false
    @Published var completed = false
    @Published var stepIndex = 0
    @Published var progress: Float = 1
    @Published var isPlaying = false
    @Published var slowMotion = false
    @Published var hintsVisible = true
    @Published var isAR = false
    @Published private(set) var isPaperGuide = false
    @Published private(set) var paperGuide = PaperGuideSession()
    @Published private(set) var isDartPractice = false
    @Published var dartPractice: DartPracticeSession
    @Published var practiceReferenceActive = false
    @Published var practiceCheckBusy = false
    @Published var practiceMarkerVisible = false
    @Published var practiceCheckSnapshot: DartCheckSnapshot?
    @Published var isReviewingPracticeComparison = false
    @Published var practiceCameraMessage = "Place the printed practice sheet on a plain dark mat."
    let practiceProgressStore: PracticeProgressStore
    let printedPaperTracker = PrintedPaperTracker()
    var practiceCheckRequest: DartPracticeCheckRequest?
    var practiceRequestRevision = 0
    var lastPracticeObservation: TimeInterval?
    var practiceFixtureVisible = true
    var practiceViewportSize: CGSize = .zero
    var practiceViewOrientation: UIInterfaceOrientation = .unknown
    var practiceTrackingLost = false
    @Published var validationIdentity = PracticeValidationIdentity()
    @Published var validationBusy = false
    @Published var validationStatus = "No test photo has been saved."
    @Published var lastValidationDirectory: URL?
    let validationCapture = PracticeValidationCapture()
    var validationRequest: PracticeValidationRequest?
    var validationFrameInFlight = false
    private let paperVision = PaperVisionTracker()
    private var paperGuideGeneration = 0
    private var paperViewportSize: CGSize = .zero
    private var paperViewOrientation: UIInterfaceOrientation = .unknown
    private var lastPaperExpiry: TimeInterval = 0
    private var fixtureSheetVisible = true

    var isPaperGuideFixture: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--ui-testing") &&
            ProcessInfo.processInfo.arguments.contains("--paper-guide-fixture")
        #else
        return false
        #endif
    }
    var supportsCurrentPaperGuideStep: Bool {
        if isDartPractice {
            return !dartPractice.completed && DartPracticeCourse.supportsPlanarCue(beforeState: dartPractice.currentAction - 1)
        }
        return lesson == .dart && stepIndex <= 1 && !completed
    }
    var paperRegistrationRevision: Int { paperGuideGeneration }
    var paperGuideMessage: String {
        if let cameraError { return cameraError }
        if !supportsCurrentPaperGuideStep { return "This paper guide starts with the center crease on a flat A4 sheet. Use 3D for the other folds." }
        if !Self.supportsAR && !isPaperGuideFixture { return "Live paper guidance needs a supported iPhone or iPad camera. You can still use the 3D lesson here." }
        if needsRescan { return "The camera session paused. Tap Find sheet again to restart." }
        switch paperGuide.status {
        case .searching: return "Place one whole A4 sheet flat on a clear, well-lit table. Keep your hands away while it aligns."
        case .needsDirection: return "Check the highlighted TOP edge. Turn the guide if needed, then confirm the direction."
        case .aligned: return "Bring the left long edge onto the right long edge. Match the corners, then press the fold."
        case .reacquiring: return "The sheet is no longer aligned. Lay it flat with its corners visible, then check the direction again."
        case .unsupported: return "Use the 3D guide for this shape. This first paper guide needs a flat A4 sheet."
        }
    }
    @Published var placed = false
    @Published var canPlace = false
    @Published var trackingReady = false
    @Published var needsRescan = false
    @Published var status = "One sheet. One small flight."
    @Published var cameraError: String?
    @Published private(set) var positionLocked = true
    @Published private(set) var savedProgressRevision = 0
    @Published private(set) var occlusionMode: AROcclusionMode = .automatic
    @Published private(set) var occlusionSummary = "Open Tabletop AR to check hand and object occlusion."
    @Published private(set) var occlusionDetails: [String: String] = [:]
    let occlusionCapabilities = AROcclusionCapabilities.current
    private(set) var arView: ARView?
    private let paper = PaperModel()
    private let depthOcclusion = SceneDepthOcclusion()
    private let progressStore: LearningProgressStore
    private var lastProgressSave: TimeInterval = 0
    private var hasFullLibrary = false
    var hasLessonAccess: Bool { lesson.isFree || hasFullLibrary }
    private var worldAnchor: AnchorEntity?
    private var anchorID: UUID?
    private var placementRoot: ModelEntity?
    private var supportPlaneY: Float?
    private var installedGestures: [UIGestureRecognizer] = []
    private let camera = PerspectiveCamera()
    private var yaw: Float = 0.32
    private var pitch: Float = 0.94
    private var followsAnglePreset = true
    private var zoomMultiplier: Float = 1
    private var dragStart = SIMD2<Float>.zero
    private var zoomStart: Float = 1
    private var displayLink: CADisplayLink?
    private var tickProxy: TickProxy?
    private var lastTick: CFTimeInterval = 0
    private var lastAssessment: TimeInterval = 0
    private var lastDiagnostic: TimeInterval = 0
    private var sessionGeneration = 0
    private var cameraStartRevision: Int?
    var cameraSessionRevision: Int { sessionGeneration }
    func acceptsCameraAuthorization(revision: Int) -> Bool {
        isAR && !needsRescan && revision == sessionGeneration
    }
    private var configured = false
    private var lastCollisionUpdate: CFTimeInterval = 0
    private var lastViewportSize: CGSize = .zero
    private let screenAwake = HandsOnScreenAwakeLease.system()

    init(progressStore: LearningProgressStore? = nil, practiceStore: PracticeProgressStore? = nil) {
        self.progressStore = progressStore ?? Self.makeProgressStore()
        let practiceStore = practiceStore ?? PracticeProgressStore.appDefault()
        self.practiceProgressStore = practiceStore
        self.dartPractice = practiceStore.load() ?? DartPracticeSession()
        super.init()
        lesson = self.progressStore.latestLesson ?? .dart
    }

    private static func makeProgressStore() -> LearningProgressStore {
        let process = ProcessInfo.processInfo
        // UI persistence tests use their own domain; other tests stay in memory.
        // Neither path grants lesson access or changes production purchase state.
        if process.arguments.contains("--ui-testing") {
            if let suite = process.environment["PROTACTA_PROGRESS_TEST_SUITE"],
               suite.hasPrefix("org.realitycore.protacta.prototype.uitests."),
               let defaults = UserDefaults(suiteName: suite) {
                if process.arguments.contains("--reset-learning-progress") {
                    defaults.removePersistentDomain(forName: suite)
                }
                return LearningProgressStore(defaults: defaults)
            }
            return LearningProgressStore(defaults: nil)
        }
        if process.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil {
            return LearningProgressStore(defaults: nil)
        }
        return LearningProgressStore()
    }

    func savedProgress(for lesson: OrigamiLesson) -> LearningProgressStore.Record? {
        progressStore.record(for: lesson)
    }

    var startTitle: String {
        guard hasLessonAccess else { return "Unlock this lesson" }
        guard let saved = savedProgress(for: lesson) else { return "Start folding" }
        if saved.completed { return "View finished fold" }
        return saved.stepIndex == 0 ? "Continue folding" : "Continue · Step \(saved.stepIndex)"
    }

    func continueLearning() {
        guard hasLessonAccess, !started else { return }
        guard let saved = savedProgress(for: lesson) else { begin(); return }
        started = true; completed = saved.completed; stepIndex = saved.stepIndex
        progress = saved.progress; slowMotion = saved.slowMotion; hintsVisible = saved.hintsVisible
        isPlaying = false; lastTick = 0
        // Only teaching state is restored. Camera and world coordinates are not saved.
        applyPose(); saveLearningProgress(); recordDiagnostic(force: true)
    }

    func saveLearningProgress() {
        guard started, hasLessonAccess else { return }
        if progressStore.save(lesson: lesson, stepIndex: stepIndex, progress: progress,
                              completed: completed, slowMotion: slowMotion, hintsVisible: hintsVisible) {
            savedProgressRevision &+= 1
            lastProgressSave = CACurrentMediaTime()
        }
    }

    func pauseAndSave() {
        isPlaying = false; lastTick = 0
        saveLearningProgress()
    }

    func toggleSlowMotion() { slowMotion.toggle(); saveLearningProgress() }

    var placementGesturesEnabled: Bool {
        isAR && !isPaperGuide && placed && trackingReady && !needsRescan && cameraError == nil && hasLessonAccess && !positionLocked
    }

    func togglePositionLock() {
        guard isAR, placed, trackingReady, !needsRescan, cameraError == nil, hasLessonAccess else { return }
        positionLocked.toggle()
        if !positionLocked { lastCollisionUpdate = 0; updateInteractionBounds() }
        updatePlacementGestures()
        status = placementInstruction
        recordDiagnostic(force: true)
    }

    private var placementInstruction: String {
        positionLocked ? "Position locked. Tap Move paper to adjust it." : "Drag to move · Pinch to resize · Twist to turn"
    }

    private func updatePlacementGestures() {
        for gesture in installedGestures { gesture.isEnabled = placementGesturesEnabled }
    }

    static var supportsAR: Bool { ARWorldTrackingConfiguration.isSupported }
    var currentStep: LessonStep { lesson.steps[stepIndex] }
    var lastStep: Int { lesson.lastStep }
    var canAnimate: Bool { hasLessonAccess && !isPaperGuide && (!isAR || (placed && trackingReady && !needsRescan)) }
    var nextTitle: String {
        if completed { return "Fold again" }
        if progress < 0.999 { return "Finish this fold" }
        return stepIndex == lastStep ? "Finish lesson" : "Next fold"
    }

    func makeView() -> ARView {
        if let arView, configured { return arView }
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView = view
        configured = true
        view.accessibilityIdentifier = "paperViewport"
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField]
        view.isMultipleTouchEnabled = true
        configureStudio()
        let proxy = TickProxy(owner: self)
        tickProxy = proxy
        let link = CADisplayLink(target: proxy, selector: #selector(TickProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
        resumeScreenAwake()
        return view
    }

    /// Screen ownership follows the foreground lesson independently of AR
    /// session recovery. Resuming it never starts a paused camera.
    func resumeScreenAwake() {
        guard configured, displayLink != nil else { return }
        screenAwake.acquire()
    }

    func suspendScreenAwake() { screenAwake.release() }

    private func clearScene() {
        guard let view = arView else { return }
        depthOcclusion.reset()
        view.session.pause()
        view.session.delegate = nil
        paper.root.removeFromParent()
        camera.removeFromParent()
        view.scene.anchors.removeAll()
        for gesture in view.gestureRecognizers ?? [] { view.removeGestureRecognizer(gesture) }
        installedGestures.removeAll()
        positionLocked = true
        worldAnchor = nil; placementRoot = nil; anchorID = nil; supportPlaneY = nil
    }

    private func configureStudio() {
        guard let view = arView else { return }
        clearScene()
        view.cameraMode = .nonAR
        view.environment.background = .color(UIColor(red: 0.91, green: 0.925, blue: 0.91, alpha: 1))
        view.environment.sceneUnderstanding.options = []
        view.environment.lighting.resource = nil
        view.environment.lighting.intensityExponent = 0
        let anchor = AnchorEntity(world: .zero)
        view.scene.addAnchor(anchor)
        worldAnchor = anchor
        anchor.addChild(paper.root)
        paper.root.position = .zero
        paper.root.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        paper.root.scale = .one
        camera.camera.fieldOfViewInDegrees = 43
        if #available(iOS 18.0, *) { camera.camera.fieldOfViewOrientation = .vertical }
        anchor.addChild(camera)
        let key = DirectionalLight()
        key.light.intensity = 1700
        key.light.color = .init(white: 1, alpha: 1)
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 2, depthBias: 1)
        key.look(at: .zero, from: [-0.4, 0.8, 0.4], relativeTo: nil)
        anchor.addChild(key)
        let fill = PointLight()
        fill.light.intensity = 120
        fill.light.attenuationRadius = 2
        fill.position = [0.4, 0.4, -0.3]
        anchor.addChild(fill)
        let floor = ModelEntity(mesh: .generatePlane(width: 3, depth: 3), materials: [SimpleMaterial(color: UIColor(red: 0.91, green: 0.925, blue: 0.91, alpha: 1), roughness: 1, isMetallic: false)])
        floor.position.y = 0
        anchor.addChild(floor)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(orbit(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(zoom(_:)))
        view.addGestureRecognizer(pan); view.addGestureRecognizer(pinch)
        updateCamera()
        applyPose()
    }

    func updateLibraryAccess(_ unlocked: Bool) {
        if hasFullLibrary && !unlocked { saveLearningProgress() }
        hasFullLibrary = unlocked
        if !hasLessonAccess && started {
            if isAR { leaveAR() }
            isPlaying = false; started = false; completed = false
            stepIndex = 0; progress = 1; applyPose()
        }
        recordDiagnostic(force: true)
    }

    func begin() {
        guard hasLessonAccess else { return }
        started = true; completed = false; stepIndex = 0; progress = 1
        isPlaying = false; updateCamera(); applyPose()
        saveLearningProgress()
        if isPaperGuide { restartPaperGuideTracking() }
        recordDiagnostic(force: true)
    }

    func selectLesson(_ selected: OrigamiLesson) {
        saveLearningProgress()
        if isAR { leaveAR() }
        isPlaying = false; started = false; completed = false
        lesson = selected; stepIndex = 0; progress = 1
        practiceReferenceActive = false
        hintsVisible = true; zoomMultiplier = 1; yaw = 0.32; pitch = 0.94; followsAnglePreset = true
        applyPose(); recordDiagnostic(force: true)
    }

    func goToStep(_ index: Int) {
        guard canAnimate, (0...lastStep).contains(index) else { return }
        isPlaying = false; started = true; completed = false; stepIndex = index
        progress = index == 0 ? 1 : 0
        applyPose()
        if index > 0 { play() }
        saveLearningProgress()
        recordDiagnostic(force: true)
    }

    func next() {
        guard canAnimate, !isPlaying else { return }
        if completed { begin(); return }
        if progress < 0.999 { play(); return }
        if stepIndex == lastStep {
            completed = true; progress = 1; applyPose()
            saveLearningProgress()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            recordDiagnostic(force: true)
            return
        }
        stepIndex += 1; progress = 0
        applyPose(); play(); saveLearningProgress()
    }

    func back() {
        guard canAnimate else { return }
        isPlaying = false
        if completed { completed = false }
        else { stepIndex = max(0, stepIndex - 1) }
        progress = 1; applyPose(); saveLearningProgress(); recordDiagnostic(force: true)
    }

    func replay() {
        guard canAnimate, stepIndex > 0 else { return }
        completed = false; progress = 0; applyPose(); play(); saveLearningProgress()
    }

    func togglePlayback() {
        if isPlaying { isPlaying = false }
        else if progress >= 0.999 { replay() }
        else { play() }
        saveLearningProgress()
    }

    private func play() {
        guard canAnimate, stepIndex > 0 else { return }
        lastTick = 0; isPlaying = true
    }

    func scrub(to value: Float) {
        guard canAnimate, stepIndex > 0 else { return }
        isPlaying = false; completed = false
        progress = min(1, max(0, value)); applyPose()
        saveLearningProgress()
    }

    func toggleHints() {
        hintsVisible.toggle(); paper.showHints(hintsVisible && started && !completed)
        updateCamera()
        saveLearningProgress()
    }

    fileprivate func advanceFrame(_ link: CADisplayLink) {
        if isPaperGuide, link.timestamp - lastPaperExpiry >= 0.1 {
            lastPaperExpiry = link.timestamp
            if isDartPractice {
                expireDartPracticeCapture(at: CACurrentMediaTime())
                if isPaperGuideFixture { updateDartPracticeFixture() }
            } else if isPaperGuideFixture {
                updatePaperGuideFixture()
            } else if paperGuide.quadrilateral != nil {
                paperGuide.expire(at: CACurrentMediaTime())
            }
        }
        // SwiftUI can resize the renderer after a lesson card changes height or
        // iPad multitasking changes width, even while playback is paused.
        if !isAR, let size = arView?.bounds.size, size != lastViewportSize { updateCamera() }
        guard isPlaying else { lastTick = 0; return }
        if isAR {
            guard canAnimate, let frame = arView?.session.currentFrame,
                  case .normal = frame.camera.trackingState,
                  CACurrentMediaTime() - frame.timestamp < 1,
                  frame.anchors.contains(where: { $0.identifier == anchorID }) else {
                pauseForTracking("Move slowly. The paper returns when tracking recovers.")
                recordDiagnostic(force: true)
                return
            }
        }
        let delta = lastTick == 0 ? 0 : min(link.timestamp - lastTick, 0.06)
        lastTick = link.timestamp
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let baseDuration: Double = lesson == .crane ? 4.2 : (lesson == .star && stepIndex == 7 ? 6.0 : 3.2)
        let duration: Double = testing ? 0.35 : baseDuration * (slowMotion ? 2 : 1)
        progress = min(1, progress + Float(delta / duration))
        applyPose()
        if progress >= 1 { isPlaying = false; saveLearningProgress(); recordDiagnostic(force: true) }
        else if CACurrentMediaTime() - lastProgressSave >= 1 { saveLearningProgress() }
    }

    private func applyPose() {
        paper.setPose(lesson: lesson, step: started ? stepIndex : lastStep, progress: started ? progress : 1)
        paper.showHints(hintsVisible && started && !completed)
        updateInteractionBounds()
        updateCamera()
    }

    private func updateInteractionBounds() {
        guard isAR, let placementRoot else { return }
        // A locked model needs no freshly generated hit shape on every fold.
        guard !positionLocked || placementRoot.collision == nil else { return }
        let now = CACurrentMediaTime()
        guard !isPlaying || progress >= 1 || now - lastCollisionUpdate > 0.15 else { return }
        lastCollisionUpdate = now
        let bounds = paper.bounds
        let padding = SIMD3<Float>(repeating: 0.012)
        let minimum = bounds.minimum - padding + paper.root.position
        let maximum = bounds.maximum + padding + paper.root.position
        placementRoot.collision = CollisionComponent(shapes: [
            .generateBox(size: maximum - minimum).offsetBy(translation: (minimum + maximum) / 2)
        ])
    }

    private func pauseForTracking(_ message: String) {
        trackingReady = false; canPlace = false; isPlaying = false; lastTick = 0
        worldAnchor?.isEnabled = false
        for gesture in installedGestures { gesture.isEnabled = false }
        status = message
        saveLearningProgress()
    }

    func setTopView() { followsAnglePreset = false; yaw = 0; pitch = 1.49; zoomMultiplier = 1; updateCamera() }
    func setAngleView() { followsAnglePreset = true; yaw = 0.55; pitch = 0.82; zoomMultiplier = 1; updateCamera() }
    private func updateCamera() {
        guard !isAR else { return }
        if followsAnglePreset && lesson.presentsStandingFinish {
            // Lower the studio angle as the final sheet stands up, so its head
            // and feet stay legible. A chosen top view or manual orbit is kept.
            let t: Float = started ? (stepIndex == lastStep ? progress : 0) : 1
            yaw = 0.55 - 0.35 * t
            pitch = 0.82 - 0.57 * t
        }
        let bounds = paper.framingBounds
        let target = (bounds.minimum + bounds.maximum) / 2 + paper.root.position
        let radius = simd_length(bounds.maximum - bounds.minimum) / 2
        let size = arView?.bounds.size ?? .zero
        lastViewportSize = size
        let width = max(Float(size.width), 1), height = max(Float(size.height), 1)
        let verticalHalf = Float(43 * Double.pi / 360)
        // Fit the enclosing sphere within both axes and leave room for the
        // viewport's top/bottom controls. A portrait viewport has a narrower
        // horizontal field of view than its declared vertical field of view.
        let horizontalScale = width / height * 0.90
        let verticalScale = max(Float(0.35), (height - 112) / height)
        let halfAngle = atan(tan(verticalHalf) * min(horizontalScale, verticalScale))
        let distance = max(0.075, radius / sin(halfAngle) * 1.06) * zoomMultiplier
        let position = target + SIMD3<Float>(sin(yaw) * cos(pitch) * distance, sin(pitch) * distance, cos(yaw) * cos(pitch) * distance)
        camera.look(at: target, from: position, relativeTo: nil)
    }
    @objc private func orbit(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { followsAnglePreset = false; dragStart = [yaw, pitch] }
        let translation = gesture.translation(in: arView)
        yaw = dragStart.x - Float(translation.x) * 0.006
        pitch = min(1.5, max(0.18, dragStart.y + Float(translation.y) * 0.005))
        updateCamera()
    }
    @objc private func zoom(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { zoomStart = zoomMultiplier }
        zoomMultiplier = min(2.0, max(0.55, zoomStart / Float(gesture.scale)))
        updateCamera()
    }

    func enterPaperGuide() {
        guard lesson == .dart, hasLessonAccess else { return }
        if isAR { leaveAR() }
        practiceReferenceActive = false
        isPaperGuide = true
        enterAR()
        restartPaperGuideTracking()
        if isPaperGuideFixture { updatePaperGuideFixture() }
    }

    func restartPaperGuideTracking() {
        guard isPaperGuide else { return }
        if isPaperGuideFixture { needsRescan = false }
        // Registration revisions must not cancel the camera permission Task.
        paperGuideGeneration += 1
        paperVision.reset(generation: paperGuideGeneration)
        resetDartPracticeCapture(generation: paperGuideGeneration)
        paperGuide.start(generation: paperGuideGeneration)
        paperGuide.setSupported(supportsCurrentPaperGuideStep)
        fixtureSheetVisible = true
        paperViewportSize = arView?.bounds.size ?? .zero
        paperViewOrientation = arView?.window?.windowScene?.interfaceOrientation ?? .portrait
        if Self.supportsAR, let view = arView, cameraStartRevision == nil,
           needsRescan || cameraError != nil || view.session.configuration == nil {
            sessionGeneration += 1
            needsRescan = false
            requestCameraStart(generation: sessionGeneration)
        }
    }

    /// Printed IDs establish semantic corner identity; do not reorder them to
    /// match the previous frame as blank-rectangle tracking does.
    func receivePrintedPracticePose(_ quad: PaperQuadrilateral?, timestamp: TimeInterval) {
        guard isDartPractice else { return }
        paperGuide.start(generation: paperGuideGeneration)
        paperGuide.setSupported(supportsCurrentPaperGuideStep)
        guard supportsCurrentPaperGuideStep else { return }
        paperGuide.receive(quad: quad, timestamp: timestamp, generation: paperGuideGeneration, now: CACurrentMediaTime())
        if quad != nil { paperGuide.confirmDirection() }
    }

    func enterDartPractice() {
        guard lesson == .dart, hasLessonAccess else { return }
        if isAR { leaveAR() }
        practiceReferenceActive = false
        isDartPractice = true
        isPaperGuide = true
        enterAR()
        restartPaperGuideTracking()
        if isPaperGuideFixture { updateDartPracticeFixture() }
    }

    /// The review uses one frozen image. Suspend paper analysis while its modal
    /// is visible so modal layout changes cannot replace or invalidate it.
    @discardableResult
    func beginPracticeComparisonReview() -> Bool {
        guard isDartPractice, !dartPractice.completed, !practiceCheckBusy,
              let snapshot = practiceCheckSnapshot, snapshot.action == dartPractice.currentAction,
              dartPractice.lastCheck?.timestamp == snapshot.capturedUptime,
              !isReviewingPracticeComparison else { return false }
        pauseAndSave()
        isReviewingPracticeComparison = true
        paperGuide.invalidate()
        practiceMarkerVisible = false
        lastPracticeObservation = nil
        printedPaperTracker.reset(generation: paperGuideGeneration + 1)
        resetValidationCapture(generation: paperGuideGeneration + 1)
        return true
    }

    func endPracticeComparisonReview() {
        guard isReviewingPracticeComparison else { return }
        isReviewingPracticeComparison = false
        // Background, failure and exit already invalidate this review through
        // the common reset. Dismissing it must not restart a paused camera.
        guard isDartPractice, !needsRescan, cameraError == nil else { return }
        guard UIApplication.shared.applicationState == .active else {
            practiceCheckSnapshot = nil
            dartPractice.clearLiveCheck()
            needsRescan = true
            return
        }
        restartPaperGuideTracking()
    }

    func confirmPaperGuideDirection() { paperGuide.confirmDirection() }
    func rotatePaperGuideDirection() { paperGuide.rotateDirection() }

    func startPaperGuideWithNewSheet() {
        guard isPaperGuide else { return }
        begin()
    }

    func showFirstFoldIn3D() {
        leaveAR()
        if !started { begin() }
        goToStep(1)
    }

    func confirmFirstPaperFold() {
        guard isPaperGuide, supportsCurrentPaperGuideStep else { return }
        // This is the learner's confirmation, never a camera assessment.
        leaveAR()
        started = true; completed = false; stepIndex = 1; progress = 1; isPlaying = false
        applyPose(); saveLearningProgress()
        status = "You confirmed the center crease. Continue in the 3D guide."
    }

    func setPaperGuideFixtureVisible(_ visible: Bool) {
        guard isPaperGuideFixture, isPaperGuide else { return }
        fixtureSheetVisible = visible
        updatePaperGuideFixture()
    }

    private func updatePaperGuideFixture() {
        guard isPaperGuideFixture, isPaperGuide, !needsRescan else { return }
        let now = CACurrentMediaTime()
        let quad = fixtureSheetVisible ? PaperQuadrilateral(
            topLeft: CGPoint(x: 0.22, y: 0.12), topRight: CGPoint(x: 0.78, y: 0.12),
            bottomRight: CGPoint(x: 0.78, y: 0.88), bottomLeft: CGPoint(x: 0.22, y: 0.88)) : nil
        paperGuide.receive(quad: quad, timestamp: now, generation: paperGuideGeneration, now: now)
    }

    private func assessPaperGuide(_ frame: ARFrame) {
        if isDartPractice { assessDartPractice(frame); return }
        guard supportsCurrentPaperGuideStep else { paperGuide.setSupported(false); return }
        guard let view = arView, view.bounds.width > 1, view.bounds.height > 1 else { return }
        let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
        if paperViewportSize != view.bounds.size || paperViewOrientation != orientation {
            restartPaperGuideTracking()
        }
        guard case .normal = frame.camera.trackingState else {
            paperGuide.receive(quad: nil, timestamp: frame.timestamp, generation: paperGuideGeneration, now: CACurrentMediaTime())
            return
        }
        // Vision runs on the raw sensor image with .up. ARKit's display transform
        // then handles orientation and aspect-fill exactly once for the viewport.
        let viewportSize = view.bounds.size
        let transform = frame.displayTransform(for: orientation, viewportSize: viewportSize)
        let generation = paperGuideGeneration
        let cameraGeneration = sessionGeneration
        paperVision.submit(pixelBuffer: frame.capturedImage, timestamp: frame.timestamp, generation: generation) { [weak self] result in
            let quad = result.observation.flatMap {
                PaperImageCoordinates.viewportQuadrilateral(visionCorners: $0.corners, displayTransform: transform)
            }
            Task { @MainActor [weak self] in
                guard let self, self.isPaperGuide, !self.needsRescan,
                      result.generation == self.paperGuideGeneration,
                      cameraGeneration == self.sessionGeneration,
                      self.arView?.bounds.size == viewportSize,
                      (self.arView?.window?.windowScene?.interfaceOrientation ?? .portrait) == orientation else { return }
                self.paperGuide.receive(quad: quad, timestamp: result.timestamp,
                                       generation: result.generation, now: CACurrentMediaTime())
            }
        }
    }

    func enterAR() {
        guard hasLessonAccess else { return }
        if !started { continueLearning() }
        pauseAndSave(); isAR = true
        positionLocked = true
        cameraError = nil; placed = false; canPlace = false; trackingReady = false; needsRescan = false
        sessionGeneration += 1
        let generation = sessionGeneration
        guard Self.supportsAR else { status = "AR needs a real iPhone or iPad."; return }
        clearScene()
        guard let view = arView else { return }
        view.cameraMode = .ar
        view.environment.background = .cameraFeed()
        view.environment.lighting.resource = nil
        view.environment.lighting.intensityExponent = 0
        view.renderOptions.remove(.disablePersonOcclusion)
        view.environment.sceneUnderstanding.options = isPaperGuide ? [] : AROcclusionConfiguration.sceneOptions(mode: occlusionMode, capabilities: occlusionCapabilities)
        view.session.delegate = self
        view.session.delegateQueue = .main
        if !isPaperGuide {
            view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapSurface(_:))))
        }
        status = "Allow the camera, then slowly scan your table."
        requestCameraStart(generation: generation)
    }

    private func requestCameraStart(generation: Int) {
        guard UIApplication.shared.applicationState != .background else { needsRescan = true; return }
        cameraStartRevision = generation
        Task { [weak self] in
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
            default: allowed = false
            }
            guard let self, self.cameraStartRevision == generation else { return }
            self.cameraStartRevision = nil
            guard self.acceptsCameraAuthorization(revision: generation),
                  UIApplication.shared.applicationState != .background else { return }
            if allowed {
                self.cameraError = nil
                self.runSession()
            } else {
                self.cameraError = "Camera access is off. You can allow it in Settings or continue in the 3D guide."
            }
        }
    }

    private func runSession(resetTracking: Bool = true) {
        guard let view = arView, isAR, !needsRescan,
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        let config = isPaperGuide ? ARWorldTrackingConfiguration() : AROcclusionConfiguration.make(mode: occlusionMode, capabilities: occlusionCapabilities)
        view.renderOptions.remove(.disablePersonOcclusion)
        view.environment.sceneUnderstanding.options = isPaperGuide ? [] : AROcclusionConfiguration.sceneOptions(mode: occlusionMode, capabilities: occlusionCapabilities)
        depthOcclusion.reset()
        view.environment.background = .cameraFeed()
        view.session.run(config, options: resetTracking ? [.resetTracking, .removeExistingAnchors] : [])
        // Attach only after resetting the AR session. A mode change keeps the
        // paper's existing ARAnchor, position, lesson and partial fold.
        if !isPaperGuide && occlusionMode == .automatic && occlusionCapabilities.sceneDepth { depthOcclusion.configure(in: view) }
        if resetTracking {
            lastAssessment = 0
            status = "Move slowly across a well-lit table."
        }
        recordDiagnostic(force: true)
    }

    func setOcclusionMode(_ mode: AROcclusionMode) {
        guard mode != occlusionMode else { return }
        occlusionMode = mode
        // Changing a help preference never starts a camera session, revives a
        // suspended one or grants access to a paid lesson.
        if isAR, hasLessonAccess, !needsRescan, cameraError == nil,
           let view = arView, view.session.configuration != nil {
            runSession(resetTracking: false)
        } else {
            recordDiagnostic(force: true)
        }
    }

    func refreshOcclusionStatus() { recordDiagnostic(force: true) }

    var placementPoint: CGPoint {
        guard let view = arView else { return .zero }
        return CGPoint(x: view.bounds.midX, y: view.bounds.height * 0.40)
    }
    private func surfaceHit(_ point: CGPoint) -> ARRaycastResult? {
        guard let view = arView else { return nil }
        return view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal).first
            ?? view.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal).first
    }
    @objc private func tapSurface(_ tap: UITapGestureRecognizer) {
        if !isPaperGuide, !placed { place(at: tap.location(in: arView)) }
    }
    func place(at point: CGPoint? = nil) {
        guard isAR, !isPaperGuide, !placed, !needsRescan, let view = arView,
              let frame = view.session.currentFrame, case .normal = frame.camera.trackingState else { return }
        guard let hit = surfaceHit(point ?? placementPoint) else {
            canPlace = false; status = "Aim at the table and move slowly to find a surface."; return
        }
        var transform = matrix_identity_float4x4
        transform.columns.3 = hit.worldTransform.columns.3
        let anchor = ARAnchor(name: "PaperSteps_Table", transform: transform)
        // Use the identifier target; Xcode 26's ARAnchor convenience overload
        // references a RealityKit symbol missing from the iOS 18 runtime.
        let root = AnchorEntity(.anchor(identifier: anchor.identifier))
        let movable = ModelEntity()
        movable.name = "Paper_Placement"
        let cam = frame.camera.transform.columns.3
        let pos = transform.columns.3
        movable.orientation = simd_quatf(angle: atan2(cam.x - pos.x, cam.z - pos.z), axis: [0, 1, 0])
        paper.root.removeFromParent()
        paper.root.position = [0, 0.004, 0]
        paper.root.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        paper.root.scale = .one
        movable.addChild(paper.root); root.addChild(movable)
        worldAnchor = root; placementRoot = movable; anchorID = anchor.identifier
        supportPlaneY = transform.columns.3.y
        lastCollisionUpdate = 0
        updateInteractionBounds()
        view.session.add(anchor: anchor); view.scene.addAnchor(root)
        installedGestures = view.installGestures([.translation, .rotation, .scale], for: movable).compactMap { $0 as? UIGestureRecognizer }
        for gesture in installedGestures { gesture.addTarget(self, action: #selector(manipulated(_:))) }
        placed = true; canPlace = false; trackingReady = true
        positionLocked = true; updatePlacementGestures()
        status = placementInstruction
        applyPose(); recordDiagnostic(force: true)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    @objc private func manipulated(_ gesture: UIGestureRecognizer) {
        guard placementGesturesEnabled else { return }
        if let placementRoot {
            placementRoot.scale = SIMD3<Float>(repeating: min(1.8, max(0.4, placementRoot.scale.x)))
        }
    }
    func placeAgain() {
        pauseAndSave(); positionLocked = true
        cameraError = nil
        paper.root.removeFromParent()
        worldAnchor?.removeFromParent(); worldAnchor = nil; placementRoot = nil
        supportPlaneY = nil
        let oldID = anchorID; anchorID = nil
        if let anchor = arView?.session.currentFrame?.anchors.first(where: { $0.identifier == oldID }) { arView?.session.remove(anchor: anchor) }
        for gesture in installedGestures { arView?.removeGestureRecognizer(gesture) }
        installedGestures.removeAll()
        placed = false; canPlace = false; trackingReady = false; needsRescan = false
        status = "Find a table. Your lesson stays at the same fold."
        runSession()
    }
    func leaveAR() {
        cameraStartRevision = nil
        paperGuide.invalidate()
        isPaperGuide = false
        paperVision.reset(generation: paperGuideGeneration + 1)
        stopDartPracticeCapture()
        isDartPractice = false
        saveLearningProgress()
        sessionGeneration += 1
        positionLocked = true
        isPlaying = false; isAR = false; placed = false; canPlace = false; trackingReady = false; needsRescan = false; cameraError = nil
        configureStudio(); recordDiagnostic(force: true)
    }
    func background() {
        suspendScreenAwake()
        sessionGeneration += 1
        cameraStartRevision = nil
        paperGuide.invalidate()
        paperVision.reset(generation: paperGuideGeneration + 1)
        stopDartPracticeCapture()
        pauseAndSave()
        if isAR {
            depthOcclusion.reset()
            arView?.session.pause(); needsRescan = true
            pauseForTracking("Session paused. Place the paper again to continue.")
        }
    }
    func shutdown() {
        sessionGeneration += 1
        cameraStartRevision = nil
        paperGuide.invalidate()
        paperVision.reset(generation: paperGuideGeneration + 1)
        stopDartPracticeCapture()
        pauseAndSave()
        depthOcclusion.reset()
        displayLink?.invalidate(); displayLink = nil
        arView?.session.pause()
        suspendScreenAwake()
    }
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        MainActor.assumeIsolated { assess(frame) }
    }
    private func assess(_ frame: ARFrame) {
        guard isAR, !needsRescan else { return }
        if isPaperGuide { assessPaperGuide(frame); return }
        if occlusionMode == .automatic && occlusionCapabilities.sceneDepth {
            depthOcclusion.update(frame: frame, supportPlaneY: placed ? supportPlaneY : nil)
        }
        guard frame.timestamp - lastAssessment > 0.12 else { return }
        lastAssessment = frame.timestamp
        guard case .normal = frame.camera.trackingState else {
            pauseForTracking("Move slowly. The paper returns when tracking recovers.")
            recordDiagnostic(); return
        }
        if placed {
            let sameAnchor = frame.anchors.contains { $0.identifier == anchorID }
            if !sameAnchor {
                pauseForTracking("Recovering the paper's position…")
                recordDiagnostic()
                return
            }
            trackingReady = sameAnchor
            worldAnchor?.isEnabled = sameAnchor
            status = sameAnchor ? placementInstruction : "Recovering the paper's position…"
        } else {
            canPlace = surfaceHit(placementPoint) != nil
            trackingReady = true
            status = canPlace ? "Surface found. Tap Place paper." : "Scan a well-lit table. Include its edges and surroundings."
        }
        updatePlacementGestures()
        recordDiagnostic()
    }
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        MainActor.assumeIsolated {
            guard isAR, arView?.session === session else { return }
            background()
        }
    }
    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        MainActor.assumeIsolated {
            guard let anchorID, anchors.contains(where: { $0.identifier == anchorID }) else { return }
            background(); status = "The position was lost. Place the paper again."
        }
    }
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        // Delegate callbacks already arrive on .main. Handle this before a
        // possible mode switch instead of queuing a task that could hide 3D.
        MainActor.assumeIsolated {
            guard isAR, arView?.session === session else { return }
            handleCameraFailure(message)
            depthOcclusion.reset()
            needsRescan = true
            pauseForTracking("AR paused. Return to the 3D guide or scan the table again.")
        }
    }
    func handleCameraFailure(_ message: String) {
        sessionGeneration += 1
        cameraStartRevision = nil
        paperGuide.invalidate()
        paperVision.reset(generation: paperGuideGeneration + 1)
        stopDartPracticeCapture()
        cameraError = "AR could not continue: \(message)"
        needsRescan = true
    }

    private func recordDiagnostic(force: Bool = false) {
        let now = CACurrentMediaTime()
        guard force || now - lastDiagnostic > 1 else { return }
        lastDiagnostic = now
        let frame = arView?.session.currentFrame
        let depth = depthOcclusion.diagnostics
        let running = arView?.session.configuration as? ARWorldTrackingConfiguration
        let personRequested = running?.frameSemantics.contains(.personSegmentationWithDepth) == true
        let rawRequested = running?.frameSemantics.contains(.sceneDepth) == true
        let personReceived = frame?.segmentationBuffer != nil && frame?.estimatedDepthData != nil
        let personRenderingEnabled = personRequested && arView?.renderOptions.contains(.disablePersonOcclusion) == false
        #if targetEnvironment(simulator)
        occlusionSummary = "Camera AR is unavailable in the Simulator. Test occlusion on a supported iPhone or iPad."
        #else
        if !Self.supportsAR {
            occlusionSummary = "Camera AR is unavailable on this device. You can use the 3D guide."
        } else if !isAR {
            occlusionSummary = "Open Tabletop AR to check hand and object occlusion."
        } else if needsRescan || cameraError != nil {
            occlusionSummary = "AR is paused. Return to the guide and scan the table again."
        } else if occlusionMode == .automatic && depth.isActive && depth.triangleCount > 0 {
            occlusionSummary = "The depth surface is active. Move your hand in front of the paper to check the result."
        } else if personRenderingEnabled && personReceived {
            occlusionSummary = "Apple's person-depth data is available. Move your hand in front of the paper to check the result."
        } else if personRenderingEnabled {
            occlusionSummary = "Waiting for Apple's person-depth data. Keep your hand visible in a well-lit room."
        } else if !occlusionCapabilities.personDepth && !occlusionCapabilities.sceneDepth {
            occlusionSummary = "Hand and live object occlusion are unavailable on this device."
        } else {
            occlusionSummary = "Waiting for depth. Move slowly and keep your hand away from the camera lens."
        }
        #endif
        func flag(_ value: Bool) -> String { value ? "Yes" : "No" }
        occlusionDetails = [
            "App build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            "Mode": occlusionMode.title,
            "Position locked": flag(positionLocked),
            "Last paper update (ms)": String(format: "%.1f", paper.diagnostics.lastPoseMilliseconds),
            "Paper mesh builds": String(paper.diagnostics.meshGenerationCalls),
            "Paper mesh reuses": String(paper.diagnostics.meshReuses),
            "Native hands supported": flag(occlusionCapabilities.personDepth),
            "Live object depth supported": flag(occlusionCapabilities.sceneDepth),
            "Native hand rendering enabled": flag(personRenderingEnabled),
            "Person mask received": flag(frame?.segmentationBuffer != nil),
            "Person depth received": flag(frame?.estimatedDepthData != nil),
            "Raw depth requested": flag(rawRequested),
            "Raw depth received": flag(frame?.sceneDepth != nil),
            "Object depth status": depth.status,
            "Depth anchor in scene": flag(depth.hasScene),
            "Depth anchor ready": flag(depth.isAnchored),
            "Depth surface active": flag(depth.isActive),
            "Depth mesh triangles": String(depth.triangleCount),
            "Depth map size": "\(depth.depthWidth) × \(depth.depthHeight)",
            "Last mesh work (ms)": String(format: "%.1f", depth.buildMilliseconds),
            "Displayed mesh age (ms)": depth.meshAgeMilliseconds.map { String(format: "%.1f", $0) } ?? "None",
            "Depth frames accepted": String(depth.displayedFrames),
            "Expired depth builds": String(depth.expiredBuilds),
            "Rejected depth samples": String(depth.rejectedSamples),
            "Rejected depth edges": String(depth.rejectedDiscontinuities),
            "Rejected table triangles": String(depth.rejectedSupportTriangles)
        ]
        let values: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "bundle": Bundle.main.bundleIdentifier ?? "unknown",
            "lesson": lesson.rawValue,
            "fullLibraryUnlocked": hasFullLibrary, "hasLessonAccess": hasLessonAccess,
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "isAR": isAR, "cameraModeAR": arView?.cameraMode == .ar,
            "positionLocked": positionLocked,
            "placementGesturesEnabled": placementGesturesEnabled,
            "paperPoseMilliseconds": paper.diagnostics.lastPoseMilliseconds,
            "paperMeshBuilds": paper.diagnostics.meshGenerationCalls,
            "paperMeshReuses": paper.diagnostics.meshReuses,
            "placed": placed, "trackingReady": trackingReady, "canPlace": canPlace,
            "needsRescan": needsRescan, "step": stepIndex, "progress": progress,
            "isPlaying": isPlaying, "completed": completed, "status": status,
            "cameraImageWidth": frame.map { CVPixelBufferGetWidth($0.capturedImage) } ?? 0,
            "hasPersonDepth": frame?.estimatedDepthData != nil,
            "hasSceneDepth": frame?.sceneDepth != nil,
            "hasSmoothedSceneDepth": frame?.smoothedSceneDepth != nil,
            "hasRawSceneDepth": frame?.sceneDepth != nil,
            "occlusionMode": occlusionMode.rawValue,
            "occlusionSummary": occlusionSummary,
            "occlusionDetails": occlusionDetails,
            "liveOcclusionStatus": depthOcclusion.status,
            "liveOcclusionTriangles": depthOcclusion.triangleCount,
            "liveOcclusionBuildMilliseconds": depthOcclusion.lastBuildMilliseconds,
            "liveOcclusionDepthWidth": depthOcclusion.depthSize.x,
            "error": cameraError ?? ""
        ]
        if let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]),
           let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: documents.appendingPathComponent("PaperStepsStatus.json"), options: .atomic)
        }
    }
}

private final class TickProxy: NSObject {
    weak var owner: LessonController?
    @MainActor init(owner: LessonController) { self.owner = owner }
    @objc @MainActor func tick(_ link: CADisplayLink) { owner?.advanceFrame(link) }
}

struct PaperViewport: UIViewRepresentable {
    let controller: LessonController
    func makeUIView(context: Context) -> ARView { controller.makeView() }
    func updateUIView(_ uiView: ARView, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ARView, context: Context) -> CGSize? {
        // ARView's previous size must not become a minimum height when a
        // longer instruction needs more space for its controls.
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite else { return nil }
        return CGSize(width: max(0, width), height: max(0, height))
    }
}
