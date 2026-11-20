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
    @State private var showsInstruction = false
    @State private var panelContentHeight: CGFloat = 280
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(courseID: EverydayTutorialID, onExit: @escaping () -> Void) {
        self.courseID = courseID; self.onExit = onExit
        let store = EverydayTutorialProgressStore.appDefault(); self.store = store
        let restored = store.load(courseID: courseID) ?? EverydayTutorialSession(courseID: courseID)
        _session = State(initialValue: restored)
        let scene = EverydaySceneController(courseID: courseID)
        scene.select(actionIndex: restored.currentAction - 1, progress: restored.completed ? 1 : 0, completed: restored.completed)
        _scene = StateObject(wrappedValue: scene)
    }
    private var course: EverydayTutorialCourse { EverydayTutorialCourse.course(courseID) }
    private var action: EverydayTutorialAction { course.actions[scene.motion.actionIndex] }
    private var previewing: Bool { scene.motion.actionIndex != session.currentAction - 1 }
    private var modalPresented: Bool { showHelp || showSteps || showSetup }
    private var shortTitle: String {
        switch courseID {
        case .towel: return "Towel"
        case .tShirt: return "T-shirt"
        case .flatBedsheet: return "Bedsheet"
        case .squareKnot: return "Square knot"
        case .fourInHand: return "Necktie"
        }
    }
    private var primaryTitle: String {
        if session.completed { return "Start over" }
        if scene.motion.isPlaying { return "Playing…" }
        if previewing { return "Return to my practice" }
        if scene.motion.progress < 0.999 { return scene.motion.progress == 0 ? "Play" : "Continue" }
        return session.currentAction == course.actions.count ? "I've done it · Finish" : "I've done it · Next"
    }

    var body: some View {
        GeometryReader { geometry in
            let sideBySide = !scene.isAR && geometry.size.width > geometry.size.height && geometry.size.width > 600
            let layout = sideBySide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            VStack(spacing: 0) {
                if !scene.isAR { header.accessibilityHidden(modalPresented) }
                // AnyLayout changes orientation without replacing the renderer.
                layout {
                    viewport(safeAreaInsets: geometry.safeAreaInsets)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityHidden(modalPresented)
                    if !scene.isAR {
                        ScrollView {
                            lessonPanel.background {
                                GeometryReader { panel in
                                    Color.clear.preference(key: EverydayPanelHeightKey.self, value: panel.size.height)
                                }
                            }
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(width: sideBySide ? min(400, geometry.size.width * 0.44) : nil,
                               height: sideBySide ? nil : min(panelContentHeight, geometry.size.height * 0.52))
                        .onPreferenceChange(EverydayPanelHeightKey.self) { if $0 > 0 { panelContentHeight = $0 } }
                        .accessibilityIdentifier("everydayActionPanel")
                        .accessibilityHidden(modalPresented)
                    }
                }
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
            Text(shortTitle).font(.headline).lineLimit(2).accessibilityLabel(course.title)
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
                    HStack { strandKey; Spacer(); focusButton; moreMenu }
                    Spacer()
                    if let message = scene.failure ?? scene.arEntryError {
                        Text(message).font(.system(size: 12)).multilineTextAlignment(.center)
                            .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityIdentifier("everydayARUnavailable")
                    }
                    if !feedback.isEmpty { feedbackBadge }
                    if !session.completed { HStack { Spacer(); voiceControl } }
                }.padding(16)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
    }

    private var focusButton: some View {
        Button { scene.focusCurrentStep() } label: {
            Image(systemName: scene.framingMode == .detail ? "arrow.up.left.and.arrow.down.right" : "viewfinder")
                .font(.system(size: 19, weight: .medium)).frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .foregroundStyle(scene.framingMode == .detail ? TutorialColors.orange : TutorialColors.ink)
        }.buttonStyle(.plain)
            .disabled(scene.failure != nil)
            .accessibilityIdentifier("everydayFocusStep")
            .accessibilityLabel(scene.framingMode == .detail ? "Show full move" : "Focus current fold")
            .accessibilityHint(scene.framingMode == .detail ? "Restore the view of the whole movement." : "Pause and enlarge this fold. Playing or dragging returns to the full movement view.")
            .accessibilityValue(ProcessInfo.processInfo.arguments.contains("--ui-testing") ? scene.focusDiagnostics : "")
    }

    private var lessonPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(session.completed ? "PRACTICE COMPLETE" : "\(previewing ? "PREVIEW" : "ACTION") \(scene.motion.actionIndex + 1) OF \(course.actions.count)")
                    .font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(TutorialColors.orange)
                    .accessibilityIdentifier("everydayCounter")
                Spacer()
                if scene.motion.speed < 1 { Text("½×").font(.caption.monospacedDigit()) }
                helpButton
            }
            if session.completed {
                actionHeading
                Text("All \(course.actions.count) actions confirmed by you")
                    .font(.subheadline).foregroundStyle(TutorialColors.muted).accessibilityIdentifier("everydayCompletion")
            } else {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { showsInstruction.toggle() }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        actionHeading
                        Spacer(minLength: 0)
                        Image(systemName: showsInstruction ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold)).foregroundStyle(TutorialColors.muted)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("everydayInstructionDisclosure")
                    .accessibilityLabel(action.title)
                    .accessibilityValue(showsInstruction ? "Instructions expanded" : "Instructions collapsed")
                    .accessibilityHint("Double tap to \(showsInstruction ? "hide" : "read") the detailed instruction.")
                if showsInstruction {
                    Text(action.instruction).font(.subheadline).lineSpacing(3).foregroundStyle(TutorialColors.muted)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("everydayInstruction")
                }
                HStack(spacing: 12) {
                    playbackButton
                    movementSlider(identifier: "everydayProgressSlider")
                    Text(scene.motion.progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit()).foregroundStyle(TutorialColors.muted)
                        .frame(minWidth: 36, alignment: .trailing).accessibilityHidden(true)
                }
            }
            actionControls(includesHelp: false)
        }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 20)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
            .background(TutorialColors.paper)
            .overlay(alignment: .top) { Rectangle().fill(TutorialColors.line).frame(height: 0.5) }
    }

    private var actionHeading: some View {
        Text(session.completed ? "Made by you." : action.title)
            .font(.title2.weight(.semibold)).tracking(-0.4)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("everydayActionTitle")
    }

    private func movementSlider(identifier: String) -> some View {
        Slider(value: Binding(get: { scene.motion.progress }, set: { scene.seek($0) }), in: 0...1,
               onEditingChanged: { editing in if editing { voice.stop(); scene.pause() } })
            .tint(TutorialColors.orange).accessibilityLabel("Movement progress")
            .accessibilityIdentifier(identifier).disabled(!scene.canAnimate)
    }

    private func actionControls(includesHelp: Bool = true) -> some View {
        HStack(spacing: 12) {
            Button(action: previous) {
                Image(systemName: "arrow.left").font(.system(size: 18)).frame(width: 50, height: 50)
                    .background(TutorialColors.line.opacity(0.55), in: Circle())
            }.accessibilityLabel("Previous action").accessibilityIdentifier("everydayPrevious")
                .accessibilityHint(previewing ? "Preview the previous action without changing your saved practice."
                                   : session.completed ? "Redo the final action."
                                   : "Return to the previous action and redo your practice from there.")
                .disabled((session.currentAction == 1 && scene.motion.actionIndex == 0) || !scene.canAnimate)
            Button(action: primaryAction) {
                HStack {
                    Spacer(); Text(primaryTitle)
                    Image(systemName: session.completed ? "arrow.counterclockwise" : "arrow.right")
                    Spacer()
                }.font(.subheadline.weight(.semibold)).padding(.vertical, 12).frame(minHeight: 50)
                    .background(TutorialColors.ink, in: RoundedRectangle(cornerRadius: 15)).foregroundStyle(.white)
            }.accessibilityIdentifier(session.completed ? "everydayRestart" : "everydayConfirm")
                .disabled(!scene.canAnimate || scene.motion.isPlaying)
            if includesHelp { helpButton }
        }.buttonStyle(.plain)
    }

    private var helpButton: some View {
        Button { showHelp = true } label: {
            Image(systemName: "questionmark.circle").font(.system(size: 20))
                .frame(width: 44, height: 44).contentShape(Circle())
        }.buttonStyle(.plain).accessibilityLabel("Help with this action").accessibilityIdentifier("everydayHelp")
    }

    private var moreMenu: some View {
        Menu {
            Button("Start position", systemImage: "backward.end") { voice.stop(); scene.seek(0) }.accessibilityIdentifier("everydayShowStart")
                .disabled(session.completed || !scene.canAnimate)
            Button("Target position", systemImage: "forward.end") { voice.stop(); scene.seek(1) }.accessibilityIdentifier("everydayShowTarget")
            Button("Replay", systemImage: "arrow.counterclockwise") { scene.replay() }.accessibilityIdentifier("everydayReplay")
                .disabled(session.completed || !scene.canAnimate)
            Button(scene.motion.speed == 1 ? "Slow down" : "Normal speed", systemImage: "tortoise") { scene.setSlow(scene.motion.speed == 1) }
                .accessibilityIdentifier("everydaySpeed").accessibilityValue(scene.motion.speed == 1 ? "Normal" : "Slow")
            Button("Reset view", systemImage: "viewfinder") { scene.resetView() }.accessibilityIdentifier("everydayResetViewMenu")
            Button("All actions", systemImage: "list.number") { showSteps = true }.accessibilityIdentifier("everydaySteps")
            Button("Phone setup", systemImage: "iphone") { showSetup = true }.accessibilityIdentifier("everydayPhoneSetup")
            if scene.isAR {
                if !session.completed, scene.objectGuide != nil {
                    Button("Align with my item", systemImage: "scope") { voice.stop(); scene.beginObjectAlignment() }
                        .accessibilityIdentifier("everydayAlignObject")
                        .disabled(!scene.tabletop.trackingReady)
                }
                if scene.tabletop.isObjectAligned {
                    Button(scene.seeThroughGuide ? "Solid model" : "See-through guide", systemImage: "square.2.layers.3d") {
                        scene.toggleSeeThroughGuide()
                    }.accessibilityIdentifier("everydayGuideOpacity")
                }
                Button("Place again", systemImage: "viewfinder") { scene.pause(); voice.stop(); scene.tabletop.resetPlacement() }
                    .accessibilityIdentifier("everydayARResetPlacement")
                Button("Start over", systemImage: "arrow.counterclockwise") { restart() }
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

    @ViewBuilder
    private var strandKey: some View {
        if courseID == .squareKnot || courseID == .fourInHand {
            HStack(spacing: 12) {
                Label(courseID == .squareKnot ? "Blue A" : "Blue W", systemImage: "circle.fill")
                    .labelStyle(StrandKeyStyle(color: Color(red: 0.20, green: 0.46, blue: 0.69)))
                Label(courseID == .squareKnot ? "Orange B" : "Orange N", systemImage: "circle.fill")
                    .labelStyle(StrandKeyStyle(color: Color(red: 0.82, green: 0.37, blue: 0.17)))
            }.font(.system(size: 11, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule()).accessibilityIdentifier("everydayStrandKey")
        }
    }

    private func arControls(safeAreaInsets: EdgeInsets) -> some View {
        ZStack {
            if scene.tabletop.isAligningObject, let guide = scene.objectGuide {
                alignmentControls(guide: guide, safeAreaInsets: safeAreaInsets)
            } else if isVoiceOnlyAR {
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
                        if scene.tabletop.placed {
                            Button { scene.pause(); voice.stop(); scene.tabletop.togglePositionLock() } label: {
                                Label(scene.tabletop.positionLocked ? "Adjust" : "Done",
                                      systemImage: scene.tabletop.positionLocked ? "arrow.up.and.down.and.arrow.left.and.right" : "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 12).frame(minHeight: 44)
                                    .background(.regularMaterial, in: Capsule())
                            }.accessibilityIdentifier("everydayARAdjust")
                                .accessibilityHint(scene.tabletop.positionLocked ? "Unlock the reference to move and resize it." : "Lock the reference in place.")
                                .disabled(!scene.tabletop.ready)
                        }
                        Spacer()
                        Button { scene.pause(); voice.stop(); isVoiceOnlyAR = true } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                                .background(.regularMaterial, in: Circle())
                        }.accessibilityLabel("Voice-only full screen").accessibilityIdentifier("everydayVoiceOnlyAR")
                            .disabled(!scene.canAnimate || session.completed)
                        moreMenu
                    }
                    if scene.tabletop.isLayoutPreview { fixtureLabel }
                    if courseID == .squareKnot || courseID == .fourInHand {
                        HStack { strandKey; Spacer() }
                    }
                    if !scene.tabletop.placed || !scene.tabletop.trackingReady || scene.tabletop.error != nil {
                        VStack(spacing: 8) {
                            Text(scene.tabletop.error ?? scene.tabletop.status).font(.system(size: 13)).multilineTextAlignment(.center)
                                .accessibilityIdentifier("everydayARStatus")
                            if !scene.tabletop.placed && scene.tabletop.error == nil {
                                Button("Place reference") { scene.tabletop.place() }.frame(minHeight: 44)
                                    .disabled(!scene.tabletop.canPlace).accessibilityIdentifier("everydayARPlace")
                            }
                            if scene.tabletop.error != nil {
                                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                            }
                        }.padding(14).frame(maxWidth: 600).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if scene.tabletop.ready && !scene.tabletop.positionLocked {
                        Text("Drag to move · Pinch to resize · Twist to rotate")
                            .font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                            .accessibilityIdentifier("everydayARAdjustHint")
                    }
                    if scene.tabletop.isObjectAligned {
                        Text("Manually aligned · Keep your item in place")
                            .font(.system(size: 11, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                            .accessibilityIdentifier("everydayAlignmentStatus")
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
                        if !session.completed { movementSlider(identifier: "everydayARProgressSlider") }
                        actionControls()
                    }.padding(14).frame(maxWidth: 720).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                }.padding(.leading, max(16, safeAreaInsets.leading + 12))
                    .padding(.trailing, max(16, safeAreaInsets.trailing + 12))
                    .padding(.top, safeAreaInsets.top + 10).padding(.bottom, max(16, safeAreaInsets.bottom + 10))
            }
        }
    }

    private func alignmentControls(guide: EverydayObjectGuide, safeAreaInsets: EdgeInsets) -> some View {
        let index = min(2, scene.tabletop.objectAlignmentPointCount)
        return ZStack {
            Image(systemName: "plus")
                .font(.system(size: 30, weight: .light)).foregroundStyle(.white)
                .padding(12).background(.black.opacity(0.35), in: Circle())
                .accessibilityHidden(true)
            VStack(spacing: 16) {
                HStack {
                    Button("Cancel") { scene.tabletop.cancelObjectAlignment() }
                        .font(.system(size: 14, weight: .medium)).padding(.horizontal, 18).frame(minHeight: 44)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityIdentifier("everydayCancelAlignment")
                    Spacer()
                    Text("Align · \(index + 1)/3").font(.system(size: 13, weight: .semibold))
                        .padding(14).background(.regularMaterial, in: Capsule())
                }
                if scene.tabletop.isLayoutPreview { fixtureLabel }
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    Text(guide.pointNames[index]).font(.system(size: 23, weight: .medium))
                    Text(index == 0 ? guide.setup : "Move the center crosshair onto the \(guide.pointNames[index].lowercased()).")
                        .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("everydayAlignmentInstructions")
                    AlignmentPointDiagram(index: index, isShirt: courseID == .tShirt)
                        .frame(height: 85).accessibilityHidden(true)
                    Text(scene.tabletop.objectAlignmentMessage ?? scene.tabletop.status)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("everydayAlignmentMessage")
                    Button {
                        scene.tabletop.captureObjectAlignmentPoint()
                    } label: {
                        Text("Set point \(index + 1)").font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(TutorialColors.ink, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }.buttonStyle(.plain).disabled(!scene.tabletop.canCaptureObjectAlignmentPoint)
                        .accessibilityIdentifier("everydayCaptureAlignment")
                    Text("This fits the starting shape. If you move your item, align it again.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: 540).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            }.padding(.horizontal, max(20, safeAreaInsets.leading + 12))
                .padding(.top, safeAreaInsets.top + 10).padding(.bottom, max(20, safeAreaInsets.bottom + 10))
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
                    Text(action.instruction).font(.body).foregroundStyle(TutorialColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if !session.completed { movementSlider(identifier: "everydayHelpProgressSlider") }
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
                    Text(scene.objectGuide != nil
                         ? "Use AR → More → Align with my item to fit the guide to three points on your flat item. It stays at those coordinates; align again if the item moves. You confirm your own folds."
                         : "The AR model is a visual reference. You confirm your own actions; the camera does not check your knots or track a tie on your body.")
                        .font(.footnote).foregroundStyle(TutorialColors.muted).accessibilityIdentifier("everydayCameraScope")
                    Text("Voice: Next step previews the next move. Read this step explains it. Use the button to confirm your own work.")
                        .font(.footnote).foregroundStyle(TutorialColors.muted)
                }.padding(24)
            }.background(TutorialColors.paper).navigationTitle("Help with this action").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showHelp = false }.accessibilityIdentifier("everydayCloseHelp") } }
        }.tint(TutorialColors.orange).foregroundStyle(TutorialColors.ink).presentationDetents([.large])
    }
    private func helpBlock(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.subheadline.weight(.semibold)); Text(text).font(.subheadline).lineSpacing(4).foregroundStyle(TutorialColors.muted) }
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
        scene.select(actionIndex: session.currentAction - 1, progress: session.completed ? 1 : 0, autoplay: !session.completed, completed: session.completed)
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
            guard !modalPresented, !scene.tabletop.isAligningObject, phase == .active,
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

private struct EverydayPanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct StrandKeyStyle: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 7)).foregroundStyle(color)
            configuration.title
        }
    }
}
