import SwiftUI

/// Presentation only: the existing lesson owns commands, tracking and progress.
/// Entering/leaving this overlay never creates an ARView or a camera session.
struct VoiceOnlyAROverlay: View {
    @ObservedObject var voice: VoiceGuide
    let trackingMessage: String?
    var commandFeedback: String? = nil
    // The paper viewport ignores safe areas and supplies its outer insets.
    // Equipment already lays controls inside the safe area, so adds none.
    var safeAreaInsets: EdgeInsets = EdgeInsets()
    let onShowControls: () -> Void
    @State private var attemptedStart = false
    @State private var showHint = true

    private var layoutPreview: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--ui-testing") &&
            ProcessInfo.processInfo.arguments.contains("--voice-only-layout-fixture")
        #else
        return false
        #endif
    }
    private var needsRetry: Bool {
        !layoutPreview && attemptedStart && !voice.isRequestingPermission && !voice.isSpeaking &&
            (voice.recoveryMessage != nil || !voice.isEnabled)
    }

    var body: some View {
        GeometryReader { _ in
            VStack(spacing: 12) {
                HStack {
                    Button { onShowControls() } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 16, weight: .medium)).frame(width: 44, height: 44)
                            .background(.regularMaterial, in: Circle())
                    }.accessibilityLabel("Exit voice-only full screen")
                        .accessibilityIdentifier("exitVoiceOnlyAR")
                    Spacer()
                }
                Spacer()
                if layoutPreview {
                    Text("VOICE LAYOUT PREVIEW · MIC OFF").font(.system(size: 10, weight: .bold))
                        .padding(8).background(.yellow, in: Capsule())
                        .accessibilityIdentifier("voiceOnlyFixtureLabel")
                }
                if let trackingMessage {
                    recoveryPanel(trackingMessage, retry: false)
                } else if needsRetry {
                    recoveryPanel(voice.recoveryMessage ?? "Voice control is paused.", retry: true)
                } else if voice.isRequestingPermission {
                    Text(voice.status).font(.callout).multilineTextAlignment(.center)
                        .padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("voiceOnlyPermissionStatus")
                } else if let commandFeedback, !commandFeedback.isEmpty {
                    Text(commandFeedback).font(.system(size: 13, weight: .medium))
                        .multilineTextAlignment(.center).padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("voiceOnlyCommandFeedback")
                } else if showHint {
                    Text("Say “Next step”").font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityIdentifier("voiceOnlyHint")
                }
            }
            .padding(.top, max(12, safeAreaInsets.top + 8))
            .padding(.bottom, max(18, safeAreaInsets.bottom + 12))
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(TutorialColors.ink).buttonStyle(.plain)
        .task {
            if !layoutPreview, !voice.isEnabled { await voice.startListening() }
            attemptedStart = true
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { showHint = false }
        }
        .onDisappear { voice.stop() }
    }

    private func recoveryPanel(_ message: String, retry: Bool) -> some View {
        VStack(spacing: 10) {
            Text(message).font(.system(size: 13)).multilineTextAlignment(.center)
                .accessibilityIdentifier("voiceOnlyRecoveryMessage")
            HStack(spacing: 20) {
                if retry {
                    Button("Retry voice") { Task { await voice.startListening(); attemptedStart = true } }
                        .frame(minHeight: 44).accessibilityIdentifier("voiceOnlyRetry")
                }
                Button("Show controls") { onShowControls() }
                    .frame(minHeight: 44).accessibilityIdentifier("voiceOnlyShowControls")
            }.font(.system(size: 14, weight: .semibold))
        }.padding(16).frame(maxWidth: 400)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
