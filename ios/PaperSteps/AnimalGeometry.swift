import Foundation
import simd

/// Each lesson starts with the same uncut 15 cm square. Layer tags identify
/// already folded ears so the rabbit's forehead can turn behind them.
enum AnimalKind: String, CaseIterable { case fox, rabbit, butterfly }

enum AnimalGeometry {
    static let sideLength: Float = 0.15
    private static let radius: Float = sideLength / sqrt(2)
    private static let epsilon: Float = 0.0000002
    private struct Fold {
        var origin: SIMD3<Float>
        var axis: SIMD3<Float>
        var normal: SIMD3<Float>
        var angle: Float
        var arrow: SIMD3<Float>
        var layer: Int? = nil
        var layers: Set<Int>? = nil
        var resultLayer: Int? = nil
        var separation: Float = 0.00022
    }

    static func stepCount(kind: AnimalKind) -> Int {
        switch kind { case .fox: return 7; case .rabbit: return 10; case .butterfly: return 19 }
    }

    static func frame(kind: AnimalKind, step requestedStep: Int, progress requestedProgress: Float) -> PaperFrame {
        let step = min(stepCount(kind: kind) - 1, max(0, requestedStep))
        let p = requestedProgress.isFinite ? min(1, max(0, requestedProgress)) : 0
        if kind == .butterfly { return butterflyFrame(step: step, progress: p) }
        var faces = square()
        var crease: PaperCrease?
        var paths = [[SIMD3<Float>]]()
        let r = radius
        func perform(_ fold: Fold, _ index: Int, amount: Float? = nil) {
            guard step >= index else { return }
            let active = index == step
            if active {
                crease = clippedCrease(fold, faces: faces)
                paths = [arrowPath(fold)]
            }
            faces = apply(fold, to: faces, fraction: amount ?? (active ? p : 1), active: active)
        }
        let first = Fold(origin: .zero, axis: [1, 0, 0], normal: [0, 0, kind == .fox ? -1 : 1],
                         angle: kind == .fox ? .pi : -.pi, arrow: [0, 0, kind == .fox ? -r * 0.82 : r * 0.82])
        perform(first, 1)
        if step >= 2 {
            var center = Fold(origin: .zero, axis: [0, 0, 1], normal: [-1, 0, 0], angle: -.pi,
                              arrow: [-r * 0.7, 0, kind == .fox ? r * 0.2 : -r * 0.2])
            let amount = step == 2 ? p : (step == 3 ? 1 - p : 0)
            let creaseFaces = faces
            faces = apply(center, to: faces, fraction: amount, active: step == 2 || step == 3)
            if step == 2 || step == 3 {
                crease = clippedCrease(center, faces: creaseFaces)
                if step == 3 { center.arrow.x *= -1; center.angle *= -1 }
                paths = [arrowPath(center)]
            }
        }
        if kind == .fox {
            for (index, sign) in [(4, Float(-1)), (5, Float(1))] {
                let hinge = SIMD3<Float>(sign * r * 0.72, 0, -r)
                let fold = Fold(origin: [0, 0, r], axis: simd_normalize(hinge),
                                normal: [sign, 0, 0.72], angle: -sign * .pi,
                                arrow: [sign * r * 0.88, 0, r * 0.05], resultLayer: index)
                perform(fold, index)
            }
            if step >= 6 {
                turnOver(&faces, amount: p)
                crease = nil
                paths = turnPath()
            }
        } else {
            let band = r * 0.115
            perform(Fold(origin: [0, 0, -band], axis: [1, 0, 0], normal: [0, 0, 1], angle: -.pi,
                         arrow: [r * 0.45, 0, -band * 0.1]), 4)
            for (index, sign) in [(5, Float(-1)), (6, Float(1))] {
                perform(Fold(origin: .zero, axis: simd_normalize([sign, 0, -1]), normal: [sign, 0, 1],
                             angle: -sign * .pi, arrow: [sign * r * 0.9, 0, -band * 2],
                             resultLayer: index), index)
            }
            if step >= 7 {
                turnOver(&faces, amount: step == 7 ? p : 1)
                if step == 7 { crease = nil; paths = turnPath() }
            }
            // Fold only the central pointed cap; the separate ear flaps stay tall.
            perform(Fold(origin: [0, 0, -r * 0.58], axis: [1, 0, 0], normal: [0, 0, -1],
                         angle: -.pi, arrow: [0, 0, -r * 0.91], layer: 0, separation: -0.00030), 8)
            perform(Fold(origin: [0, 0, -r * 0.13], axis: [1, 0, 0], normal: [0, 0, 1],
                         angle: .pi, arrow: [0, 0, -r * 0.015], separation: -0.00030), 9)
        }
        return aboveTable(removingFlatSeamOutlines(from: faces), crease: crease, paths: paths)
    }

    /// Fox/rabbit clipping introduces panel edges even where the sheet remains
    /// flat. Hide only fully shared, coplanar material seams. A fold-back has
    /// opposite normals and must retain its boundary; unrelated overlapping
    /// layers must never be treated as neighboring pieces of the source sheet.
    /// Explicit masks (including the butterfly's teaching creases) are retained.
    static func removingFlatSeamOutlines(from faces: [PaperFace]) -> [PaperFace] {
        struct Segment {
            let face: Int
            let a: PaperVertex
            let b: PaperVertex
        }
        let tolerance: Float = 0.0000005
        let positionTolerance: Float = 0.000002
        let half = sideLength / 2
        let normals = faces.map(\.normal)
        let centers = faces.map { face in
            face.vertices.reduce(SIMD2<Float>.zero) { $0 + $1.source } / Float(max(1, face.vertices.count))
        }
        let segments = faces.enumerated().flatMap { index, face in
            face.vertices.indices.map { Segment(face: index, a: face.vertices[$0], b: face.vertices[($0 + 1) % face.vertices.count]) }
        }
        func cross2(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }
        return faces.enumerated().map { index, face in
            guard face.outlinedEdges == nil else { return face }
            var result = face
            result.outlinedEdges = face.vertices.indices.map { edgeIndex in
                let a = face.vertices[edgeIndex], b = face.vertices[(edgeIndex + 1) % face.vertices.count]
                for axis in 0..<2 {
                    if abs(abs(a.source[axis]) - half) < tolerance && abs(a.source[axis] - b.source[axis]) < tolerance { return true }
                }
                let delta = b.source - a.source
                let length = simd_length(delta)
                guard length > tolerance else { return true }
                let direction = delta / length
                let ownSide = cross2(direction, centers[index] - a.source)
                var coveredIntervals = [(Float, Float)]()
                for other in segments where other.face != index {
                    guard faces[other.face].isMoving == face.isMoving,
                          simd_dot(normals[index], normals[other.face]) > 0.9999,
                          ownSide * cross2(direction, centers[other.face] - a.source) < 0,
                          abs(cross2(direction, other.a.source - a.source)) <= tolerance,
                          abs(cross2(direction, other.b.source - a.source)) <= tolerance else { continue }
                    let start = simd_dot(other.a.source - a.source, direction)
                    let end = simd_dot(other.b.source - a.source, direction)
                    let low = max(0, min(start, end)), high = min(length, max(start, end))
                    guard high - low > tolerance, abs(end - start) > tolerance else { continue }
                    var contiguous = true
                    for distance in [low, high] {
                        let p = a.position + (b.position - a.position) * (distance / length)
                        let q = other.a.position + (other.b.position - other.a.position) * ((distance - start) / (end - start))
                        if simd_distance(p, q) > positionTolerance { contiguous = false; break }
                    }
                    if contiguous { coveredIntervals.append((low, high)) }
                }
                // A long edge may meet several short edges after later folds.
                // Require their union to cover the full edge, including ends.
                var covered: Float = 0
                for interval in coveredIntervals.sorted(by: { $0.0 < $1.0 }) {
                    if interval.0 > covered + tolerance { return true }
                    covered = max(covered, interval.1)
                }
                return covered < length - tolerance
            }
            return result
        }
    }

    private static func square() -> [PaperFace] {
        let a = sideLength / 2
        let sources: [SIMD2<Float>] = [[-a, a], [a, a], [a, -a], [-a, -a]]
        return [PaperFace(vertices: sources.map { s in
            PaperVertex(position: [(s.x + s.y) / sqrt(2), 0, (s.y - s.x) / sqrt(2)], source: s)
        }, originalSide: 0, outlinedEdges: [true, true, true, true])]
    }

    private static func apply(_ fold: Fold, to faces: [PaperFace], fraction: Float, active: Bool) -> [PaperFace] {
        let axis = simd_normalize(fold.axis)
        let angle = fold.angle * fraction
        var result = [PaperFace]()
        for face in faces {
            guard (fold.layer == nil || fold.layer == face.originalSide) && (fold.layers?.contains(face.originalSide) ?? true) else {
                result.append(face); continue
            }
            let pieces = split(face.vertices, point: fold.origin, normal: fold.normal)
            if pieces.stationary.count >= 3 {
                result.append(PaperFace(vertices: pieces.stationary, originalSide: face.originalSide,
                                        isMoving: face.isMoving))
            }
            if pieces.moving.count >= 3 {
                let vertices = pieces.moving.map { original -> PaperVertex in
                    var v = original
                    v.position = rotated(v.position, origin: fold.origin, axis: axis, angle: angle)
                    v.separation = rotated(v.separation, origin: .zero, axis: axis, angle: angle)
                        + SIMD3<Float>(0, fold.separation * sin(abs(angle) / 2), 0)
                    return v
                }
                result.append(PaperFace(vertices: vertices, originalSide: fold.resultLayer ?? face.originalSide,
                                        isMoving: active || face.isMoving))
            }
        }
        return result.filter { $0.area > 1e-12 }
    }

    private static func split(_ vertices: [PaperVertex], point: SIMD3<Float>, normal: SIMD3<Float>)
        -> (stationary: [PaperVertex], moving: [PaperVertex]) {
        func clip(_ positive: Bool) -> [PaperVertex] {
            guard !vertices.isEmpty else { return [] }
            var output = [PaperVertex]()
            for i in vertices.indices {
                let a = vertices[i], b = vertices[(i + 1) % vertices.count]
                let da = simd_dot(a.position - point, normal), db = simd_dot(b.position - point, normal)
                let ai = positive ? da >= -epsilon : da <= epsilon
                let bi = positive ? db >= -epsilon : db <= epsilon
                if ai { output.append(a) }
                if ai != bi, abs(da - db) > epsilon {
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
        return (clip(false), clip(true))
    }

    private static func clippedCrease(_ fold: Fold, faces: [PaperFace]) -> PaperCrease? {
        let axis = simd_normalize(fold.axis)
        var distances = [Float]()
        for face in faces where (fold.layer == nil || fold.layer == face.originalSide) && (fold.layers?.contains(face.originalSide) ?? true) {
            for i in face.vertices.indices {
                let a = face.vertices[i].position, b = face.vertices[(i + 1) % face.vertices.count].position
                let da = simd_dot(a - fold.origin, fold.normal), db = simd_dot(b - fold.origin, fold.normal)
                if abs(da) < epsilon { distances.append(simd_dot(a - fold.origin, axis)) }
                if da * db < 0 { distances.append(simd_dot(a + (b - a) * da / (da - db) - fold.origin, axis)) }
            }
        }
        guard let lo = distances.min(), let hi = distances.max(), hi - lo > 0.00001 else { return nil }
        return PaperCrease(start: fold.origin + axis * lo, end: fold.origin + axis * hi)
    }

    private static func arrowPath(_ fold: Fold) -> [SIMD3<Float>] {
        (0...24).map { i in
            rotated(fold.arrow, origin: fold.origin, axis: simd_normalize(fold.axis),
                    angle: fold.angle * (0.08 + 0.84 * Float(i) / 24))
        }
    }

    private static func turnPath() -> [[SIMD3<Float>]] {
        [(0...24).map { i in rotated([-radius * 0.65, 0, 0], origin: .zero, axis: [0, 0, 1], angle: -.pi * Float(i) / 24) }]
    }

    private static func turnOver(_ faces: inout [PaperFace], amount: Float) {
        for i in faces.indices {
            for j in faces[i].vertices.indices {
                faces[i].vertices[j].position = rotated(faces[i].vertices[j].position, origin: .zero, axis: [0, 0, 1], angle: -.pi * amount)
                faces[i].vertices[j].separation = rotated(faces[i].vertices[j].separation, origin: .zero, axis: [0, 0, 1], angle: -.pi * amount)
            }
            faces[i].isMoving = amount < 1
        }
    }

    private static func aboveTable(_ original: [PaperFace], crease originalCrease: PaperCrease?, paths originalPaths: [[SIMD3<Float>]]) -> PaperFrame {
        var faces = original
        var crease = originalCrease
        let minY = faces.flatMap(\.vertices).map { ($0.position + $0.separation).y }.min() ?? 0
        let lift = max(0, -minY) + 0.001
        for i in faces.indices { for j in faces[i].vertices.indices { faces[i].vertices[j].position.y += lift } }
        if var c = crease { c.start.y += lift + 0.001; c.end.y += lift + 0.001; crease = c }
        let paths = originalPaths.map { path in
            let height = max(lift + 0.006, 0.006 - (path.map(\.y).min() ?? 0))
            return path.map { $0 + SIMD3<Float>(0, height, 0) }
        }
        return PaperFrame(faces: faces, crease: crease, actionPaths: paths, tableLift: lift)
    }

    private static func rotated(_ point: SIMD3<Float>, origin: SIMD3<Float>, axis: SIMD3<Float>, angle: Float) -> SIMD3<Float> {
        let v = point - origin
        let rawS = sin(angle), rawC = cos(angle)
        let s: Float = abs(rawS) < 1e-6 ? 0 : rawS, c: Float = abs(rawC) < 1e-6 ? 0 : rawC
        return origin + v * c + simd_cross(axis, v) * s + axis * simd_dot(axis, v) * (1 - c)
    }

    /// Traditional double-boat butterfly. The two end pockets are each made of
    /// four linked rigid triangles. Their shared corner is solved geometrically
    /// rather than interpolating between unrelated flat outlines.
    private static func butterflyFrame(step: Int, progress p: Float) -> PaperFrame {
        let a = sideLength / 2, q = a / 2
        var faces = butterflyPockets(top: 0, bottom: 0, unfolded: step < 8)
        var crease: PaperCrease?
        var paths = [[SIMD3<Float>]]()
        func perform(_ fold: Fold, _ index: Int) {
            guard step >= index else { return }
            let active = step == index
            if active { crease = clippedCrease(fold, faces: faces); paths = [arrowPath(fold)] }
            faces = apply(fold, to: faces, fraction: active ? p : 1, active: active)
        }
        if step >= 1 && step <= 5 {
            let amount = p < 0.5 ? 2 * p : 2 * (1 - p)
            var folds = [Fold]()
            if step == 1 {
                folds = [Fold(origin: .zero, axis: [1, 0, 0], normal: [0, 0, -1], angle: .pi, arrow: [a * 0.35, 0, -a * 0.85])]
            } else if step == 2 {
                folds = [Fold(origin: .zero, axis: [0, 0, 1], normal: [-1, 0, 0], angle: -.pi, arrow: [-a * 0.85, 0, a * 0.35])]
            } else if step == 3 {
                folds = [Fold(origin: .zero, axis: simd_normalize([1, 0, 1]), normal: [-1, 0, 1], angle: -.pi, arrow: [-a * 0.8, 0, a * 0.8])]
            } else if step == 4 {
                folds = [Fold(origin: .zero, axis: simd_normalize([1, 0, -1]), normal: [1, 0, 1], angle: -.pi, arrow: [a * 0.8, 0, a * 0.8])]
            } else {
                for sx: Float in [-1, 1] { for sz: Float in [-1, 1] {
                    let origin = SIMD3<Float>(sx * q, 0, sz * q)
                    let axis = simd_normalize(SIMD3<Float>(sz, 0, -sx))
                    folds.append(Fold(origin: origin, axis: axis, normal: [sx, 0, sz], angle: .pi,
                                      arrow: [sx * a * 0.83, 0, sz * a * 0.83]))
                } }
            }
            for var fold in folds {
                if simd_cross(fold.axis, fold.arrow - fold.origin).y < 0 { fold.angle *= -1 }
                faces = apply(fold, to: faces, fraction: amount, active: true)
                if crease == nil { crease = clippedCrease(fold, faces: butterflyPockets(top: 0, bottom: 0, unfolded: true)) }
                if p > 0.5 {
                    fold.arrow = rotated(fold.arrow, origin: fold.origin, axis: fold.axis, angle: fold.angle)
                    fold.angle *= -1
                }
                paths.append(arrowPath(fold))
            }
        }
        if step == 6 || step == 7 {
            perform(Fold(origin: [-q, 0, 0], axis: [0, 0, 1], normal: [-1, 0, 0], angle: -.pi,
                         arrow: [-a * 0.86, 0, a * 0.55]), 6)
            perform(Fold(origin: [q, 0, 0], axis: [0, 0, 1], normal: [1, 0, 0], angle: .pi,
                         arrow: [a * 0.86, 0, a * 0.55]), 7)
        }
        if step >= 8 {
            faces = butterflyPockets(top: step == 8 ? p : 1, bottom: step == 9 ? p : (step > 9 ? 1 : 0), unfolded: false)
            if step == 8 || step == 9 {
                let sz: Float = step == 8 ? 1 : -1
                crease = PaperCrease(start: [-q, 0, -sz * q], end: [q, 0, -sz * q])
                paths = [-1, Float(1)].map { sx in
                    (0...24).map { i in
                        let f = Float(i) / 24
                        let c = pocketCorner(f)
                        return SIMD3<Float>(sx * -c.x, c.y, sz * c.z)
                    }
                }
                for i in faces.indices { faces[i].isMoving = faces[i].originalSide % 2 == (step == 8 ? 1 : 0) }
            }
        }
        // The far boat's two corners turn into the narrower rear wings.
        for (index, sign) in [(10, Float(-1)), (11, Float(1))] {
            perform(Fold(origin: .zero, axis: simd_normalize([sign, 0, -1]), normal: [sign, 0, 1],
                         angle: -sign * .pi, arrow: [sign * a * 0.86, 0, 0], layer: 3), index)
        }
        perform(Fold(origin: .zero, axis: [1, 0, 0], normal: [0, 0, -1], angle: -.pi,
                     arrow: [q * 0.4, 0, -a * 0.82], separation: -0.00035), 12)
        if step >= 13 {
            turnOver(&faces, amount: step == 13 ? p : 1)
            if step == 13 { crease = nil; paths = turnPath() }
        }
        for (index, sign) in [(14, Float(-1)), (15, Float(1))] {
            perform(Fold(origin: [0, 0, a], axis: simd_normalize([sign * q, 0, -a]),
                         normal: [sign, 0, 0.5], angle: -sign * .pi,
                         arrow: [sign * q * 0.85, 0, q * 0.9], layers: [1, 3]), index)
        }
        if step >= 16 {
            let fold = Fold(origin: .zero, axis: [0, 0, 1], normal: [-1, 0, 0], angle: -.pi,
                            arrow: [-a * 0.8, 0, q * 0.3], resultLayer: 10)
            let amount = step == 16 ? p : 1
            if step == 16 { crease = clippedCrease(fold, faces: faces); paths = [arrowPath(fold)] }
            faces = apply(fold, to: faces, fraction: amount, active: step == 16)
            let angle = Float.pi / 2 * amount
            for i in faces.indices { for j in faces[i].vertices.indices {
                faces[i].vertices[j].position = rotated(faces[i].vertices[j].position, origin: .zero, axis: [0, 0, 1], angle: angle)
                faces[i].vertices[j].separation = rotated(faces[i].vertices[j].separation, origin: .zero, axis: [0, 0, 1], angle: angle)
            } }
            if var c = crease {
                c.start = rotated(c.start, origin: .zero, axis: [0, 0, 1], angle: angle)
                c.end = rotated(c.end, origin: .zero, axis: [0, 0, 1], angle: angle)
                crease = c
            }
            paths = paths.map { $0.map { rotated($0, origin: .zero, axis: [0, 0, 1], angle: angle) } }
        }
        let body: Float = 0.008
        if step >= 17 {
            let hinge = simd_normalize(SIMD3<Float>(0, -body, q))
            let fold = Fold(origin: [0, body, 0], axis: hinge, normal: [0, 1, body / q], angle: .pi * 0.43,
                            arrow: [0, a * 0.7, q * 0.3], layer: 10)
            perform(fold, 17)
        }
        if step >= 18 {
            let hinge = simd_normalize(SIMD3<Float>(0, -body, q))
            var allPaths = [[SIMD3<Float>]]()
            for layer in [1, 2, 3, 4] {
                let fold = Fold(origin: [0, body, 0], axis: hinge, normal: [0, 1, body / q], angle: -.pi * 0.43,
                                arrow: [0, a * 0.7, q * 0.3], layer: layer)
                if let c = clippedCrease(fold, faces: faces) { crease = c }
                faces = apply(fold, to: faces, fraction: p, active: true)
                if allPaths.isEmpty { allPaths = [arrowPath(fold)] }
            }
            paths = allPaths
        }
        if step < 10 {
            for i in faces.indices {
                let vertices = faces[i].vertices
                faces[i].outlinedEdges = vertices.indices.map { j in
                    let u = vertices[j].source, v = vertices[(j + 1) % vertices.count].source
                    func line(_ normal: SIMD2<Float>, _ d: Float) -> Bool {
                        abs(simd_dot(u, normal) - d) < 0.000002 && abs(simd_dot(v, normal) - d) < 0.000002
                    }
                    if [a, -a].contains(where: { line([1, 0], $0) || line([0, 1], $0) }) { return true }
                    if step >= 1 && line([0, 1], 0) { return true }
                    if step >= 2 && line([1, 0], 0) { return true }
                    if step >= 3 && line([1, -1], 0) { return true }
                    if step >= 4 && line([1, 1], 0) { return true }
                    if step >= 5 && [a, -a].contains(where: { line([1, 1], $0) || line([1, -1], $0) }) { return true }
                    if step >= 6 && line([1, 0], -q) { return true }
                    if step >= 7 && line([1, 0], q) { return true }
                    if step >= 8 && line([0, 1], -q) { return true }
                    if step >= 9 && line([0, 1], q) { return true }
                    return false
                }
            }
        }
        return aboveTable(faces, crease: crease, paths: paths)
    }

    private static func butterflyPockets(top: Float, bottom: Float, unfolded: Bool) -> [PaperFace] {
        let q = sideLength / 4
        var result = [PaperFace]()
        for xs: Float in [1, -1] { for zs: Float in [1, -1] {
            let p = zs > 0 ? top : bottom
            let Q = SIMD3<Float>(-q, 0, -q)
            let L = SIMD3<Float>(0, 0, 0)
            let F = SIMD3<Float>(-q, 0, 0)
            let O = SIMD3<Float>(0, 0, 0)
            let W = SIMD3<Float>(0, 0, -q)
            let T = rotated([-q, 0, -2 * q], origin: Q, axis: [1, 0, 0], angle: .pi * p)
            let U = rotated([0, 0, -2 * q], origin: Q, axis: [1, 0, 0], angle: .pi * p)
            let V = rotated([0, 0, -q], origin: Q, axis: simd_normalize(L - Q), angle: .pi * p)
            let C = pocketCorner(p)
            let data: [(SIMD2<Float>, SIMD3<Float>)] = [
                ([-q,-q],Q),([-2*q,0],L),([-q,0],F),([0,0],O),([0,-q],W),
                ([-q,-2*q],T),([0,-2*q],U),([-2*q,-q],V),([-2*q,-2*q],C)
            ]
            let indices = [[0,5,8],[0,8,7],[0,7,1],[0,1,2],[0,4,6],[0,6,5],[0,2,3],[0,3,4]]
            for (triangleIndex, triangle) in indices.enumerated() {
                var vertices = triangle.map { index -> PaperVertex in
                    let pair = data[index]
                    let source = SIMD2<Float>(pair.0.x * xs, pair.0.y * zs)
                    let pos = unfolded ? SIMD3<Float>(source.x, 0, source.y) : SIMD3<Float>(pair.1.x * xs, pair.1.y, pair.1.z * zs)
                    return PaperVertex(position: pos, source: source)
                }
                let u = vertices[1].source - vertices[0].source, v = vertices[2].source - vertices[0].source
                if u.x * v.y - u.y * v.x > 0 { vertices.reverse() }
                let isFlap = [0, 1, 2, 5].contains(triangleIndex)
                var face = PaperFace(vertices: vertices, originalSide: (zs > 0 ? 1 : 2) + (isFlap ? 2 : 0))
                if !unfolded {
                    // Opposite faces receive opposite offsets, exposing thin
                    // layers without changing the material coordinates.
                    for i in face.vertices.indices { face.vertices[i].separation = face.normal * 0.00012 }
                }
                result.append(face)
            }
        } }
        return result
    }

    private static func pocketCorner(_ fraction: Float) -> SIMD3<Float> {
        let q = Double(sideLength) / 4
        if fraction <= 0.000001 { return [0, 0, Float(-2 * q)] }
        if fraction >= 0.999999 { return [Float(-2 * q), 0, 0] }
        let theta = Double.pi * Double(fraction)
        let first = SIMD3<Double>(-q, 0, -q)
        let second = SIMD3<Double>(-q, q * sin(theta), -q - q * cos(theta))
        // Rotation of V about Q--L, written explicitly in double precision.
        let third = SIMD3<Double>(-q * (1 - cos(theta)) / 2,
                                  q * sin(theta) / sqrt(2), -q * (1 + cos(theta)) / 2)
        let r1 = q * sqrt(2), r2 = q, r3 = q
        let d = simd_distance(first, second), ex = (second - first) / d
        let delta = third - first, i = simd_dot(ex, delta)
        let perpendicular = delta - i * ex, j = simd_length(perpendicular)
        let ey = perpendicular / j, ez = simd_cross(ex, ey)
        let x = (r1*r1 - r2*r2 + d*d) / (2*d)
        let y = (r1*r1 - r3*r3 + i*i + j*j - 2*i*x) / (2*j)
        let z = sqrt(max(0, r1*r1 - x*x - y*y))
        let base = first + ex*x + ey*y
        let one = base + ez*z, two = base - ez*z
        let chosen = one.x < two.x ? one : two
        return SIMD3<Float>(chosen)
    }
}
