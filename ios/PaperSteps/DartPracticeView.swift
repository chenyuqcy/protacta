import SwiftUI

/// Planar cues are sampled from the same authored fold geometry as the 3D
/// lesson. Their projection is an instruction, not measured paper deformation.
struct DartPracticeCueGeometry {
    let currentOutline: [CGPoint]
    let targetOutline: [CGPoint]
    let crease: [CGPoint]
    let movement: [[CGPoint]]

    init?(action: Int) {
        guard (1...10).contains(action), DartPracticeCourse.supportsPlanarCue(beforeState: action - 1),
              let current = DartOutlineChecker.outline(state: action - 1) else { return nil }
        let frame = PaperGeometry.frame(step: action, progress: 0)
        func point(_ vertex: SIMD3<Float>) -> CGPoint {
            CGPoint(x: CGFloat(vertex.x / PaperGeometry.width + 0.5), y: CGFloat(vertex.z / PaperGeometry.height + 0.5))
        }
        currentOutline = current
        targetOutline = DartOutlineChecker.outline(state: action) ?? []
        crease = frame.crease.map { [point($0.start), point($0.end)] } ?? []
        movement = frame.actionPaths.map { $0.map(point) }
    }
}

struct DartPracticeOverlay: View {
    @ObservedObject var controller: LessonController

    var body: some View {
        Canvas { context, size in
            if controller.isPaperGuideFixture {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.18)))
            }
            guard controller.paperGuide.status == .aligned,
                  let registration = controller.paperGuide.registration,
                  let cue = DartPracticeCueGeometry(action: controller.dartPractice.currentAction) else { return }
            func mapped(_ points: [CGPoint]) -> [CGPoint]? {
                let values = points.compactMap(registration.map)
                guard values.count == points.count else { return nil }
                return values.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            }
            func draw(_ points: [CGPoint], color: Color, closed: Bool = false, dashed: Bool = false) {
                guard let points = mapped(points), points.count > 1 else { return }
                var path = Path(); path.addLines(points)
                if closed { path.closeSubpath() }
                context.stroke(path, with: .color(.black.opacity(0.75)), lineWidth: 5)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: dashed ? [7, 5] : []))
            }
            if controller.isPaperGuideFixture, let points = mapped(cue.currentOutline) {
                var paper = Path(); paper.addLines(points); paper.closeSubpath()
                context.fill(paper, with: .color(.white))
            }
            draw(cue.currentOutline, color: .white.opacity(0.75), closed: true)
            draw(cue.targetOutline, color: .mint, closed: true, dashed: true)
            draw(cue.crease, color: .orange, dashed: true)
            for movement in cue.movement {
                draw(movement, color: .orange)
                if let end = mapped(movement)?.last, let points = mapped(movement),
                   let start = points.dropLast().reversed().first(where: { hypot($0.x - end.x, $0.y - end.y) > 12 }) {
                    let angle = atan2(end.y - start.y, end.x - start.x)
                    var head = Path()
                    head.move(to: CGPoint(x: end.x - 12 * cos(angle - 0.5), y: end.y - 12 * sin(angle - 0.5)))
                    head.addLine(to: end)
                    head.addLine(to: CGPoint(x: end.x - 12 * cos(angle + 0.5), y: end.y - 12 * sin(angle + 0.5)))
                    context.stroke(head, with: .color(.orange), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Printed paper practice guide")
        .accessibilityValue(controller.paperGuide.status.rawValue)
        .accessibilityIdentifier("practiceOverlay")
    }
}

struct DartPracticeCard<VoiceControls: View>: View {
    @ObservedObject var controller: LessonController
    let onOpenComparison: () -> Void
    let onPracticeToolsPresented: (Bool) -> Void
    @ViewBuilder var voiceControls: () -> VoiceControls
    @State private var presentedPracticeTool: PracticeTool?
    @State private var showComparison = false

    private enum PracticeTool: String, Identifiable {
        case setup, help
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(controller.dartPractice.completed ? "PRACTICE FINISHED" : "ACTION \(controller.dartPractice.currentAction) OF 10")
                        .font(.system(size: 11, weight: .bold)).tracking(1)
                        .accessibilityIdentifier("practiceCounter")
                    Spacer()
                    Button { presentPracticeTool(.setup) } label: { Image(systemName: "printer") }
                        .frame(minWidth: 44, minHeight: 32).accessibilityLabel("Practice paper and setup")
                        .accessibilityIdentifier("practiceSetup")
                }
                if controller.isPaperGuideFixture {
                    Text("SYNTHETIC UI FIXTURE — NOT A LIVE CAMERA")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.orange)
                        .accessibilityIdentifier("practiceFixtureLabel")
                }
                Text(controller.practiceAction.title).font(.system(size: 22, weight: .semibold))
                    .accessibilityIdentifier("practiceActionTitle")
                Text(controller.practiceMessage).font(.system(size: 13))
                    .accessibilityIdentifier("practiceCameraStatus")
                if !controller.dartPractice.completed {
                    Text(controller.practiceAction.instruction).font(.system(size: 15))
                    voiceControls()
                    Text("Orange: fold and movement · Green: target outline")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    if let result = controller.dartPractice.lastCheck {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(checkTitle(result.outcome), systemImage: checkIcon(result.outcome))
                                .font(.system(size: 13, weight: .semibold))
                            Text(result.message).font(.system(size: 13))
                            Text("Snapshot comparison · Visible outline only")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("practiceCheckResult")
                        if controller.practiceCheckSnapshot != nil {
                            Button {
                                guard controller.beginPracticeComparisonReview() else { return }
                                onOpenComparison()
                                showComparison = true
                            } label: {
                                Label("See this comparison", systemImage: "photo")
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }.buttonStyle(.bordered)
                                .accessibilityIdentifier("reviewPracticeComparison")
                        }
                    }
                    Button { controller.checkPracticeAction() } label: {
                        Label(controller.practiceCheckBusy ? "Checking…" : "Check my step", systemImage: "camera.viewfinder")
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }.buttonStyle(.bordered).disabled(controller.practiceCheckBusy)
                        .accessibilityIdentifier("checkPracticeStep")
                    Button { controller.confirmPracticeAction() } label: {
                        Text(controller.dartPractice.currentAction == 10 ? "I have finished · Save my progress" : "I have made this fold · Next action")
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }.buttonStyle(.borderedProminent).tint(.black).foregroundStyle(.white)
                        .accessibilityIdentifier("confirmPracticeAction")
                    Text("You confirm the physical action. The camera does not check hidden layers or advance for you.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text("All ten actions confirmed by you. Camera checks were limited to supported visible outlines.")
                        .font(.system(size: 14)).accessibilityIdentifier("practiceCompletion")
                    Text("\(controller.dartPractice.checkSummaries.count) comparison summaries saved on this device.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("Start again with a new practice sheet") { controller.restartDartPractice() }
                        .buttonStyle(.borderedProminent).tint(.black).foregroundStyle(.white)
                        .accessibilityIdentifier("restartPractice")
                }
                HStack {
                    Button("Previous action") { controller.previousPracticeAction() }
                        .disabled(controller.dartPractice.currentAction == 1 && !controller.dartPractice.completed)
                        .accessibilityIdentifier("previousPracticeAction")
                    Spacer()
                    Button("Watch in 3D") { controller.showPracticeActionIn3D() }
                        .accessibilityIdentifier("practice3DReference")
                }.font(.system(size: 12, weight: .semibold)).frame(minHeight: 44)
                HStack {
                    Button("Find sheet again") { controller.restartPaperGuideTracking() }
                        .accessibilityIdentifier("reacquirePractice")
                    Spacer()
                    Button("I'm stuck") { presentPracticeTool(.help) }.accessibilityIdentifier("practiceHelp")
                }.font(.system(size: 12)).frame(minHeight: 40)
                if controller.validationEnabled { PracticeValidationControls(controller: controller) }
                if controller.isPaperGuideFixture {
                    HStack {
                        Button("Lose sample") { controller.setDartPracticeFixtureVisible(false) }.accessibilityIdentifier("losePracticeFixture")
                        Button("Restore sample") { controller.setDartPracticeFixtureVisible(true) }.accessibilityIdentifier("restorePracticeFixture")
                    }.font(.caption)
                }
            }.padding(.horizontal, 22).padding(.vertical, 16)
        }.frame(maxHeight: 370).background(Color(red: 0.96, green: 0.96, blue: 0.93))
            .onChange(of: controller.practiceCheckSnapshot?.id) { _, id in
                if id == nil { showComparison = false }
            }
            .sheet(isPresented: $showComparison, onDismiss: { controller.endPracticeComparisonReview() }) {
                if let snapshot = controller.practiceCheckSnapshot {
                    DartCheckSnapshotView(snapshot: snapshot, action: DartPracticeCourse.action(snapshot.action)) {
                        controller.showPracticeActionIn3D()
                    }
                }
            }
            .onDisappear {
                // A compact-height sheet may cover its presenter. Clear on a
                // real mode exit; the parent also clears when its lesson exits.
                if !controller.isDartPractice { onPracticeToolsPresented(false) }
            }
            .sheet(item: $presentedPracticeTool, onDismiss: { onPracticeToolsPresented(false) }) { tool in
                switch tool {
                case .setup:
                    DartPracticeSetupView(controller: controller)
                case .help:
                    NavigationStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                Text(controller.practiceAction.instruction)
                                Text("Compare your paper").font(.headline)
                                Text(controller.practiceAction.manualCheckpoint)
                                Text("If you are stuck").font(.headline)
                                Text(controller.practiceAction.commonMistake)
                                Button("Watch this action in 3D") { presentedPracticeTool = nil; controller.showPracticeActionIn3D() }
                                    .buttonStyle(.borderedProminent).tint(.black).foregroundStyle(.white)
                            }.padding(24)
                        }.navigationTitle("Action \(controller.dartPractice.currentAction) help")
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { presentedPracticeTool = nil } } }
                    }
                }
            }
    }

    private func presentPracticeTool(_ tool: PracticeTool) {
        // Set the parent's routing gate synchronously, before SwiftUI presents
        // the modal. Keep it set through the dismissal animation; onDismiss
        // (or leaving this card) is the only path that clears it.
        onPracticeToolsPresented(true)
        presentedPracticeTool = tool
    }

    private func checkTitle(_ outcome: PaperCheckOutcome) -> String {
        switch outcome {
        case .visibleMatch: return "Visible outline matches"
        case .needsAdjustment: return "Compare the outline"
        case .cannotJudge: return "Cannot judge this view"
        }
    }
    private func checkIcon(_ outcome: PaperCheckOutcome) -> String {
        switch outcome {
        case .visibleMatch: return "checkmark.viewfinder"
        case .needsAdjustment: return "arrow.triangle.2.circlepath"
        case .cannotJudge: return "viewfinder"
        }
    }
}

struct DartPracticeSetupView: View {
    @ObservedObject var controller: LessonController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("One sheet, ten actions").font(.title2.bold())
                    Text("Print the practice PDF on white A4 paper at 100% / Actual Size. Turn off Fit to Page. Keep the codes on the visible face and both rows of codes at the end closest to you. The other short edge is the top.")
                    Text("Use the PTC2 revision 2 sheet supplied with this build. Earlier PTC1 sheets cannot establish alignment.")
                        .font(.footnote.weight(.semibold)).accessibilityIdentifier("practicePaperRevision")
                    if let file = Bundle.main.url(forResource: "Protacta_Dart_Practice_A4", withExtension: "pdf") {
                        ShareLink(item: file) { Label("Open or print the practice sheet", systemImage: "printer") }
                            .buttonStyle(.borderedProminent).tint(.black).foregroundStyle(.white)
                    }
                    Text("Use a plain dark mat, even light and a phone stand. Keep the full sheet and four codes visible; move your hands away before Check my step.")
                    Text("When the sheet is flat, the codes let the guide follow its position and direction. Folds that hide codes or lift the sheet use 3D reference and your own comparison.")
                    Text("A camera outline cannot prove a crease or hidden layer is correct. Check the authored comparison notes before confirming each action.")
                    Text(DartPracticeCourse.reviewNotice).font(.footnote).foregroundStyle(.secondary)
                    if controller.validationEnabled {
                        NavigationLink("Configure local validation samples") {
                            PracticeValidationSettingsView(controller: controller)
                        }.accessibilityIdentifier("openValidationSettings")
                    }
                }.padding(24)
            }.navigationTitle("Practice setup")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
