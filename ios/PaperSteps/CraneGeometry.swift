import Foundation
import simd

/// A single 20 cm square, carried through the traditional square-base route.
/// Every triangle retains its coordinates on the original sheet. Squash folds
/// are four-triangle closed linkages; petals solve the shared side vertices by
/// trilateration. Later folds clip the existing material and turn it on a hinge.
/// Small layer offsets in inside-reverse demonstrations are visibility aids,
/// not an assertion of collision-free paper mechanics.
enum CraneGeometry {
    static let width: Float = 0.20
    static let stepCount = 29
    static let lastStep = stepCount - 1
    private static let a = width / sqrt(Float(2))
    private static let h = a * (1 - 1 / sqrt(Float(2)))
    private static let epsilon: Float = 0.0000002

    private struct Patch {
        var face: PaperFace
        var pocket: Int
        var corner: Int // -1 north, +1 south, 0 outer wing
        var pointSegment = false
    }

    static func frame(step requestedStep: Int, progress requestedProgress: Float) -> PaperFrame {
        let step = min(lastStep, max(0, requestedStep))
        let p = requestedProgress.isFinite ? min(1, max(0, requestedProgress)) : 0
        func amount(_ index: Int) -> Float { step > index ? 1 : step == index ? p : 0 }
        func pulse(_ index: Int) -> Float { step == index ? sin(.pi * p) : 0 }
        var patches = [Patch]()
        var crease: PaperCrease?
        var paths = [[SIMD3<Float>]]()

        if step < 3 {
            patches = unfoldedPatches()
            if step >= 1 {
                applyFold(&patches, point: .zero, axis: [1, 0, 0], normal: [0, 0, -1],
                          angle: .pi * amount(1), select: { _ in true }, moving: step == 1)
            }
            if step >= 2 {
                applyFold(&patches, point: .zero, axis: [0, 0, 1], normal: [-1, 0, 0],
                          angle: -.pi * p, select: { _ in true }, moving: true)
            }
            if step == 1 {
                crease = PaperCrease(start: [-a, 0, 0], end: [a, 0, 0])
                paths = [arc(point: [0, 0, -a * 0.85], origin: .zero, axis: [1, 0, 0], angle: .pi)]
            } else if step == 2 {
                crease = PaperCrease(start: .zero, end: [0, 0, a])
                paths = [arc(point: [-a * 0.78, 0, a * 0.12], origin: .zero, axis: [0, 0, 1], angle: -.pi)]
            }
        } else {
            for pocket in [-1, 1] {
                let squashStep = pocket == -1 ? 3 : 5
                let petalStep = pocket == 1 ? 9 : 14
                let squash = amount(squashStep)
                let petal = amount(petalStep)
                patches += pocketPatches(pocket: pocket, squash: squash, petal: petal,
                                         isSquashing: step == squashStep,
                                         isPetaling: step == petalStep)
                if step == squashStep {
                    crease = PaperCrease(start: .zero, end: [0, 0, a])
                    paths = [(0...28).map { squashCorner(Float($0) / 28, sign: Float(-pocket)) }]
                }
                if step == petalStep {
                    crease = PaperCrease(start: [-h, 0, h], end: [h, 0, h])
                    paths = [arc(point: [0, 0, a * 0.95], origin: [0, 0, h],
                                 axis: [1, 0, 0], angle: -Float(-pocket) * .pi)]
                }
            }

            // The three precreases on each face return to the same square base.
            for index in [6, 7, 11, 12] where step == index {
                let pocket = index < 10 ? 1 : -1
                let side: Float = (index == 6 || index == 12) ? 1 : -1
                let origin = SIMD3<Float>(0, 0, a)
                let end = SIMD3<Float>(side * h, 0, h)
                let normal = SIMD3<Float>(side, 0, h / (a - h))
                let angle = side * Float(-pocket) * .pi * pulse(index)
                applyFold(&patches, point: origin, axis: end - origin, normal: normal,
                          angle: angle, select: { $0.pocket == pocket }, moving: true)
                crease = PaperCrease(start: origin, end: end)
                paths = [arc(point: [side * a * 0.43, 0, a * 0.53], origin: origin,
                             axis: end - origin, angle: side * Float(-pocket) * .pi)]
            }
            if step == 8 || step == 13 {
                let sign: Float = step == 8 ? -1 : 1
                let origin = SIMD3<Float>(0, 0, h)
                applyFold(&patches, point: origin, axis: [1, 0, 0], normal: [0, 0, -1],
                          angle: sign * .pi * pulse(step), select: { _ in true }, moving: true)
                crease = PaperCrease(start: [-h, 0, h], end: [h, 0, h])
                paths = [arc(point: [0, 0, h * 0.10], origin: origin,
                             axis: [1, 0, 0], angle: sign * .pi)]
            }

            for index in [15, 16, 18, 19] where step >= index {
                let pocket = index < 17 ? -1 : 1
                let side: Float = (index == 15 || index == 19) ? -1 : 1
                let slope = tan(Float.pi / 16)
                let origin = SIMD3<Float>(0, 0, a)
                let end = SIMD3<Float>(side * slope * (a - h), 0, h)
                let normal = SIMD3<Float>(side, 0, slope)
                let angle = side * Float(-pocket) * .pi * amount(index)
                if step == index {
                    crease = PaperCrease(start: origin, end: end)
                    paths = [arc(point: [side * h * 0.80, 0, h + (a - h) * 0.13],
                                 origin: origin, axis: end - origin,
                                 angle: side * Float(-pocket) * .pi)]
                }
                applyFold(&patches, point: origin, axis: end - origin, normal: normal,
                          angle: angle, select: { $0.pocket == pocket }, moving: step == index)
            }

            // North and south original corners form the two independent lower
            // points. Both sides of each point move together; no tip is replaced.
            for corner in [-1, 1] {
                let markStep = corner == -1 ? 20 : 21
                let reverseStep = corner == -1 ? 22 : 23
                let fraction = step == markStep ? pulse(markStep) : amount(reverseStep)
                let direction: Float = corner == -1 ? 1 : -1
                let origin = SIMD3<Float>(0, 0, a * (corner == -1 ? 0.38 : 0.43))
                let axis = SIMD3<Float>(1, 0, direction * tan(corner == -1 ? .pi / 12 : .pi / 8))
                let normal = SIMD3<Float>(-axis.z, 0, 1)
                if step == markStep || step == reverseStep {
                    crease = PaperCrease(start: origin - axis * 0.021, end: origin + axis * 0.021)
                    paths = [arc(point: [0, 0, a * 0.97], origin: origin, axis: axis,
                                 angle: -.pi)]
                    if step == reverseStep { separateForView(&patches, amount: sin(.pi * p), region: 0) }
                }
                if fraction > 0 {
                    applyFold(&patches, point: origin, axis: axis, normal: normal,
                              angle: -.pi * fraction, select: { $0.corner == corner },
                              moving: step == markStep || step == reverseStep, markPoint: true)
                }
            }

            if step >= 24 {
                let neckOrigin = SIMD3<Float>(0, 0, a * 0.38)
                let neckAxis = SIMD3<Float>(1, 0, tan(Float.pi / 12))
                let tip = rotate([0, 0, a], origin: neckOrigin, axis: neckAxis, angle: -.pi)
                let headOrigin = neckOrigin + (tip - neckOrigin) * 0.82
                let fraction = step == 24 ? pulse(24) : amount(25)
                if step == 24 || step == 25 {
                    crease = PaperCrease(start: headOrigin - SIMD3<Float>(0.013, 0, 0),
                                         end: headOrigin + SIMD3<Float>(0.013, 0, 0))
                    paths = [arc(point: tip, origin: headOrigin, axis: [1, 0, 0], angle: .pi)]
                    if step == 25 { separateForView(&patches, amount: sin(.pi * p), region: 1) }
                }
                applyFold(&patches, point: headOrigin, axis: [1, 0, 0], normal: [0, 0, -1],
                          angle: .pi * fraction, select: { $0.corner == -1 && $0.pointSegment },
                          moving: step == 24 || step == 25)
            }

            for index in [26, 27] where step >= index {
                let pocket = index == 26 ? 1 : -1
                let angle = Float(-pocket) * .pi * 0.65
                applyFold(&patches, point: .zero, axis: [1, 0, 0], normal: [0, 0, -1],
                          angle: angle * amount(index),
                          select: { $0.pocket == pocket && $0.corner == 0 }, moving: step == index)
                if step == index {
                    crease = PaperCrease(start: [-h * 0.58, 0, 0], end: [h * 0.58, 0, 0])
                    paths = [arc(point: [0, 0, (2 * h - a) * 0.85], origin: .zero,
                                 axis: [1, 0, 0], angle: angle)]
                }
            }
        }

        // Whole-sheet turns make the side named by the lesson face the learner.
        // Standing the bird up as its wings open is a presentation movement.
        let turn = .pi * (amount(4) + amount(10) + amount(17))
        let stand = Float.pi / 2 * amount(26)
        func present(_ point: SIMD3<Float>) -> SIMD3<Float> {
            let turned = rotate(point, origin: .zero, axis: [0, 0, 1], angle: turn)
            return rotate(turned, origin: .zero, axis: [1, 0, 0], angle: stand)
        }
        for i in patches.indices {
            for j in patches[i].face.vertices.indices {
                patches[i].face.vertices[j].position = present(patches[i].face.vertices[j].position)
                patches[i].face.vertices[j].separation = present(patches[i].face.vertices[j].separation)
            }
        }
        if let c = crease { crease = PaperCrease(start: present(c.start), end: present(c.end)) }
        paths = paths.map { $0.map(present) }
        let vertices = patches.flatMap { $0.face.vertices }
        let minimum = vertices.map(\.position).reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude), simd_min)
        let maximum = vertices.map(\.position).reduce(SIMD3<Float>(repeating: -.greatestFiniteMagnitude), simd_max)
        let minY = vertices.map { min($0.position.y, ($0.position + $0.separation).y) }.min() ?? 0
        let lift = max(0, -minY) + 0.001
        let offset = SIMD3<Float>(-(minimum.x + maximum.x) / 2, lift, -(minimum.z + maximum.z) / 2)
        for i in patches.indices {
            for j in patches[i].face.vertices.indices { patches[i].face.vertices[j].position += offset }
        }
        if var c = crease {
            c.start += offset + SIMD3<Float>(0, 0.002, 0)
            c.end += offset + SIMD3<Float>(0, 0.002, 0)
            crease = c
        }
        paths = paths.map { path in
            let shifted = path.map { $0 + offset }
            let extra = max(0, 0.006 - (shifted.map(\.y).min() ?? 0))
            return shifted.map { $0 + SIMD3<Float>(0, extra, 0) }
        }
        if step < 15 {
            for i in patches.indices {
                let vertices = patches[i].face.vertices
                patches[i].face.outlinedEdges = vertices.indices.map { j in
                    outline(vertices[j].source, vertices[(j + 1) % vertices.count].source, step: step)
                }
            }
        }
        return PaperFrame(faces: patches.map(\.face), crease: crease, actionPaths: paths, tableLift: lift)
    }

    private static func unfoldedPatches() -> [Patch] {
        var result = [Patch]()
        for pocket in [-1, 1] {
            let c = SIMD2<Float>(Float(pocket) * a, 0)
            for corner in [-1, 1] {
                let q = SIMD2<Float>(0, Float(corner) * a)
                let m = (c + q) / 2
                result.append(patch([(.zero, .zero), (c, flat(c)), (m, flat(m))], pocket: pocket, corner: 0))
                result.append(patch([(.zero, .zero), (m, flat(m)), (q, flat(q))], pocket: pocket, corner: corner))
            }
        }
        return result
    }

    private static func pocketPatches(pocket: Int, squash: Float, petal: Float,
                                      isSquashing: Bool, isPetaling: Bool) -> [Patch] {
        let cSource = SIMD2<Float>(Float(pocket) * a, 0)
        let c = squashCorner(squash, sign: Float(-pocket))
        let q = SIMD3<Float>(0, 0, a)
        var result = [Patch]()
        for corner in [-1, 1] {
            let qSource = SIMD2<Float>(0, Float(corner) * a)
            let mSource = (cSource + qSource) / 2
            let movingMidpoint = pocket == corner
            let theta = movingMidpoint ? Float(-pocket) * .pi * squash : 0
            let m = SIMD3<Float>(a / 2 * cos(theta), a / 2 * sin(theta), a / 2)
            if squash < 1 - 0.000001 {
                result.append(patch([(.zero, .zero), (cSource, c), (mSource, m)],
                                    pocket: pocket, corner: 0, moving: isSquashing))
                result.append(patch([(.zero, .zero), (mSource, m), (qSource, q)],
                                    pocket: pocket, corner: corner, moving: isSquashing && movingMidpoint))
                continue
            }
            let side: Float = movingMidpoint ? -1 : 1
            let hs = mSource * (2 * h / a)
            let ks = cSource * (h / a)
            let hp = SIMD3<Float>(side * h, 0, h)
            let kp = SIMD3<Float>(0, 0, h)
            let cp = rotate(q, origin: kp, axis: [1, 0, 0], angle: -Float(-pocket) * .pi * petal)
            let mp = petalSide(side: side, fraction: petal, sign: Float(-pocket))
            result.append(patch([(.zero, .zero), (hs, hp), (ks, kp)], pocket: pocket, corner: 0))
            result.append(patch([(hs, hp), (ks, kp), (cSource, cp)], pocket: pocket, corner: 0, moving: isPetaling))
            result.append(patch([(hs, hp), (cSource, cp), (mSource, mp)], pocket: pocket, corner: 0, moving: isPetaling))
            result.append(patch([(.zero, .zero), (hs, hp), (qSource, q)], pocket: pocket, corner: corner))
            result.append(patch([(hs, hp), (qSource, q), (mSource, mp)], pocket: pocket, corner: corner, moving: isPetaling))
        }
        return result
    }

    /// Two midpoints lie on a circle about the O–B diagonal. Keeping one fixed
    /// while the other turns through π uniquely determines their shared corner.
    private static func squashCorner(_ fraction: Float, sign: Float) -> SIMD3<Float> {
        let delta = .pi / 2 * fraction
        let cosine = cos(delta)
        let radial = 2 * a * cosine / (1 + cosine * cosine)
        return [radial * cos(delta), sign * radial * sin(delta),
                a * (1 - cosine * cosine) / (1 + cosine * cosine)]
    }

    /// Intersection of three spheres: the moving side stays the same distance
    /// from its hinge vertex, the raised tip and the stationary back corner.
    private static func petalSide(side: Float, fraction: Float, sign: Float) -> SIMD3<Float> {
        let initial = SIMD3<Float>(side * a / 2, 0, a / 2)
        if fraction <= 0.000001 { return initial }
        if fraction >= 0.999999 { return [0, 0, h] }
        let first = SIMD3<Float>(side * h, 0, h)
        let second = SIMD3<Float>(0, 0, a)
        let third = rotate(second, origin: [0, 0, h], axis: [1, 0, 0], angle: -sign * .pi * fraction)
        let r1 = simd_distance(initial, first), r2 = simd_distance(initial, second)
        let d = simd_distance(first, second)
        let ex = (second - first) / d
        let displacement = third - first
        let i = simd_dot(ex, displacement)
        let perpendicular = displacement - i * ex
        let j = simd_length(perpendicular)
        guard j > 1e-10 else { return initial }
        let ey = perpendicular / j
        let ez = simd_cross(ex, ey)
        let x = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
        let y = (r1 * r1 - r2 * r2 + i * i + j * j - 2 * i * x) / (2 * j)
        let z = sqrt(max(0, r1 * r1 - x * x - y * y))
        let base = first + x * ex + y * ey
        let one = base + z * ez, two = base - z * ez
        // The outward intersection is the continuous branch issuing from the
        // broad side corner. The other branch starts inside the pocket.
        return side * one.x > side * two.x ? one : two
    }

    private static func patch(_ data: [(SIMD2<Float>, SIMD3<Float>)], pocket: Int,
                              corner: Int, moving: Bool = false) -> Patch {
        var vertices = data.map { PaperVertex(position: $0.1, source: $0.0) }
        let s0 = vertices[0].source, s1 = vertices[1].source, s2 = vertices[2].source
        let cross = (s1.x - s0.x) * (s2.y - s0.y) - (s1.y - s0.y) * (s2.x - s0.x)
        if cross > 0 { vertices.reverse() }
        var face = PaperFace(vertices: vertices, originalSide: pocket, isMoving: moving)
        let layer: Float = corner == 0 ? 0.00020 : 0.00010
        for j in face.vertices.indices { face.vertices[j].separation = face.normal * layer }
        return Patch(face: face, pocket: pocket, corner: corner)
    }

    private static func flat(_ point: SIMD2<Float>) -> SIMD3<Float> { [point.x, 0, point.y] }

    /// Hide triangulation until a lesson action actually makes that crease.
    private static func outline(_ p: SIMD2<Float>, _ q: SIMD2<Float>, step: Int) -> Bool {
        let tolerance: Float = 0.000002
        for x: Float in [-1, 1] {
            for z: Float in [-1, 1] {
                let n = SIMD2<Float>(x, z)
                if abs(simd_dot(p, n) - a) < tolerance && abs(simd_dot(q, n) - a) < tolerance { return true }
            }
        }
        func onLine(_ start: SIMD2<Float>, _ end: SIMD2<Float>) -> Bool {
            let d = end - start
            let n = SIMD2<Float>(-d.y, d.x) / simd_length(d)
            return abs(simd_dot(p - start, n)) < tolerance && abs(simd_dot(q - start, n)) < tolerance
        }
        if step >= 1 && onLine([-a, 0], [a, 0]) { return true }
        if step >= 2 && onLine([0, -a], [0, a]) { return true }
        for pocket in [-1, 1] {
            let c = SIMD2<Float>(Float(pocket) * a, 0)
            for corner in [-1, 1] {
                let other = SIMD2<Float>(0, Float(corner) * a)
                let midpoint = (c + other) / 2
                let hs = midpoint * (2 * h / a)
                if step >= (pocket == -1 ? 3 : 5) && onLine(.zero, midpoint) { return true }
                let markStep = pocket == 1 ? (corner == -1 ? 6 : 7) : (corner == -1 ? 11 : 12)
                if step >= markStep && (onLine(hs, c) || onLine(hs, other)) { return true }
                if step >= 8 && (onLine(hs, c * (h / a)) || onLine(hs, other * (h / a))) { return true }
            }
        }
        return false
    }

    private static func rotate(_ point: SIMD3<Float>, origin: SIMD3<Float>,
                               axis: SIMD3<Float>, angle: Float) -> SIMD3<Float> {
        let n = simd_normalize(axis), v = point - origin
        return origin + v * cos(angle) + simd_cross(n, v) * sin(angle)
            + n * simd_dot(n, v) * (1 - cos(angle))
    }

    private static func arc(point: SIMD3<Float>, origin: SIMD3<Float>,
                            axis: SIMD3<Float>, angle: Float) -> [SIMD3<Float>] {
        (0...28).map { rotate(point, origin: origin, axis: axis, angle: angle * Float($0) / 28) }
    }

    private static func applyFold(_ patches: inout [Patch], point: SIMD3<Float>, axis: SIMD3<Float>,
                                  normal: SIMD3<Float>, angle: Float,
                                  select: (Patch) -> Bool, moving: Bool, markPoint: Bool = false) {
        var result = [Patch]()
        for patch in patches {
            guard select(patch) else { result.append(patch); continue }
            for positive in [false, true] {
                var vertices = clip(patch.face.vertices, point: point, normal: normal, positive: positive)
                guard vertices.count >= 3 else { continue }
                if positive {
                    for i in vertices.indices {
                        vertices[i].position = rotate(vertices[i].position, origin: point, axis: axis, angle: angle)
                        vertices[i].separation = rotate(vertices[i].separation, origin: .zero, axis: axis, angle: angle)
                    }
                }
                let face = PaperFace(vertices: vertices, originalSide: patch.face.originalSide,
                                     isMoving: patch.face.isMoving || (positive && moving))
                if face.area > 1e-12 {
                    result.append(Patch(face: face, pocket: patch.pocket, corner: patch.corner,
                                        pointSegment: patch.pointSegment || (positive && markPoint)))
                }
            }
        }
        patches = result
    }

    private static func clip(_ vertices: [PaperVertex], point: SIMD3<Float>, normal: SIMD3<Float>,
                              positive: Bool) -> [PaperVertex] {
        var result = [PaperVertex]()
        for i in vertices.indices {
            let current = vertices[i], next = vertices[(i + 1) % vertices.count]
            let da = simd_dot(current.position - point, normal)
            let db = simd_dot(next.position - point, normal)
            let insideA = positive ? da >= -epsilon : da <= epsilon
            let insideB = positive ? db >= -epsilon : db <= epsilon
            if insideA { result.append(current) }
            if insideA != insideB, abs(da - db) > epsilon {
                result.append(PaperVertex.interpolate(current, next, min(1, max(0, da / (da - db)))))
            }
        }
        return result
    }

    private static func separateForView(_ patches: inout [Patch], amount: Float, region: Int) {
        for i in patches.indices {
            for j in patches[i].face.vertices.indices {
                let point = patches[i].face.vertices[j].position
                let weight: Float
                if region == 0 { weight = max(0, 1 - abs(point.z - h) / (a * 0.45)) }
                else { weight = patches[i].corner == -1 ? 0.35 : 0 }
                patches[i].face.vertices[j].separation.y += Float(-patches[i].pocket) * 0.007 * amount * weight
            }
        }
    }
}
