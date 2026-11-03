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
    @State private var showDetails = false
    @State private var showCredits = false
    @State private var isVoiceOnlyAR = false

    init(tutorial: AssemblyTutorial, sharedView: ARView? = nil, onExit: @escaping () -> Void) {
        _scene = StateObject(wrappedValue: AssemblySceneController(tutorial: tutorial, sharedView: sharedView))
        self.onExit = onExit
    }

    var body: some View {
        ZStack {
            TutorialColors.paper.ignoresSafeArea()
            if scene.isAR { arStage }
            else {
            GeometryReader { geometry in
                let sidebar = showDetails && geometry.size.width >= 900 && geometry.size.height >= 650
                    && geometry.size.width > geometry.size.height
                VStack(spacing: 12) {
                    ZStack {
                        VStack(spacing: 4) {
                            Text(scene.tutorial.title.components(separatedBy: " · ").first ?? scene.tutorial.title)
                                .font(.system(size: 17, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
                            Text("\(scene.stepIndex + 1)/\(scene.tutorial.steps.count)")
                                .font(.system(size: 12)).monospacedDigit().foregroundStyle(TutorialColors.muted)
                                .accessibilityIdentifier("assemblyCounter")
                        }.frame(maxWidth: 125)
                        HStack(spacing: 8) {
                        Button { close() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                            .background(.regularMaterial, in: Circle()).accessibilityLabel("Close full-screen 3D")
                            .accessibilityIdentifier("assemblyClose")
                        Spacer(minLength: 8)
                        Button {
                            isPlaying = false; voice.contextDidChange()
                            if scene.enterAR() { showDetails = false }
                        } label: {
                            Label("AR", systemImage: "arkit").font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 12).frame(minHeight: 44)
                        }.background(.regularMaterial, in: Capsule()).disabled(!scene.isLoaded)
                            .accessibilityLabel("View in AR").accessibilityIdentifier("assemblyEnterAR")
                        moreMenu
                        }
                    }
                    // AnyLayout preserves the viewport's identity across rotation
                    // and compact mode. Only its bounds and control placement change.
                    let layout = sidebar ? AnyLayout(HStackLayout(alignment: .center, spacing: 20))
                        : AnyLayout(VStackLayout(spacing: 12))
                    layout {
                        GeometryReader { geometry in
                            if scene.isLoaded {
                                modelViewport
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                            }
                        }.frame(minHeight: 160)
                        if let failure = scene.failure {
                            Text(failure).font(.callout).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                                .accessibilityIdentifier("assemblyFailure")
                        } else if !scene.isLoaded {
                            ProgressView("Loading 3D model…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        } else { controls.frame(width: sidebar ? 380 : nil).frame(maxWidth: sidebar ? 380 : 720) }
                    }
                }.padding(16)
            }
            }
        }
        .foregroundStyle(TutorialColors.ink).preferredColorScheme(.light)
        .statusBarHidden(isVoiceOnlyAR)
        .sheet(isPresented: $showCredits) { credits }
        .task {
            await scene.load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(40))
                guard !Task.isCancelled else { return }
                if isPlaying, phase == .active, !scene.isExploded, scene.canAnimate {
                    scene.setProgress(scene.progress + 0.008 * speed)
                    if scene.progress >= 1 { isPlaying = false }
                }
            }
        }
        .onAppear { screenAwake.acquire(); configureVoice() }
        .onDisappear { isPlaying = false; voice.stop(); voice.onCommand = nil; screenAwake.release(); scene.shutdown() }
        .onChange(of: phase) { _, value in
            if value == .active { screenAwake.acquire(); voice.handleSceneActive(); scene.tabletop.handleActive() }
            else {
                screenAwake.release(); isPlaying = false; voice.handleSceneInactive()
                if value == .background { isVoiceOnlyAR = false }
                if !(value == .inactive && voice.isRequestingPermission) { scene.tabletop.handleInactive() }
            }
        }
        .onChange(of: scene.tabletop.trackingReady) { _, ready in if !ready { isPlaying = false } }
        .onChange(of: scene.isAR) { _, active in if !active { isVoiceOnlyAR = false } }
    }

    private var modelViewport: some View {
        AssemblySceneView(controller: scene, isActive: phase == .active)
            .accessibilityLabel("Interactive assembly model")
            .accessibilityValue(scene.isLoaded ? "Model loaded" : "Loading")
            .accessibilityIdentifier("assemblyViewportRegion")
            .overlay(alignment: .bottom) {
                if !scene.isAR, !showDetails, let feedback = voice.feedbackMessage {
                    Text(feedback).font(.system(size: 12, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .padding(8).accessibilityIdentifier("assemblyVoiceStatus")
                        .allowsHitTesting(false)
                }
            }
    }

    private var arStage: some View {
        ZStack {
            modelViewport.ignoresSafeArea()
            if !isVoiceOnlyAR, !scene.tabletop.placed, scene.tabletop.error == nil {
                Image(systemName: "viewfinder").font(.system(size: 42, weight: .light))
                    .foregroundStyle(.white).shadow(radius: 3).allowsHitTesting(false)
            }
            if isVoiceOnlyAR {
                VoiceOnlyAROverlay(voice: voice,
                                   trackingMessage: !scene.tabletop.trackingReady || scene.tabletop.error != nil
                                       ? scene.tabletop.error ?? scene.tabletop.status : nil) {
                    voice.stop(); isVoiceOnlyAR = false
                }
                if scene.tabletop.isLayoutPreview {
                    VStack {
                        Text("AR LAYOUT PREVIEW · NO LIVE CAMERA").font(.system(size: 10, weight: .bold))
                            .padding(8).background(.yellow, in: Capsule())
                            .accessibilityIdentifier("assemblyARFixtureLabel")
                        Spacer()
                    }.padding(.top, 72).allowsHitTesting(false)
                }
            } else {
            VStack(spacing: 12) {
                HStack {
                    Button {
                        isPlaying = false; voice.contextDidChange(); scene.exitAR()
                    } label: { Label("3D", systemImage: "arrow.uturn.backward").padding(.horizontal, 14).frame(minHeight: 44) }
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityLabel("Return to 3D view").accessibilityIdentifier("assemblyExitAR")
                    if scene.tabletop.placed {
                        Button { isPlaying = false; voice.stop(); scene.tabletop.togglePositionLock() } label: {
                            Label(scene.tabletop.positionLocked ? "Adjust" : "Done",
                                  systemImage: scene.tabletop.positionLocked ? "arrow.up.and.down.and.arrow.left.and.right" : "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12).frame(minHeight: 44)
                                .background(.regularMaterial, in: Capsule())
                        }.accessibilityIdentifier("assemblyARAdjust")
                            .accessibilityHint(scene.tabletop.positionLocked ? "Unlock the reference to move and resize it." : "Lock the reference in place.")
                            .disabled(!scene.tabletop.ready)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(scene.stepIndex + 1)/\(scene.tutorial.steps.count)").font(.system(size: 15, weight: .medium)).monospacedDigit()
                            .accessibilityIdentifier("assemblyARCounter")
                    }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
                    Button {
                        isPlaying = false; showDetails = false; voice.stop(); isVoiceOnlyAR = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                            .background(.regularMaterial, in: Circle())
                    }.accessibilityLabel("Voice-only full screen")
                        .accessibilityIdentifier("assemblyEnterVoiceOnlyAR")
                        .disabled(!scene.canAnimate)
                    moreMenu
                }
                if scene.tabletop.isLayoutPreview {
                    Text("AR LAYOUT PREVIEW · NO LIVE CAMERA").font(.system(size: 11, weight: .bold))
                        .padding(10).background(.regularMaterial, in: Capsule())
                        .accessibilityIdentifier("assemblyARFixtureLabel")
                } else {
                    if !scene.tabletop.placed || !scene.tabletop.trackingReady || scene.tabletop.error != nil {
                    VStack(spacing: 6) {
                        Text(scene.tabletop.status).font(.system(size: 13, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("assemblyARStatus")
                        if !scene.tabletop.placed, scene.tabletop.error == nil {
                            Button("Place reference") { scene.tabletop.place() }
                                .frame(minHeight: 44).disabled(!scene.tabletop.canPlace)
                                .accessibilityIdentifier("assemblyARPlace")
                        }
                    }.padding(12).frame(maxWidth: 620).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                if scene.tabletop.ready && !scene.tabletop.positionLocked {
                    Text("Drag to move · Pinch to resize · Twist to rotate")
                        .font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityIdentifier("assemblyARAdjustHint")
                }
                Spacer(minLength: 8)
                if !showDetails, let feedback = voice.feedbackMessage {
                    Text(feedback).font(.system(size: 12, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true).padding(12)
                        .frame(maxWidth: 620).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("assemblyVoiceStatus")
                }
                controls.frame(maxWidth: 720)
            }.padding(16)
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("Model credits & scope") { isPlaying = false; voice.stop(); showCredits = true }
                .accessibilityIdentifier("assemblyCredits")
            Button("Replay", systemImage: "arrow.counterclockwise") {
                guard scene.canAnimate else { return }
                isPlaying = false; scene.setExploded(false); scene.setProgress(0); isPlaying = true
            }.disabled(!scene.canAnimate)
            Button(scene.isExploded ? "Return to step pose" : "Explode all parts") {
                isPlaying = false; scene.setExploded(!scene.isExploded)
            }.disabled(!scene.canAnimate)
            Button(scene.isAR ? "Reset size and rotation" : "Reset view") { scene.resetCameraView() }
                .disabled(!scene.canAnimate)
            if scene.isAR {
                Button("Scan again") { isPlaying = false; scene.tabletop.resetPlacement() }
                    .accessibilityIdentifier("assemblyARRescan")
                Section("Hand edges") {
            ForEach(EquipmentOcclusionMode.allCases) { mode in
                Button(mode.title) { isPlaying = false; scene.tabletop.setOcclusionMode(mode) }
                    .disabled(mode == .stableEdges && !scene.tabletop.supportsStableEdges)
            }
                }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 19, weight: .medium)).frame(width: 44, height: 44)
        }.background(.regularMaterial, in: Circle())
            .accessibilityLabel("More options")
            .accessibilityIdentifier(scene.isAR ? "assemblyARHandEdges" : "assemblyMore")
            .accessibilityValue(scene.isAR ? scene.tabletop.occlusionMode.title : "3D")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = scene.arEntryError {
                Text(error).font(.footnote).accessibilityIdentifier("assemblyARUnavailable")
            }
            HStack(spacing: 8) {
                Menu {
                    Button("Focus selected part") { scene.focusSelectedPart() }.disabled(scene.selectedPart == nil || scene.isAR)
                    Button("Clear selection") { scene.select(nil) }
                    ForEach(scene.tutorial.parts) { part in
                        Button(part.title) { scene.select(part.id) }
                            .accessibilityIdentifier("assemblyPart_\(part.id)")
                    }
                } label: {
                    Text(scene.step.title)
                        .font(.system(size: 16, weight: .medium)).frame(minHeight: 44)
                }.accessibilityIdentifier("assemblyPartMenu")
                Spacer(minLength: 0)
                if showDetails {
                Button {
                    isPlaying = false; scene.setExploded(!scene.isExploded)
                } label: { Image(systemName: scene.isExploded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44) }
                    .accessibilityLabel(scene.isExploded ? "Return to step pose" : "Explode all parts")
                    .accessibilityValue(scene.isExploded ? "Exploded" : "Step pose")
                    .accessibilityIdentifier("assemblyExplode")
                    .disabled(!scene.canAnimate)
                Button { scene.resetCameraView() } label: { Image(systemName: "viewfinder").frame(width: 44, height: 44) }
                    .accessibilityLabel(scene.isAR ? "Reset model size and rotation" : "Reset camera view").accessibilityValue(scene.isPartFocused ? "Focused part" : "Overview")
                    .accessibilityIdentifier("assemblyResetView")
                    .disabled(!scene.canAnimate)
                }
                Button { showDetails.toggle() } label: { Image(systemName: showDetails ? "chevron.down" : "info.circle").frame(width: 44, height: 44) }
                    .accessibilityLabel(showDetails ? "Hide instructions" : "Show instructions")
                    .accessibilityIdentifier("assemblyToggleDetails")
            }
            if showDetails {
                ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                Text(scene.step.title).font(.system(size: 21, weight: .semibold, design: .rounded))
                    .accessibilityIdentifier("assemblyStepTitle")
                Text(scene.step.instruction)
                    .font(.system(size: 14)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                if let part = scene.selectedPart {
                    Text(part.detail).font(.system(size: 12)).foregroundStyle(TutorialColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("assemblyPartDetail")
                }
                Text(scene.isAR ? "Drag to move · Pinch to resize · Twist to rotate · Tap a part" : "Drag to rotate · Pinch to zoom · Tap a part")
                    .font(.system(size: 11)).foregroundStyle(TutorialColors.muted)
                Slider(value: Binding(get: { scene.progress }, set: { isPlaying = false; scene.setProgress($0) }), in: 0...1)
                    .disabled(scene.isExploded || !scene.canAnimate).accessibilityLabel("Assembly movement progress")
                    .accessibilityIdentifier("assemblySlider")
                HStack {
                    Button {
                        isPlaying = false; scene.setExploded(false); scene.setProgress(0); isPlaying = true
                    } label: { Label("Replay", systemImage: "arrow.counterclockwise") }
                        .accessibilityIdentifier("assemblyReplay")
                        .disabled(!scene.canAnimate)
                    Spacer()
                    Button { speed = speed == 1 ? 0.4 : 1 } label: { Text(speed == 1 ? "1×" : "0.4×") }
                        .accessibilityLabel("Playback speed").accessibilityIdentifier("assemblySpeed")
                }.font(.system(size: 12, weight: .medium)).frame(minHeight: 34)
                }
                }.frame(maxHeight: 300)
            }
            HStack(spacing: 8) {
                Button { go(to: scene.stepIndex - 1) } label: { Image(systemName: "arrow.left").frame(width: 44, height: 44) }
                    .disabled(scene.stepIndex == 0 || !scene.canAnimate).accessibilityLabel("Previous animation step").accessibilityIdentifier("assemblyPrevious")
                Button {
                    voice.contextDidChange(); scene.setExploded(false)
                    if scene.progress >= 1 { scene.setProgress(0) }
                    isPlaying.toggle()
                } label: { Image(systemName: isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }
                    .accessibilityLabel(isPlaying ? "Pause movement" : "Play movement").accessibilityIdentifier("assemblyPlay")
                    .disabled(!scene.canAnimate)
                Button {
                    if voice.isEnabled || voice.isSpeaking || voice.isRequestingPermission { voice.stop() }
                    else { isPlaying = false; Task { await voice.startListening() } }
                } label: { Image(systemName: voiceIsActive ? "mic.fill" : "mic").frame(width: 44, height: 44) }
                    .accessibilityLabel(voiceIsActive ? "Stop voice" : "Hands-free voice").accessibilityIdentifier("assemblyVoice")
                Button { isPlaying = false; voice.speak(scene.step.instruction) } label: {
                    Image(systemName: "speaker.wave.2").frame(width: 44, height: 44)
                }.accessibilityLabel("Read step").accessibilityIdentifier("assemblyReadStep")
                Spacer(minLength: 0)
                Button { next() } label: {
                    Label(scene.stepIndex == scene.tutorial.steps.count - 1 ? "Restart" : "Next", systemImage: "arrow.right")
                        .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).frame(minHeight: 44)
                }.background(TutorialColors.ink, in: Capsule()).foregroundStyle(.white).accessibilityIdentifier("assemblyNext")
                    .disabled(!scene.canAnimate)
            }
            if showDetails {
                HStack {
                    if let message = voice.feedbackMessage {
                    Text(message)
                        .font(.system(size: 10)).foregroundStyle(TutorialColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("assemblyVoiceStatus")
                    }
                    Spacer(minLength: 4)
                }
            }
        }.padding(.horizontal, 18).padding(.vertical, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
            .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.65), lineWidth: 0.7) }
            .shadow(color: .black.opacity(0.055), radius: 24, y: 9)
    }

    private func go(to index: Int) {
        guard scene.canAnimate else { return }
        isPlaying = false; voice.contextDidChange(); scene.setStep(index)
    }
    private var voiceIsActive: Bool { voice.isEnabled || voice.isSpeaking || voice.isRequestingPermission }
    private func next() { go(to: scene.stepIndex + 1 < scene.tutorial.steps.count ? scene.stepIndex + 1 : 0) }
    private func close() { isPlaying = false; voice.stop(); screenAwake.release(); onExit() }

    private var credits: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(scene.tutorial.scope).font(.body).accessibilityIdentifier("assemblyScope")
                    Text(scene.tutorial.attribution).font(.subheadline.weight(.medium))
                    if let source = scene.tutorial.sourceURL { Link("Model source", destination: source) }
                    if let license = scene.tutorial.licenseURL { Link(scene.tutorial.licenseName, destination: license) }
                    else { Text(scene.tutorial.licenseName).font(.subheadline) }
                    if let name = scene.tutorial.noticeResource,
                       let url = Bundle.main.url(forResource: name, withExtension: "txt"),
                       let notice = try? String(contentsOf: url, encoding: .utf8) {
                        Text(notice).font(.caption).textSelection(.enabled)
                    }
                }.padding(22)
            }.background(TutorialColors.paper).navigationTitle("Model credits & scope")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showCredits = false }.accessibilityIdentifier("assemblyCreditsDone") } }
        }
    }

    private func configureVoice() {
        voice.onCommand = { command in
            guard scene.isLoaded else { return }
            if !scene.canAnimate, [.next, .back, .replay, .restart, .resume].contains(command) {
                isPlaying = false; voice.speak(scene.tabletop.status); return
            }
            switch command {
            case .next:
                next()
                if isVoiceOnlyAR { isPlaying = true }
            case .back:
                go(to: scene.stepIndex - 1)
                if isVoiceOnlyAR { isPlaying = true }
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
