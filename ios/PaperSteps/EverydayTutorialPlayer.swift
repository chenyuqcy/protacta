import SwiftUI

struct EverydayTutorialPlayer: View {
    let courseID: EverydayTutorialID
    let onExit: () -> Void
    private let store: EverydayTutorialProgressStore
    @State private var session: EverydayTutorialSession
    @StateObject private var voice = VoiceGuide()
    @StateObject private var screenAwake = HandsOnScreenAwakeLease.system()
    @Environment(\.scenePhase) private var scenePhase
    @State private var progress: Double = 0
    @State private var isPlaying = false
    @State private var speed: Double = 1
    @State private var showHelp = false
    @State private var showSteps = false
    @State private var feedback = ""

    init(courseID: EverydayTutorialID, onExit: @escaping () -> Void) {
        self.courseID = courseID; self.onExit = onExit
        let store = EverydayTutorialProgressStore.appDefault()
        self.store = store
        let restored = store.load(courseID: courseID) ?? EverydayTutorialSession(courseID: courseID)
        _session = State(initialValue: restored)
        _progress = State(initialValue: restored.completed ? 1 : 0)
    }

    private var course: EverydayTutorialCourse { EverydayTutorialCourse.course(courseID) }
    private var action: EverydayTutorialAction { course.actions[session.currentAction - 1] }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    titleBlock.id("everydayTop")
                    visualCard
                    if session.completed { completionCard }
                    else { actionCard }
                    setupCard
                    Text(course.reviewNotice).font(.footnote).foregroundStyle(TutorialColors.muted)
                        .accessibilityIdentifier("everydayReviewNotice")
                }.padding(22).frame(maxWidth: 820).frame(maxWidth: .infinity)
            }.background(TutorialColors.paper).foregroundStyle(TutorialColors.ink)
                .onChange(of: session.currentAction) { _, _ in proxy.scrollTo("everydayTop", anchor: .top) }
                .onChange(of: session.completed) { _, _ in proxy.scrollTo("everydayTop", anchor: .top) }
                .onChange(of: isPlaying) { _, playing in if playing { proxy.scrollTo("everydayTop", anchor: .top) } }
                .navigationTitle(course.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { close() } label: { Image(systemName: "house") }
                            .accessibilityLabel("All tutorials").accessibilityIdentifier("everydayClose")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { isPlaying = false; voice.stop(); showSteps = true } label: { Image(systemName: "list.number") }
                            .accessibilityLabel("Tutorial actions").accessibilityIdentifier("everydaySteps")
                    }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 40_000_000)
                guard !Task.isCancelled else { return }
                if isPlaying && scenePhase == .active {
                    progress = min(1, progress + 0.008 * speed)
                    if progress >= 1 { isPlaying = false }
                }
            }
        }
        .onAppear { screenAwake.acquire(); configureVoice() }
        .onDisappear { screenAwake.release(); stopAndSave(); voice.onCommand = nil }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { screenAwake.acquire(); voice.handleSceneActive() }
            else if phase == .background { screenAwake.release(); stopAndSave(); voice.handleSceneInactive() }
            else {
                // Speech permission sheets temporarily make the scene inactive;
                // VoiceGuide preserves its matching permission request itself.
                screenAwake.release(); isPlaying = false; _ = store.save(session); voice.handleSceneInactive()
            }
        }
        .sheet(isPresented: $showHelp, onDismiss: { voice.stop() }) { helpSheet }
        .sheet(isPresented: $showSteps) { stepSheet }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.completed ? "PRACTICE COMPLETE" : "ACTION \(session.currentAction) OF \(course.actions.count)")
                    .font(.system(size: 11, weight: .bold)).tracking(1.5)
                    .accessibilityIdentifier("everydayCounter")
                Spacer()
                Text("ILLUSTRATED GUIDE").font(.system(size: 9, weight: .medium)).foregroundStyle(TutorialColors.muted)
            }
            Text(session.completed ? "You have practised every action." : action.title)
                .font(.system(size: 27, weight: .semibold, design: .rounded)).tracking(-0.5)
                .accessibilityIdentifier("everydayActionTitle")
            Text(session.completed ? "Your confirmations are saved on this device." : action.instruction)
                .font(.system(size: 16)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("everydayInstruction")
        }
    }

    private var visualCard: some View {
        VStack(spacing: 12) {
            EverydayTutorialVisual(courseID: courseID.rawValue, stepIndex: session.currentAction - 1, progress: progress)
                .frame(height: 360).clipped()
                .accessibilityIdentifier("everydayVisual")
            HStack {
                Text(progress < 0.01 ? "START POSITION" : progress >= 1 ? "TARGET POSITION" : "FOLLOW THE MOVEMENT")
                    .font(.system(size: 9, weight: .bold)).tracking(1)
                Spacer()
                Button("Start") { isPlaying = false; progress = 0 }
                    .accessibilityIdentifier("everydayShowStart")
                Button("Target") { isPlaying = false; progress = 1 }
                    .accessibilityIdentifier("everydayShowTarget")
            }.font(.system(size: 11, weight: .medium)).buttonStyle(.bordered).tint(TutorialColors.ink)
            Slider(value: $progress, in: 0...1, onEditingChanged: { editing in
                if editing { isPlaying = false }
                else if progress > 0.98 { progress = 1 }
                else if progress < 0.02 { progress = 0 }
            })
                .tint(TutorialColors.ink).accessibilityLabel("Movement progress")
                .accessibilityIdentifier("everydayProgressSlider")
            HStack(spacing: 12) {
                Button {
                    voice.contextDidChange()
                    if progress >= 1 { progress = 0 }
                    isPlaying.toggle()
                } label: { Label(isPlaying ? "Pause" : "Play move", systemImage: isPlaying ? "pause.fill" : "play.fill") }
                    .accessibilityIdentifier("everydayPlay")
                Spacer()
                Button { progress = 0; isPlaying = true } label: { Image(systemName: "arrow.counterclockwise") }
                    .accessibilityLabel("Replay movement").accessibilityIdentifier("everydayReplay")
                Button { speed = speed == 1 ? 0.4 : 1 } label: { Text(speed == 1 ? "1×" : "0.4×") }
                    .accessibilityLabel("Playback speed").accessibilityValue(speed == 1 ? "Normal" : "Slow")
                    .accessibilityIdentifier("everydaySpeed")
            }.font(.system(size: 14, weight: .semibold)).buttonStyle(.bordered)
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Compare your result", systemImage: "eye").font(.headline)
            Text(action.manualCheckpoint).font(.subheadline).lineSpacing(3)
                .accessibilityIdentifier("everydayCheckpoint")
            Text("You confirm the action. This guide does not inspect your object with the camera.")
                .font(.footnote).foregroundStyle(TutorialColors.muted).accessibilityIdentifier("everydayCameraScope")
            Button { confirm() } label: {
                Label(session.currentAction == course.actions.count ? "I have finished · Save progress" : "I have done this · Next action", systemImage: "checkmark")
                    .font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.borderedProminent).tint(TutorialColors.ink).foregroundStyle(.white)
                .accessibilityIdentifier("everydayConfirm")
            HStack {
                Button("Previous action") { previous() }.disabled(session.currentAction == 1)
                    .accessibilityIdentifier("everydayPrevious")
                Spacer()
                Button("I'm stuck") { isPlaying = false; voice.stop(); showHelp = true }
                    .accessibilityIdentifier("everydayHelp")
            }.font(.system(size: 13, weight: .medium)).frame(minHeight: 40)
            voiceControls
            if !feedback.isEmpty {
                Text(feedback).font(.footnote).foregroundStyle(TutorialColors.muted)
                    .accessibilityIdentifier("everydayVoiceFeedback")
            }
        }.padding(18).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
    }

    private var completionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("All \(course.actions.count) actions confirmed by you", systemImage: "checkmark.circle")
                .font(.headline).accessibilityIdentifier("everydayCompletion")
            Text("Compare the finished result and practise again at your own pace. The animation and your confirmations do not certify physical correctness.")
                .font(.subheadline).foregroundStyle(TutorialColors.muted)
            Button("Start again") { restart() }.buttonStyle(.borderedProminent).tint(TutorialColors.ink)
                .accessibilityIdentifier("everydayRestart")
            Button("All tutorials") { close() }.buttonStyle(.bordered).accessibilityIdentifier("everydayFinishClose")
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Before you start").font(.headline)
            Text(course.materials.joined(separator: " · ")).font(.subheadline.weight(.medium))
            Text(course.setup).font(.subheadline).foregroundStyle(TutorialColors.muted)
            if !course.references.isEmpty {
                ForEach(course.references, id: \.url) { reference in
                    Link(reference.title, destination: reference.url).font(.footnote)
                }
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(TutorialColors.line, lineWidth: 1) }
    }

    private var voiceControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Button {
                    if voice.isEnabled || voice.isSpeaking || voice.isRequestingPermission { voice.stop() }
                    else { isPlaying = false; Task { await voice.startListening() } }
                } label: { Label(voice.isEnabled ? "Stop voice" : voice.isSpeaking ? "Stop reading" : "Hands-free", systemImage: "mic") }
                    .accessibilityIdentifier("everydayVoice")
                Spacer()
                Button { isPlaying = false; voice.speak(action.instruction) } label: { Label("Read step", systemImage: "speaker.wave.2") }
                    .accessibilityIdentifier("everydayReadStep")
            }.font(.system(size: 12, weight: .medium)).buttonStyle(.bordered)
            Text(voice.isEnabled || voice.isSpeaking || !voice.lastHeard.isEmpty ? voice.status : "English commands: Show me again · Slower · Read this step")
                .font(.system(size: 11)).foregroundStyle(TutorialColors.muted)
        }
    }

    private var helpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(action.title).font(.title2.weight(.semibold))
                    helpBlock("What should I see?", action.manualCheckpoint)
                    helpBlock("A common difficulty", action.commonMistake)
                    helpBlock("Try this", action.help)
                    Text("Written guidance for this action. It is not a camera assessment or generated AI answer.")
                        .font(.footnote).foregroundStyle(TutorialColors.muted)
                    Button("Replay the movement") { voice.stop(); progress = 0; isPlaying = true; showHelp = false }
                        .buttonStyle(.borderedProminent).tint(TutorialColors.ink).accessibilityIdentifier("everydayHelpReplay")
                    Button("Read this help") { voice.speak(action.help) }.buttonStyle(.bordered)
                }.padding(22)
            }.background(TutorialColors.paper).navigationTitle("Help with this action").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showHelp = false } } }
        }
    }

    private func helpBlock(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.headline); Text(text).lineSpacing(4) }
    }

    private var stepSheet: some View {
        NavigationStack {
            List(course.actions) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(item.id). \(item.title)", systemImage: session.confirmedActions.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline.weight(.medium))
                    Text(item.instruction).font(.footnote).foregroundStyle(.secondary)
                }.padding(.vertical, 5)
            }.navigationTitle("All actions").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSteps = false } } }
        }
    }

    private func configureVoice() {
        voice.onCommand = { command in
            guard EverydayPracticeVoiceBoundary.permitsCommand(completed: session.completed,
                                                               stop: { voice.stop() }) else { return }
            switch command {
            case .next: feedback = "Use I have done this to confirm your own action and continue."
            case .back: previous()
            case .replay: progress = 0; isPlaying = true; feedback = "Replaying this movement."
            case .restart: restart(); feedback = "Practice restarted."
            case .slower: speed = 0.4; feedback = "Slower playback."
            case .normalSpeed: speed = 1; feedback = "Normal playback."
            case .pause: isPlaying = false
            case .resume: if progress >= 1 { progress = 0 }; isPlaying = true
            case .readStep: isPlaying = false; voice.speak(action.instruction)
            case .explainSimply, .help: isPlaying = false; voice.speak(action.help)
            case .why: isPlaying = false; voice.speak(action.manualCheckpoint)
            case .stopListening: voice.stop()
            }
        }
    }
    private func confirm() {
        isPlaying = false
        _ = EverydayPracticeVoiceBoundary.confirm(&session, stop: { voice.stop() },
                                                  continueListening: { voice.contextDidChange() })
        _ = store.save(session); progress = session.completed ? 1 : 0; feedback = ""
    }
    private func previous() {
        voice.contextDidChange(); isPlaying = false
        _ = session.previousAction(); _ = store.save(session); progress = 0; feedback = ""
    }
    private func restart() {
        voice.contextDidChange(); isPlaying = false; session.restart(); _ = store.save(session); progress = 0
    }
    private func stopAndSave() { isPlaying = false; voice.stop(); _ = store.save(session) }
    private func close() { screenAwake.release(); stopAndSave(); onExit() }
}
