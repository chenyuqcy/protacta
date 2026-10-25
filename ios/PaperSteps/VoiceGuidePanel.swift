import SwiftUI

struct VoiceGuidePanel: View {
    @ObservedObject var voice: VoiceGuide
    @ObservedObject var controller: LessonController
    let feedback: String
    let onCommand: (VoiceCommand) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("A little help, hands free.")
                        .font(.system(size: 29, weight: .regular, design: .serif))
                    Text("Rest your phone on a stand where you can see the guide. In AR, place the model on your table first. Tap Hands-free once, then keep folding and say one command at a time.")
                        .font(.subheadline)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Next step → play the next fold")
                        Text("Previous step → return to the previous fold")
                        Text("Show me again → replay this fold")
                        Text("Restart lesson → return to a blank sheet")
                    }.font(.subheadline.weight(.medium))
                        .accessibilityIdentifier("handsFreeQuickStart")
                    Text("Wait for each animation to finish before saying Next step. Listening resumes after each command and spoken explanation. Keep the app open; say Stop listening when you are done.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(voice.status).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("voiceStatus")
                    Button {
                        if voice.isEnabled || voice.isRequestingPermission { voice.stop() }
                        else {
                            guard controller.canUseVoiceGuide else { voice.stop(); dismiss(); return }
                            Task {
                                guard controller.canUseVoiceGuide else { return }
                                await voice.startListening()
                                if voice.isEnabled { dismiss() }
                            }
                        }
                    } label: {
                        Label(voice.isEnabled || voice.isRequestingPermission ? "Stop voice control" : "Start voice control",
                              systemImage: voice.isEnabled ? "mic.slash" : "mic")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.borderedProminent).tint(Color(red: 0.16, green: 0.22, blue: 0.20))
                        .accessibilityIdentifier("startVoiceControl")
                        .disabled(!controller.canUseVoiceGuide && !voice.isEnabled && !voice.isRequestingPermission)
                    Text("English voice recognition stays on your device when supported. If it is unavailable, use the buttons below. Reading aloud does not need microphone access.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Try a command").font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(VoiceCommand.allCases) { command in
                            Button { onCommand(command) } label: {
                                Text(command.phrase).font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 6)
                                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).accessibilityIdentifier("voiceCommand_\(command.rawValue)")
                                .disabled(!controller.canUseVoiceGuide && command != .stopListening)
                        }
                    }
                    if !feedback.isEmpty {
                        Text(feedback).font(.subheadline).accessibilityIdentifier("voiceFeedback")
                    }
                    if !voice.lastHeard.isEmpty {
                        Text("Heard: \(voice.lastHeard)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Explanations come from this lesson's written guidance. Foliafold does not listen until you turn voice control on, save recordings, or judge your real paper.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }.background(Color(red: 0.96, green: 0.96, blue: 0.93))
                .navigationTitle("Voice guide").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("closeVoiceGuide")
                    }
                }
        }.presentationDetents([.large])
    }
}
