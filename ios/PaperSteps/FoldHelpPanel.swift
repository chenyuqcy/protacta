import SwiftUI

struct FoldHelpPanel: View {
    @ObservedObject var controller: LessonController
    @ObservedObject var voice: VoiceGuide
    let onReplay: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Let's take it one fold at a time.")
                        .font(.system(size: 28, weight: .regular, design: .serif))
                    Text(controller.currentStep.title).font(.headline)
                    if let help = FoldHelp.forStep(lesson: controller.lesson, stepIndex: controller.stepIndex) {
                        section("Try this", help.simplerInstruction, identifier: "simplerInstruction")
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
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.bordered).accessibilityIdentifier("readFoldHelp")
                            .disabled(!controller.canUseVoiceGuide && !voice.isSpeaking)
                        if voice.status != "Voice commands are off." {
                            Text(voice.status).font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("helpVoiceStatus")
                        }
                    }
                    Button(action: onReplay) {
                        Label("Replay this fold", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).tint(Color(red: 0.16, green: 0.22, blue: 0.20))
                        .disabled(!controller.canUseVoiceGuide || controller.stepIndex == 0 || !controller.canAnimate)
                        .accessibilityIdentifier("replayFromHelp")
                    Text("Written guidance for this step. Compare with your own paper; the camera does not check whether your fold is correct.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }.background(Color(red: 0.96, green: 0.96, blue: 0.93))
                .navigationTitle("I'm stuck").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("closeFoldHelp")
                    }
                }
        }.presentationDetents([.large])
    }

    private func section(_ title: String, _ content: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(content).font(.subheadline).lineSpacing(4).accessibilityIdentifier(identifier)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
    }
}
