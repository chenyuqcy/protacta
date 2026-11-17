import SwiftUI

/// Shows physical landmarks from the learner's near edge, not camera pixels.
struct AlignmentPointDiagram: View {
    let index: Int
    let isShirt: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let left = width * 0.36, right = width * 0.64
            let top: CGFloat = 15, bottom: CGFloat = 70
            ZStack {
                Path { path in
                    if isShirt {
                        path.move(to: CGPoint(x: left, y: bottom))
                        path.addLine(to: CGPoint(x: left, y: 32))
                        path.addLine(to: CGPoint(x: left - 25, y: 38))
                        path.addLine(to: CGPoint(x: left - 32, y: 22))
                        path.addLine(to: CGPoint(x: left, y: top))
                        path.addLine(to: CGPoint(x: width * 0.46, y: 9))
                        path.addQuadCurve(to: CGPoint(x: width * 0.54, y: 9), control: CGPoint(x: width / 2, y: 25))
                        path.addLine(to: CGPoint(x: right, y: top))
                        path.addLine(to: CGPoint(x: right + 32, y: 22))
                        path.addLine(to: CGPoint(x: right + 25, y: 38))
                        path.addLine(to: CGPoint(x: right, y: 32))
                        path.addLine(to: CGPoint(x: right, y: bottom))
                        path.closeSubpath()
                    } else {
                        path.addRect(CGRect(x: left, y: top, width: right - left, height: bottom - top))
                    }
                }.fill(TutorialColors.orange.opacity(0.12))
                Path { path in
                    path.move(to: CGPoint(x: left, y: top))
                    path.addLine(to: CGPoint(x: left, y: bottom))
                    path.addLine(to: CGPoint(x: right, y: bottom))
                }.stroke(TutorialColors.ink.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ForEach(0..<3) { point in
                    Text("\(point + 1)").font(.system(size: 11, weight: .bold))
                        .frame(width: 23, height: 23)
                        .foregroundStyle(point == index ? .white : TutorialColors.ink)
                        .background(point == index ? TutorialColors.ink : TutorialColors.line, in: Circle())
                        .position(x: point == 1 ? right : left, y: point == 2 ? top : bottom)
                }
            }
        }
    }
}
