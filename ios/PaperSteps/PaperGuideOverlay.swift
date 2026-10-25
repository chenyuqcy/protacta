import SwiftUI

/// A camera-space drawing on a supported flat sheet, not a deforming 3D mesh.
struct PaperGuideOverlay: View {
    let session: PaperGuideSession
    let isFixture: Bool

    private let accent = Color(red: 0.90, green: 0.34, blue: 0.12)
    private let target = Color(red: 0.06, green: 0.52, blue: 0.43)

    var body: some View {
        Canvas { context, size in
            if isFixture {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.88)))
            }
            guard let quad = session.quadrilateral else { return }
            func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
            var outline = Path()
            outline.addLines(quad.points.map(screen))
            outline.closeSubpath()
            if isFixture { context.fill(outline, with: .color(.white)) }
            context.stroke(outline, with: .color(.black.opacity(0.5)), lineWidth: 5)
            context.stroke(outline, with: .color(session.directionConfirmed ? target : .yellow), lineWidth: 2)

            if session.status == .aligned, let registration = session.registration {
            func draw(_ points: [CGPoint], color: Color, dashed: Bool = false) {
                let mapped = points.compactMap(registration.map)
                guard mapped.count == points.count else { return }
                var path = Path()
                path.addLines(mapped.map(screen))
                context.stroke(path, with: .color(.white.opacity(0.95)), lineWidth: 6)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: dashed ? [7, 6] : []))
            }
            draw([CGPoint(x: 0.5, y: 0.03), CGPoint(x: 0.5, y: 0.97)], color: accent, dashed: true)
            draw([CGPoint(x: 0.97, y: 0.03), CGPoint(x: 0.97, y: 0.97)], color: target)
            draw([CGPoint(x: 0.12, y: 0.5), CGPoint(x: 0.87, y: 0.5)], color: accent)
            draw([CGPoint(x: 0.76, y: 0.42), CGPoint(x: 0.87, y: 0.5), CGPoint(x: 0.76, y: 0.58)], color: accent)
            }
            // TOP remains visible before confirmation so the person can resolve
            // the symmetry that rectangle detection cannot resolve by itself.
            if let preview = PaperRegistration(quadrilateral: quad),
               let top = preview.map(CGPoint(x: 0.5, y: 0.08)) {
                let position = screen(top)
                context.fill(Path(roundedRect: CGRect(x: position.x - 22, y: position.y - 12, width: 44, height: 24), cornerRadius: 6), with: .color(.white.opacity(0.95)))
                context.draw(Text("TOP").font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black), at: screen(top))
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Paper guide")
        .accessibilityValue(session.status.rawValue)
        .accessibilityIdentifier("paperGuideOverlay")
    }
}

struct PaperGuideCard: View {
    @ObservedObject var controller: LessonController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("On your paper", systemImage: "viewfinder")
                        .font(.system(size: 18, weight: .semibold))
                    Spacer()
                    Text("FIRST FOLD · A4").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                }
                if controller.isPaperGuideFixture {
                    Text("SYNTHETIC UI FIXTURE — NOT A LIVE CAMERA")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.orange)
                        .accessibilityIdentifier("paperGuideFixtureLabel")
                }
                Text(controller.paperGuideMessage).font(.system(size: 14))
                    .accessibilityIdentifier("paperGuideStatus")
                if controller.supportsCurrentPaperGuideStep {
                    HStack(spacing: 10) {
                        if !controller.paperGuide.directionConfirmed {
                            Button("Direction looks right") { controller.confirmPaperGuideDirection() }
                                .buttonStyle(.borderedProminent).tint(.black).foregroundStyle(.white)
                                .disabled(controller.paperGuide.quadrilateral == nil)
                                .accessibilityIdentifier("confirmPaperDirection")
                        }
                        Button("Turn guide") { controller.rotatePaperGuideDirection() }
                            .buttonStyle(.bordered)
                            .disabled(controller.paperGuide.quadrilateral == nil)
                            .accessibilityIdentifier("rotatePaperDirection")
                    }.font(.system(size: 13, weight: .medium))
                    Text("Keep the sheet flat and its corners visible. The camera aligns the guide; you decide when you have made the fold.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("I have made this fold · Continue in 3D") { controller.confirmFirstPaperFold() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("confirmFirstPaperFold")
                } else {
                    Button("Start with a new flat sheet") { controller.startPaperGuideWithNewSheet() }
                        .buttonStyle(.borderedProminent).tint(.black).foregroundStyle(.white)
                        .accessibilityIdentifier("restartPaperGuide")
                }
                HStack {
                    Button("Find sheet again") { controller.restartPaperGuideTracking() }
                        .accessibilityIdentifier("reacquirePaper")
                    Spacer()
                    Button("Watch the fold in 3D") { controller.showFirstFoldIn3D() }
                        .accessibilityIdentifier("paperGuideReference")
                }.font(.system(size: 12, weight: .medium)).frame(minHeight: 40)
                if controller.isPaperGuideFixture {
                    HStack {
                        Button("Lose sample") { controller.setPaperGuideFixtureVisible(false) }
                            .accessibilityIdentifier("losePaperFixture")
                        Button("Restore sample") { controller.setPaperGuideFixtureVisible(true) }
                            .accessibilityIdentifier("restorePaperFixture")
                    }.font(.caption)
                }
            }.padding(.horizontal, 22).padding(.vertical, 16)
        }.frame(maxHeight: 315).background(Color(red: 0.96, green: 0.96, blue: 0.93))
    }
}
