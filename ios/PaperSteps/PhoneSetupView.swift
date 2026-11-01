import SwiftUI

/// Advice, not an alignment or stability certificate. Opening it starts no sensors.
struct PhoneSetupView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28).fill(TutorialColors.line.opacity(0.45))
                        HStack(spacing: 36) {
                            Image(systemName: "iphone").font(.system(size: 76, weight: .ultraLight)).rotationEffect(.degrees(-12))
                            Image(systemName: "rectangle.portrait").font(.system(size: 62, weight: .ultraLight))
                        }.foregroundStyle(TutorialColors.orange).padding(38)
                    }.frame(height: 180).accessibilityHidden(true)
                    Text("Make room for both hands.")
                        .font(.system(size: 28, weight: .medium)).tracking(-0.5)
                    row("1", "Support your phone", "Use a stable stand, with the screen facing you and the rear camera clear.")
                    row("2", "Frame your workspace", "In AR, scan a well-lit, textured table and place the 3D reference beside your paper. For paper alignment, keep all four A4 corners visible.")
                    row("3", "Choose your controls", "Use Next and Help, or turn on voice control. AR still shows the same movement when you use voice.")
                    Text("If the phone moves or tracking is lost, pause and reposition it before continuing.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("phoneSetupRecovery")
                }.padding(24)
            }.background(TutorialColors.paper)
                .navigationTitle("Phone setup").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("closePhoneSetup")
                } }
        }.foregroundStyle(TutorialColors.ink).presentationDetents([.large])
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
