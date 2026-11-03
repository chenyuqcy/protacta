import SwiftUI

/// Separate from tutorial progress. A preview never opens a camera or lesson.
struct FirstRunIntroductionPreferences {
    private static let completionKey = "protacta.quickTour.v1.completed"
    private let defaults: UserDefaults
    private let automaticallyEnabled: Bool

    static func appDefault() -> Self {
        #if DEBUG
        let process = ProcessInfo.processInfo
        if process.arguments.contains("--ui-testing") {
            let suite = process.environment["PROTACTA_INTRODUCTION_TEST_SUITE"]
            let isolated = suite.flatMap { $0.hasPrefix("org.realitycore.protacta.prototype.uitests.") ? UserDefaults(suiteName: $0) : nil }
            return Self(defaults: isolated ?? .standard,
                        automaticallyEnabled: process.arguments.contains("--enable-introduction"))
        }
        #endif
        return Self(defaults: .standard, automaticallyEnabled: true)
    }

    var shouldPresent: Bool { automaticallyEnabled && !defaults.bool(forKey: Self.completionKey) }
    func complete() { defaults.set(true, forKey: Self.completionKey) }
}

struct FirstRunIntroductionView: View {
    let onFinish: () -> Void
    @State private var page = 0
    @State private var previewProgress = 0.35
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let red = Color(red: 0.78, green: 0.19, blue: 0.15)
    private let titles = ["See it. Then try it.", "Move at your pace.", "Make room for your hands."]
    private let descriptions = [
        "Choose a tutorial and watch each movement before trying it yourself.",
        "Drag the timeline to replay any part of a fold. Red arrows show the direction of movement.",
        "Place a 3D reference beside your paper. Turn on voice when you want both hands free."
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("\(page + 1) OF 3").font(.caption.weight(.semibold)).tracking(1.5)
                        .foregroundStyle(TutorialColors.orange).accessibilityIdentifier("introductionCounter")
                    Text(titles[page]).font(.largeTitle.weight(.semibold)).tracking(-0.8)
                        .accessibilityIdentifier("introductionTitle")
                    Text(descriptions[page]).font(.body).foregroundStyle(TutorialColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    preview
                        .padding(22).frame(maxWidth: .infinity)
                        .background(.white, in: RoundedRectangle(cornerRadius: 26))
                    if page == 2 {
                        Text("Camera and microphone permissions are requested only when you use them.")
                            .font(.footnote).foregroundStyle(TutorialColors.muted)
                    }
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .background(TutorialColors.paper)
            .navigationTitle("Quick tour").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Skip") { onFinish() }.frame(minHeight: 44)
                        .accessibilityIdentifier("skipIntroduction")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 16) {
                    if page > 0 {
                        Button("Back") { changePage(-1) }.frame(minWidth: 60, minHeight: 48)
                            .accessibilityIdentifier("introductionBack")
                    }
                    Button {
                        if page == 2 { onFinish() } else { changePage(1) }
                    } label: {
                        HStack {
                            Text(page == 2 ? "Get started" : "Next")
                            Image(systemName: "arrow.right")
                        }.font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(.white).background(TutorialColors.ink, in: Capsule())
                    }.buttonStyle(.plain).accessibilityLabel(page == 2 ? "Get started" : "Next")
                        .accessibilityIdentifier("introductionNext")
                }.padding(.horizontal, 24).padding(.vertical, 16)
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
                    .background(TutorialColors.paper)
            }
        }.foregroundStyle(TutorialColors.ink).tint(TutorialColors.orange)
            .presentationDetents([.large]).presentationDragIndicator(.hidden)
            .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var preview: some View {
        switch page {
        case 0:
            VStack(alignment: .leading, spacing: 12) {
                pointer("Choose a lesson", symbol: "arrow.down.left")
                VStack(alignment: .leading, spacing: 14) {
                    if let image = UIImage(named: "dart-preview") {
                        Image(uiImage: image).resizable().scaledToFit().frame(height: 130)
                            .frame(maxWidth: .infinity).accessibilityHidden(true)
                    } else {
                        Image(systemName: "paperplane").font(.system(size: 70, weight: .light))
                            .frame(maxWidth: .infinity, minHeight: 130).accessibilityHidden(true)
                    }
                    HStack { Text("Origami").font(.title3.weight(.medium)); Spacer(); Image(systemName: "arrow.right") }
                }.padding(20).background(TutorialColors.line.opacity(0.45), in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityElement(children: .combine).accessibilityLabel("Origami lesson preview")
            }
        case 1:
            VStack(spacing: 18) {
                HStack { Text("PREVIEW").font(.caption2.weight(.semibold)).tracking(1.2); Spacer() }
                    .foregroundStyle(TutorialColors.muted)
                ZStack {
                    Rectangle().fill(TutorialColors.line).frame(width: 88, height: 122).offset(x: 44)
                    Rectangle().fill(Color(red: 0.90, green: 0.87, blue: 0.79)).frame(width: 88, height: 122)
                        .rotation3DEffect(.degrees(-150 * previewProgress), axis: (x: 0, y: 1, z: 0), anchor: .trailing,
                                          perspective: 0.35).offset(x: -44)
                    Image(systemName: "arrow.turn.up.right").font(.system(size: 38, weight: .medium))
                        .foregroundStyle(red).offset(x: -12, y: -24)
                }.frame(maxWidth: .infinity, minHeight: 145).accessibilityHidden(true)
                pointer("Try dragging below", symbol: "arrow.down")
                Slider(value: $previewProgress, in: 0...1)
                    .tint(TutorialColors.orange).frame(minHeight: 44)
                    .accessibilityLabel("Preview fold progress")
                    .accessibilityValue("\(Int(previewProgress * 100)) percent")
                    .accessibilityIdentifier("introductionProgress")
            }
        default:
            VStack(alignment: .leading, spacing: 20) {
                pointer("Place a reference in AR", symbol: "arrow.down.left")
                Label("AR", systemImage: "arkit").font(.title3.weight(.semibold))
                    .padding(.horizontal, 22).padding(.vertical, 14)
                    .background(TutorialColors.line.opacity(0.6), in: Capsule())
                Divider()
                Label("“Next step”", systemImage: "mic").font(.title2.weight(.medium))
                Text("Start voice from the lesson controls.").font(.subheadline)
                    .foregroundStyle(TutorialColors.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pointer(_ text: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 24, weight: .semibold)).accessibilityHidden(true)
            Text(text).font(.subheadline.weight(.medium))
        }.foregroundStyle(red)
    }

    private func changePage(_ delta: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { page += delta }
    }
}
