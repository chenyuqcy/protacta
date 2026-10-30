import SwiftUI
import RealityKit

/// Full-screen virtual walkthrough. Progress belongs to the animation only.
struct AssemblyTutorialPlayer: View {
    let onExit: () -> Void
    @StateObject private var scene: AssemblySceneController
    @StateObject private var voice = VoiceGuide()
    @StateObject private var screenAwake = HandsOnScreenAwakeLease.system()
    @Environment(\.scenePhase) private var phase
    @State private var isPlaying = false
    @State private var speed: Double = 1
    @State private var showDetails = true

    init(tutorial: AssemblyTutorial, sharedView: ARView? = nil, onExit: @escaping () -> Void) {
        _scene = StateObject(wrappedValue: AssemblySceneController(tutorial: tutorial, sharedView: sharedView))
        self.onExit = onExit
    }

    var body: some View {
        ZStack {
            Color(red: 0.91, green: 0.94, blue: 0.92).ignoresSafeArea()
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    Button { close() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .background(.regularMaterial, in: Circle()).accessibilityLabel("Close full-screen 3D")
                        .accessibilityIdentifier("assemblyClose")
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(scene.tutorial.title).font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text("VIRTUAL WALKTHROUGH · \(scene.stepIndex + 1)/\(scene.tutorial.steps.count)")
                            .font(.system(size: 10, weight: .bold)).tracking(0.6)
                            .accessibilityIdentifier("assemblyCounter")
                    }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
                }
                // Keep the live viewport in one stable branch. Resizing the
                // controls changes its bounds, never creates another renderer.
                GeometryReader { geometry in
                    if scene.isLoaded {
                    AssemblySceneView(controller: scene, isActive: phase == .active)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .accessibilityLabel("Interactive assembly model")
                        .accessibilityValue(scene.isLoaded ? "Model loaded" : "Loading")
                        .accessibilityIdentifier("assemblyViewportRegion")
                    }
                }.frame(minHeight: 160)
                if let failure = scene.failure {
                    Text(failure).font(.callout).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("assemblyFailure")
                } else if !scene.isLoaded {
                    ProgressView("Loading 3D model…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                } else { controls }
            }.padding(16).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .foregroundStyle(TutorialColors.ink).preferredColorScheme(.light)
        .task {
            await scene.load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(40))
                guard !Task.isCancelled else { return }
                if isPlaying, phase == .active, !scene.isExploded {
                    scene.setProgress(scene.progress + 0.008 * speed)
                    if scene.progress >= 1 { isPlaying = false }
                }
            }
        }
        .onAppear { screenAwake.acquire(); configureVoice() }
        .onDisappear { isPlaying = false; voice.stop(); voice.onCommand = nil; screenAwake.release(); scene.shutdown() }
        .onChange(of: phase) { _, value in
            if value == .active { screenAwake.acquire(); voice.handleSceneActive() }
            else { screenAwake.release(); isPlaying = false; voice.handleSceneInactive() }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Menu {
                    Button("Original materials") { scene.select(nil) }
                    ForEach(scene.tutorial.parts) { part in
                        Button(part.title) { scene.select(part.id) }
                            .accessibilityIdentifier("assemblyPart_\(part.id)")
                    }
                } label: {
                    Label(scene.selectedPart?.title ?? "Select a part", systemImage: "cube.transparent")
                        .font(.system(size: 13, weight: .semibold)).frame(minHeight: 44)
                }.accessibilityIdentifier("assemblyPartMenu")
                Spacer(minLength: 0)
                Button {
                    isPlaying = false; scene.setExploded(!scene.isExploded)
                } label: { Image(systemName: scene.isExploded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44) }
                    .accessibilityLabel(scene.isExploded ? "Return to step pose" : "Explode all parts")
                    .accessibilityValue(scene.isExploded ? "Exploded" : "Step pose")
                    .accessibilityIdentifier("assemblyExplode")
                Button { scene.renderer.resetView() } label: { Image(systemName: "viewfinder").frame(width: 44, height: 44) }
                    .accessibilityLabel("Reset camera view").accessibilityIdentifier("assemblyResetView")
                Button { showDetails.toggle() } label: { Image(systemName: showDetails ? "chevron.down" : "chevron.up").frame(width: 44, height: 44) }
                    .accessibilityLabel(showDetails ? "Hide instructions" : "Show instructions")
                    .accessibilityIdentifier("assemblyToggleDetails")
            }
            if showDetails {
                Text(scene.step.title).font(.system(size: 21, weight: .semibold, design: .rounded))
                    .accessibilityIdentifier("assemblyStepTitle")
                Text(scene.step.instruction)
                    .font(.system(size: 14)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                if let part = scene.selectedPart {
                    Text(part.detail).font(.system(size: 12)).foregroundStyle(TutorialColors.muted)
                    .accessibilityIdentifier("assemblyPartDetail")
                }
                Text("Drag to rotate · Pinch to zoom · Tap a part")
                    .font(.system(size: 11)).foregroundStyle(TutorialColors.muted)
                Slider(value: Binding(get: { scene.progress }, set: { isPlaying = false; scene.setProgress($0) }), in: 0...1)
                    .disabled(scene.isExploded).accessibilityLabel("Assembly movement progress")
                    .accessibilityIdentifier("assemblySlider")
                HStack {
                    Button {
                        isPlaying = false; scene.setExploded(false); scene.setProgress(0); isPlaying = true
                    } label: { Label("Replay", systemImage: "arrow.counterclockwise") }
                        .accessibilityIdentifier("assemblyReplay")
                    Spacer()
                    Button { speed = speed == 1 ? 0.4 : 1 } label: { Text(speed == 1 ? "1×" : "0.4×") }
                        .accessibilityLabel("Playback speed").accessibilityIdentifier("assemblySpeed")
                    Button { isPlaying = false; voice.speak(scene.step.instruction) } label: { Label("Read step", systemImage: "speaker.wave.2") }
                        .accessibilityIdentifier("assemblyReadStep")
                }.font(.system(size: 12, weight: .medium)).frame(minHeight: 34)
            }
            HStack(spacing: 8) {
                Button { go(to: scene.stepIndex - 1) } label: { Image(systemName: "arrow.left").frame(width: 44, height: 44) }
                    .disabled(scene.stepIndex == 0).accessibilityLabel("Previous animation step").accessibilityIdentifier("assemblyPrevious")
                Button {
                    voice.contextDidChange(); scene.setExploded(false)
                    if scene.progress >= 1 { scene.setProgress(0) }
                    isPlaying.toggle()
                } label: { Image(systemName: isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }
                    .accessibilityLabel(isPlaying ? "Pause movement" : "Play movement").accessibilityIdentifier("assemblyPlay")
                Button {
                    if voice.isEnabled || voice.isSpeaking || voice.isRequestingPermission { voice.stop() }
                    else { isPlaying = false; Task { await voice.startListening() } }
                } label: { Image(systemName: voice.isEnabled ? "mic.fill" : "mic").frame(width: 44, height: 44) }
                    .accessibilityLabel(voice.isEnabled ? "Stop voice" : "Hands-free voice").accessibilityIdentifier("assemblyVoice")
                Spacer(minLength: 0)
                Button { next() } label: {
                    Label(scene.stepIndex == scene.tutorial.steps.count - 1 ? "Restart" : "Next step", systemImage: "arrow.right")
                        .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).frame(minHeight: 44)
                }.background(TutorialColors.ink, in: Capsule()).foregroundStyle(.white).accessibilityIdentifier("assemblyNext")
            }
            if showDetails {
                Text(voice.isEnabled || voice.isSpeaking ? voice.status : "Animation only · \(scene.tutorial.attribution)")
                    .font(.system(size: 10)).foregroundStyle(TutorialColors.muted)
            }
        }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private func go(to index: Int) { isPlaying = false; voice.contextDidChange(); scene.setStep(index) }
    private func next() { go(to: scene.stepIndex + 1 < scene.tutorial.steps.count ? scene.stepIndex + 1 : 0) }
    private func close() { isPlaying = false; voice.stop(); screenAwake.release(); onExit() }

    private func configureVoice() {
        voice.onCommand = { command in
            guard scene.isLoaded else { return }
            switch command {
            case .next: next()
            case .back: go(to: scene.stepIndex - 1)
            case .replay: scene.setExploded(false); scene.setProgress(0); isPlaying = true
            case .restart: go(to: 0)
            case .slower: speed = 0.4
            case .normalSpeed: speed = 1
            case .pause: isPlaying = false
            case .resume: scene.setExploded(false); if scene.progress >= 1 { scene.setProgress(0) }; isPlaying = true
            case .readStep, .explainSimply, .help: isPlaying = false; voice.speak(scene.step.instruction)
            case .why: isPlaying = false; voice.speak(scene.selectedPart?.detail ?? scene.step.instruction)
            case .stopListening: voice.stop()
            }
        }
    }
}
