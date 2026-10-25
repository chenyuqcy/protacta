import Foundation
import simd

/// A vertex remembers its point on the original uncut sheet. `separation` is a
/// tiny rendering-only layer offset; it never changes the paper's geometry.
struct PaperVertex {
    var position: SIMD3<Float>
    var source: SIMD2<Float>
    var separation: SIMD3<Float> = .zero

    static func interpolate(_ a: PaperVertex, _ b: PaperVertex, _ t: Float) -> PaperVertex {
        PaperVertex(position: a.position + (b.position - a.position) * t,
                    source: a.source + (b.source - a.source) * t,
                    separation: a.separation + (b.separation - a.separation) * t)
    }
}

struct PaperFace {
    var vertices: [PaperVertex]
    /// Original half of the sheet: -1 = left, +1 = right. This distinguishes
    /// coincident layers when folding one wing without moving the other.
    var originalSide: Int
    var isMoving = false
    /// Optional per-edge mask: hide tessellation edges that are not real creases.
    var outlinedEdges: [Bool]? = nil

    var normal: SIMD3<Float> {
        guard vertices.count > 2 else { return [0, 1, 0] }
        var largest = SIMD3<Float>.zero
        var magnitude: Float = 0
        for i in 1..<(vertices.count - 1) {
            let n = simd_cross(vertices[i].position - vertices[0].position,
                               vertices[i + 1].position - vertices[0].position)
            let squared = simd_length_squared(n)
            if squared.isFinite && squared > magnitude { largest = n; magnitude = squared }
        }
        return magnitude > 1e-24 ? largest / sqrt(magnitude) : [0, 1, 0]
    }

    var area: Float {
        guard vertices.count > 2 else { return 0 }
        return (1..<(vertices.count - 1)).reduce(0) {
            $0 + simd_length(simd_cross(vertices[$1].position - vertices[0].position,
                                       vertices[$1 + 1].position - vertices[0].position)) / 2
        }
    }
}

struct PaperCrease {
    var start: SIMD3<Float>
    var end: SIMD3<Float>
}

struct PaperFrame {
    var faces: [PaperFace]
    var crease: PaperCrease?
    var actionPaths: [[SIMD3<Float>]]
    /// Applied equally to every face so moving paper remains above the table.
    var tableLift: Float

    var area: Float { faces.reduce(0) { $0 + $1.area } }
    var bounds: (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        let points = faces.flatMap { $0.vertices.map(\.position) }
        return (points.reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude), simd_min),
                points.reduce(SIMD3<Float>(repeating: -.greatestFiniteMagnitude), simd_max))
    }
}

/// Rigid polygon folding of one A4 sheet. Every crease clips convex faces into
/// material-preserving polygons and rotates the moving polygons about a hinge.
/// No pose is an unrelated replacement mesh, and no animation scales the paper.
enum PaperGeometry {
    static let width: Float = 0.210
    static let height: Float = 0.297
    static let stepCount = 11
    static let lastStep = stepCount - 1
    private static let halfWidth = width / 2
    private static let front = -height / 2
    private static let edgeSlope: Float = tan(.pi / 8)
    private static let wingSlope: Float = tan(.pi / 16)
    private static let epsilon: Float = 0.0000003

    private struct Fold {
        var axisStart: SIMD3<Float>
        var axisEnd: SIMD3<Float>
        var cutNormal: SIMD3<Float>
        var angle: Float
        var side: Int?
        var separation: SIMD3<Float>
        var arrowPoint: SIMD3<Float>
    }

    static func frame(step requestedStep: Int, progress requestedProgress: Float) -> PaperFrame {
        let step = min(lastStep, max(0, requestedStep))
        let p = requestedProgress.isFinite ? min(1, max(0, requestedProgress)) : 0
        var faces = initialFaces()
        var crease: PaperCrease?
        var paths = [[SIMD3<Float>]]()
        var presentationAngle: Float = 0

        if step == 1 || step == 2 {
            var f = foldForStep(1)
            let amount = step == 1 ? p : 1 - p
            faces = apply(f, to: faces, fraction: amount, markMoving: true)
            crease = clippedCrease(for: f, faces: initialFaces())
            if step == 2 { f.angle *= -1; f.arrowPoint.x *= -1 }
            paths = [arrowPath(for: f)]
        } else if step >= 3 {
            for index in 3...min(step, 6) {
                let f = foldForStep(index)
                let active = index == step
                if active {
                    crease = clippedCrease(for: f, faces: faces)
                    paths = [arrowPath(for: f)]
                }
                faces = apply(f, to: faces, fraction: active ? p : 1, markMoving: active)
            }
        }

        if step >= 7 {
            let f = foldForStep(7)
            if step == 7 {
                crease = clippedCrease(for: f, faces: faces)
                paths = [arrowPath(for: f)]
            }
            faces = apply(f, to: faces, fraction: step == 7 ? p : 1, markMoving: step == 7)
            // Tip the entire sheet upright while bringing the halves together.
            // This is a rigid presentation movement, not an extra paper crease.
            presentationAngle = .pi / 2 * (step == 7 ? p : 1)
            transform(&faces, angle: presentationAngle, axis: [0, 0, 1])
            if let c = crease { crease = rotate(c, angle: presentationAngle, axis: [0, 0, 1]) }
            paths = paths.map { $0.map { rotatePoint($0, around: .zero, axis: [0, 0, 1], angle: presentationAngle) } }
        }

        if step >= 8 {
            for index in 8...min(step, 9) {
                let f = foldForStep(index)
                let active = step == index
                let amount: Float
                if step == 10 { amount = 1 - 0.5 * p }
                else { amount = active ? p : 1 }
                if active {
                    crease = clippedCrease(for: f, faces: faces)
                    paths = [arrowPath(for: f)]
                }
                faces = apply(f, to: faces, fraction: amount, markMoving: active || step == 10)
            }
            if step == 10 {
                // The last action opens two already-creased wings together.
                crease = nil
                paths = [8, 9].map { index in
                    let f = foldForStep(index)
                    let axis = simd_normalize(f.axisEnd - f.axisStart)
                    return (0...22).map { i in
                        let t = Float(i) / 22
                        return rotatePoint(f.arrowPoint, around: f.axisStart, axis: axis,
                                           angle: f.angle * (1 - 0.5 * t))
                            + SIMD3<Float>(0, 0.005, 0)
                    }
                }
            }
        }

        // Keep all real sheet vertices and the layered rendering above y = 0.
        // When a fold goes underneath, the whole sheet rises just enough to clear
        // the table, as the learner lifts the paper in their hands.
        let minY = faces.flatMap { $0.vertices }.map { ($0.position + $0.separation).y }.min() ?? 0
        let lift = max(0, -minY) + 0.001
        for faceIndex in faces.indices {
            for vertexIndex in faces[faceIndex].vertices.indices {
                faces[faceIndex].vertices[vertexIndex].position.y += lift
            }
        }
        if var c = crease { c.start.y += lift + 0.0018; c.end.y += lift + 0.0018; crease = c }
        paths = paths.map { path in
            // Arrows are explanatory annotations. Keep their complete sweep
            // visible above a real table even when describing an underside fold.
            let arrowLift = max(lift, 0.007 - (path.map(\.y).min() ?? 0))
            return path.map { $0 + SIMD3<Float>(0, arrowLift, 0) }
        }
        return PaperFrame(faces: faces, crease: crease, actionPaths: paths, tableLift: lift)
    }

    private static func initialFaces() -> [PaperFace] {
        [-1, 1].map { side in
            let left: Float = side == -1 ? -halfWidth : 0
            let right: Float = side == -1 ? 0 : halfWidth
            let points: [SIMD3<Float>] = [[left, 0, -front], [right, 0, -front],
                                          [right, 0, front], [left, 0, front]]
            return PaperFace(vertices: points.map { PaperVertex(position: $0, source: [$0.x, $0.z]) },
                             originalSide: side)
        }
    }

    private static func foldForStep(_ step: Int) -> Fold {
        let nose = SIMD3<Float>(0, 0, front)
        switch step {
        case 1, 7:
            return Fold(axisStart: nose, axisEnd: [0, 0, -front], cutNormal: [-1, 0, 0],
                        angle: step == 1 ? -.pi : .pi, side: -1,
                        separation: [0, step == 1 ? 0.00020 : -0.0012, 0],
                        arrowPoint: [-halfWidth * 0.77, 0, 0.025])
        case 3, 4:
            let s: Float = step == 3 ? -1 : 1
            return Fold(axisStart: nose, axisEnd: [s * halfWidth, 0, front + halfWidth],
                        cutNormal: [s, 0, -1], angle: s * .pi, side: Int(s),
                        separation: [0, 0.00023, 0],
                        arrowPoint: [s * halfWidth * 0.83, 0, front + halfWidth * 0.15])
        case 5, 6:
            let s: Float = step == 5 ? -1 : 1
            return Fold(axisStart: nose, axisEnd: [s * halfWidth, 0, front + halfWidth / edgeSlope],
                        cutNormal: [s, 0, -edgeSlope], angle: s * .pi, side: Int(s),
                        separation: [0, 0.0007, 0],
                        arrowPoint: [s * halfWidth * 0.9, 0, front + halfWidth * 1.25])
        default:
            let s: Float = step == 8 ? 1 : -1
            return Fold(axisStart: nose, axisEnd: [0, wingSlope * height, -front],
                        cutNormal: [0, 1, -wingSlope], angle: -s * .pi,
                        side: step == 8 ? -1 : 1, separation: [s * 0.0013, 0, 0],
                        arrowPoint: [0, halfWidth * 0.91, front + height * 0.78])
        }
    }

    private static func apply(_ fold: Fold, to faces: [PaperFace], fraction: Float,
                              markMoving: Bool) -> [PaperFace] {
        let axis = simd_normalize(fold.axisEnd - fold.axisStart)
        let angle = fold.angle * fraction
        var result = [PaperFace]()
        for face in faces {
            guard fold.side == nil || face.originalSide == fold.side else {
                result.append(face); continue
            }
            let pieces = split(face.vertices, point: fold.axisStart, normal: fold.cutNormal)
            if pieces.stationary.count >= 3 {
                result.append(PaperFace(vertices: pieces.stationary, originalSide: face.originalSide,
                                        isMoving: face.isMoving))
            }
            if pieces.moving.count >= 3 {
                let moving = pieces.moving.map { original -> PaperVertex in
                    var v = original
                    v.position = rotatePoint(v.position, around: fold.axisStart, axis: axis, angle: angle)
                    v.separation = rotatePoint(v.separation, around: .zero, axis: axis, angle: angle)
                        + fold.separation * sin(abs(angle) / 2)
                    return v
                }
                result.append(PaperFace(vertices: moving, originalSide: face.originalSide,
                                        isMoving: markMoving || face.isMoving))
            }
        }
        return result.filter { $0.area > 1e-12 }
    }

    private static func split(_ vertices: [PaperVertex], point: SIMD3<Float>, normal: SIMD3<Float>)
        -> (stationary: [PaperVertex], moving: [PaperVertex]) {
        func clipped(keepPositive: Bool) -> [PaperVertex] {
            guard !vertices.isEmpty else { return [] }
            var output = [PaperVertex]()
            for i in vertices.indices {
                let a = vertices[i], b = vertices[(i + 1) % vertices.count]
                let da = simd_dot(a.position - point, normal)
                let db = simd_dot(b.position - point, normal)
                let aInside = keepPositive ? da >= -epsilon : da <= epsilon
                let bInside = keepPositive ? db >= -epsilon : db <= epsilon
                if aInside { output.append(a) }
                if aInside != bInside, abs(da - db) > epsilon {
                    output.append(.interpolate(a, b, min(1, max(0, da / (da - db)))))
                }
            }
            var clean = [PaperVertex]()
            for v in output where clean.last.map({ simd_distance($0.position, v.position) > epsilon }) ?? true {
                clean.append(v)
            }
            if clean.count > 1, simd_distance(clean[0].position, clean.last!.position) < epsilon { clean.removeLast() }
            return clean
        }
        return (clipped(keepPositive: false), clipped(keepPositive: true))
    }

    private static func clippedCrease(for fold: Fold, faces: [PaperFace]) -> PaperCrease? {
        let axis = simd_normalize(fold.axisEnd - fold.axisStart)
        var values = [Float]()
        for face in faces where fold.side == nil || face.originalSide == fold.side {
            for i in face.vertices.indices {
                let a = face.vertices[i].position, b = face.vertices[(i + 1) % face.vertices.count].position
                let da = simd_dot(a - fold.axisStart, fold.cutNormal)
                let db = simd_dot(b - fold.axisStart, fold.cutNormal)
                if abs(da) < epsilon { values.append(simd_dot(a - fold.axisStart, axis)) }
                if da * db < 0 {
                    values.append(simd_dot(a + (b - a) * da / (da - db) - fold.axisStart, axis))
                }
            }
        }
        guard let a = values.min(), let b = values.max(), b - a > 0.00001 else { return nil }
        return PaperCrease(start: fold.axisStart + axis * a, end: fold.axisStart + axis * b)
    }

    private static func arrowPath(for fold: Fold) -> [SIMD3<Float>] {
        let axis = simd_normalize(fold.axisEnd - fold.axisStart)
        return (0...28).map { i in
            let t = Float(i) / 28
            return rotatePoint(fold.arrowPoint, around: fold.axisStart, axis: axis,
                               angle: fold.angle * (0.08 + 0.84 * t)) + SIMD3<Float>(0, 0.007, 0)
        }
    }

    private static func transform(_ faces: inout [PaperFace], angle: Float, axis: SIMD3<Float>) {
        for i in faces.indices {
            for j in faces[i].vertices.indices {
                faces[i].vertices[j].position = rotatePoint(faces[i].vertices[j].position, around: .zero, axis: axis, angle: angle)
                faces[i].vertices[j].separation = rotatePoint(faces[i].vertices[j].separation, around: .zero, axis: axis, angle: angle)
            }
        }
    }

    private static func rotate(_ crease: PaperCrease, angle: Float, axis: SIMD3<Float>) -> PaperCrease {
        PaperCrease(start: rotatePoint(crease.start, around: .zero, axis: axis, angle: angle),
                    end: rotatePoint(crease.end, around: .zero, axis: axis, angle: angle))
    }

    private static func rotatePoint(_ point: SIMD3<Float>, around origin: SIMD3<Float>,
                                    axis: SIMD3<Float>, angle: Float) -> SIMD3<Float> {
        let p = point - origin
        // Snap full/half turns to avoid accumulating float drift in flat layers.
        let rawS = sin(angle), rawC = cos(angle)
        let s: Float = abs(rawS) < 1e-6 ? 0 : rawS
        let c: Float = abs(rawC) < 1e-6 ? 0 : rawC
        return origin + p * c + simd_cross(axis, p) * s + axis * simd_dot(axis, p) * (1 - c)
    }
}
