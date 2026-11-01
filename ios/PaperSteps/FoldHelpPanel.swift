import SwiftUI

enum FoldHelpAction {
    case replay, play, notes, steps, practice, paperGuide, setup
}

/// Secondary actions stay here so the object and the current move can lead.
struct FoldHelpPanel: View {
    @ObservedObject var controller: LessonController
    @ObservedObject var voice: VoiceGuide
    let onAction: (FoldHelpAction) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(controller.currentStep.title)
                        .font(.system(size: 25, weight: .medium)).tracking(-0.5)
                    HStack(spacing: 12) {
                        Button { onAction(.replay) } label: {
                            Label("Replay", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }.accessibilityIdentifier("replayFromHelp")
                            .disabled(controller.stepIndex == 0 || !controller.canAnimate)
                        Button { controller.toggleSlowMotion() } label: {
                            Label(controller.slowMotion ? "½× speed" : "Slow down", systemImage: "tortoise")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }.accessibilityIdentifier("playbackSpeed")
                            .accessibilityValue(controller.slowMotion ? "Half speed" : "Normal speed")
                            .disabled(!controller.canAnimate)
                    }.buttonStyle(.bordered).tint(TutorialColors.ink)
                    if controller.stepIndex > 0 && !controller.completed {
                        HStack(spacing: 12) {
                            Button { onAction(.play) } label: {
                                Image(systemName: "play.fill").frame(width: 44, height: 44)
                            }.accessibilityLabel("Play fold").accessibilityIdentifier("playPause")
                            Slider(value: Binding(get: { controller.progress }, set: { controller.scrub(to: $0) }), in: 0...1,
                                   onEditingChanged: { editing in if editing { voice.stop() } })
                                .tint(TutorialColors.orange).accessibilityLabel("Fold progress")
                                .accessibilityIdentifier("foldProgress")
                        }.disabled(!controller.canAnimate)
                    }
                    if let help = FoldHelp.forStep(lesson: controller.lesson, stepIndex: controller.stepIndex) {
                        Text(help.simplerInstruction).font(.body).lineSpacing(4)
                            .accessibilityIdentifier("simplerInstruction")
                        section("Check your fold", help.checkpoint, identifier: "foldCheckpoint")
                        section("Watch out", help.commonMistake, identifier: "foldMistake")
                        Button {
                            if voice.isSpeaking { voice.stop() }
                            else {
                                guard controller.canUseVoiceGuide else { voice.stop(); dismiss(); return }
                                voice.speak("\(help.simplerInstruction) Check your fold: \(help.checkpoint) Watch out: \(help.commonMistake)")
                            }
                        } label: {
                            Label(voice.isSpeaking ? "Stop reading" : "Read aloud", systemImage: voice.isSpeaking ? "stop.fill" : "speaker.wave.2")
                                .frame(minHeight: 44)
                        }.accessibilityIdentifier("readFoldHelp")
                            .disabled(!controller.canUseVoiceGuide && !voice.isSpeaking)
                        if voice.status != "Voice commands are off." {
                            Text(voice.status).font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("helpVoiceStatus")
                        }
                    }
                    VStack(spacing: 0) {
                        link("Why this fold?", symbol: "book.closed", id: "foldNotes", action: .notes)
                        Divider()
                        link("All steps", symbol: "list.bullet", id: "stepList", action: .steps)
                        Divider()
                        link("Set up your phone", symbol: "iphone", id: "helpPhoneSetup", action: .setup)
                        if controller.lesson == .dart {
                            Divider()
                            link(controller.practiceReferenceActive ? "Return to my practice" : "Practice with paper",
                                 symbol: "hand.draw", id: "openDartPractice", action: .practice)
                            Divider()
                            link("Align a flat A4 sheet", symbol: "viewfinder", id: "openPaperGuide", action: .paperGuide)
                        }
                    }
                    Text("Compare the guide with your paper. The 3D animation does not check your fold.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }.background(TutorialColors.paper)
                .navigationTitle("Help").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("closeFoldHelp")
                    }
                }
        }.foregroundStyle(TutorialColors.ink)
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }

    private func section(_ title: String, _ content: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(content).font(.subheadline).lineSpacing(4).foregroundStyle(.secondary)
                .accessibilityIdentifier(identifier)
        }
    }

    private func link(_ title: String, symbol: String, id: String, action: FoldHelpAction) -> some View {
        Button { onAction(action) } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }.font(.subheadline).frame(minHeight: 52).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
}
