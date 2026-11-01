import SwiftUI

struct EverydayTutorialPlayer: View {
    let courseID: EverydayTutorialID
    let onExit: () -> Void
    private let store: EverydayTutorialProgressStore
    @State private var session: EverydayTutorialSession
    @StateObject private var scene: EverydaySceneController
    @StateObject private var voice = VoiceGuide()
    @StateObject private var screenAwake = HandsOnScreenAwakeLease.system()
    @Environment(\.scenePhase) private var phase
    @State private var showHelp = false
    @State private var showSteps = false
    @State private var showSetup = false
    @State private var isVoiceOnlyAR = false
    @State private var feedback = ""
    @State private var feedbackRevision = 0
    @State private var pendingReplay = false

    init(courseID: EverydayTutorialID, onExit: @escaping () -> Void) {
        self.courseID = courseID; self.onExit = onExit
        let store = EverydayTutorialProgressStore.appDefault(); self.store = store
        let restored = store.load(courseID: courseID) ?? EverydayTutorialSession(courseID: courseID)
        _session = State(initialValue: restored)
        let scene = EverydaySceneController(courseID: courseID)
        scene.select(actionIndex: restored.currentAction - 1, progress: restored.completed ? 1 : 0)
        _scene = StateObject(wrappedValue: scene)
    }
    private var course: EverydayTutorialCourse { EverydayTutorialCourse.course(courseID) }
    private var action: EverydayTutorialAction { course.actions[scene.motion.actionIndex] }
    private var previewing: Bool { scene.motion.actionIndex != session.currentAction - 1 }
    private var modalPresented: Bool { showHelp || showSteps || showSetup }
    private var primaryTitle: String {
        if session.completed { return "Start again" }
        if scene.motion.isPlaying { return "Playing move…" }
        if previewing { return "Return to my practice" }
        if scene.motion.progress < 0.999 { return scene.motion.progress == 0 ? "Watch move" : "Continue move" }
        return session.currentAction == course.actions.count ? "I've done it · Finish" : "I've done it · Next"
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if !scene.isAR { header.accessibilityHidden(modalPresented) }
                viewport(safeAreaInsets: geometry.safeAreaInsets).accessibilityHidden(modalPresented)
                if !scene.isAR { lessonPanel.accessibilityHidden(modalPresented) }
            }.ignoresSafeArea(.container, edges: scene.isAR ? .all : [])
        }.background(TutorialColors.paper).foregroundStyle(TutorialColors.ink)
            .statusBarHidden(isVoiceOnlyAR)
            .onAppear {
                screenAwake.acquire(); configureVoice()
                if !session.completed { scene.play() }
            }
            .onDisappear { stopAndSave(); screenAwake.release(); voice.onCommand = nil; scene.shutdown() }
            .task {
                var last = CACurrentMediaTime()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(40))
                    guard !Task.isCancelled else { return }
                    let now = CACurrentMediaTime(); let elapsed = now - last; last = now
                    scene.tick(elapsed: elapsed, allowed: phase == .active && !modalPresented)
                }
            }
            .task(id: feedbackRevision) {
                guard !feedback.isEmpty else { return }
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled { feedback = "" }
            }
            .onChange(of: phase) { _, value in
                if value == .active { screenAwake.acquire(); voice.handleSceneActive(); scene.handleActive() }
                else {
                    scene.pause(); screenAwake.release(); _ = store.save(session); voice.handleSceneInactive()
                    scene.handleInactive()
                    if value == .background { voice.stop(); isVoiceOnlyAR = false }
                }
            }
            .onChange(of: scene.tabletop.trackingReady) { _, ready in if scene.isAR && !ready { scene.pause() } }
            .onChange(of: modalPresented) { _, presented in if presented { scene.pause(); voice.stop() } }
            .sheet(isPresented: $showHelp, onDismiss: {
                voice.stop()
                if pendingReplay { pendingReplay = false; if phase == .active && !session.completed { scene.replay() } }
            }) { helpSheet }
            .sheet(isPresented: $showSteps) { stepSheet }
            .sheet(isPresented: $showSetup) { PhoneSetupView() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: close) { Image(systemName: "house").font(.system(size: 19)).frame(width: 44, height: 44) }
                .accessibilityLabel("All tutorials").accessibilityIdentifier("everydayClose")
            Text(course.title).font(.system(size: 17, weight: .medium)).lineLimit(2)
            Spacer(minLength: 4)
            Button { voice.stop(); _ = scene.enterAR() } label: {
                Label("AR", systemImage: "arkit").font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(TutorialColors.ink, in: Capsule()).foregroundStyle(.white)
            }.accessibilityLabel("View in AR").accessibilityIdentifier("everydayEnterAR")
                .disabled(scene.failure != nil)
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func viewport(safeAreaInsets: EdgeInsets) -> some View {
        ZStack {
            // This call stays at one location. AR and voice-only presentation
            // change the surrounding controls, never the renderer's ownership.
            EverydaySceneView(controller: scene, isActive: phase == .active)
                .accessibilityLabel("Animated 3D teaching model")
                .accessibilityValue("Action \(scene.motion.actionIndex + 1), movement \(Int(scene.motion.progress * 100)) percent")
                .accessibilityIdentifier("everydayViewport")
            if scene.isAR {
                arControls(safeAreaInsets: safeAreaInsets)
            } else {
                VStack {
                    HStack { Spacer(); moreMenu }
                    Spacer()
                    if let message = scene.failure ?? scene.arEntryError {
                        Text(message).font(.system(size: 12)).multilineTextAlignment(.center)
                            .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityIdentifier("everydayARUnavailable")
                    }
                    if !feedback.isEmpty { feedbackBadge }
                    HStack {
                        if !session.completed { playbackButton }
                        Spacer()
                        if !session.completed { voiceControl }
                    }
                }.padding(16)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
    }

    private var lessonPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(session.completed ? "PRACTICE COMPLETE" : "\(previewing ? "PREVIEW" : "ACTION") \(scene.motion.actionIndex + 1) OF \(course.actions.count)")
                    .font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(TutorialColors.orange)
                    .accessibilityIdentifier("everydayCounter")
                Spacer()
                if scene.motion.speed < 1 { Text("½×").font(.caption.monospacedDigit()) }
            }
            Text(session.completed ? "Made by you." : action.title)
                .font(.system(size: 25, weight: .medium)).tracking(-0.5)
                .accessibilityIdentifier("everydayActionTitle")
            if session.completed {
                Text("All \(course.actions.count) actions confirmed by you")
                    .font(.subheadline).foregroundStyle(TutorialColors.muted).accessibilityIdentifier("everydayCompletion")
            } else {
                Text(action.instruction).font(.system(size: 14)).lineSpacing(3).foregroundStyle(TutorialColors.muted)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("everydayInstruction")
                movementSlider(identifier: "everydayProgressSlider")
            }
            actionControls
        }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 20)
            .frame(maxWidth: 720).frame(maxWidth: .infinity).background(TutorialColors.paper)
    }

    private func movementSlider(identifier: String) -> some View {
        Slider(value: Binding(get: { scene.motion.progress }, set: { scene.seek($0) }), in: 0...1,
               onEditingChanged: { editing in if editing { voice.stop(); scene.pause() } })
            .tint(TutorialColors.orange).accessibilityLabel("Movement progress")
            .accessibilityIdentifier(identifier).disabled(!scene.canAnimate)
    }

    private var actionControls: some View {
        HStack(spacing: 12) {
            Button(action: previous) {
                Image(systemName: "arrow.left").font(.system(size: 18)).frame(width: 50, height: 50)
                    .background(TutorialColors.line.opacity(0.55), in: Circle())
            }.accessibilityLabel("Previous action").accessibilityIdentifier("everydayPrevious")
                .disabled((session.currentAction == 1 && scene.motion.actionIndex == 0) || !scene.canAnimate)
            Button(action: primaryAction) {
                HStack {
                    Spacer(); Text(primaryTitle)
                    Image(systemName: session.completed ? "arrow.counterclockwise" : "arrow.right")
                    Spacer()
                }.font(.system(size: 14, weight: .semibold)).frame(minHeight: 50)
                    .background(TutorialColors.ink, in: RoundedRectangle(cornerRadius: 15)).foregroundStyle(.white)
            }.accessibilityIdentifier(session.completed ? "everydayRestart" : "everydayConfirm")
                .disabled(!scene.canAnimate || scene.motion.isPlaying)
            Button { showHelp = true } label: {
                VStack(spacing: 3) {
                    Image(systemName: "questionmark").font(.system(size: 16, weight: .semibold))
                    Text("Help").font(.system(size: 10, weight: .medium))
                }.frame(width: 50, height: 50).background(TutorialColors.line.opacity(0.55), in: Circle())
            }.accessibilityLabel("Help").accessibilityIdentifier("everydayHelp")
        }.buttonStyle(.plain)
    }

    private var moreMenu: some View {
        Menu {
            Button("Start position", systemImage: "backward.end") { voice.stop(); scene.seek(0) }.accessibilityIdentifier("everydayShowStart")
            Button("Target position", systemImage: "forward.end") { voice.stop(); scene.seek(1) }.accessibilityIdentifier("everydayShowTarget")
            Button("Replay", systemImage: "arrow.counterclockwise") { scene.replay() }.accessibilityIdentifier("everydayReplay")
                .disabled(session.completed || !scene.canAnimate)
            Button(scene.motion.speed == 1 ? "Slow down" : "Normal speed", systemImage: "tortoise") { scene.setSlow(scene.motion.speed == 1) }
                .accessibilityIdentifier("everydaySpeed").accessibilityValue(scene.motion.speed == 1 ? "Normal" : "Slow")
            Button("Reset view", systemImage: "viewfinder") { scene.resetView() }.accessibilityIdentifier("everydayResetViewMenu")
            Button("All actions", systemImage: "list.number") { showSteps = true }.accessibilityIdentifier("everydaySteps")
            Button("Phone setup", systemImage: "iphone") { showSetup = true }.accessibilityIdentifier("everydayPhoneSetup")
            if scene.isAR {
                Button("Place again", systemImage: "viewfinder") { scene.pause(); voice.stop(); scene.tabletop.resetPlacement() }
                    .accessibilityIdentifier("everydayARResetPlacement")
                Button("Start again", systemImage: "arrow.counterclockwise") { restart() }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44).background(.regularMaterial, in: Circle())
        }.accessibilityLabel("More options").accessibilityIdentifier("everydayMore")
    }

    private var playbackButton: some View {
        Button {
            voice.contextDidChange()
            if scene.motion.isPlaying { scene.pause() } else { scene.play() }
        } label: {
            Image(systemName: scene.motion.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .medium)).frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
        }.accessibilityLabel(scene.motion.isPlaying ? "Pause move" : "Play move")
            .accessibilityIdentifier("everydayPlay").disabled(!scene.canAnimate)
    }

    private var voiceControl: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if voice.isEnabled || voice.isSpeaking || voice.isRequestingPermission || voice.recoveryMessage != nil {
                Text(voice.recoveryMessage ?? voice.status)
                    .font(.system(size: 11)).multilineTextAlignment(.trailing).lineLimit(3)
                    .padding(10).frame(maxWidth: 300)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("everydayVoiceStatus")
            }
            Button {
                if voice.isEnabled || voice.isSpeaking || voice.isRequestingPermission { voice.stop() }
                else {
                    Task {
                        guard !modalPresented, phase == .active, scene.canAnimate, !session.completed else { return }
                        await voice.startListening()
                    }
                }
            } label: {
                Label(voice.isEnabled ? "Stop voice" : voice.isSpeaking ? "Stop reading" : "Voice",
                      systemImage: voice.isEnabled ? "mic.fill" : voice.isSpeaking ? "speaker.wave.2" : "mic")
                    .font(.system(size: 12, weight: .medium)).padding(.horizontal, 16).frame(minHeight: 44)
                    .background(.regularMaterial, in: Capsule())
            }.accessibilityIdentifier("everydayVoice").accessibilityValue(voice.status)
                .disabled(!scene.canAnimate && !voice.isEnabled && !voice.isSpeaking && !voice.isRequestingPermission)
        }
    }

    private var feedbackBadge: some View {
        Text(feedback).font(.system(size: 12)).multilineTextAlignment(.center).lineLimit(3)
            .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("everydayVoiceFeedback")
    }

    private func arControls(safeAreaInsets: EdgeInsets) -> some View {
        ZStack {
            if isVoiceOnlyAR {
                VoiceOnlyAROverlay(voice: voice,
                                   trackingMessage: scene.tabletop.ready ? nil : scene.tabletop.error ?? scene.tabletop.status,
                                   commandFeedback: feedback.isEmpty ? nil : feedback,
                                   safeAreaInsets: safeAreaInsets) {
                    voice.stop(); isVoiceOnlyAR = false
                }
                if scene.tabletop.isLayoutPreview { fixtureLabel.padding(.top, safeAreaInsets.top + 70).frame(maxHeight: .infinity, alignment: .top) }
            } else {
                VStack(spacing: 12) {
                    HStack {
                        Button { voice.stop(); scene.exitAR() } label: {
                            Label("3D", systemImage: "arrow.uturn.backward").font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14).frame(minHeight: 44).background(.regularMaterial, in: Capsule())
                        }.accessibilityIdentifier("everydayExitAR")
                        Spacer()
                        Button { scene.pause(); voice.stop(); isVoiceOnlyAR = true } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                                .background(.regularMaterial, in: Circle())
                        }.accessibilityLabel("Voice-only full screen").accessibilityIdentifier("everydayVoiceOnlyAR")
                            .disabled(!scene.canAnimate || session.completed)
                        moreMenu
                    }
                    if scene.tabletop.isLayoutPreview { fixtureLabel }
                    if !scene.tabletop.placed || !scene.tabletop.trackingReady || scene.tabletop.error != nil {
                        VStack(spacing: 8) {
                            Text(scene.tabletop.error ?? scene.tabletop.status).font(.system(size: 13)).multilineTextAlignment(.center)
                                .accessibilityIdentifier("everydayARStatus")
                            if !scene.tabletop.placed && scene.tabletop.error == nil {
                                Button("Place here") { scene.tabletop.place() }.frame(minHeight: 44)
                                    .disabled(!scene.tabletop.canPlace).accessibilityIdentifier("everydayARPlace")
                            }
                            if scene.tabletop.error != nil {
                                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                            }
                        }.padding(14).frame(maxWidth: 600).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    Spacer(minLength: 8)
                    if !feedback.isEmpty { feedbackBadge }
                    if !session.completed { HStack { playbackButton; Spacer(); voiceControl } }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(session.completed ? "Complete" : "\(previewing ? "Preview " : "")\(scene.motion.actionIndex + 1)/\(course.actions.count)")
                                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                .accessibilityIdentifier("everydayARCounter")
                            Spacer()
                            Text(action.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                        }
                        actionControls
                    }.padding(14).frame(maxWidth: 720).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                }.padding(.leading, max(16, safeAreaInsets.leading + 12))
                    .padding(.trailing, max(16, safeAreaInsets.trailing + 12))
                    .padding(.top, safeAreaInsets.top + 10).padding(.bottom, max(16, safeAreaInsets.bottom + 10))
            }
        }
    }
    private var fixtureLabel: some View {
        Text("AR LAYOUT PREVIEW · NO LIVE CAMERA").font(.system(size: 10, weight: .bold))
            .padding(8).background(.yellow, in: Capsule()).accessibilityIdentifier("everydayARFixtureLabel")
    }

    private var helpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(action.title).font(.title2.weight(.medium))
                    movementSlider(identifier: "everydayHelpProgressSlider")
                    Button("Replay the movement", systemImage: "arrow.counterclockwise") { voice.stop(); pendingReplay = true; showHelp = false }
                        .buttonStyle(.borderedProminent).tint(TutorialColors.ink).frame(minHeight: 44)
                        .accessibilityIdentifier("everydayHelpReplay").disabled(session.completed || !scene.canAnimate)
                    Button(scene.motion.speed == 1 ? "Slow down" : "Normal speed", systemImage: "tortoise") { scene.setSlow(scene.motion.speed == 1) }
                        .frame(minHeight: 44).accessibilityIdentifier("everydayHelpSpeed")
                    helpBlock("Check your result", action.manualCheckpoint)
                    helpBlock("Watch out", action.commonMistake)
                    helpBlock("Try this", action.help)
                    Button("Read this help", systemImage: "speaker.wave.2") { voice.speak(action.help) }.frame(minHeight: 44)
                    DisclosureGroup("Diagram reference") {
                        EverydayTutorialVisual(courseID: courseID.rawValue, stepIndex: scene.motion.actionIndex,
                                               progress: scene.motion.progress, showsCaption: false)
                            .frame(height: 300)
                    }.accessibilityIdentifier("everydayDiagramReference")
                    DisclosureGroup("Materials & setup") {
                        Text(course.materials.joined(separator: " · ")).font(.subheadline)
                        Text(course.setup).font(.subheadline).lineSpacing(4)
                    }
                    Text("The AR model is a visual reference. You confirm your own actions; the camera does not check your clothes or knots.")
                        .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("everydayCameraScope")
                    Text("Voice: Next step previews the next move. Read this step explains it. Use the button to confirm your own work.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }.background(TutorialColors.paper).navigationTitle("Help with this action").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showHelp = false }.accessibilityIdentifier("everydayCloseHelp") } }
        }.presentationDetents([.large])
    }
    private func helpBlock(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.subheadline.weight(.semibold)); Text(text).font(.subheadline).lineSpacing(4).foregroundStyle(.secondary) }
    }
    private var stepSheet: some View {
        NavigationStack {
            List(course.actions) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(item.id). \(item.title)", systemImage: session.confirmedActions.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    Text(item.instruction).font(.footnote).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
            }.navigationTitle("All actions").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSteps = false }.accessibilityIdentifier("everydayCloseSteps") } }
        }
    }

    private func primaryAction() {
        guard scene.canAnimate, !modalPresented, phase == .active else { return }
        voice.contextDidChange()
        if session.completed { restart(); return }
        if scene.motion.isPlaying { return }
        if previewing { scene.select(actionIndex: session.currentAction - 1, autoplay: true); return }
        if scene.motion.progress < 0.999 { scene.play(); return }
        confirm()
    }
    private func confirm() {
        guard !previewing, scene.motion.progress >= 0.999, !scene.motion.isPlaying else { return }
        _ = EverydayPracticeVoiceBoundary.confirm(&session, stop: { voice.stop() }, continueListening: { voice.contextDidChange() })
        _ = store.save(session)
        scene.select(actionIndex: session.currentAction - 1, progress: session.completed ? 1 : 0, autoplay: !session.completed)
        if session.completed { voice.stop(); isVoiceOnlyAR = false }
        feedback = ""
    }
    private func previous() {
        guard scene.canAnimate, !modalPresented else { return }
        voice.contextDidChange(); scene.pause()
        if previewing { scene.select(actionIndex: max(0, scene.motion.actionIndex - 1)); return }
        _ = session.previousAction(); _ = store.save(session)
        scene.select(actionIndex: session.currentAction - 1); feedback = ""
    }
    private func restart() {
        guard scene.canAnimate, !modalPresented else { return }
        voice.contextDidChange(); session.restart(); _ = store.save(session)
        scene.select(actionIndex: 0, autoplay: true); feedback = ""
    }
    private func stopAndSave() { scene.pause(); voice.stop(); _ = store.save(session) }
    private func close() { stopAndSave(); screenAwake.release(); onExit() }
    private func sayFeedback(_ text: String) { feedback = text; feedbackRevision &+= 1 }

    private func configureVoice() {
        voice.onCommand = { command in
            guard !modalPresented, phase == .active,
                  EverydayPracticeVoiceBoundary.permitsCommand(completed: session.completed, stop: { voice.stop() }) else { voice.stop(); return }
            switch command {
            case .next:
                guard scene.canAnimate else { sayFeedback("Wait for the table to be ready."); return }
                if scene.motion.progress < 0.999 { scene.play() }
                else if scene.motion.actionIndex + 1 < course.actions.count {
                    scene.select(actionIndex: scene.motion.actionIndex + 1, autoplay: true)
                    sayFeedback("Previewing the next move. Your practice confirmations stay unchanged.")
                } else { sayFeedback("This is the last movement. Use the controls to confirm your own work.") }
            case .back: previous()
            case .replay: if scene.canAnimate { scene.replay() }
            case .restart: restart(); sayFeedback("Practice restarted.")
            case .slower: scene.setSlow(true)
            case .normalSpeed: scene.setSlow(false)
            case .pause: scene.pause()
            case .resume: scene.play()
            case .readStep: scene.pause(); voice.speak(action.instruction)
            case .explainSimply, .help: scene.pause(); voice.speak(action.help)
            case .why: scene.pause(); voice.speak(action.manualCheckpoint)
            case .stopListening: voice.stop()
            }
        }
    }
}
