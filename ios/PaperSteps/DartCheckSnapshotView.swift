import SwiftUI

/// A historical comparison, rendered entirely from one immutable capture.
/// The camera image and annotations share its frozen viewport and transform.
struct DartCheckSnapshotView: View {
    let snapshot: DartCheckSnapshot
    let action: DartPracticeAction
    let onReplay: () -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Colors {
        static let ink = Color(red: 0.16, green: 0.22, blue: 0.20)
        static let background = Color(red: 0.96, green: 0.96, blue: 0.93)
        static let line = Color(red: 0.86, green: 0.88, blue: 0.84)
        static let outline = Color(red: 0.22, green: 0.92, blue: 0.52)
        static let comparison = Color(red: 0.95, green: 0.22, blue: 0.20)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if snapshot.isSynthetic {
                    Text("SYNTHETIC SAMPLE — NOT LIVE CAMERA")
                        .font(.system(size: 11, weight: .bold))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.orange.opacity(0.15))
                        .accessibilityIdentifier("comparisonSyntheticLabel")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ACTION \(snapshot.action) · FROZEN CAPTURE")
                                .font(.system(size: 11, weight: .bold)).tracking(1)
                                .foregroundStyle(.secondary)
                            Text(action.title).font(.system(size: 25, weight: .semibold))
                        }

                        snapshotCanvas
                        comparisonLegend

                        VStack(alignment: .leading, spacing: 9) {
                            Label(outcomeTitle, systemImage: outcomeIcon)
                                .font(.headline)
                            Text(snapshot.result.message).font(.subheadline)
                            Text("Visible outline only. This frozen capture is a comparison, not live approval. A camera outline cannot verify a crease, hidden layers or which fold caused a difference.")
                                .font(.footnote).foregroundStyle(.secondary)
                                .accessibilityIdentifier("comparisonScope")
                            Text("Before changing a fold, check that the guide aligns with the sheet, clear your hands and use even lighting.")
                                .font(.footnote)
                            if snapshot.action == 2 {
                                Text(DartPracticeCourse.creaseAmbiguityNote)
                                    .font(.footnote.weight(.semibold))
                                    .accessibilityIdentifier("comparisonCreaseUnknown")
                            }
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))

                        VStack(alignment: .leading, spacing: 16) {
                            guidance("Compare your paper", text: action.manualCheckpoint)
                            guidance("If you are stuck", text: action.commonMistake)
                            guidance("Why this action matters", text: action.explanation)
                            Text(DartPracticeCourse.reviewNotice)
                                .font(.footnote).foregroundStyle(.secondary)
                                .accessibilityIdentifier("comparisonDraftNotice")
                        }

                        VStack(spacing: 10) {
                            Button {
                                dismiss()
                                onReplay()
                            } label: {
                                Label("Replay this action", systemImage: "play.circle")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent).tint(Colors.ink).foregroundStyle(.white)
                            .accessibilityIdentifier("comparisonReplay")
                            Button("Return to camera") { dismiss() }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .buttonStyle(.bordered).tint(Colors.ink)
                                .accessibilityIdentifier("comparisonReturnToCamera")
                        }
                    }
                    .padding(20).frame(maxWidth: 740, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(Colors.ink).background(Colors.background)
            .navigationTitle("Captured comparison")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Return to camera")
                        .accessibilityIdentifier("comparisonClose")
                }
            }
        }
    }

    private var snapshotCanvas: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.clip(to: Path(bounds))
            context.fill(Path(bounds), with: .color(.black))

            // p(raw normalized) -> frozen normalized viewport -> Canvas pixels.
            // Scale each OUTPUT axis; rotating/mirroring the bitmap separately
            // would break correspondence with the already frozen annotations.
            let transform = snapshot.displayTransform
            let pixelTransform = CGAffineTransform(a: transform.a * size.width,
                                                    b: transform.b * size.height,
                                                    c: transform.c * size.width,
                                                    d: transform.d * size.height,
                                                    tx: transform.tx * size.width,
                                                    ty: transform.ty * size.height)
            var imageContext = context
            imageContext.concatenate(pixelTransform)
            imageContext.draw(Image(decorative: snapshot.cgImage, scale: 1, orientation: .up),
                              in: CGRect(x: 0, y: 0, width: 1, height: 1))

            func pixels(_ points: [CGPoint]) -> [CGPoint] {
                points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            }
            // Fill all overlapping ellipses in one non-zero-winding path so
            // they form one translucent mask, not stacked rings or counts of
            // separate mistakes. The reference stays legible above the mask.
            var comparisonAreas = Path()
            for point in pixels(snapshot.mismatchViewportPoints) {
                comparisonAreas.addEllipse(in: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24))
            }
            context.fill(comparisonAreas, with: .color(Colors.comparison.opacity(0.32)))

            let outline = pixels(snapshot.outlineViewportPoints)
            if outline.count >= 3 {
                var path = Path(); path.addLines(outline); path.closeSubpath()
                context.stroke(path, with: .color(.black.opacity(0.8)), lineWidth: 5)
                context.stroke(path, with: .color(Colors.outline),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
        .aspectRatio(viewportAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Colors.line, lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.isSynthetic ? "Frozen synthetic sample comparison" : "Frozen camera comparison")
        .accessibilityValue(canvasDescription)
        .accessibilityIdentifier("comparisonSnapshotCanvas")
    }

    private var comparisonLegend: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1).fill(Colors.outline).frame(width: 22, height: 3)
                Text("Green: reference outline")
            }
            HStack(spacing: 8) {
                Circle().fill(Colors.comparison.opacity(0.32)).frame(width: 16, height: 16)
                    .frame(width: 22)
                Text("Red shading: areas to compare")
            }
            if snapshot.outlineViewportPoints.isEmpty {
                Text("No registered reference outline is shown for this capture.")
                    .foregroundStyle(.secondary)
            }
        }.font(.footnote)
    }

    private func guidance(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.subheadline)
        }
    }

    private var viewportAspectRatio: CGFloat {
        let size = snapshot.viewportSize
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return 1 }
        return size.width / size.height
    }

    private var canvasDescription: String {
        switch snapshot.result.outcome {
        case .needsAdjustment:
            return "Reference outline and highlighted comparison areas. Visible outline only."
        case .visibleMatch:
            return "Reference outline only. No highlighted outline differences."
        case .cannotJudge:
            return snapshot.outlineViewportPoints.isEmpty
                ? "No registered reference outline. This capture cannot be judged. Compare the action manually."
                : "Reference outline for manual comparison. This capture cannot be judged."
        }
    }

    private var outcomeTitle: String {
        switch snapshot.result.outcome {
        case .visibleMatch: return "Visible outline matches"
        case .needsAdjustment: return "Compare the highlighted areas"
        case .cannotJudge: return "Cannot judge this capture"
        }
    }

    private var outcomeIcon: String {
        switch snapshot.result.outcome {
        case .visibleMatch: return "viewfinder"
        case .needsAdjustment: return "arrow.triangle.2.circlepath"
        case .cannotJudge: return "questionmark.circle"
        }
    }
}
