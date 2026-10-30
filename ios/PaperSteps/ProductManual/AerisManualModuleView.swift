import SwiftUI
import QuickLook

private let forest = Color(red: 0.15, green: 0.31, blue: 0.23)
private let muted = Color(red: 0.49, green: 0.56, blue: 0.45)
private let paper = Color(red: 0.965, green: 0.972, blue: 0.938)

/// Embedded native module, presented by Protacta's hub. The root must suspend
/// its other renderer before presentation; this module owns its own lifecycle.
struct AerisManualModuleView: View {
    let onExit: () -> Void
    @Environment(\.scenePhase) private var phase
    @StateObject private var scene = ProductSceneController()
    @State private var progress = ManualProgress()
    @State private var showAR = false
    @State private var showAppleAR = false
    @State private var showAssembly = false
    @State private var showHelp = false
    @State private var exploring = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("PROTACTA").font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text("/ PRODUCT MANUAL").font(.system(size: 8, weight: .medium)).tracking(1.4).foregroundStyle(muted)
                        Spacer()
                        Button { showHelp = true } label: { Image(systemName: "questionmark.circle").font(.system(size: 18, weight: .light)) }.accessibilityLabel("About this guide")
                        Button("Close") { closeModule() }.font(.system(size: 12, weight: .semibold))
                    .accessibilityIdentifier("aerisClose")
                    }.padding(.top, 8)
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("AERIS ONE / AIR PURIFIER").font(.system(size: 8, weight: .medium)).tracking(1.6).foregroundStyle(muted)
                            Menu {
                                ForEach(ManualTask.allCases) { task in Button(task.rawValue) { progress.select(task); applyCurrent() } }
                            } label: {
                                HStack(spacing: 9) { Text(progress.task.rawValue).font(.system(size: 26, weight: .regular, design: .rounded)).tracking(-0.7); Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium)) }
                            }.accessibilityIdentifier("taskMenu")
                        }
                        Spacer(minLength: 0)
                    }
                    modelCard
                    Text("Virtual concept product. This guide does not recognise or align to a real appliance.")
                        .font(.system(size: 11)).foregroundStyle(muted)
                    .accessibilityIdentifier("aerisScope")
                    Button {
                        scene.shutdown(); showAssembly = true
                    } label: { Label("Full-screen 3D · Explore the parts", systemImage: "arrow.up.left.and.arrow.down.right") }
                        .font(.system(size: 13, weight: .medium)).frame(minHeight: 44)
                        .accessibilityIdentifier("aerisAssemblyPlayer")
                    HStack(spacing: 6) {
                        ForEach(progress.task.steps) { s in
                            Button { progress.go(to: s.id); applyCurrent() } label: {
                                ZStack { Capsule().fill(s.id == progress.index ? forest : forest.opacity(s.id < progress.index || progress.completed ? 0.20 : 0.07)); Text(progress.completed || s.id < progress.index ? "✓" : "\(s.id + 1)").font(.system(size: 10, weight: .medium)).foregroundStyle(s.id == progress.index ? paper : muted) }.frame(height: 26)
                            }.disabled(s.id > progress.highestUnlocked).accessibilityLabel("Step \(s.id + 1): \(s.title)").accessibilityIdentifier("step_\(s.id)")
                        }
                    }
                    guideCard
                    HStack { Text("CONCEPT PRODUCT").font(.system(size: 7, weight: .medium)).tracking(1); Spacer(); Text("Original model · Demonstration instructions").font(.system(size: 8)) }.foregroundStyle(muted).padding(.bottom, 14)
                }.padding(.horizontal, 21)
            }.background(paper).foregroundStyle(forest).toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.light)
        .onChange(of: scene.isLoaded) { _, loaded in if loaded { applyCurrent(animated: false) } }
        .onChange(of: scene.releasePressed) { _, pressed in if pressed { progress.confirmAction() } }
        .fullScreenCover(isPresented: $showAR, onDismiss: { restoreStudio() }) { ProductARScreen(task: progress.task, sharedView: scene.view) }
        .fullScreenCover(isPresented: $showAssembly, onDismiss: { restoreStudio() }) {
            AssemblyTutorialPlayer(tutorial: .aeris, sharedView: scene.view, onExit: { showAssembly = false })
        }
        .fullScreenCover(isPresented: $showAppleAR, onDismiss: { restoreStudio() }) {
            if let url = Bundle.main.url(forResource: "aeris-one", withExtension: "usdz") {
                AppleARPreview(url: url, isPresented: $showAppleAR).ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showHelp) { helpSheet.presentationDetents([.medium]) }
        .onDisappear {
            // Covers borrow the already-prepared shared ARView. Do not clear a
            // new AR controller's scene while that cover is being presented.
            if !showAR && !showAppleAR && !showAssembly { scene.shutdown() }
        }
        .onChange(of: phase) { _, phase in
            if phase == .background, !showAR, !showAppleAR, !showAssembly { scene.shutdown() }
            if phase == .active, !showAR, !showAppleAR, !showAssembly { restoreStudio() }
        }
    }
    private var modelCard: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if showAR || showAppleAR || showAssembly { paper.frame(height: 325) }
                else { ProductSceneView(controller: scene).frame(height: 325) }
                HStack {
                    HStack(spacing: 5) { Circle().fill(scene.isAnimating ? Color.orange : forest).frame(width: 4, height: 4); Text(scene.isAnimating ? "PLAYING" : "INTERACTIVE 3D").font(.system(size: 8)).tracking(1) }
                    Spacer()
                    Button { scene.prepareForAR(); showAppleAR = true } label: { Text("Apple AR").font(.system(size: 10)).padding(.horizontal, 10).padding(.vertical, 8).background(paper.opacity(0.9), in: Capsule()) }.accessibilityIdentifier("openAppleAR").accessibilityLabel("Apple AR Viewer")
                    Button { scene.prepareForAR(); showAR = true } label: { Label("View in AR", systemImage: "arkit").font(.system(size: 10)).padding(.horizontal, 10).padding(.vertical, 8).background(paper.opacity(0.9), in: Capsule()) }.accessibilityIdentifier("openAR")
                }.padding(13)
                if !scene.isLoaded {
                    VStack { Spacer(); if let failure = scene.failure { Text(failure).font(.caption).padding() } else { ProgressView("Loading product…").font(.caption) }; Spacer() }
                }
                if !exploring, progress.current.requiresPress, let point = scene.hotspot {
                    GeometryReader { geometry in
                        Button { scene.pressRelease() } label: {
                            HStack(spacing: 4) { Image(systemName: scene.releasePressed ? "checkmark" : "hand.tap.fill"); Text(scene.releasePressed ? "RELEASED" : "PRESS") }.font(.system(size: 9, weight: .bold)).tracking(0.4).padding(.horizontal, 10).padding(.vertical, 8).background(scene.releasePressed ? forest : Color.red, in: Capsule()).foregroundStyle(.white).shadow(color: .black.opacity(0.10), radius: 5, y: 2)
                        }.disabled(scene.isAnimating || scene.releasePressed).position(x: min(max(point.x + 52, 55), geometry.size.width - 55), y: max(point.y - 18, 65)).accessibilityIdentifier("pressReleaseHotspot")
                    }
                }
                VStack {
                    Spacer()
                    HStack(spacing: 5) {
                        if !exploring && !scene.callout.isEmpty { Image(systemName: scene.releasePressed ? "checkmark.circle.fill" : "arrow.up.right").foregroundStyle(scene.releasePressed ? forest : .red); Text(scene.callout).font(.system(size: 8, weight: .semibold)).tracking(0.5) }
                        Spacer()
                        Button { exploring.toggle(); if exploring { scene.setPose(.exploded) } else { applyCurrent() } } label: { Text(exploring ? "Back to guide" : "Explore parts").font(.system(size: 9)).underline() }.accessibilityIdentifier("exploreParts")
                    }.padding(.horizontal, 13).padding(.bottom, 12)
                }
            }
            if exploring {
                HStack { ForEach([ProductPose.assembled, .cover, .exploded], id: \.self) { p in Button(p.title) { scene.setPose(p) }.font(.system(size: 10)).frame(maxWidth: .infinity).padding(.vertical, 10).background(scene.pose == p ? forest.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8)).accessibilityIdentifier("pose_\(p.rawValue)") } }.padding(6)
            }
        }.background(Color(red: 0.91, green: 0.94, blue: 0.88)).clipShape(RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(forest.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .contain).accessibilityValue(scene.isLoaded ? "Model loaded" : "Loading model")
    }
    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(progress.completed ? "WALKTHROUGH COMPLETE" : "STEP \(String(format: "%02d", progress.index + 1)) OF \(String(format: "%02d", progress.task.steps.count))").font(.system(size: 8, weight: .medium)).tracking(1.3).foregroundStyle(muted); Spacer(); if !progress.completed { Text(progress.current.requiresPress ? "TRY IT" : "FOLLOW ALONG").font(.system(size: 7, weight: .semibold)).tracking(1).foregroundStyle(progress.current.requiresPress ? .red : muted) } }
            Text(progress.completed ? "Demonstration complete." : progress.current.title).font(.system(size: 20, weight: .medium, design: .rounded)).tracking(-0.4).accessibilityIdentifier("stepTitle")
            Text(progress.completed ? "You have finished this model walkthrough. This does not verify work on a real appliance. Restart to practise again, or choose another task." : progress.current.detail).font(.system(size: 11.5)).foregroundStyle(muted).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            if progress.current.requiresPress && !progress.actionConfirmed && !progress.completed {
                Button { scene.pressRelease() } label: { Label("Press the highlighted tab", systemImage: "hand.tap").font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).padding(10).background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(.red) }.disabled(scene.isAnimating).accessibilityIdentifier("pressRelease")
            }
            Button {
                progress.next(); applyCurrent()
            } label: {
                HStack { Text(progress.completed ? "Start Again" : progress.index == 0 ? "Power Is Off · Continue" : progress.index == progress.task.steps.count - 1 ? "Finish Guide" : "Next Step"); Spacer(); Image(systemName: "arrow.right") }.font(.system(size: 12, weight: .semibold)).padding(15).background(forest, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(paper)
            }.disabled(!scene.isLoaded || scene.isAnimating || (!progress.canAdvance && !progress.completed)).opacity(!progress.canAdvance && !progress.completed ? 0.45 : 1).accessibilityIdentifier("nextStep")
            HStack {
                Button { if progress.index > 0 { progress.go(to: progress.index - 1); applyCurrent() } } label: { Label("Back", systemImage: "arrow.left").font(.system(size: 10)) }.disabled(progress.index == 0)
                Spacer()
                Button { progress.actionConfirmed = false; exploring = false; scene.guide(progress.current, replay: true) } label: { Label("Replay action", systemImage: "arrow.counterclockwise").font(.system(size: 10)) }.disabled(!scene.isLoaded).accessibilityIdentifier("replayStep")
            }.padding(.top, 2)
        }.padding(18).background(.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 17))
    }
    private func applyCurrent(animated: Bool = true) {
        exploring = false
        if progress.completed { scene.setPose(.assembled) }
        else {
            // Rebuilding or leaving exploded view restores the virtual tab's
            // unpressed pose; its interaction gate must be restored with it.
            if progress.current.requiresPress { progress.actionConfirmed = false }
            scene.guide(progress.current, animated: animated)
        }
    }
    private func restoreStudio() {
        guard !showAR, !showAppleAR, !showAssembly, phase != .background else { return }
        _ = scene.makeView()
        if scene.isLoaded { applyCurrent(animated: false) }
    }
    private func closeModule() {
        scene.shutdown()
        onExit()
    }
    private var helpSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Learn by doing.").font(.title3.weight(.medium)); Spacer(); Button("Done") { showHelp = false } }
            Text("Follow the red arrows. Press the highlighted release tab, then move through the steps to watch each part move.").font(.body)
            Text("View in AR places a virtual purifier on a detected table. It does not align instructions to a real appliance.").font(.subheadline).foregroundStyle(muted)
            Text("Apple AR opens Apple's own AR Quick Look viewer for free placement. Choose its AR tab to see the model in your room. Use View in AR for the complete step-by-step lesson.").font(.subheadline).foregroundStyle(muted)
            Text("AERIS One is an original concept. The guide uses authored demonstration content, not an AI service or manufacturer-approved instructions. Use the actual device’s manual for real maintenance.").font(.caption).foregroundStyle(muted)
            Spacer()
        }.padding(25).padding(.top, 14).foregroundStyle(forest).background(paper)
    }
}

struct AppleARPreview: UIViewControllerRepresentable {
    let url: URL
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url) { isPresented = false }
    }
    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        preview.delegate = context.coordinator
        let done = UIBarButtonItem(title: "Done", style: .done, target: context.coordinator, action: #selector(Coordinator.close))
        done.accessibilityIdentifier = "closeAppleAR"
        preview.navigationItem.leftBarButtonItem = done
        return UINavigationController(rootViewController: preview)
    }
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let item: ARQuickLookPreviewItem
        let dismiss: () -> Void
        init(url: URL, dismiss: @escaping () -> Void) {
            item = ARQuickLookPreviewItem(fileAt: url)
            item.allowsContentScaling = true
            self.dismiss = dismiss
        }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { item }
        func previewControllerDidDismiss(_ controller: QLPreviewController) { dismiss() }
        @objc func close() { dismiss() }
    }
}
