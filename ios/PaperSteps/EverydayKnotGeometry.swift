import Foundation
import simd

/// Authored spatial teaching routes. These meshes show which strand goes above
/// or below another; they are not a rope-contact or fabric simulation.
/// Diagram left is model -X, the far edge is -Z and height is +Y.
enum EverydayKnotGeometry {
    private typealias Point = SIMD3<Float>
    private static let sampleCount = 81
    private static let cordRadius: Float = 0.009

    static func parts(courseID: EverydayTutorialID, actionIndex: Int, progress: Double) -> [EverydayMeshPart] {
        let count = courseID == .squareKnot ? 5 : 7
        let action = min(count - 1, max(0, actionIndex))
        let amount = progress.isFinite ? Float(min(1, max(0, progress))) : 0
        switch courseID {
        case .squareKnot: return squareParts(action: action, amount: amount)
        case .fourInHand: return tieParts(action: action, amount: amount)
        default: return []
        }
    }

    private static func squareParts(action: Int, amount: Float) -> [EverydayMeshPart] {
        let start = squareRoutes(state: action), end = squareRoutes(state: action + 1)
        let a = interpolate(start.a, end.a, amount: amount)
        let b = interpolate(start.b, end.b, amount: amount)
        // The standing sections join outside the knot, making this one practice
        // cord with two named ends rather than two disconnected floating ropes.
        let aJoin = smooth([a[0], Point(-0.30, 0.045, 0.35), Point(-0.18, 0.045, 0.39), Point(0, 0.045, 0.39)])
        let bJoin = smooth([b[0], Point(0.30, 0.045, 0.35), Point(0.18, 0.045, 0.39), Point(0, 0.045, 0.39)])
        return [tube(id: "cord-A", route: a, radius: cordRadius, color: 1, moving: true),
                tube(id: "cord-B", route: b, radius: cordRadius, color: 2, moving: true),
                tube(id: "cord-A-standing", route: aJoin, radius: cordRadius, color: 1, moving: action == 4),
                tube(id: "cord-B-standing", route: bJoin, radius: cordRadius, color: 2, moving: action == 4)]
    }

    private static func squareRoutes(state: Int) -> (a: [Point], b: [Point]) {
        let firstA = [point(85, 340, 0.05), point(135, 280, 0.05), point(175, 248, 0.102),
                      point(222, 260, 0.102), point(247, 236, 0.075), point(223, 214, 0.035), point(194, 225, 0.035)]
        let firstB = [point(315, 340, 0.05), point(263, 280, 0.05), point(225, 248, 0.035),
                      point(178, 260, 0.035), point(153, 236, 0.075), point(177, 214, 0.102), point(206, 225, 0.102)]
        switch state {
        case 0:
            return ([point(85, 340, 0.05), point(120, 110, 0.05)],
                    [point(315, 340, 0.05), point(280, 110, 0.05)])
        case 1:
            return ([point(85, 340, 0.05), point(155, 245, 0.065), point(200, 220, 0.105), point(280, 110, 0.075)],
                    [point(315, 340, 0.05), point(245, 245, 0.045), point(200, 220, 0.035), point(120, 110, 0.045)])
        case 2:
            return (firstA + [point(200, 200, 0.04), point(250, 150, 0.06), point(290, 105, 0.06)],
                    firstB + [point(200, 200, 0.115), point(150, 150, 0.08), point(110, 105, 0.06)])
        case 3:
            return (firstA + [point(245, 180, 0.08), point(205, 140, 0.15), point(115, 95, 0.11)],
                    firstB + [point(155, 180, 0.08), point(195, 140, 0.055), point(285, 95, 0.065)])
        case 4:
            return (firstA + [point(248, 192, 0.10), point(250, 155, 0.09), point(223, 134, 0.055),
                             point(187, 154, 0.055), point(150, 125, 0.08), point(95, 100, 0.08)],
                    firstB + [point(152, 192, 0.08), point(150, 155, 0.09), point(177, 134, 0.125),
                             point(213, 154, 0.125), point(250, 125, 0.08), point(305, 100, 0.08)])
        default:
            // Two bights with the two opposite over/under crossings retained.
            // Each free end leaves alongside its own standing section.
            return ([point(70, 285, 0.05), point(140, 250, 0.05), point(185, 238, 0.102),
                     point(225, 252, 0.102), point(255, 240, 0.102), point(263, 213, 0.07),
                     point(246, 188, 0.035), point(215, 185, 0.035), point(180, 201, 0.035),
                     point(140, 186, 0.05), point(70, 160, 0.05)],
                    [point(330, 285, 0.05), point(260, 250, 0.05), point(215, 238, 0.035),
                     point(175, 252, 0.035), point(145, 240, 0.035), point(137, 213, 0.07),
                     point(154, 188, 0.102), point(185, 185, 0.102), point(220, 201, 0.102),
                     point(260, 186, 0.05), point(330, 160, 0.05)])
        }
    }

    private static func tieParts(action: Int, amount: Float) -> [EverydayMeshPart] {
        let wide = interpolate(tieWide(state: action), tieWide(state: action + 1), amount: amount)
        let narrow = interpolate(tieNarrow(state: action), tieNarrow(state: action + 1), amount: amount)
        let neck = smooth([point(155, 115, 0.075), point(140, 84, 0.075), point(162, 52, 0.075),
                           point(200, 42, 0.075), point(238, 52, 0.075), point(260, 84, 0.075), point(245, 115, 0.055)])
        let collarAmount: Float = action == 6 ? amount : 0
        var result = [ribbon(id: "tie-wide-W", route: wide, width: 0.047, pointed: true, color: 1, moving: action < 6),
                      ribbon(id: "tie-narrow-N", route: narrow, width: 0.020, pointed: true, color: 2, moving: action == 6),
                      ribbon(id: "tie-neck-loop", route: neck, width: 0.016, pointed: false, color: 1, moving: false)]
        result += [collar(left: true, amount: collarAmount), collar(left: false, amount: collarAmount)]
        // The physical keeper sits on the back of W. It remains attached to the
        // same tail region as the blade moves; orbiting reveals the rear gap.
        let index = Int(Float(wide.count - 1) * 0.79)
        let center = wide[index]
        let frame = basis(route: wide, index: index)
        let across = frame.side * 0.028
        let behind = Point(0, -0.010, 0)
        let keeperRoute = smooth([center - across, center - across * 0.75 + behind,
                                  center + across * 0.75 + behind, center + across])
        result.append(ribbon(id: "tie-rear-keeper", route: keeperRoute, width: 0.016,
                             pointed: false, color: 4, moving: action < 6))
        return result
    }

    private static func tieWide(state: Int) -> [Point] {
        let first = [point(155, 115, 0.075), point(145, 170, 0.075), point(195, 211, 0.105)]
        let wrap = first + [point(244, 227, 0.065), point(224, 247, 0.035), point(170, 252, 0.035)]
        let band = wrap + [point(185, 271, 0.115), point(236, 278, 0.115)]
        switch state {
        case 0: return [point(155, 115, 0.075), point(142, 190, 0.075), point(135, 275, 0.075), point(130, 355, 0.075)]
        case 1: return first + [point(250, 250, 0.105), point(287, 325, 0.085)]
        case 2: return wrap + [point(125, 310, 0.065)]
        case 3: return band + [point(285, 315, 0.095)]
        case 4: return band + [point(251, 249, 0.04), point(224, 202, 0.035), point(200, 151, 0.04), point(200, 87, 0.055)]
        case 5: return band + [point(251, 249, 0.04), point(224, 202, 0.035), point(200, 151, 0.04),
                               point(202, 105, 0.06), point(233, 145, 0.145), point(218, 212, 0.145),
                               point(203, 267, 0.145), point(199, 350, 0.125)]
        default:
            return [point(155, 115, 0.075), point(155, 165, 0.075), point(197, 182, 0.105),
                    point(230, 191, 0.065), point(211, 207, 0.035), point(176, 206, 0.035),
                    point(191, 227, 0.115), point(225, 226, 0.115), point(228, 199, 0.045),
                    point(201, 169, 0.045), point(202, 135, 0.055), point(220, 165, 0.145),
                    point(203, 220, 0.145), point(199, 350, 0.125)]
        }
    }

    private static func tieNarrow(state: Int) -> [Point] {
        if state < 7 {
            return [point(245, 115, 0.055), point(224, 222, 0.055), point(218, 325, 0.045)]
        }
        let wide = smooth(tieWide(state: 6))
        let keeper = wide[Int(Float(wide.count - 1) * 0.79)]
        let tail = wide[Int(Float(wide.count - 1) * 0.95)]
        let insideGap = Point(0, -0.005, 0)
        return [point(245, 115, 0.055), point(224, 222, 0.055), keeper + insideGap, tail + insideGap]
    }

    private static func collar(left: Bool, amount: Float) -> EverydayMeshPart {
        let sign: Float = left ? -1 : 1
        let positions = [Point(sign * 0.115, 0.085, -0.25), Point(sign * 0.005, 0.085, -0.26),
                         Point(sign * 0.06, 0.175 - 0.11 * amount, -0.20 - 0.08 * amount)]
        return EverydayMeshPart(id: left ? "tie-collar-left" : "tie-collar-right", positions: positions,
                                triangles: left ? [0, 1, 2] : [0, 2, 1], colorIndex: 3, isMoving: amount > 0)
    }

    private static func point(_ x: Float, _ z: Float, _ height: Float) -> Point {
        Point((x - 200) * 0.0022, height, (z - 210) * 0.0022)
    }

    private static func interpolate(_ start: [Point], _ end: [Point], amount: Float) -> [Point] {
        if amount <= 0 { return smooth(start) }
        if amount >= 1 { return smooth(end) }
        let a = smooth(start), b = smooth(end)
        return zip(a, b).map { $0 + ($1 - $0) * amount }
    }

    /// Cubic smoothing followed by distance sampling keeps a stable ring count
    /// and the free tip at the same final index across every authored action.
    private static func smooth(_ controls: [Point]) -> [Point] {
        guard controls.count >= 2 else { return Array(repeating: controls.first ?? .zero, count: sampleCount) }
        var dense: [Point] = []
        for i in 0..<(controls.count - 1) {
            let p0 = controls[max(0, i - 1)], p1 = controls[i]
            let p2 = controls[i + 1], p3 = controls[min(controls.count - 1, i + 2)]
            for j in 0..<10 {
                let t = Float(j) / 10, t2 = t * t, t3 = t2 * t
                let linear: Point = (p2 - p0) * t
                let quadratic: Point = (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
                let cubic: Point = (-p0 + p1 * 3 - p2 * 3 + p3) * t3
                var p: Point = (p1 * 2 + linear + quadratic + cubic) * 0.5
                p.y = max(0.018, p.y)
                dense.append(p)
            }
        }
        dense.append(controls.last!)
        var lengths: [Float] = [0]
        for i in 1..<dense.count { lengths.append(lengths.last! + simd_distance(dense[i - 1], dense[i])) }
        let total = lengths.last!
        guard total > 0.000001 else { return Array(repeating: dense[0], count: sampleCount) }
        var segment = 0
        return (0..<sampleCount).map { index in
            let distance = total * Float(index) / Float(sampleCount - 1)
            while segment + 1 < lengths.count - 1 && lengths[segment + 1] < distance { segment += 1 }
            let amount = (distance - lengths[segment]) / max(0.000001, lengths[segment + 1] - lengths[segment])
            return dense[segment] + (dense[segment + 1] - dense[segment]) * amount
        }
    }

    private static func basis(route: [Point], index: Int) -> (side: Point, normal: Point) {
        let delta = route[min(route.count - 1, index + 1)] - route[max(0, index - 1)]
        let tangent = simd_length_squared(delta) > 1e-12 ? simd_normalize(delta) : Point(0, 0, 1)
        let reference = abs(tangent.y) < 0.92 ? Point(0, 1, 0) : Point(1, 0, 0)
        let side = simd_normalize(simd_cross(tangent, reference))
        return (side, simd_normalize(simd_cross(side, tangent)))
    }

    private static func tube(id: String, route: [Point], radius: Float, color: Int, moving: Bool) -> EverydayMeshPart {
        let sides = 10
        var positions: [Point] = [], triangles: [UInt32] = []
        for i in route.indices {
            let frame = basis(route: route, index: i)
            for j in 0..<sides {
                let angle = 2 * Float.pi * Float(j) / Float(sides)
                positions.append(route[i] + radius * (cos(angle) * frame.side + sin(angle) * frame.normal))
            }
        }
        for i in 0..<(route.count - 1) {
            for j in 0..<sides {
                let a = UInt32(i * sides + j), b = UInt32(i * sides + (j + 1) % sides)
                let c = UInt32((i + 1) * sides + j), d = UInt32((i + 1) * sides + (j + 1) % sides)
                triangles += [a, c, b, b, c, d]
            }
        }
        let first = UInt32(positions.count); positions.append(route[0])
        let last = UInt32(positions.count); positions.append(route.last!)
        let offset = UInt32((route.count - 1) * sides)
        for j in 0..<sides {
            let a = UInt32(j), b = UInt32((j + 1) % sides)
            triangles += [first, a, b, last, offset + b, offset + a]
        }
        return EverydayMeshPart(id: id, positions: positions, triangles: triangles, colorIndex: color, isMoving: moving)
    }

    private static func ribbon(id: String, route: [Point], width: Float, pointed: Bool, color: Int, moving: Bool) -> EverydayMeshPart {
        var positions: [Point] = [], triangles: [UInt32] = []
        for i in route.indices {
            let frame = basis(route: route, index: i)
            let t = Float(i) / Float(route.count - 1)
            let tip = pointed ? max(0.012, min(1, (1 - t) / 0.075)) : 1
            let half = width * tip / 2
            let thickness: Float = 0.0013
            positions += [route[i] - frame.side * half - frame.normal * thickness,
                          route[i] + frame.side * half - frame.normal * thickness,
                          route[i] + frame.side * half + frame.normal * thickness,
                          route[i] - frame.side * half + frame.normal * thickness]
        }
        for i in 0..<(route.count - 1) {
            for j in 0..<4 {
                let a = UInt32(i * 4 + j), b = UInt32(i * 4 + (j + 1) % 4)
                let c = UInt32((i + 1) * 4 + j), d = UInt32((i + 1) * 4 + (j + 1) % 4)
                triangles += [a, c, b, b, c, d]
            }
        }
        let end = UInt32((route.count - 1) * 4)
        triangles += [0, 1, 2, 0, 2, 3, end, end + 2, end + 1, end, end + 3, end + 2]
        return EverydayMeshPart(id: id, positions: positions, triangles: triangles, colorIndex: color, isMoving: moving)
    }
}
