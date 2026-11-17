import SwiftUI
import simd

@main
struct ProtactaClipApp: App {
    var body: some Scene {
        WindowGroup {
            FirstFoldView()
                .preferredColorScheme(.light)
        }
    }
}

private struct FirstFoldView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var motion = EverydayMotionPlayback()
    private let ink = Color(red: 0.10, green: 0.21, blue: 0.17)
    private let background = Color(red: 0.97, green: 0.975, blue: 0.965)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image("ProtactaLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 108)
                    .accessibilityLabel("Protacta")

                VStack(alignment: .leading, spacing: 8) {
                    Text("CLASSIC DART · FIRST FOLD")
                        .font(.caption.weight(.semibold))
                        .tracking(1.7)
                    Text("Fold in half")
                        .font(.largeTitle.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Bring the left edge of an A4 sheet to the right edge. Press along the center crease.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                FoldStage(progress: motion.progress)
                    .aspectRatio(1.1, contentMode: .fit)
                    .accessibilityLabel("3D illustration of the center fold")

                HStack(spacing: 16) {
                    Button {
                        if motion.isPlaying { motion.pause() }
                        else { motion.play() }
                    } label: {
                        Image(systemName: playbackIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(ink, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(playbackLabel)

                    Slider(value: Binding(
                        get: { motion.progress },
                        set: { motion.seek(to: $0) }
                    ), in: 0...1) {
                        Text("Fold progress")
                    }
                    .accessibilityValue(motion.progress.formatted(.percent.precision(.fractionLength(0))))
                }
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .background(background.ignoresSafeArea())
        .foregroundStyle(ink)
        .tint(ink)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { motion.pause() }
        }
        .task(id: motion.isPlaying) {
            let clock = ContinuousClock()
            var previous = clock.now
            while motion.isPlaying, !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(16)) }
                catch { return }
                let now = clock.now
                let elapsed = previous.duration(to: now) / .seconds(1)
                motion.advance(elapsed: elapsed, allowed: scenePhase == .active)
                previous = now
            }
        }
    }

    private var playbackIcon: String {
        if motion.isPlaying { return "pause.fill" }
        return motion.progress == 1 ? "arrow.counterclockwise" : "play.fill"
    }

    private var playbackLabel: String {
        if motion.isPlaying { return "Pause fold" }
        return motion.progress == 1 ? "Replay fold" : "Play fold"
    }
}

private struct FoldStage: View {
    let progress: Double

    // A fixed, angled camera keeps the hinge in place while the paper moves.
    private let towardCamera = simd_normalize(SIMD3<Float>(0.30, 0.77, 0.56))
    private let paperEdge = Color(red: 0.30, green: 0.42, blue: 0.36)
    private let paperMint = Color(red: 0.77, green: 0.89, blue: 0.82)
    private let arrowColor = Color(red: 0.72, green: 0.28, blue: 0.09)

    var body: some View {
        Canvas { context, size in
            let right = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), towardCamera))
            let up = simd_cross(towardCamera, right)
            let scale = min(size.width, size.height) / 0.39
            func project(_ point: SIMD3<Float>) -> CGPoint {
                CGPoint(x: size.width * 0.5 + CGFloat(simd_dot(point, right)) * scale,
                        y: size.height * 0.54 - CGFloat(simd_dot(point, up)) * scale)
            }

            let frame = PaperGeometry.frame(step: 1, progress: Float(progress))
            let faces = frame.faces.sorted { depth(of: $0) < depth(of: $1) }
            for face in faces {
                let outline = path(face.vertices.map { project($0.position + $0.separation) }, closed: true)
                let color = face.isMoving ? paperMint : Color(red: 0.99, green: 0.99, blue: 0.95)
                context.fill(outline, with: .color(color))
                context.stroke(outline, with: .color(paperEdge), lineWidth: 1)
            }

            if let crease = frame.crease {
                context.stroke(
                    path([project(crease.start), project(crease.end)]),
                    with: .color(paperEdge),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 5])
                )
            }

            if progress < 0.12, let actionPath = frame.actionPaths.first {
                let points = actionPath.map(project)
                let color = arrowColor.opacity(1 - progress / 0.12)
                context.stroke(path(points), with: .color(color),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                if let tip = points.last, let previous = points.dropLast(2).last {
                    let angle = atan2(tip.y - previous.y, tip.x - previous.x)
                    let wings = [-0.48, 0.48].map { offset in
                        CGPoint(x: tip.x - cos(angle + offset) * 12,
                                y: tip.y - sin(angle + offset) * 12)
                    }
                    context.stroke(path([wings[0], tip, wings[1]]), with: .color(color),
                                   style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .background(Color(red: 0.88, green: 0.92, blue: 0.89), in: RoundedRectangle(cornerRadius: 24))
    }

    private func depth(of face: PaperFace) -> Float {
        let total = face.vertices.reduce(Float.zero) {
            $0 + simd_dot($1.position + $1.separation, towardCamera)
        }
        return total / Float(face.vertices.count)
    }

    private func path(_ points: [CGPoint], closed: Bool = false) -> Path {
        Path { outline in
            guard let first = points.first else { return }
            outline.move(to: first)
            for point in points.dropFirst() { outline.addLine(to: point) }
            if closed { outline.closeSubpath() }
        }
    }
}
