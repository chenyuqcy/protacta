import SwiftUI

/// Global how-to guidance. Opening it never starts camera or microphone work.
struct TutorialSupportView: View {
    let onQuickTour: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showPhoneSetup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("A little guidance.")
                        .font(.system(size: 28, weight: .medium)).tracking(-0.5)
                    VStack(spacing: 0) {
                        Button(action: onQuickTour) {
                            actionRow("Quick tour", symbol: "hand.draw")
                        }.accessibilityIdentifier("supportQuickTour")
                        Divider()
                        Button { showPhoneSetup = true } label: {
                            actionRow("Set up your phone", symbol: "iphone")
                        }.accessibilityIdentifier("supportPhoneSetup")
                    }.buttonStyle(.plain).padding(.horizontal, 16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))

                    DisclosureGroup("Replay or inspect a movement") {
                        guidance("In an origami lesson, drag the fold timeline back or forward to inspect the current move. This pauses playback. Use Finish this fold to continue from that point.")
                        guidance("Open Help for Replay, slow motion and written fold notes. Finishing an animation does not confirm that your real paper is ready.")
                    }.accessibilityIdentifier("supportPlayback")

                    DisclosureGroup("Place or recover an AR reference") {
                        guidance("In Tabletop AR, slowly scan a well-lit table and choose Place reference. Use Adjust to move, turn or resize it, then Done to lock it.")
                        guidance("If tracking is lost, point back at the same table and move slowly. If needed, scan again and place the reference. Your lesson step stays separate from its placement.")
                        guidance("For origami hand visibility, Hands first keeps recognised hands in front of virtual paper on supported devices. If an edge looks unstable, improve the light and keep the camera lens clear. This does not make the model a physical object.")
                    }.accessibilityIdentifier("supportAR")

                    DisclosureGroup("Use voice without touching the screen") {
                        guidance("Start Voice from the lesson controls. Allow microphone and speech access when requested. Say one supported English command at a time, and wait for the movement or narration to finish.")
                        VStack(alignment: .leading, spacing: 10) {
                            voiceExample(.next, meaning: "Continue the movement or go to the next step")
                            voiceExample(.back, meaning: "Return to the previous movement")
                            voiceExample(.replay, meaning: "Replay the current movement")
                            voiceExample(.pause, meaning: "Pause playback")
                            voiceExample(.readStep, meaning: "Hear the instructions")
                            voiceExample(.stopListening, meaning: "Turn voice control off")
                        }.padding(.vertical, 8)
                        guidance("In the complete Dart practice, confirm your physical action with the confirmation button. Voice navigation does not confirm it for you. If voice is unavailable, use the touch controls.")
                    }.accessibilityIdentifier("supportVoice")

                    DisclosureGroup("Choose the right guidance mode") {
                        guidance("3D lets you watch and inspect the authored movements. Tabletop AR places that reference in your camera view beside your real object; placement is manual.")
                        guidance("The separate flat-A4 paper guide and PTC2 printed-paper checks are experimental and limited to supported paper states. Everyday and equipment lessons do not check or automatically align to real objects.")
                    }.accessibilityIdentifier("supportScope")

                    Text("Your progress stays on this device. Cloud AI chat is not enabled.")
                        .font(.footnote).foregroundStyle(TutorialColors.muted)
                }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.background(TutorialColors.paper)
                .navigationTitle("Help").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("closeTutorialSupport")
                } }
        }.foregroundStyle(TutorialColors.ink).tint(TutorialColors.orange)
            .presentationDetents([.large])
            .sheet(isPresented: $showPhoneSetup) { PhoneSetupView() }
    }

    private func actionRow(_ title: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol).font(.body.weight(.medium))
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(TutorialColors.muted)
        }.frame(minHeight: 56).contentShape(Rectangle())
    }

    private func guidance(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(TutorialColors.muted)
            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
    }

    private func voiceExample(_ command: VoiceCommand, meaning: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("“\(command.phrase)”").font(.subheadline.weight(.medium))
            Text(meaning).font(.caption).foregroundStyle(TutorialColors.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
