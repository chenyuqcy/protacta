import SwiftUI

/// Orthographic teaching projection of a flap turning around an in-plane
/// hinge. Halfway is edge-on; the target is an exact reflection. This is a
/// diagram, not a fabric simulation or a physical task assessment.
enum EverydayFoldProjection {
    static func points(_ points: [CGPoint], hingeStart: CGPoint, hingeEnd: CGPoint,
                       progress: Double) -> [CGPoint] {
        let dx = hingeEnd.x - hingeStart.x, dy = hingeEnd.y - hingeStart.y
        let length = hypot(dx, dy)
        guard length.isFinite, length > 0, progress.isFinite else { return points }
        let ux = dx / length, uy = dy / length
        let turn = cos(.pi * min(1, max(0, progress)))
        return points.map { point in
            let x = point.x - hingeStart.x, y = point.y - hingeStart.y
            let along = x * ux + y * uy
            let normalX = x - along * ux, normalY = y - along * uy
            return CGPoint(x: hingeStart.x + along * ux + normalX * turn,
                           y: hingeStart.y + along * uy + normalY * turn)
        }
    }
}

/// Step-specific visual reference. stepIndex is ZERO based; progress 0...1
/// represents only that action. No camera, recognition or file capture is used.
struct EverydayTutorialVisual: View {
    let courseID: String
    let stepIndex: Int
    let progress: Double
    var showsCaption = true
    var showsAnnotations = true
    var showsPartLabels = true

    var body: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                context.concatenate(CGAffineTransform(scaleX: size.width / 400, y: size.height / 430))
                EverydayDiagram.draw(courseID: courseID, stepIndex: stepIndex,
                                     progress: progress, annotations: showsAnnotations, partLabels: showsPartLabels, context: &context)
            }
            .aspectRatio(400.0 / 430.0, contentMode: .fit)
            .background(showsPartLabels ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Animated teaching diagram")
            .accessibilityValue(EverydayDiagram.accessibilityDescription(courseID: courseID, stepIndex: stepIndex, progress: progress))
            .accessibilityIdentifier("everydayTutorialVisual")
            if showsCaption {
            Text("Animated diagram · Compare with your own object.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("everydayVisualScope")
            }
        }
    }
}

private enum EverydayDiagram {
    static let ink = Color(red: 0.16, green: 0.22, blue: 0.20)
    static let muted = Color(red: 0.39, green: 0.46, blue: 0.42)
    static let blue = Color(red: 0.20, green: 0.46, blue: 0.69)
    static let orange = Color(red: 0.77, green: 0.31, blue: 0.16)
    static let cloth = Color(red: 0.78, green: 0.87, blue: 0.84)
    static let flap = Color(red: 0.60, green: 0.76, blue: 0.72)
    static let board = Color.white
    private static let squareCaptions = [
        "A over B → A moves to the right",
        "A under B → through the first gap",
        "A, now right, over B → to the left",
        "A under B → through the new gap",
        "Draw all four strands gently; dress the knot flat"
    ]
    private static let tieCaptions = [
        "W crosses in FRONT of N → diagram right",
        "W goes BEHIND N → diagram left",
        "W crosses the FRONT → hold this band open",
        "W goes UP through the neck loop from behind",
        "W goes DOWN through the front band",
        "Hold N; tighten W gently and slide the knot up",
        "Back view: tuck N into W's keeper; lower collar"
    ]

    private struct Mark {
        let title: String
        let point: CGPoint
        let moves: Bool
    }
    private struct FoldScene {
        let stationary: [[CGPoint]]
        let moving: [[CGPoint]]
        let hinge: [CGPoint]
        let marks: [Mark]
        let caption: String
    }

    static func draw(courseID: String, stepIndex: Int, progress: Double,
                     annotations: Bool, partLabels: Bool, context: inout GraphicsContext) {
        let p = finiteProgress(progress)
        if let scene = clothScene(courseID: courseID, step: stepIndex) {
            drawFold(scene, progress: p, annotations: annotations, partLabels: partLabels, context: &context)
        } else if courseID == "square_knot", (0..<5).contains(stepIndex) {
            drawSquareKnot(step: stepIndex, progress: p, annotations: annotations, partLabels: partLabels, context: &context)
        } else if courseID == "four_in_hand", (0..<7).contains(stepIndex) {
            drawTie(step: stepIndex, progress: p, annotations: annotations, partLabels: partLabels, context: &context)
        } else {
            text("Choose an action to see its diagram", at: CGPoint(x: 200, y: 210), context: &context)
        }
    }

    static func accessibilityDescription(courseID: String, stepIndex: Int, progress: Double) -> String {
        let phase = finiteProgress(progress) == 0 ? "Before movement" : finiteProgress(progress) == 1 ? "Target position" : "Movement in progress"
        let captions = courseID == "square_knot" ? squareCaptions : tieCaptions
        let action = clothScene(courseID: courseID, step: stepIndex)?.caption ??
            (captions.indices.contains(stepIndex) ? captions[stepIndex] : "Teaching reference")
        return "\(phase). \(action). Schematic reference only; compare manually."
    }

    private static func clip(_ polygon: [CGPoint], axis: Int, at value: CGFloat, keepLower: Bool) -> [CGPoint] {
        guard let last = polygon.last else { return [] }
        func coordinate(_ p: CGPoint) -> CGFloat { axis == 0 ? p.x : p.y }
        func inside(_ p: CGPoint) -> Bool { keepLower ? coordinate(p) <= value : coordinate(p) >= value }
        var result: [CGPoint] = [], previous = last
        for point in polygon {
            if inside(point) != inside(previous) {
                let amount = (value - coordinate(previous)) / (coordinate(point) - coordinate(previous))
                result.append(mix(previous, point, Double(amount)))
            }
            if inside(point) { result.append(point) }
            previous = point
        }
        return result
    }

    private static func folded(_ polygons: [[CGPoint]], _ hinge: [CGPoint]) -> [[CGPoint]] {
        polygons.map { EverydayFoldProjection.points($0, hingeStart: hinge[0], hingeEnd: hinge[1], progress: 1) }
    }

    private static func clothScene(courseID: String, step: Int) -> FoldScene? {
        if courseID == "t_shirt" { return shirtScene(step: step) }
        if courseID == "towel", (0..<3).contains(step) {
            let third: CGFloat = 200 / 3
            switch step {
            case 0:
                return FoldScene(stationary: [rectangle(100 + third, 80, third * 2, 270)],
                                 moving: [rectangle(100, 80, third, 270)],
                                 hinge: [CGPoint(x: 100 + third, y: 80), CGPoint(x: 100 + third, y: 350)],
                                 marks: [Mark(title: "L", point: CGPoint(x: 100, y: 200), moves: true),
                                         Mark(title: "R", point: CGPoint(x: 300, y: 200), moves: false)],
                                 caption: "Left third → across the middle third")
            case 1:
                return FoldScene(stationary: [rectangle(100 + third, 80, third, 270)],
                                 moving: [rectangle(100 + third * 2, 80, third, 270)],
                                 hinge: [CGPoint(x: 100 + third * 2, y: 80), CGPoint(x: 100 + third * 2, y: 350)],
                                 marks: [Mark(title: "R", point: CGPoint(x: 300, y: 200), moves: true),
                                         Mark(title: "L", point: CGPoint(x: 100 + third, y: 200), moves: false)],
                                 caption: "Right third → onto the folded stack")
            default:
                return FoldScene(stationary: [rectangle(100 + third, 80, third, 135)],
                                 moving: [rectangle(100 + third, 215, third, 135)],
                                 hinge: [CGPoint(x: 100 + third, y: 215), CGPoint(x: 100 + third * 2, y: 215)],
                                 marks: [Mark(title: "B", point: CGPoint(x: 200, y: 350), moves: true),
                                         Mark(title: "T", point: CGPoint(x: 200, y: 80), moves: false)],
                                 caption: "Bottom short edge → top short edge")
            }
        }
        if courseID == "flat_bedsheet", (0..<4).contains(step) {
            switch step {
            case 0:
                return FoldScene(stationary: [rectangle(200, 80, 100, 270)], moving: [rectangle(100, 80, 100, 270)],
                                 hinge: [CGPoint(x: 200, y: 80), CGPoint(x: 200, y: 350)],
                                 marks: [Mark(title: "A", point: CGPoint(x: 100, y: 80), moves: true),
                                         Mark(title: "D", point: CGPoint(x: 100, y: 350), moves: true),
                                         Mark(title: "B", point: CGPoint(x: 300, y: 80), moves: false),
                                         Mark(title: "C", point: CGPoint(x: 300, y: 350), moves: false)],
                                 caption: "Left long edge → right: A to B, D to C")
            case 1:
                return FoldScene(stationary: [rectangle(200, 80, 100, 135)], moving: [rectangle(200, 215, 100, 135)],
                                 hinge: [CGPoint(x: 200, y: 215), CGPoint(x: 300, y: 215)],
                                 marks: [Mark(title: "C/D", point: CGPoint(x: 300, y: 350), moves: true),
                                         Mark(title: "A/B", point: CGPoint(x: 300, y: 80), moves: false)],
                                 caption: "Bottom short edge → top; pair the corners")
            case 2:
                return FoldScene(stationary: [rectangle(250, 80, 50, 135)], moving: [rectangle(200, 80, 50, 135)],
                                 hinge: [CGPoint(x: 250, y: 80), CGPoint(x: 250, y: 215)],
                                 marks: [Mark(title: "L", point: CGPoint(x: 200, y: 150), moves: true),
                                         Mark(title: "R", point: CGPoint(x: 300, y: 150), moves: false)],
                                 caption: "Packet left edge → right edge")
            default:
                return FoldScene(stationary: [rectangle(250, 80, 50, 67.5)], moving: [rectangle(250, 147.5, 50, 67.5)],
                                 hinge: [CGPoint(x: 250, y: 147.5), CGPoint(x: 300, y: 147.5)],
                                 marks: [Mark(title: "B", point: CGPoint(x: 275, y: 215), moves: true),
                                         Mark(title: "T", point: CGPoint(x: 275, y: 80), moves: false)],
                                 caption: "Packet bottom edge → top edge")
            }
        }
        return nil
    }

    private static func shirtScene(step: Int) -> FoldScene? {
        guard (0..<6).contains(step) else { return nil }
        let body: [CGPoint] = [CGPoint(x: 120, y: 95), CGPoint(x: 170, y: 75), CGPoint(x: 185, y: 90),
                               CGPoint(x: 215, y: 90), CGPoint(x: 230, y: 75), CGPoint(x: 280, y: 95),
                               CGPoint(x: 300, y: 160), CGPoint(x: 300, y: 350), CGPoint(x: 100, y: 350), CGPoint(x: 100, y: 160)]
        let leftSleeve: [CGPoint] = [CGPoint(x: 120, y: 95), CGPoint(x: 55, y: 130), CGPoint(x: 80, y: 180), CGPoint(x: 100, y: 160)]
        let rightSleeve = leftSleeve.map { CGPoint(x: 400 - $0.x, y: $0.y) }
        let leftHinge = [CGPoint(x: 165, y: 75), CGPoint(x: 165, y: 350)]
        let rightHinge = [CGPoint(x: 235, y: 75), CGPoint(x: 235, y: 350)]
        let leftPanel = clip(body, axis: 0, at: 165, keepLower: true)
        let rightPanel = clip(body, axis: 0, at: 235, keepLower: false)
        let center = clip(clip(body, axis: 0, at: 165, keepLower: false), axis: 0, at: 235, keepLower: true)
        let leftIn = folded([leftPanel], leftHinge)
        let rightIn = folded([rightPanel], rightHinge)
        let sleeveLeftIn = folded([leftSleeve], leftHinge)
        let sleeveRightIn = folded([rightSleeve], rightHinge)
        let leftSeam = [CGPoint(x: 210, y: 95), CGPoint(x: 230, y: 160)]
        let rightSeam = [CGPoint(x: 190, y: 95), CGPoint(x: 170, y: 160)]
        let sleeveLeftTucked = folded(sleeveLeftIn, leftSeam)
        let sleeveRightTucked = folded(sleeveRightIn, rightSeam)
        switch step {
        case 0:
            return FoldScene(stationary: [center, rightPanel, rightSleeve], moving: [leftPanel, leftSleeve], hinge: leftHinge,
                             marks: [Mark(title: "L", point: CGPoint(x: 100, y: 300), moves: true)],
                             caption: "Left body panel → inward; sleeve moves with it")
        case 1:
            return FoldScene(stationary: [center, rightPanel, rightSleeve] + leftIn, moving: sleeveLeftIn, hinge: leftSeam,
                             marks: [Mark(title: "L", point: CGPoint(x: 275, y: 130), moves: true)],
                             caption: "Left sleeve → back and down inside the panel")
        case 2:
            return FoldScene(stationary: [center] + leftIn + sleeveLeftTucked, moving: [rightPanel, rightSleeve], hinge: rightHinge,
                             marks: [Mark(title: "R", point: CGPoint(x: 300, y: 300), moves: true)],
                             caption: "Right body panel → inward over the stack")
        case 3:
            return FoldScene(stationary: [center] + leftIn + rightIn + sleeveLeftTucked, moving: sleeveRightIn, hinge: rightSeam,
                             marks: [Mark(title: "R", point: CGPoint(x: 125, y: 130), moves: true)],
                             caption: "Right sleeve → back and down inside the panel")
        case 4:
            let upper = ([center] + leftIn + rightIn + sleeveLeftTucked + sleeveRightTucked).map {
                clip($0, axis: 1, at: 212.5, keepLower: true)
            }
            return FoldScene(stationary: upper, moving: [rectangle(165, 212.5, 70, 137.5)],
                             hinge: [CGPoint(x: 165, y: 212.5), CGPoint(x: 235, y: 212.5)],
                             marks: [Mark(title: "H", point: CGPoint(x: 200, y: 350), moves: true),
                                     Mark(title: "T", point: CGPoint(x: 200, y: 75), moves: false)],
                             caption: "Bottom hem → shoulder edge; fold height in half")
        default:
            return FoldScene(stationary: [rectangle(165, 75, 70, 68.75)], moving: [rectangle(165, 143.75, 70, 68.75)],
                             hinge: [CGPoint(x: 165, y: 143.75), CGPoint(x: 235, y: 143.75)],
                             marks: [Mark(title: "B", point: CGPoint(x: 200, y: 212.5), moves: true),
                                     Mark(title: "T", point: CGPoint(x: 200, y: 75), moves: false)],
                             caption: "Packet bottom → top; fold height in half again")
        }
    }

    private static func drawFold(_ scene: FoldScene, progress: Double, annotations: Bool, partLabels: Bool, context: inout GraphicsContext) {
        let points = (scene.stationary + scene.moving).flatMap { $0 }
        let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 400
        let minY = points.map(\.y).min() ?? 0, maxY = points.map(\.y).max() ?? 400
        let scale = min(270 / max(1, maxX - minX), 255 / max(1, maxY - minY))
        func display(_ p: CGPoint) -> CGPoint {
            CGPoint(x: 200 + (p.x - (minX + maxX) / 2) * scale,
                    y: 222 + (p.y - (minY + maxY) / 2) * scale)
        }
        if annotations { text(scene.caption, at: CGPoint(x: 200, y: 25), size: 12, weight: .semibold, context: &context) }
        if annotations { text("Top / far edge ↑ · View from above", at: CGPoint(x: 200, y: 47), size: 11, color: muted, context: &context) }
        for shape in scene.stationary { patch(shape.map(display), context: &context) }
        let target = folded(scene.moving, scene.hinge)
        for shape in target {
            let outline = polygon(shape.map(display))
            context.stroke(outline, with: .color(orange.opacity(0.65)), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
        }
        for shape in scene.moving {
            let turned = EverydayFoldProjection.points(shape, hingeStart: scene.hinge[0], hingeEnd: scene.hinge[1], progress: progress)
            patch(turned.map(display), fill: progress < 0.5 ? flap : cloth.opacity(0.94), context: &context)
        }
        line(scene.hinge.map(display), color: orange, width: 2, dashed: true, context: &context)
        for mark in scene.marks {
            let target = EverydayFoldProjection.points([mark.point], hingeStart: scene.hinge[0], hingeEnd: scene.hinge[1], progress: 1)[0]
            if mark.moves { arrow(from: display(mark.point), to: display(target), bend: 26, context: &context) }
            let point = mark.moves ? EverydayFoldProjection.points([mark.point], hingeStart: scene.hinge[0], hingeEnd: scene.hinge[1], progress: progress)[0] : mark.point
            var shown = display(point)
            if !mark.moves { shown.x += 22 }
            if partLabels { badge(mark.title, at: shown, color: mark.moves ? orange : ink, context: &context) }
        }
        if annotations { text("Orange dashes: fold line + target edge", at: CGPoint(x: 200, y: 389), size: 11, color: muted, context: &context) }
        if annotations { text("\(progress == 0 ? "Before" : progress == 1 ? "Target" : "Moving") · diagram scale adjusts between actions", at: CGPoint(x: 200, y: 409), size: 10, color: muted, context: &context) }
    }

    private static func smoothPath(_ points: [CGPoint]) -> Path {
        guard let first = points.first else { return Path() }
        var path = Path(); path.move(to: first)
        guard points.count > 2 else { path.addLines(points); return path }
        for index in 1..<(points.count - 1) {
            let end = mix(points[index], points[index + 1], 0.5)
            path.addQuadCurve(to: end, control: points[index])
        }
        if let last = points.last { path.addLine(to: last) }
        return path
    }

    private static func strand(_ points: [CGPoint], color: Color, width: CGFloat = 11,
                               front: Bool = false, context: inout GraphicsContext) {
        let path = smoothPath(points)
        let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        if front {
            context.stroke(path, with: .color(board), style: StrokeStyle(lineWidth: width + 5, lineCap: .round, lineJoin: .round))
        }
        context.stroke(path, with: .color(ink.opacity(0.65)), style: StrokeStyle(lineWidth: width + 2, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(color), style: style)
    }

    /// Equal-distance sampling keeps the same material end at the end of a
    /// route while its action changes shape. It does not model rope contact.
    private static func route(_ points: [CGPoint], count: Int = 49) -> [CGPoint] {
        guard points.count > 1 else { return points }
        var lengths: [CGFloat] = [0]
        for pair in zip(points, points.dropFirst()) { lengths.append(lengths.last! + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)) }
        let length = lengths.last!
        return (0..<count).map { index in
            let distance = length * CGFloat(index) / CGFloat(count - 1)
            let segment = min(points.count - 2, max(0, (lengths.lastIndex(where: { $0 <= distance }) ?? 0)))
            let portion = (distance - lengths[segment]) / max(0.0001, lengths[segment + 1] - lengths[segment])
            return mix(points[segment], points[segment + 1], Double(portion))
        }
    }

    private static func movingRoute(_ start: [CGPoint], _ end: [CGPoint], progress: Double) -> [CGPoint] {
        zip(route(start), route(end)).map { mix($0.0, $0.1, progress) }
    }

    private static func squareRoutes(state: Int) -> (a: [CGPoint], b: [CGPoint]) {
        let firstA = [CGPoint(x: 85, y: 340), CGPoint(x: 135, y: 280), CGPoint(x: 175, y: 248),
                      CGPoint(x: 222, y: 260), CGPoint(x: 247, y: 236), CGPoint(x: 223, y: 214), CGPoint(x: 194, y: 225)]
        let firstB = [CGPoint(x: 315, y: 340), CGPoint(x: 263, y: 280), CGPoint(x: 225, y: 248),
                      CGPoint(x: 178, y: 260), CGPoint(x: 153, y: 236), CGPoint(x: 177, y: 214), CGPoint(x: 206, y: 225)]
        switch state {
        case 0:
            return ([CGPoint(x: 85, y: 340), CGPoint(x: 120, y: 110)],
                    [CGPoint(x: 315, y: 340), CGPoint(x: 280, y: 110)])
        case 1:
            return ([CGPoint(x: 85, y: 340), CGPoint(x: 155, y: 245), CGPoint(x: 200, y: 220), CGPoint(x: 280, y: 110)],
                    [CGPoint(x: 315, y: 340), CGPoint(x: 245, y: 245), CGPoint(x: 200, y: 220), CGPoint(x: 120, y: 110)])
        case 2:
            return (firstA + [CGPoint(x: 200, y: 200), CGPoint(x: 250, y: 150), CGPoint(x: 290, y: 105)],
                    firstB + [CGPoint(x: 200, y: 200), CGPoint(x: 150, y: 150), CGPoint(x: 110, y: 105)])
        case 3:
            return (firstA + [CGPoint(x: 245, y: 180), CGPoint(x: 205, y: 140), CGPoint(x: 115, y: 95)],
                    firstB + [CGPoint(x: 155, y: 180), CGPoint(x: 195, y: 140), CGPoint(x: 285, y: 95)])
        case 4:
            return (firstA + [CGPoint(x: 248, y: 192), CGPoint(x: 250, y: 155), CGPoint(x: 223, y: 134),
                             CGPoint(x: 187, y: 154), CGPoint(x: 150, y: 125), CGPoint(x: 95, y: 100)],
                    firstB + [CGPoint(x: 152, y: 192), CGPoint(x: 150, y: 155), CGPoint(x: 177, y: 134),
                             CGPoint(x: 213, y: 154), CGPoint(x: 250, y: 125), CGPoint(x: 305, y: 100)])
        default:
            // Two interlocking bights, with the blue end and blue standing
            // part leaving together on the left; orange leaves on the right.
            return ([CGPoint(x: 70, y: 285), CGPoint(x: 140, y: 250), CGPoint(x: 185, y: 238),
                     CGPoint(x: 225, y: 252), CGPoint(x: 255, y: 240), CGPoint(x: 263, y: 213),
                     CGPoint(x: 246, y: 188), CGPoint(x: 215, y: 185), CGPoint(x: 180, y: 201),
                     CGPoint(x: 140, y: 186), CGPoint(x: 70, y: 160)],
                    [CGPoint(x: 330, y: 285), CGPoint(x: 260, y: 250), CGPoint(x: 215, y: 238),
                     CGPoint(x: 175, y: 252), CGPoint(x: 145, y: 240), CGPoint(x: 137, y: 213),
                     CGPoint(x: 154, y: 188), CGPoint(x: 185, y: 185), CGPoint(x: 220, y: 201),
                     CGPoint(x: 260, y: 186), CGPoint(x: 330, y: 160)])
        }
    }

    private static func drawSquareKnot(step: Int, progress: Double, annotations: Bool, partLabels: Bool, context: inout GraphicsContext) {
        let before = squareRoutes(state: step), target = squareRoutes(state: step + 1)
        let a = movingRoute(before.a, target.a, progress: progress)
        let b = movingRoute(before.b, target.b, progress: progress)
        if annotations { text(squareCaptions[step], at: CGPoint(x: 200, y: 24), size: 12, weight: .semibold, context: &context) }
        if annotations { text("A = blue · B = orange · loose practice cord", at: CGPoint(x: 200, y: 47), size: 11, color: muted, context: &context) }
        strand(a, color: blue, context: &context)
        strand(b, color: orange, context: &context)
        // The highlighted crossing, rather than a same-color X, explicitly
        // tells the learner which strand passes in front of the other.
        if step == 0 {
            strand(a, color: blue, front: true, context: &context)
        } else if step == 1 {
            strand(Array(a[10...21]), color: blue, front: true, context: &context)
            strand(Array(b[22...33]), color: orange, front: true, context: &context)
        } else if step == 2 {
            strand(Array(a[32...48]), color: blue, front: true, context: &context)
            strand(Array(a[9...18]), color: blue, front: true, context: &context)
        } else if step == 3 {
            strand(Array(a[9...17]), color: blue, front: true, context: &context)
            strand(Array(b[30...40]), color: orange, front: true, context: &context)
        } else {
            strand(Array(a[9...17]), color: blue, front: true, context: &context)
            strand(Array(b[30...39]), color: orange, front: true, context: &context)
        }
        if let endA = a.last, let endB = b.last {
            if partLabels { badge("A", at: CGPoint(x: endA.x, y: endA.y - 19), color: blue, context: &context) }
            if partLabels { badge("B", at: CGPoint(x: endB.x, y: endB.y - 19), color: orange, context: &context) }
        }
        let note: String
        switch step {
        case 0:
            arrow(from: CGPoint(x: 125, y: 90), to: CGPoint(x: 280, y: 90), bend: 10, context: &context)
            note = "A passes OVER the orange strand"
        case 1:
            arrow(from: CGPoint(x: 264, y: 194), to: CGPoint(x: 205, y: 226), bend: 23, context: &context)
            if partLabels { text("UNDER", at: CGPoint(x: 299, y: 220), size: 10, color: blue, weight: .bold, context: &context) }
            note = "Feed A under B and out through the first gap"
        case 2:
            arrow(from: CGPoint(x: 280, y: 77), to: CGPoint(x: 115, y: 77), bend: 9, context: &context)
            note = "Reverse the direction: A moves right → left"
        case 3:
            arrow(from: CGPoint(x: 163, y: 126), to: CGPoint(x: 225, y: 158), bend: 19, context: &context)
            if partLabels { text("UNDER", at: CGPoint(x: 105, y: 160), size: 10, color: blue, weight: .bold, context: &context) }
            note = "Feed A under B through the new upper gap"
        default:
            for (from, to) in [(CGPoint(x: 108, y: 163), CGPoint(x: 58, y: 143)),
                               (CGPoint(x: 105, y: 284), CGPoint(x: 58, y: 305)),
                               (CGPoint(x: 292, y: 163), CGPoint(x: 342, y: 143)),
                               (CGPoint(x: 295, y: 284), CGPoint(x: 342, y: 305))] {
                arrow(from: from, to: to, context: &context)
            }
            note = "Matching colors leave together; compare both bights"
        }
        if annotations { text(note, at: CGPoint(x: 200, y: 383), size: 11, color: muted, context: &context) }
        if annotations { text("Practice only · Not for supporting weight", at: CGPoint(x: 200, y: 407), size: 11, color: muted, context: &context) }
    }

    private static func tieRoute(state: Int) -> [CGPoint] {
        let first = [CGPoint(x: 155, y: 115), CGPoint(x: 145, y: 170), CGPoint(x: 195, y: 211)]
        let wrap = first + [CGPoint(x: 244, y: 227), CGPoint(x: 224, y: 247), CGPoint(x: 170, y: 252)]
        let band = wrap + [CGPoint(x: 185, y: 271), CGPoint(x: 236, y: 278)]
        switch state {
        case 0: return [CGPoint(x: 155, y: 115), CGPoint(x: 142, y: 190), CGPoint(x: 135, y: 275), CGPoint(x: 130, y: 355)]
        case 1: return first + [CGPoint(x: 250, y: 250), CGPoint(x: 287, y: 325)]
        case 2: return wrap + [CGPoint(x: 125, y: 310)]
        case 3: return band + [CGPoint(x: 285, y: 315)]
        case 4: return band + [CGPoint(x: 251, y: 249), CGPoint(x: 224, y: 202), CGPoint(x: 200, y: 151), CGPoint(x: 200, y: 87)]
        case 5: return band + [CGPoint(x: 251, y: 249), CGPoint(x: 224, y: 202), CGPoint(x: 200, y: 151),
                               CGPoint(x: 202, y: 105), CGPoint(x: 233, y: 145), CGPoint(x: 218, y: 212),
                               CGPoint(x: 203, y: 267), CGPoint(x: 199, y: 350)]
        default:
            return [CGPoint(x: 155, y: 115), CGPoint(x: 155, y: 165), CGPoint(x: 197, y: 182),
                    CGPoint(x: 230, y: 191), CGPoint(x: 211, y: 207), CGPoint(x: 176, y: 206),
                    CGPoint(x: 191, y: 227), CGPoint(x: 225, y: 226), CGPoint(x: 228, y: 199),
                    CGPoint(x: 201, y: 169), CGPoint(x: 202, y: 135), CGPoint(x: 220, y: 165),
                    CGPoint(x: 203, y: 220), CGPoint(x: 199, y: 350)]
        }
    }

    private static func drawTie(step: Int, progress: Double, annotations: Bool, partLabels: Bool, context: inout GraphicsContext) {
        if annotations { text(tieCaptions[step], at: CGPoint(x: 200, y: 24), size: 12, weight: .semibold, context: &context) }
        if step == 6 { drawTieKeeper(progress: progress, annotations: annotations, partLabels: partLabels, context: &context); return }
        if annotations { text("Front view · your right is diagram left", at: CGPoint(x: 200, y: 47), size: 11, color: muted, context: &context) }
        // Neck/collar context, not an extra rope strand.
        var neck = Path(); neck.move(to: CGPoint(x: 155, y: 115))
        neck.addCurve(to: CGPoint(x: 245, y: 115), control1: CGPoint(x: 110, y: 55), control2: CGPoint(x: 290, y: 55))
        neck.addCurve(to: CGPoint(x: 155, y: 115), control1: CGPoint(x: 270, y: 205), control2: CGPoint(x: 130, y: 205))
        context.stroke(neck, with: .color(muted.opacity(0.35)), lineWidth: 4)
        // On action 3, keep the already completed rear wrap fixed while its
        // active tail sweeps across the front. A complete target band must not
        // appear in the Before view before this movement has happened.
        let formingBand: [CGPoint]? = step == 2 ? movingRoute(
            [CGPoint(x: 170, y: 252), CGPoint(x: 125, y: 310)],
            [CGPoint(x: 170, y: 252), CGPoint(x: 185, y: 271), CGPoint(x: 236, y: 278), CGPoint(x: 285, y: 315)],
            progress: progress) : nil
        let w = formingBand.map { route(Array(tieRoute(state: 2).dropLast()) + Array($0.dropFirst())) } ??
            movingRoute(tieRoute(state: step), tieRoute(state: step + 1), progress: progress)
        let narrow = [CGPoint(x: 245, y: 115), CGPoint(x: 224, y: 222), CGPoint(x: 218, y: 325)]
        strand(w, color: blue, width: 24, context: &context)
        strand(narrow, color: orange, width: 10, context: &context)
        // Restore the first front crossing while the next segment goes behind.
        if step > 0 || progress > 0.3 {
            let cross = [CGPoint(x: 151, y: 176), CGPoint(x: 195, y: 211), CGPoint(x: 240, y: 228)]
            strand(cross, color: blue, width: 24, front: true, context: &context)
        }
        if let formingBand {
            strand(formingBand, color: blue, width: 24, front: true, context: &context)
        } else if step >= 3 {
            let height = step == 5 ? 271 - 60 * progress : 271
            strand([CGPoint(x: 174, y: height - 15), CGPoint(x: 191, y: height), CGPoint(x: 235, y: height + 5)],
                   color: blue, width: 24, front: true, context: &context)
        }
        // The down-going active W exits in front after threading the open band.
        if step >= 4 {
            let tailStart = step == 5 ? 267 - 50 * progress : 267
            let endpoint = w.last ?? CGPoint(x: 199, y: 350)
            if endpoint.y > tailStart {
                strand([CGPoint(x: 203, y: tailStart), endpoint], color: blue, width: 24, front: true, context: &context)
            }
        }
        if let tip = w.last {
            let previous = w[max(0, w.count - 3)]
            let angle = atan2(tip.y - previous.y, tip.x - previous.x)
            let left = CGPoint(x: tip.x - 14 * sin(angle) - 18 * cos(angle), y: tip.y + 14 * cos(angle) - 18 * sin(angle))
            let right = CGPoint(x: tip.x + 14 * sin(angle) - 18 * cos(angle), y: tip.y - 14 * cos(angle) - 18 * sin(angle))
            patch([left, tip, right], fill: blue, context: &context)
            if partLabels { badge("W", at: CGPoint(x: tip.x + (tip.x < 200 ? -28 : 28), y: tip.y), color: blue, context: &context) }
        }
        if partLabels { badge("N", at: CGPoint(x: 243, y: 327), color: orange, context: &context) }
        switch step {
        case 0:
            arrow(from: CGPoint(x: 115, y: 288), to: CGPoint(x: 285, y: 290), bend: 18, context: &context)
            if partLabels { text("FRONT", at: CGPoint(x: 291, y: 206), size: 10, color: blue, weight: .bold, context: &context) }
        case 1:
            arrow(from: CGPoint(x: 284, y: 294), to: CGPoint(x: 122, y: 282), bend: 14, context: &context)
            if partLabels { text("BEHIND N", at: CGPoint(x: 298, y: 248), size: 10, color: blue, weight: .bold, context: &context) }
        case 2:
            arrow(from: CGPoint(x: 120, y: 302), to: CGPoint(x: 282, y: 302), bend: 20, context: &context)
            if partLabels { text("OPEN BAND", at: CGPoint(x: 299, y: 271), size: 10, color: blue, weight: .bold, context: &context) }
        case 3:
            arrow(from: CGPoint(x: 278, y: 294), to: CGPoint(x: 208, y: 98), bend: 27, context: &context)
            if partLabels { text("UP / UNDER", at: CGPoint(x: 294, y: 151), size: 10, color: blue, weight: .bold, context: &context) }
        case 4:
            arrow(from: CGPoint(x: 274, y: 139), to: CGPoint(x: 263, y: 326), bend: 22, context: &context)
            if partLabels { text("THROUGH BAND", at: CGPoint(x: 300, y: 248), size: 9, color: blue, weight: .bold, context: &context) }
        default:
            arrow(from: CGPoint(x: 160, y: 280), to: CGPoint(x: 160, y: 202), bend: -13, context: &context)
            arrow(from: CGPoint(x: 202, y: 304), to: CGPoint(x: 202, y: 361), context: &context)
            if partLabels { text("HOLD N", at: CGPoint(x: 285, y: 323), size: 10, color: orange, weight: .bold, context: &context) }
        }
        if annotations { text("W = wide / active end · N = narrow / held end", at: CGPoint(x: 200, y: 391), size: 11, color: muted, context: &context) }
        if annotations { text("White gaps at crossings show which layer is behind", at: CGPoint(x: 200, y: 411), size: 10, color: muted, context: &context) }
    }

    private static func drawTieKeeper(progress: Double, annotations: Bool, partLabels: Bool, context: inout GraphicsContext) {
        if annotations { text("Back of the wide end · N slides into the keeper", at: CGPoint(x: 200, y: 47), size: 11, color: muted, context: &context) }
        patch([CGPoint(x: 165, y: 100), CGPoint(x: 235, y: 100), CGPoint(x: 235, y: 325),
               CGPoint(x: 200, y: 355), CGPoint(x: 165, y: 325)], fill: blue.opacity(0.22), context: &context)
        let end = mix(CGPoint(x: 286, y: 178), CGPoint(x: 200, y: 311), progress)
        let route = [CGPoint(x: 200, y: 102), CGPoint(x: 212, y: 161),
                     mix(CGPoint(x: 273, y: 160), CGPoint(x: 200, y: 213), progress), end]
        strand(route, color: orange, width: 12, context: &context)
        patch(rectangle(156, 229, 88, 22), fill: flap, context: &context)
        line([CGPoint(x: 165, y: 229), CGPoint(x: 165, y: 251)], color: ink, context: &context)
        line([CGPoint(x: 235, y: 229), CGPoint(x: 235, y: 251)], color: ink, context: &context)
        if partLabels { badge("N", at: CGPoint(x: end.x + 24, y: end.y), color: orange, context: &context) }
        if partLabels { text("KEEPER", at: CGPoint(x: 292, y: 240), size: 10, color: muted, weight: .bold, context: &context) }
        arrow(from: CGPoint(x: 279, y: 193), to: CGPoint(x: 205, y: 275), bend: -16, context: &context)
        let collarDrop = max(0, (progress - 0.65) / 0.35)
        let leftCollar = [CGPoint(x: 153, y: 81), CGPoint(x: 195, y: 87),
                          CGPoint(x: 175, y: 67 + 55 * collarDrop)]
        let rightCollar = leftCollar.map { CGPoint(x: 400 - $0.x, y: $0.y) }
        patch(leftCollar, fill: cloth, context: &context); patch(rightCollar, fill: cloth, context: &context)
        if annotations { text("Then lower the collar and adjust gently", at: CGPoint(x: 200, y: 391), size: 11, color: muted, context: &context) }
        if annotations { text("Back view for the keeper · Collar motion is schematic", at: CGPoint(x: 200, y: 411), size: 10, color: muted, context: &context) }
    }

    static func finiteProgress(_ progress: Double) -> Double {
        progress.isFinite ? min(1, max(0, progress)) : 0
    }

    static func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }

    static func rectangle(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> [CGPoint] {
        [CGPoint(x: x, y: y), CGPoint(x: x + width, y: y),
         CGPoint(x: x + width, y: y + height), CGPoint(x: x, y: y + height)]
    }

    static func mix(_ a: CGPoint, _ b: CGPoint, _ progress: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress)
    }

    static func text(_ text: String, at point: CGPoint, size: CGFloat = 13,
                     color: Color = ink, weight: Font.Weight = .medium,
                     context: inout GraphicsContext) {
        context.draw(Text(text).font(.system(size: size, weight: weight)).foregroundStyle(color), at: point)
    }

    static func line(_ points: [CGPoint], color: Color = ink, width: CGFloat = 2,
                     dashed: Bool = false, context: inout GraphicsContext) {
        guard points.count >= 2 else { return }
        var path = Path(); path.addLines(points)
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round,
                                          lineJoin: .round, dash: dashed ? [6, 5] : []))
    }

    static func patch(_ points: [CGPoint], fill: Color = cloth,
                      context: inout GraphicsContext) {
        guard points.count >= 3 else { return }
        let path = polygon(points)
        context.fill(path, with: .color(fill))
        context.stroke(path, with: .color(ink),
                       style: StrokeStyle(lineWidth: 2, lineJoin: .round))
    }

    static func badge(_ title: String, at point: CGPoint, color: Color = ink,
                      context: inout GraphicsContext) {
        let rect = CGRect(x: point.x - 13, y: point.y - 13, width: 26, height: 26)
        context.fill(Path(ellipseIn: rect), with: .color(board))
        context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 1.5)
        text(title, at: point, size: 12, color: color, weight: .bold, context: &context)
    }

    static func arrow(from: CGPoint, to: CGPoint, bend: CGFloat = 0,
                      context: inout GraphicsContext) {
        guard hypot(to.x - from.x, to.y - from.y) > 1 else { return }
        let mid = CGPoint(x: (from.x + to.x) / 2 + bend,
                          y: (from.y + to.y) / 2 - abs(bend))
        var path = Path(); path.move(to: from); path.addQuadCurve(to: to, control: mid)
        context.stroke(path, with: .color(orange), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        let angle = atan2(to.y - mid.y, to.x - mid.x)
        let left = CGPoint(x: to.x - 10 * cos(angle - 0.45), y: to.y - 10 * sin(angle - 0.45))
        let right = CGPoint(x: to.x - 10 * cos(angle + 0.45), y: to.y - 10 * sin(angle + 0.45))
        line([left, to, right], color: orange, width: 3, context: &context)
    }
}
