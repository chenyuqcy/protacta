import SwiftUI
import StoreKit

/// Cancel queued speech work as well as refusing the navigation/narration
/// callback. Keeping this boundary independent of microphone access lets tests
/// exercise a command that was already queued when a local tool opens.
@MainActor
enum PracticeToolVoiceCommandGate {
    static func route(_ command: VoiceCommand, modalPresented: Bool,
                      practiceCompleted: Bool = false,
                      stopVoice: () -> Void,
                      perform: (VoiceCommand) -> LessonVoiceResponse) -> LessonVoiceResponse? {
        guard !modalPresented, !practiceCompleted else { stopVoice(); return nil }
        if command == .stopListening { stopVoice() }
        return perform(command)
    }
}

@main
struct ProtactaApp: App {
    init() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-testing") && args.contains("--reset-everyday-progress") {
            let store = EverydayTutorialProgressStore.appDefault()
            for id in EverydayTutorialID.allCases { store.clear(courseID: id) }
        }
        #endif
    }
    private var isLogicTestHost: Bool {
        #if DEBUG
        return NSClassFromString("XCTestCase") != nil &&
            !ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        return false
        #endif
    }
    var body: some Scene {
        WindowGroup {
            // Logic tests exercise their own controllers. Starting a live
            // renderer here adds unrelated simulator shader work before XCTest
            // connects; UI tests still launch the full application below.
            if isLogicTestHost { Color.clear }
            else {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") &&
                    !ProcessInfo.processInfo.arguments.contains("--tutorial-hub") {
                    // Existing focused origami tests retain their direct entry.
                    // Hub tests explicitly exercise the normal app destination.
                    PaperStepsView().preferredColorScheme(.light)
                } else { ProtactaHomeView().preferredColorScheme(.light) }
                #else
                ProtactaHomeView().preferredColorScheme(.light)
                #endif
            }
        }
    }
}

private enum Palette {
    static let ink = Color(red: 0.16, green: 0.22, blue: 0.20)
    static let accent = Color(red: 0.68, green: 0.28, blue: 0.18)
    static let muted = Color(red: 0.39, green: 0.46, blue: 0.42)
    static let background = Color(red: 0.96, green: 0.96, blue: 0.93)
    static let line = Color(red: 0.86, green: 0.88, blue: 0.84)
}

struct PaperStepsView: View {
    let onExit: (() -> Void)?
    init(onExit: (() -> Void)? = nil) { self.onExit = onExit }
    @StateObject private var controller = LessonController()
    @StateObject private var purchases = PurchaseStore()
    @StateObject private var voice = VoiceGuide()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showNotes = false
    @State private var showAbout = false
    @State private var showLibrary = false
    @State private var showStepList = false
    @State private var showUnlock = false
    @State private var showPrivacy = false
    @State private var showARHelp = false
    @State private var showVoiceGuide = false
    @State private var showFoldHelp = false
    @State private var practiceToolsPresented = false
    @State private var voiceFeedback = ""
    @State private var voiceFeedbackRevision = 0
    @State private var selectedPurchasePlan: PurchasePlan = .annual
    @State private var afterAbout: String?
    @State private var selectedStepToReplay: Int?
    @State private var isARFullScreen = false
    @State private var compactVoiceFeedbackVisible = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if !isARFullScreen { header }
                // Keep this renderer at one stable location. Expanding the
                // layout must not create a second ARView or restart tracking.
                viewport(safeAreaInsets: geometry.safeAreaInsets)
                if !isARFullScreen { lessonPanels }
            }
            .ignoresSafeArea(.container, edges: isARFullScreen ? .all : [])
        }
        .statusBarHidden(isARFullScreen)
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .sheet(isPresented: $showNotes) { notesSheet }
        .sheet(isPresented: $showAbout, onDismiss: {
            if afterAbout == "unlock" { showUnlock = true }
            if afterAbout == "privacy" { showPrivacy = true }
            if afterAbout == "arHelp" { showARHelp = true }
            afterAbout = nil
        }) { aboutSheet }
        .sheet(isPresented: $showLibrary) { librarySheet }
        .sheet(isPresented: $showUnlock) { unlockSheet }
        .sheet(isPresented: $showPrivacy) { privacySheet }
        .sheet(isPresented: $showARHelp) { AROcclusionHelpView(controller: controller) }
        .sheet(isPresented: $showVoiceGuide) {
            VoiceGuidePanel(voice: voice, controller: controller, feedback: voiceFeedback) { command in
                voice.contextDidChange()
                voice.onCommand?(command)
            }
        }
        .sheet(isPresented: $showFoldHelp, onDismiss: { voice.stop() }) {
            FoldHelpPanel(controller: controller, voice: voice) {
                voice.stop()
                controller.replay()
                showFoldHelp = false
            }
        }
        .sheet(isPresented: $showStepList, onDismiss: {
            if let step = selectedStepToReplay {
                selectedStepToReplay = nil
                controller.goToStep(step)
            }
        }) { stepListSheet }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive { controller.suspendScreenAwake(); controller.pauseAndSave(); voice.handleSceneInactive() }
            if phase == .background { controller.background(); voice.stop() }
            if phase == .active { controller.resumeScreenAwake(); voice.handleSceneActive(); Task { await purchases.refresh() } }
        }
        .onAppear { configureVoiceCommands() }
        .task(id: voiceFeedbackRevision) {
            compactVoiceFeedbackVisible = !voiceFeedback.isEmpty
            guard !voiceFeedback.isEmpty else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { compactVoiceFeedbackVisible = false }
        }
        .onDisappear { voice.stop(); voice.onCommand = nil; practiceToolsPresented = false; isARFullScreen = false }
        .onChange(of: controller.stepIndex) { _, _ in voice.contextDidChange() }
        .onChange(of: controller.dartPractice.currentAction) { _, _ in voice.contextDidChange() }
        .onChange(of: controller.dartPractice.completed) { _, completed in
            if completed && controller.isDartPractice { closeVoiceTools() }
        }
        .onChange(of: controller.lesson) { _, _ in voice.stop() }
        .onChange(of: controller.isAR) { _, active in
            voice.stop()
            if !active { isARFullScreen = false }
        }
        .onChange(of: controller.isPaperGuide) { _, active in if active { isARFullScreen = false } }
        .onChange(of: controller.placed) { _, placed in
            if !placed { voice.stop(); isARFullScreen = false }
        }
        .onChange(of: controller.started) { _, started in if !started { closeVoiceTools() } }
        .onChange(of: blockingSheetPresented) { _, presented in
            if presented { voice.stop(); controller.pauseAndSave() }
        }
        .task { await purchases.refresh(); controller.updateLibraryAccess(purchases.isUnlocked) }
        .onChange(of: purchases.isUnlocked) { _, unlocked in
            controller.updateLibraryAccess(unlocked)
            if unlocked { showUnlock = false }
            if !controller.hasLessonAccess { closeVoiceTools() }
        }
    }

    private var lessonPanels: some View {
        VStack(spacing: 0) {
            if controller.isDartPractice {
                DartPracticeCard(controller: controller, onOpenComparison: { voice.stop(); controller.pauseAndSave() },
                                 onConfirmAction: { DartPracticeVoiceBoundary.confirm(controller: controller, stopVoice: { voice.stop() }) },
                                 onPracticeToolsPresented: { presented in
                    practiceToolsPresented = presented
                    if presented { voice.stop(); controller.pauseAndSave() }
                }) {
                    voiceControlButton
                }
            }
            else if controller.isPaperGuide { PaperGuideCard(controller: controller) }
            else if !controller.started { introduction }
            else if controller.isAR && (!controller.placed || controller.cameraError != nil) { placementCard }
            else { lessonCard }
            if controller.lesson == .dart && !controller.isAR {
                Button { voice.stop(); controller.enterDartPractice() } label: {
                    Label(controller.practiceReferenceActive ? "Return to my practice" : "Practice the complete Dart", systemImage: "hand.draw")
                        .font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).tint(Palette.ink).foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.top, 6)
                    .accessibilityIdentifier("openDartPractice")
                Button { voice.stop(); controller.enterPaperGuide() } label: {
                    Label("Guide on my paper", systemImage: "viewfinder")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.bordered).tint(Palette.ink)
                    .padding(.horizontal, 22).padding(.bottom, 10)
                    .accessibilityIdentifier("openPaperGuide")
            }
        }
    }

    private var blockingSheetPresented: Bool {
        showNotes || showAbout || showLibrary || showStepList || showUnlock || showPrivacy || showARHelp || showFoldHelp || practiceToolsPresented
    }

    private func closeVoiceTools() {
        voice.stop()
        showVoiceGuide = false
        showFoldHelp = false
    }

    private func configureVoiceCommands() {
        let feedback = $voiceFeedback
        let feedbackRevision = $voiceFeedbackRevision
        let practiceTools = $practiceToolsPresented
        voice.onCommand = { [weak controller, weak voice] command in
            guard let controller, let voice else { return }
            guard let response = PracticeToolVoiceCommandGate.route(command, modalPresented: practiceTools.wrappedValue,
                                                                    practiceCompleted: controller.isDartPractice && controller.dartPractice.completed,
                                                                    stopVoice: { voice.stop() },
                                                                    perform: controller.performVoiceCommand) else { return }
            feedbackRevision.wrappedValue &+= 1
            switch response {
            case .message(let text): feedback.wrappedValue = text
            case .narration(let text):
                feedback.wrappedValue = text
                voice.speak(text)
            }
        }
    }

    private func startHandsFree() {
        guard controller.canUseVoiceGuide, !blockingSheetPresented else { return }
        controller.pauseAndSave()
        voiceFeedback = ""
        Task { @MainActor in
            guard controller.canUseVoiceGuide, !blockingSheetPresented else { return }
            await voice.startListening()
        }
    }

    private var voiceControlButton: some View {
        HStack(spacing: 4) {
            Button(action: toggleHandsFree) {
                Label(voice.isEnabled ? "Stop voice" : voice.isSpeaking ? "Stop reading" : "Hands-free",
                      systemImage: voice.isEnabled ? "mic.slash" : voice.isSpeaking ? "speaker.slash" : "mic")
                    .frame(minHeight: 44)
            }.accessibilityIdentifier("toggleHandsFree").accessibilityValue(voice.status)
            Button { controller.pauseAndSave(); showVoiceGuide = true } label: {
                Image(systemName: "questionmark.circle").frame(width: 36, height: 44)
            }.accessibilityLabel("Voice commands and help").accessibilityIdentifier("openVoiceGuide")
        }
    }

    private func toggleHandsFree() {
        if voice.isEnabled || voice.isSpeaking || voice.isRequestingPermission { voice.stop() }
        else { startHandsFree() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let onExit {
                Button {
                    voice.stop(); controller.shutdown(); onExit()
                } label: {
                    Image(systemName: "house").font(.system(size: 19, weight: .medium)).frame(width: 30, height: 44)
                }.accessibilityLabel("All tutorials").accessibilityIdentifier("returnTutorialHub")
            } else {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 20, weight: .medium)).foregroundStyle(Palette.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("PROTACTA").font(.system(size: 12, weight: .bold, design: .rounded)).tracking(2.4)
                Text(controller.isPaperGuide ? "On your paper" : controller.isAR ? "On your table" : controller.lesson.title)
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 4)
            Button { controller.pauseAndSave(); showLibrary = true } label: {
                Image(systemName: "square.grid.2x2").font(.system(size: 17)).frame(width: 44, height: 44)
            }.accessibilityLabel("Choose a lesson").accessibilityIdentifier("chooseLesson")
            if controller.isAR {
                Button { controller.leaveAR() } label: {
                    Label("3D guide", systemImage: "xmark").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 11)
                        .background(.white.opacity(0.7), in: Capsule())
                }.accessibilityIdentifier("closeAR")
            } else {
                Button { withLessonAccess { controller.enterAR() } } label: {
                    Label("Tabletop AR", systemImage: "arkit").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 11)
                        .background(Palette.ink, in: Capsule()).foregroundStyle(.white)
                }.accessibilityIdentifier("openAR")
            }
        }.padding(.horizontal, 22).padding(.vertical, 12).layoutPriority(2)
    }

    private func viewport(safeAreaInsets: EdgeInsets) -> some View {
        ZStack {
            PaperViewport(controller: controller)
            if controller.isDartPractice {
                DartPracticeOverlay(controller: controller)
            } else if controller.isPaperGuide {
                PaperGuideOverlay(session: controller.paperGuide, isFixture: controller.isPaperGuideFixture)
            }
            if controller.isPaperGuide && controller.isPaperGuideFixture {
                VStack {
                    Text("SIMULATED PAPER · NO LIVE CAMERA")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.yellow, in: Capsule())
                    Spacer()
                }.padding(.top, 10).allowsHitTesting(false)
            }
            if controller.isAR && !controller.isPaperGuide && LessonController.supportsAR && !controller.placed && controller.cameraError == nil {
                GeometryReader { geometry in
                    Image(systemName: "viewfinder")
                        .font(.system(size: 42, weight: .ultraLight))
                        .foregroundStyle(controller.canPlace ? Color.green : .white)
                        .shadow(color: .black.opacity(0.25), radius: 3)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.40)
                }.allowsHitTesting(false)
            }
            if controller.isAR && !controller.isPaperGuide && !LessonController.supportsAR && !controller.isTabletopLayoutFixture {
                Palette.background.opacity(0.96)
                VStack(spacing: 14) {
                    Image(systemName: "arkit").font(.system(size: 42, weight: .light))
                    Text("Your table, your workspace.").font(.system(size: 20, weight: .medium, design: .serif))
                    Text("Camera-based AR needs a supported iPhone or iPad.\nYou can explore every fold in the 3D guide here.")
                        .font(.system(size: 14)).multilineTextAlignment(.center).foregroundStyle(Palette.muted)
                    Button("Return to 3D guide") { controller.leaveAR() }
                        .buttonStyle(.borderedProminent).tint(Palette.ink).accessibilityIdentifier("returnTo3D")
                }.padding(24)
            }
            if controller.isTabletopLayoutFixture && controller.isAR {
                VStack {
                    Text("AR LAYOUT PREVIEW · NO LIVE CAMERA")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.yellow, in: Capsule())
                        .accessibilityIdentifier("arLayoutFixtureLabel")
                    Spacer()
                }.padding(.top, isARFullScreen ? safeAreaInsets.top + 60 : 68)
                    .allowsHitTesting(false)
            }
            if isARFullScreen {
                fullScreenARControls(safeAreaInsets: safeAreaInsets)
            } else {
                standardViewportControls
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var standardViewportControls: some View {
        VStack {
            HStack {
                if !controller.isAR {
                    Text(controller.started ? "DRAG TO EXPLORE" : controller.lesson.title.uppercased())
                        .font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(Palette.muted)
                    Spacer()
                    HStack(spacing: 0) {
                        Button("Top") { controller.setTopView() }.accessibilityIdentifier("topView")
                        Divider().frame(height: 12).padding(.horizontal, 10)
                        Button("Angle") { controller.setAngleView() }.accessibilityIdentifier("angleView")
                    }.font(.system(size: 11, weight: .medium)).padding(.horizontal, 13).padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                } else if controller.placed && !controller.isPaperGuide {
                    Label(controller.trackingReady ? "ANCHORED TO YOUR TABLE" : "RECOVERING TRACKING", systemImage: "circle.fill")
                        .font(.system(size: 9, weight: .semibold)).tracking(1)
                        .padding(10).background(.regularMaterial, in: Capsule())
                    Spacer()
                }
                if controller.isAR && !controller.isPaperGuide {
                    if !controller.placed { Spacer() }
                    if controller.placed {
                        Button { isARFullScreen = true } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .background(.regularMaterial, in: Circle())
                        }.accessibilityLabel("Full screen AR")
                            .accessibilityHint("Show a larger view with next fold and voice controls. Exit full screen to adjust the model position.")
                            .accessibilityIdentifier("enterARFullScreen")
                    }
                    Button { showARHelp = true } label: {
                        Label("AR help", systemImage: "hand.raised")
                            .font(.system(size: 10, weight: .medium)).padding(10)
                            .background(.regularMaterial, in: Capsule())
                    }.accessibilityIdentifier("openARHelp")
                }
            }.padding(.horizontal, 22).padding(.top, 14)
            Spacer()
            if voice.isEnabled || voice.isSpeaking {
                Label(voice.isSpeaking ? "Reading aloud" : voice.isListening ? "Listening for a command" : voice.status,
                      systemImage: voice.isSpeaking ? "speaker.wave.2.fill" : "mic.fill")
                    .font(.system(size: 11, weight: .medium)).padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .accessibilityIdentifier("activeVoiceStatus")
                if voice.isEnabled && !voice.isSpeaking {
                    Text("Next step · Previous step · Show me again")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityIdentifier("handsFreeCommandHint")
                }
                if voice.isEnabled && !voiceFeedback.isEmpty {
                    Text(voiceFeedback).font(.system(size: 11)).lineLimit(2)
                        .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 22).accessibilityIdentifier("activeVoiceFeedback")
                }
            }
            if let message = voice.recoveryMessage, controller.canUseVoiceGuide {
                VStack(spacing: 4) {
                    Text(message).font(.system(size: 11)).multilineTextAlignment(.center)
                        .accessibilityIdentifier("voiceRecoveryMessage")
                    Button("Try voice again") { startHandsFree() }
                        .font(.system(size: 12, weight: .semibold)).frame(minHeight: 44)
                        .accessibilityIdentifier("retryHandsFree")
                }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 22)
            }
            if controller.isAR && !controller.isPaperGuide && controller.placed {
                HStack {
                    Button { controller.togglePositionLock() } label: {
                        Label(controller.positionLocked ? "Move paper" : "Lock position",
                              systemImage: controller.positionLocked ? "lock.fill" : "lock.open")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 15).frame(minHeight: 44)
                            .background(.regularMaterial, in: Capsule())
                    }.accessibilityIdentifier("togglePositionLock")
                        .accessibilityValue(controller.positionLocked ? "Locked" : "Movable")
                        .disabled(!controller.trackingReady || controller.needsRescan || controller.cameraError != nil)
                    Spacer()
                }.padding(.horizontal, 22).padding(.bottom, 8)
            }
            if controller.started && (!controller.isAR || controller.placed) {
                HStack {
                    if controller.isAR {
                        Button { controller.placeAgain() } label: { Label("Place again", systemImage: "viewfinder") }
                            .accessibilityIdentifier("placeAgain")
                    } else {
                        Label("Pinch to zoom", systemImage: "hand.pinch")
                    }
                    Spacer()
                    voiceControlButton
                    Spacer()
                    Button { controller.toggleHints() } label: {
                        Label(controller.hintsVisible ? "Hints on" : "Hints off", systemImage: controller.hintsVisible ? "arrow.turn.up.right" : "eye.slash")
                    }.accessibilityIdentifier("toggleHints")
                }.font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 13).padding(.vertical, 10).background(.regularMaterial, in: Capsule())
                    .padding(.horizontal, 22).padding(.bottom, 12)
            }
        }
    }

    private func fullScreenARControls(safeAreaInsets: EdgeInsets) -> some View {
        VStack(spacing: 12) {
            HStack {
                Button { isARFullScreen = false } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                        .background(Palette.ink.opacity(0.94), in: Circle())
                }.accessibilityLabel("Exit full screen")
                    .accessibilityIdentifier("exitARFullScreen")
                Spacer()
                Text(controller.stepIndex == 0 ? "Before you begin" : "Step \(controller.stepIndex) of \(controller.lastStep)")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Palette.ink.opacity(0.94), in: Capsule())
                    .accessibilityIdentifier("compactARStep")
            }
            Spacer(minLength: 12)
            if controller.needsRescan || !controller.trackingReady || controller.cameraError != nil {
                VStack(spacing: 8) {
                    Text(controller.cameraError ?? controller.status)
                        .font(.system(size: 13, weight: .medium)).multilineTextAlignment(.center)
                        .accessibilityIdentifier("compactARTrackingStatus")
                    if controller.needsRescan {
                        Button("Scan table again") { isARFullScreen = false; controller.placeAgain() }
                            .font(.system(size: 14, weight: .semibold)).frame(minHeight: 44)
                            .accessibilityIdentifier("compactARRescan")
                    } else if controller.cameraError != nil {
                        Button("Show camera help") { isARFullScreen = false }
                            .font(.system(size: 14, weight: .semibold)).frame(minHeight: 44)
                    }
                }.padding(14).frame(maxWidth: 360)
                    .background(Palette.ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
            }
            if voice.isEnabled || voice.isSpeaking || voice.isRequestingPermission || voice.recoveryMessage != nil {
                Text(voice.recoveryMessage ?? voice.status)
                    .font(.system(size: 12, weight: .medium)).multilineTextAlignment(.center).lineLimit(3)
                    .padding(.horizontal, 14).padding(.vertical, 9).frame(maxWidth: 360)
                    .background(Palette.ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("compactARVoiceStatus")
            }
            if compactVoiceFeedbackVisible && !voiceFeedback.isEmpty {
                Text(voiceFeedback).font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.center).lineLimit(2)
                    .padding(.horizontal, 14).padding(.vertical, 9).frame(maxWidth: 360)
                    .background(Palette.ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("compactARVoiceFeedback")
            }
            HStack(spacing: 12) {
                Button(action: toggleHandsFree) {
                    Image(systemName: voice.isEnabled || voice.isRequestingPermission ? "mic.fill" : voice.isSpeaking ? "speaker.wave.2.fill" : "mic")
                        .font(.system(size: 20, weight: .medium)).frame(width: 52, height: 52)
                        .background(Palette.ink.opacity(0.94), in: Circle())
                }.accessibilityLabel(voice.isEnabled || voice.isSpeaking || voice.isRequestingPermission ? "Stop voice" : "Start voice control")
                    .accessibilityValue(voice.status).accessibilityIdentifier("compactARVoice")
                    .disabled(!controller.canUseVoiceGuide)
                Button { voice.contextDidChange(); controller.next() } label: {
                    Label(controller.isPlaying ? "Folding…" : controller.nextTitle,
                          systemImage: controller.completed ? "arrow.counterclockwise" : "arrow.right")
                        .font(.system(size: 15, weight: .semibold)).lineLimit(2)
                        .padding(.horizontal, 22).frame(minHeight: 52)
                        .background(Palette.ink.opacity(controller.isPlaying || !controller.canAnimate ? 0.6 : 0.94), in: Capsule())
                }.accessibilityIdentifier("compactARNext")
                    .disabled(controller.isPlaying || !controller.canAnimate)
            }
        }
        .buttonStyle(.plain).foregroundStyle(.white)
        .padding(.top, max(12, safeAreaInsets.top + 8))
        .padding(.bottom, max(16, safeAreaInsets.bottom + 12))
        .padding(.leading, max(16, safeAreaInsets.leading + 12))
        .padding(.trailing, max(16, safeAreaInsets.trailing + 12))
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 13) {
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(OrigamiLesson.allCases) { lesson in
                            Button { controller.selectLesson(lesson) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: lesson.symbol)
                                    Text(lesson.shortTitle).lineLimit(1)
                                    if !lesson.isFree && !purchases.isUnlocked { Image(systemName: "lock.fill").font(.system(size: 8)) }
                                }.font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 14).frame(minHeight: 44)
                                    .background(controller.lesson == lesson ? Palette.ink : Palette.line.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(controller.lesson == lesson ? .white : Palette.ink)
                            }.buttonStyle(.plain).id(lesson)
                                .accessibilityIdentifier("lesson_\(lesson.rawValue)")
                                .accessibilityAddTraits(controller.lesson == lesson ? [.isSelected] : [])
                        }
                    }
                }
                .onChange(of: controller.lesson) { _, lesson in reader.scrollTo(lesson, anchor: .center) }
                .onAppear { reader.scrollTo(controller.lesson, anchor: .center) }
            }
            HStack {
                Text(controller.lesson.level).font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(Palette.accent)
                Spacer()
                Button { showAbout = true } label: { Image(systemName: "info.circle").font(.system(size: 17)) }.accessibilityIdentifier("aboutLesson")
            }
            Text(controller.lesson.introductionTitle)
                .font(.system(size: 28, weight: .regular, design: .serif)).lineSpacing(-1)
                .fixedSize(horizontal: false, vertical: true)
            Text(controller.lesson.introduction)
                .font(.system(size: 13)).lineSpacing(3).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                Label(controller.lesson.paperLabel, systemImage: "rectangle.portrait")
                Label(controller.lesson.time, systemImage: "clock")
                Label("\(controller.lastStep) steps", systemImage: "square.stack.3d.up")
            }.font(.system(size: 11, weight: .medium)).padding(.vertical, 2)
            primaryButton(controller.startTitle, symbol: controller.hasLessonAccess ? "arrow.right" : "lock.open", id: "startLesson") {
                withLessonAccess { controller.continueLearning() }
            }
            if controller.hasLessonAccess, controller.savedProgress(for: controller.lesson) != nil {
                Button("Start over with a new sheet") { controller.begin() }
                    .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("startOverLesson")
            }
            if controller.lesson.isFree && !purchases.isUnlocked {
                Text("Free lesson · No purchase needed").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
            }
        }.padding(24).frame(maxWidth: 620).background(Palette.background).layoutPriority(1)
    }

    private var lessonCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(controller.completed ? "LESSON COMPLETE" : controller.stepIndex == 0 ? "BEFORE YOU BEGIN" : "STEP \(controller.stepIndex) OF \(controller.lastStep)")
                    .font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(Palette.accent)
                    .accessibilityIdentifier("stepCounter")
                Spacer()
                Button { showStepList = true } label: {
                    Label("Steps", systemImage: "list.bullet").font(.system(size: 11, weight: .medium))
                }.accessibilityIdentifier("stepList").disabled(!controller.canAnimate)
                Spacer().frame(width: 10)
                Button { showAbout = true } label: { Image(systemName: "info.circle").font(.system(size: 16)) }
                    .accessibilityIdentifier("aboutLesson")
            }
            Text(controller.completed ? "Made by you." : controller.currentStep.title)
                .font(.system(size: 23, weight: .regular, design: .serif)).accessibilityIdentifier("stepTitle")
            Text(controller.completed ? controller.lesson.completion : controller.currentStep.instruction)
                .font(.system(size: 13)).lineSpacing(3).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("stepInstruction")
            if !controller.completed {
                HStack(spacing: 12) {
                    Label(controller.currentStep.cue, systemImage: "arrow.turn.up.right")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { showFoldHelp = true } label: {
                        Label("I'm stuck", systemImage: "lifepreserver")
                            .font(.system(size: 11, weight: .medium)).fixedSize()
                            .frame(minHeight: 32)
                    }.accessibilityIdentifier("foldHelp")
                }
                if controller.stepIndex > 0 {
                    HStack(spacing: 12) {
                        Button { voice.contextDidChange(); controller.togglePlayback() } label: {
                            Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 12)).frame(width: 30, height: 32)
                        }.accessibilityLabel(controller.isPlaying ? "Pause fold" : "Play fold").accessibilityIdentifier("playPause")
                        Slider(value: Binding(get: { controller.progress }, set: { controller.scrub(to: $0) }), in: 0...1,
                               onEditingChanged: { editing in if editing { voice.stop() } })
                            .tint(Palette.accent).accessibilityLabel("Fold progress").accessibilityIdentifier("foldProgress")
                        Button { controller.toggleSlowMotion() } label: {
                            Text(controller.slowMotion ? "0.5×" : "1×").font(.system(size: 12, weight: .semibold, design: .monospaced)).frame(width: 34, height: 32)
                        }.accessibilityLabel("Playback speed").accessibilityIdentifier("playbackSpeed")
                    }.disabled(!controller.canAnimate)
                }
            }
            if controller.isAR && !controller.trackingReady {
                Text(controller.status).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent)
                if controller.needsRescan { Button("Scan table again") { controller.placeAgain() }.accessibilityIdentifier("rescanTable") }
            }
            primaryButton(controller.isPlaying ? "Folding…" : controller.nextTitle, symbol: controller.completed ? "arrow.counterclockwise" : "arrow.right", id: "nextStep") { voice.contextDidChange(); controller.next() }
                .disabled(controller.isPlaying || !controller.canAnimate)
            HStack {
                Button { voice.contextDidChange(); controller.back() } label: { Label("Back", systemImage: "arrow.left") }
                    .disabled(controller.stepIndex == 0 || !controller.canAnimate).accessibilityIdentifier("backStep")
                Spacer()
                Button { voice.contextDidChange(); controller.replay() } label: { Label("Replay", systemImage: "arrow.counterclockwise") }
                    .disabled(controller.stepIndex == 0 || !controller.canAnimate).accessibilityIdentifier("replayStep")
                Spacer()
                Button { showNotes = true } label: { Label("Why this fold?", systemImage: "questionmark.circle") }
                    .accessibilityIdentifier("foldNotes")
            }.font(.system(size: 11, weight: .medium)).padding(.top, 2)
        }.padding(.horizontal, 24).padding(.top, 19).padding(.bottom, 18)
            .frame(maxWidth: 620).background(Palette.background).layoutPriority(1)
    }

    private var placementCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("YOUR REAL WORKSPACE").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(Palette.accent)
            Text("Put the paper on your table.").font(.system(size: 25, weight: .regular, design: .serif))
            Text(controller.cameraError ?? controller.status).font(.system(size: 14)).lineSpacing(3).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("arStatus")
            if LessonController.supportsAR && controller.cameraError == nil {
                if controller.needsRescan {
                    primaryButton("Scan table again", symbol: "viewfinder", id: "rescanTable") { controller.placeAgain() }
                } else {
                    primaryButton("Place paper", symbol: "plus.viewfinder", id: "placePaper") { controller.place() }
                        .disabled(!controller.canPlace)
                }
            } else if controller.cameraError != nil {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }.buttonStyle(.bordered).tint(Palette.ink)
                Button("Try camera again") { controller.enterAR() }.accessibilityIdentifier("retryCamera")
            }
            Text("Place it beside your real sheet. Each fold stays in AR, including pause, replay and the next step.")
                .font(.system(size: 12)).lineSpacing(3).foregroundStyle(Palette.muted)
        }.padding(24).frame(maxWidth: 620).background(Palette.background).layoutPriority(1)
    }

    private func primaryButton(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Spacer(); Text(title); Image(systemName: symbol); Spacer() }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .padding(.vertical, 15).background(Palette.ink, in: RoundedRectangle(cornerRadius: 15))
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private func withLessonAccess(_ action: () -> Void) {
        controller.updateLibraryAccess(purchases.isUnlocked)
        if controller.hasLessonAccess { action() }
        else { showUnlock = true }
    }

    private var notesSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("A little understanding.").font(.system(size: 30, weight: .regular, design: .serif))
                    Text(controller.currentStep.title).font(.headline)
                    Text(controller.currentStep.explanation).font(.body).lineSpacing(6)
                    Label("Written fold notes", systemImage: "book.closed").font(.caption).foregroundStyle(Palette.muted)
                    Text("Watch the motion again, then try the fold on your own sheet. Move your phone around the model to see the layers.")
                        .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4)
                }.padding(25)
            }.background(Palette.background).foregroundStyle(Palette.ink)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showNotes = false }.accessibilityIdentifier("closeNotes") } }
        }.presentationDetents([.medium, .large])
    }

    private var aboutSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(controller.lesson.title).font(.system(size: 30, weight: .regular, design: .serif))
                    Text(controller.lesson.material).font(.headline)
                    Text("Prepare the paper listed above. Match each animated fold, then continue when your own paper is ready. Use Pause or Replay whenever a motion needs a closer look.")
                    Text("Red arrows show movement. Teal dashed lines show the crease. The virtual paper demonstrates the steps; it does not check your real folds.")
                    Button("Hand and object occlusion") { afterAbout = "arHelp"; showAbout = false }
                        .accessibilityIdentifier("openARHelp")
                    Text("Tutorial reference").font(.headline)
                    Link(controller.lesson.sourceName, destination: controller.lesson.sourceURL)
                    Text("Independently written instructions and an original animated model. The reference above identifies the folding procedure or the design that inspired this variation.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    Divider()
                    if purchases.isUnlocked {
                        Label(purchases.isLifetimeUnlocked ? "Lifetime library access" : "Full library access is active", systemImage: "checkmark.seal").foregroundStyle(Palette.accent)
                        Button("Manage library access") { afterAbout = "unlock"; showAbout = false }
                    } else {
                        Button("Explore the full library") { afterAbout = "unlock"; showAbout = false }
                    }
                    manageSubscriptionsLink
                    Button("Restore Purchases") { Task { await purchases.restore() } }.disabled(purchases.isBusy)
                    if let message = purchases.message { Text(message).font(.caption).foregroundStyle(Palette.muted) }
                    Link("Contact support", destination: URL(string: "mailto:adrianchenyuqiu@gmail.com?subject=Protacta%20Support")!)
                    Button("Privacy Policy") { afterAbout = "privacy"; showAbout = false }
                    Text("Protacta · RealityCore\nVersion \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"))")
                        .font(.caption).foregroundStyle(Palette.muted)
                }.lineSpacing(4).padding(25)
            }.background(Palette.background).foregroundStyle(Palette.ink)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAbout = false }.accessibilityIdentifier("closeAbout") } }
        }
    }

    private var librarySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("What will you make?").font(.system(size: 29, weight: .regular, design: .serif))
                    Text("Start something new, or pick up where you left off.").font(.subheadline).foregroundStyle(Palette.muted)
                    ForEach(OrigamiLesson.allCases) { lesson in
                        Button {
                            controller.selectLesson(lesson)
                            showLibrary = false
                        } label: {
                            HStack(spacing: 18) {
                                Image(systemName: lesson.symbol).font(.system(size: 28, weight: .light)).frame(width: 36)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(lesson.title).font(.system(size: 20, weight: .regular, design: .serif))
                                    Text("\(lesson.steps.count - 1) steps · \(lesson.time)").font(.caption).foregroundStyle(Palette.muted)
                                    Text(lesson.material).font(.caption).foregroundStyle(Palette.muted)
                                    if let saved = controller.savedProgress(for: lesson) {
                                        Label(saved.completed ? "Completed" : "Continue at step \(saved.stepIndex)",
                                              systemImage: saved.completed ? "checkmark.circle" : "bookmark")
                                            .font(.caption).foregroundStyle(Palette.accent)
                                            .accessibilityIdentifier("savedProgress_\(lesson.rawValue)")
                                    }
                                    Text(lesson.isFree ? "FREE LESSON" : purchases.isUnlocked ? "UNLOCKED" : "FULL LIBRARY")
                                        .font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(Palette.accent)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.right").font(.caption)
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain).accessibilityIdentifier("library_\(lesson.rawValue)")
                    }
                }.padding(24)
            }.accessibilityIdentifier("lessonLibraryScroll")
                .background(Palette.background).foregroundStyle(Palette.ink)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showLibrary = false }.accessibilityIdentifier("closeLibrary") } }
        }
    }

    private var unlockSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        Image(systemName: "leaf").font(.system(size: 26, weight: .light))
                        Text("PROTACTA COMPLETE").font(.system(size: 10, weight: .bold)).tracking(1.7)
                    }.foregroundStyle(Palette.accent)
                    Text("Small folds.\nMore possibilities.").font(.system(size: 32, weight: .regular, design: .serif))
                    Text("Explore the complete tutorial library, one animated fold at a time. Choose monthly or annual access, or a one-time lifetime unlock.")
                        .font(.subheadline).lineSpacing(4).foregroundStyle(Palette.muted)
                    VStack(alignment: .leading, spacing: 11) {
                        Label("Complete step-by-step 3D lessons", systemImage: "square.stack.3d.up")
                        Label("Fold on your real table with AR", systemImage: "arkit")
                        Label("Pause, replay and understand each fold", systemImage: "arrow.counterclockwise")
                    }.font(.subheadline)

                    if purchases.isLifetimeUnlocked {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Your lifetime access is unlocked", systemImage: "checkmark.seal.fill")
                                .font(.headline).accessibilityIdentifier("libraryUnlocked")
                            Text("Enjoy the complete library. No subscription purchase is needed.")
                                .font(.subheadline).foregroundStyle(Palette.muted)
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.line.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        if purchases.isUnlocked {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("\(purchases.activePlan?.displayName ?? "Subscription") access is active", systemImage: "checkmark.seal.fill")
                                    .font(.subheadline.weight(.semibold)).accessibilityIdentifier("libraryUnlocked")
                                if let date = purchases.expirationDate {
                                    Text("Access through \(date.formatted(date: .abbreviated, time: .omitted)). Check renewal details in Manage Subscriptions.")
                                        .font(.caption).foregroundStyle(Palette.muted)
                                }
                            }
                        }
                        VStack(spacing: 9) {
                            ForEach(PurchasePlan.allCases) { plan in purchasePlanRow(plan) }
                        }
                        if purchases.isUnlocked && selectedPurchasePlan == .lifetime {
                            Text("A lifetime purchase does not cancel your existing subscription. Use Manage Subscriptions to stop its renewal separately.")
                                .font(.caption).lineSpacing(3).foregroundStyle(Palette.accent)
                                .accessibilityIdentifier("lifetimeSubscriptionNotice")
                        }
                        purchaseAction
                    }
                    if let message = purchases.message {
                        Text(message).font(.footnote).foregroundStyle(Palette.muted).accessibilityIdentifier("purchaseMessage")
                    }
                    HStack {
                        Button("Restore Purchases") { Task { await purchases.restore() } }
                            .disabled(purchases.isBusy).accessibilityIdentifier("restorePurchases")
                        Spacer(minLength: 12)
                        manageSubscriptionsLink
                    }.font(.caption)
                    Text("The dart and fox lessons stay free. Every plan includes the complete current library on devices using the same Apple Account. Monthly and annual access lasts while your subscription is active. Lifetime is a one-time purchase without recurring charges.")
                        .font(.caption).foregroundStyle(Palette.muted).lineSpacing(4)
                    Text("Payment is charged to your Apple Account when you confirm. Subscriptions renew automatically unless canceled at least 24 hours before the current period ends. Manage or cancel in Settings → your name → Subscriptions.")
                        .font(.caption2).foregroundStyle(Palette.muted).lineSpacing(3)
                    HStack(spacing: 20) {
                        Link("Privacy Policy", destination: URL(string: "https://realitycore.org/foliafold/privacy")!)
                            .accessibilityIdentifier("purchasePrivacy")
                        Link("Terms of Use (EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                            .accessibilityIdentifier("purchaseTerms")
                    }.font(.caption)
                    Button("Keep exploring") { showUnlock = false }.font(.subheadline).accessibilityIdentifier("keepExploring")
                }.padding(28)
            }.background(Palette.background).foregroundStyle(Palette.ink)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showUnlock = false }.accessibilityIdentifier("closeUnlock") } }
                .onAppear { selectAvailablePurchasePlan(preferActive: true) }
                .onChange(of: purchases.availablePlans) { _, _ in selectAvailablePurchasePlan() }
        }
    }

    private func purchasePlanRow(_ plan: PurchasePlan) -> some View {
        let product = purchases.product(for: plan)
        let selected = selectedPurchasePlan == plan
        return Button { selectedPurchasePlan = plan } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20)).foregroundStyle(selected ? Palette.accent : Palette.muted)
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.displayName).font(.system(size: 16, weight: .semibold))
                    Text(plan.isSubscription ? "Auto-renewing subscription" : "One-time purchase")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(product?.displayPrice ?? "Unavailable")
                        .font(.system(size: product == nil ? 12 : 19, weight: .semibold, design: .rounded))
                    if product != nil {
                        Text(plan == .monthly ? "per month" : plan == .annual ? "per year" : "pay once")
                            .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                }
            }.padding(16).frame(maxWidth: .infinity, minHeight: 76)
                .background(selected ? Palette.accent.opacity(0.055) : .white.opacity(0.65), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(selected ? Palette.accent : Palette.line, lineWidth: selected ? 1.5 : 1))
                .opacity(product == nil ? 0.5 : 1)
        }.buttonStyle(.plain).disabled(product == nil || purchases.isBusy)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("purchasePlan_\(plan.rawValue)")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var purchaseAction: some View {
        if purchases.isUnlocked && purchases.activePlan == selectedPurchasePlan {
            manageSubscriptionsLink
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 50)
                .background(Palette.line.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
        } else if let product = purchases.product(for: selectedPurchasePlan) {
            let title = selectedPurchasePlan == .lifetime
                ? "Buy lifetime · \(product.displayPrice)"
                : "Subscribe · \(product.displayPrice)/\(selectedPurchasePlan == .monthly ? "month" : "year")"
            primaryButton(purchases.isBusy ? "Please wait…" : title, symbol: "lock.open", id: "purchaseLibrary") {
                let plan = selectedPurchasePlan
                Task { await purchases.purchase(plan) }
            }.disabled(purchases.isBusy)
        } else {
            primaryButton(purchases.isBusy ? "Connecting to the store…" : "Try the store again", symbol: "arrow.clockwise", id: "retryStore") {
                Task { await purchases.refresh() }
            }.disabled(purchases.isBusy)
        }
    }

    private var manageSubscriptionsLink: some View {
        Link("Manage Subscriptions", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            .accessibilityIdentifier("manageSubscriptions")
    }

    private func selectAvailablePurchasePlan(preferActive: Bool = false) {
        if preferActive, let active = purchases.activePlan, purchases.availablePlans.contains(active) {
            selectedPurchasePlan = active
        } else if !purchases.availablePlans.contains(selectedPurchasePlan), let first = purchases.availablePlans.first {
            selectedPurchasePlan = first
        }
    }

    private var privacySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Privacy, simply.").font(.system(size: 30, weight: .regular, design: .serif))
                    Text("Protacta Privacy Policy · September 13, 2026").font(.caption).foregroundStyle(Palette.muted)
                    Text("Your camera and surroundings").font(.headline)
                    Text(controller.validationEnabled
                         ? "Camera analysis stays on your device. In this explicitly enabled local test mode, Save local test sample stores one camera photo and analysis metadata in the app's Documents folder. A photo is saved only when you press that button; no image is uploaded. Normal practice does not save camera photos."
                         : "Protacta uses the camera to align guidance with a flat sheet or display a 3D lesson on your table. Images and geometry are processed on your device. Check my step can temporarily show that checked view for comparison; changing action, restarting the camera, leaving the guide or backgrounding clears it. Normal practice does not save camera photos to storage or send them to a server.")
                    Text("Optional voice control and reading aloud").font(.headline)
                    Text("Voice control starts only when you turn it on and allow microphone and speech recognition access. English commands use Apple's on-device recognition when it is available; Protacta does not fall back to server recognition. Audio and recognized words are not saved or uploaded by the app. Listening stops when you turn it off or leave the app. Reading aloud uses Apple's speech synthesis and does not require microphone access. The explanations are written lesson notes, not generated answers or a camera assessment of your folds.")
                    Text("Purchases and local data").font(.headline)
                    Text("Apple processes purchases and restores. Protacta checks Apple's verified purchase information to unlock lessons. We do not receive your payment card details. The app keeps a small local status file for troubleshooting; it contains the lesson, step and AR status, but no camera images or room coordinates. It is not automatically uploaded.")
                    Text("Your lesson progress, completion state, playback speed and hint preference are saved locally so you can continue later. These records do not include camera images, room positions or purchase credentials, and are not automatically uploaded. Start over begins a fresh attempt; deleting the app removes its local learning records.")
                    Text("No account, ads or tracking").font(.headline)
                    Text("Protacta does not require an app account. We do not use advertising SDKs, third-party analytics or cross-app tracking. Tutorials are included in the app. Opening a reference link uses the linked site's own privacy policy.")
                    Text("Support and your choices").font(.headline)
                    Text("If you email support, we receive the address and information you choose to send and use it to respond. You can request deletion of support correspondence. You can turn off camera access in Settings and keep using the 3D guide, or delete the app to remove its local files. Apple manages purchase records under its own privacy policy.")
                    Link("adrianchenyuqiu@gmail.com", destination: URL(string: "mailto:adrianchenyuqiu@gmail.com?subject=Protacta%20Privacy")!)
                    Link("Apple Privacy Policy", destination: URL(string: "https://www.apple.com/legal/privacy/")!)
                }.font(.subheadline).lineSpacing(5).padding(26)
            }.background(Palette.background).foregroundStyle(Palette.ink)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPrivacy = false } } }
        }
    }

    private var stepListSheet: some View {
        NavigationStack {
            List(controller.lesson.steps) { step in
                Button {
                    selectedStepToReplay = step.id
                    showStepList = false
                } label: {
                    HStack(spacing: 14) {
                        Text(step.id == 0 ? "•" : String(format: "%02d", step.id))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.accent).frame(width: 24)
                        Text(step.title).font(.system(size: 15))
                        Spacer(minLength: 2)
                        if step.id == controller.stepIndex { Image(systemName: "play.circle.fill").foregroundStyle(Palette.accent) }
                    }.padding(.vertical, 6).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("jumpStep_\(step.id)")
                    .listRowBackground(Palette.background)
            }.listStyle(.plain).scrollContentBackground(.hidden)
                .background(Palette.background).foregroundStyle(Palette.ink)
                .navigationTitle(controller.lesson.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showStepList = false }.accessibilityIdentifier("closeSteps") } }
        }
    }
}
