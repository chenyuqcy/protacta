import SwiftUI
import simd

enum FoldHelpAction {
    case replay, play, notes, steps, practice, paperGuide, setup
}

/// Secondary actions stay here so the object and the current move can lead.
struct FoldHelpPanel: View {
    @ObservedObject var controller: LessonController
    @ObservedObject var voice: VoiceGuide
    let onAction: (FoldHelpAction) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(controller.currentStep.title)
                        .font(.system(size: 25, weight: .medium)).tracking(-0.5)
                    if let comparison = DartFoldComparison(lesson: controller.lesson, stepIndex: controller.stepIndex) {
                        DartFoldComparisonView(comparison: comparison)
                    }
                    HStack(spacing: 12) {
                        Button { onAction(.replay) } label: {
                            Label("Replay", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }.accessibilityIdentifier("replayFromHelp")
                            .disabled(controller.stepIndex == 0 || !controller.canAnimate)
                        Button { controller.toggleSlowMotion() } label: {
                            Label(controller.slowMotion ? "½× speed" : "Slow down", systemImage: "tortoise")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }.accessibilityIdentifier("playbackSpeed")
                            .accessibilityValue(controller.slowMotion ? "Half speed" : "Normal speed")
                            .disabled(!controller.canAnimate)
                    }.buttonStyle(.bordered).tint(TutorialColors.ink)
                    if controller.stepIndex > 0 && !controller.completed {
                        HStack(spacing: 12) {
                            Button { onAction(.play) } label: {
                                Image(systemName: "play.fill").frame(width: 44, height: 44)
                            }.accessibilityLabel("Play fold").accessibilityIdentifier("playPause")
                            Slider(value: Binding(get: { controller.progress }, set: { controller.scrub(to: $0) }), in: 0...1,
                                   onEditingChanged: { editing in if editing { voice.stop() } })
                                .tint(TutorialColors.orange).accessibilityLabel("Fold progress")
                                .accessibilityIdentifier("foldProgress")
                        }.disabled(!controller.canAnimate)
                    }
                    if let help = FoldHelp.forStep(lesson: controller.lesson, stepIndex: controller.stepIndex) {
                        Text(help.simplerInstruction).font(.body).lineSpacing(4)
                            .accessibilityIdentifier("simplerInstruction")
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
                                .frame(minHeight: 44)
                        }.accessibilityIdentifier("readFoldHelp")
                            .disabled(!controller.canUseVoiceGuide && !voice.isSpeaking)
                        if voice.status != "Voice commands are off." {
                            Text(voice.status).font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("helpVoiceStatus")
                        }
                    }
                    VStack(spacing: 0) {
                        link("Why this fold?", symbol: "book.closed", id: "foldNotes", action: .notes)
                        Divider()
                        link("All steps", symbol: "list.bullet", id: "stepList", action: .steps)
                        Divider()
                        link("Set up your phone", symbol: "iphone", id: "helpPhoneSetup", action: .setup)
                        if controller.lesson == .dart {
                            Divider()
                            link(controller.practiceReferenceActive ? "Return to my practice" : "Practice with paper",
                                 symbol: "hand.draw", id: "openDartPractice", action: .practice)
                            Divider()
                            link("Align a flat A4 sheet", symbol: "viewfinder", id: "openPaperGuide", action: .paperGuide)
                        }
                    }
                    Text("Compare the guide with your paper. The 3D animation does not check your fold.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }.background(TutorialColors.paper)
                .navigationTitle("Help").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("closeFoldHelp")
                    }
                }
        }.foregroundStyle(TutorialColors.ink)
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }

    private func section(_ title: String, _ content: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(content).font(.subheadline).lineSpacing(4).foregroundStyle(.secondary)
                .accessibilityIdentifier(identifier)
        }
    }

    private func link(_ title: String, symbol: String, id: String, action: FoldHelpAction) -> some View {
        Button { onAction(action) } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }.font(.subheadline).frame(minHeight: 52).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
}

enum DartFoldComparison: Int {
    case closeBody = 7
    case firstWing = 8

    init?(lesson: OrigamiLesson, stepIndex: Int) {
        guard lesson == .dart else { return nil }
        self.init(rawValue: stepIndex)
    }

    var beforeDescription: String {
        switch self {
        case .closeBody: return "The nose points away and both halves are open. The left half moves."
        case .firstWing: return "The body is upright. The highlighted outer flap moves."
        }
    }

    var afterDescription: String {
        switch self {
        case .closeBody: return "The body is closed with its crease along the bottom and the nose layers outside."
        case .firstWing: return "The dashed outline marks the folded wing. The opposite flap stays upright."
        }
    }
}

private struct DartFoldComparisonView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let comparison: DartFoldComparison

    var body: some View {
        let before = Diagram(frame: PaperGeometry.frame(step: comparison.rawValue, progress: 0), showCrease: true)
        let after = Diagram(frame: PaperGeometry.frame(step: comparison.rawValue, progress: 1), showCrease: false)
        let extent = CGSize(width: max(before.bounds.width, after.bounds.width),
                            height: max(before.bounds.height, after.bounds.height))
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))

        VStack(alignment: .leading, spacing: 10) {
            Text("Before & after").font(.headline)
                .accessibilityIdentifier("dartFoldComparison")
            layout {
                panel("Before", diagram: before, extent: extent, description: comparison.beforeDescription)
                panel("After", diagram: after, extent: extent, description: comparison.afterDescription,
                      showFoldedWing: comparison == .firstWing)
            }
            if comparison == .firstWing {
                Text("Dashed outline shows the folded wing.")
                    .font(.footnote).foregroundStyle(TutorialColors.muted)
            }
        }
    }

    private func panel(_ label: String, diagram: Diagram, extent: CGSize, description: String,
                       showFoldedWing: Bool = false) -> some View {
        let foldedWing = showFoldedWing
            ? DartOutlineChecker.convexHull(diagram.faces.filter(\.moves).flatMap(\.points))
            : nil
        return VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.semibold))
            Canvas { context, size in
                let inset: CGFloat = 12
                let scale = min(max(0, size.width - 2 * inset) / extent.width,
                                max(0, size.height - 2 * inset) / extent.height)
                func point(_ projected: CGPoint) -> CGPoint {
                    CGPoint(x: size.width / 2 + (projected.x - diagram.bounds.midX) * scale,
                            y: size.height / 2 + (projected.y - diagram.bounds.midY) * scale)
                }

                for face in diagram.faces {
                    var path = Path()
                    path.addLines(face.points.map(point))
                    path.closeSubpath()
                    let paper = face.moves
                        ? Color(red: 0.62, green: 0.79, blue: 0.71)
                        : Color(red: 0.99, green: 0.98, blue: 0.93)
                    context.fill(path, with: .color(paper))
                    context.stroke(path, with: .color(TutorialColors.ink.opacity(0.58)), lineWidth: 0.7)
                }

                if let crease = diagram.crease {
                    var path = Path()
                    path.move(to: point(crease.start))
                    path.addLine(to: point(crease.end))
                    context.stroke(path, with: .color(Color(red: 0.64, green: 0.27, blue: 0.17)),
                                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 3]))
                }
                if let foldedWing {
                    // The folded flap sits against the body and can be hidden
                    // in this view. Trace its outline so the alignment is legible.
                    var path = Path()
                    path.addLines(foldedWing.map(point))
                    path.closeSubpath()
                    context.stroke(path, with: .color(TutorialColors.orange),
                                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [3, 3]))
                }
            }
            .frame(height: 112)
            .background(TutorialColors.line, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(description)")
        .accessibilityIdentifier(label == "Before" ? "dartFoldBefore" : "dartFoldAfter")
    }

    private struct Diagram {
        struct Face {
            let points: [CGPoint]
            let depth: Float
            let moves: Bool
        }

        let faces: [Face]
        let bounds: CGRect
        let crease: (start: CGPoint, end: CGPoint)?

        init(frame: PaperFrame, showCrease: Bool) {
            // Keep the same oblique view for both endpoints so the upright
            // body and its individual wing layers remain visible.
            let right = simd_normalize(SIMD3<Float>(0.82, 0, -0.57))
            let eye = simd_normalize(SIMD3<Float>(0.57, 0.62, 0.82))
            let up = simd_cross(eye, right)
            func project(_ point: SIMD3<Float>) -> CGPoint {
                CGPoint(x: CGFloat(simd_dot(point, right)), y: CGFloat(-simd_dot(point, up)))
            }

            faces = frame.faces.map { face in
                let vertices = face.vertices.map { $0.position + $0.separation }
                let depth = vertices.map { simd_dot($0, eye) }.reduce(0, +) / Float(vertices.count)
                return Face(points: vertices.map(project), depth: depth, moves: face.isMoving)
            }.sorted { $0.depth < $1.depth }
            let points = faces.flatMap(\.points)
            let x = points.map(\.x)
            let y = points.map(\.y)
            bounds = CGRect(x: x.min() ?? 0, y: y.min() ?? 0,
                            width: max(0.001, (x.max() ?? 0) - (x.min() ?? 0)),
                            height: max(0.001, (y.max() ?? 0) - (y.min() ?? 0)))
            crease = showCrease ? frame.crease.map { (project($0.start), project($0.end)) } : nil
        }
    }
}
