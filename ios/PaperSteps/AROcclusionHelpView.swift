import SwiftUI

struct AROcclusionHelpView: View {
    @ObservedObject var controller: LessonController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Let your hand come first.")
                        .font(.system(size: 27, weight: .regular, design: .serif))
                    Text("Hold your hand in front of the virtual paper. It should hide the paper. Move behind it, and the paper should hide your hand.")
                        .font(.subheadline)
                    Text(controller.occlusionSummary)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("occlusionAvailability")
                    ForEach(AROcclusionMode.allCases) { mode in
                        Button { controller.setOcclusionMode(mode) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: controller.occlusionMode == mode ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(mode.title).font(.headline)
                                    Text(mode.explanation).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier(mode == .automatic ? "modeAutomatic" : "modePeopleOnly")
                            .accessibilityAddTraits(controller.occlusionMode == mode ? [.isSelected] : [])
                    }
                    Text("Changing this option keeps your fold and table position. If your hand is still covered, try Hands only, then compare with the animation paused and playing.")
                        .font(.footnote).foregroundStyle(.secondary)
                    DisclosureGroup("Device details") {
                        VStack(spacing: 10) {
                            ForEach(controller.occlusionDetails.keys.sorted(), id: \.self) { key in
                                HStack(alignment: .top) {
                                    Text(key)
                                    Spacer(minLength: 12)
                                    Text(controller.occlusionDetails[key] ?? "Unknown")
                                        .multilineTextAlignment(.trailing).foregroundStyle(.secondary)
                                }.font(.caption)
                            }
                        }.padding(.top, 12)
                    }.accessibilityIdentifier("occlusionDetails")
                    Text("Use a well-lit room. Keep your hand away from the camera lens. Thin, reflective or transparent objects may not provide reliable depth. These readings stay on your device.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }.background(Color(red: 0.96, green: 0.96, blue: 0.93))
                .navigationTitle("AR help").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("closeARHelp")
                    }
                }
        }.presentationDetents([.medium, .large])
            .onAppear { controller.refreshOcclusionStatus() }
    }
}
