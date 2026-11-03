import SwiftUI

/// Advice, not an alignment or stability certificate. Opening it starts no sensors.
struct PhoneSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode: SetupMode = .tabletop

    private enum SetupMode: String, CaseIterable, Identifiable {
        case tabletop = "Tabletop AR", paper = "Paper guide"
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Make room for both hands.")
                        .font(.system(size: 28, weight: .medium)).tracking(-0.5)
                    Picker("Guidance mode", selection: $mode) {
                        ForEach(SetupMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("phoneSetupMode")
                    PhoneWorkspaceDiagram(isPaperGuide: mode == .paper)
                        .frame(height: 180).accessibilityHidden(true)
                    row("1", "Support your phone", "Use a stable stand. Keep the screen visible and leave the rear camera clear.")
                    if mode == .tabletop {
                        row("2", "Scan, then place", "Slowly scan a well-lit, textured table. Tap Place reference, then Adjust to move or resize it. Tap Done to lock it.")
                        row("3", "Keep your hands free", "Place the reference beside your object. Turn on Voice in the lesson, or use the fold timeline and Next button.")
                        recovery("If the reference disappears", "Pause and point back at the same table. Move slowly until tracking returns. If it does not recover, use Retry scan and place the reference again.")
                        Text("Tabletop AR places a virtual reference. It does not automatically align to your real paper, clothes or equipment.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("phoneSetupTabletopScope")
                    } else {
                        row("2", "Show the whole sheet", "For the flat-A4 guide, put one flat sheet on a clear surface. Keep all four corners in view and confirm the highlighted TOP edge.")
                        row("3", "Keep the guide visible", "Avoid glare and keep hands away while the sheet is being found. If cues hide, uncover the sheet and confirm its direction again when asked.")
                        recovery("If the guide disappears", "Lay the sheet flat and show all four corners again. Recheck the highlighted TOP edge before continuing. Use the 3D lesson when the paper is folded or lifted.")
                        Text("The natural-paper guide is experimental and supports the flat-A4 centre crease. Later printed-paper cues require the PTC2 practice sheet.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("phoneSetupPaperScope")
                    }
                }.padding(24)
            }.background(TutorialColors.paper)
                .navigationTitle("Phone setup").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("closePhoneSetup")
                } }
        }.foregroundStyle(TutorialColors.ink).presentationDetents([.large])
    }

    private func recovery(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "viewfinder").font(.subheadline.weight(.semibold))
            Text(detail).font(.subheadline).foregroundStyle(.secondary).lineSpacing(3)
                .accessibilityIdentifier("phoneSetupRecovery")
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private func row(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number).font(.subheadline.weight(.semibold))
                .frame(width: 30, height: 30).background(TutorialColors.line.opacity(0.6), in: Circle())
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).lineSpacing(4).foregroundStyle(.secondary)
            }
        }
    }
}

/// A setup sketch, not a live preview or a measured camera-framing overlay.
private struct PhoneWorkspaceDiagram: View {
    let isPaperGuide: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 24).fill(TutorialColors.line.opacity(0.35))
                Rectangle().fill(TutorialColors.line).frame(height: 2).padding(.horizontal, 18).offset(y: -33)
                HStack(alignment: .bottom, spacing: geometry.size.width * 0.10) {
                    ZStack(alignment: .bottom) {
                        Image(systemName: "triangle").font(.system(size: 43, weight: .ultraLight))
                            .foregroundStyle(TutorialColors.muted).offset(x: 9, y: 7)
                        RoundedRectangle(cornerRadius: 9).fill(TutorialColors.paper)
                            .overlay { RoundedRectangle(cornerRadius: 9).stroke(TutorialColors.ink, lineWidth: 2) }
                            .overlay(alignment: .top) { Capsule().fill(TutorialColors.ink).frame(width: 20, height: 4).padding(.top, 7) }
                            .frame(width: 58, height: 105).rotationEffect(.degrees(-14))
                    }.frame(width: 86, height: 120)
                    VStack(spacing: 12) {
                        Text(isPaperGuide ? "All four corners" : "Reference beside you")
                            .font(.caption.weight(.medium)).foregroundStyle(TutorialColors.muted)
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 2).fill(.white)
                                .overlay { RoundedRectangle(cornerRadius: 2).stroke(TutorialColors.muted, lineWidth: 1) }
                                .overlay { if isPaperGuide { Rectangle().stroke(TutorialColors.orange, style: StrokeStyle(lineWidth: 2, dash: [4, 3])).padding(4) } }
                                .frame(width: 46, height: 64).rotationEffect(.degrees(-8))
                            if !isPaperGuide {
                                Image(systemName: "paperplane").font(.system(size: 35, weight: .light))
                                    .foregroundStyle(TutorialColors.orange)
                            }
                        }.frame(height: 78)
                    }.frame(maxWidth: .infinity)
                }.padding(.horizontal, 24).padding(.bottom, 35)
            }
        }
    }
}
