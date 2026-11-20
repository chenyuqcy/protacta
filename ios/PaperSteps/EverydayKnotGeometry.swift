import Foundation
import simd

/// Authored spatial teaching routes. These meshes show which strand goes above
/// or below another; they are not a rope-contact or fabric simulation.
/// Diagram left is model -X, the far edge is -Z and height is +Y.
enum EverydayKnotGeometry {
    private typealias Point = SIMD3<Float>
    private static let sampleCount = 161
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
        // Sample each standing section and its working end as one curve. Two
        // independently capped tubes formerly met here with different tangents,
        // leaving an angular seam as the knot was dressed. The only remaining
        // join is the colour boundary, on a straight run away from the knot.
        func continuous(_ route: [Point], side: Float) -> [Point] {
            let end = route[0], direction = simd_normalize(route[1] - route[0])
            let start = Point(side * 0.06, 0.045, 0.39)
            let first = Point(side * 0.45, 0.045, 0.39), last = end - direction * 0.14
            // A cubic standing bend has a horizontal tangent at the colour
            // boundary and enters the working route along its own tangent.
            // There is no extra corner/control point at the old side join.
            var controls = [Point(0, 0.045, 0.39), Point(side * 0.02, 0.045, 0.39), Point(side * 0.04, 0.045, 0.39)]
            controls += (0...24).map { index -> Point in
                let t = Float(index) / 24, s = 1 - t
                return start * (s * s * s) + first * (3 * s * s * t)
                    + last * (3 * s * t * t) + end * (t * t * t)
            }
            // Uniform Catmull-Rom tangents must not be pulled backwards by a
            // half-metre straight tail adjacent to a short standing bend.
            // Only subdivide this incoming leg; the authored knot controls
            // retain their rounded bights and original over/under crossings.
            let sections = max(1, Int(ceil(simd_distance(route[0], route[1]) / 0.045)))
            for section in 1...sections {
                controls.append(route[0] + (route[1] - route[0]) * (Float(section) / Float(sections)))
            }
            controls += route.dropFirst(2)
            return controls
        }
        let aStart = continuous(start.a, side: -1), aEnd = continuous(end.a, side: -1)
        let bStart = continuous(start.b, side: 1), bEnd = continuous(end.b, side: 1)
        return [tube(id: "cord-A", route: interpolate(aStart, aEnd, amount: amount),
                     radius: cordRadius, color: 1, moving: true,
                     orientation: transitionFrames(aStart, aEnd, amount: amount)),
                tube(id: "cord-B", route: interpolate(bStart, bEnd, amount: amount),
                     radius: cordRadius, color: 2, moving: true,
                     orientation: transitionFrames(bStart, bEnd, amount: amount))]
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
        let wideStart = tieWide(state: action), wideEnd = tieWide(state: action + 1)
        let narrowStart = tieNarrow(state: action), narrowEnd = tieNarrow(state: action + 1)
        let wide = interpolate(wideStart, wideEnd, amount: amount)
        let narrow = interpolate(narrowStart, narrowEnd, amount: amount)
        let baseWideFrames = transitionFrames(wideStart, wideEnd, amount: amount, faceForward: true)
        let startRoll = tieWideRoll(state: action), endRoll = tieWideRoll(state: action + 1)
        let wideFrames = baseWideFrames.indices.map { index in
            let frame = baseWideFrames[index]
            let roll = startRoll[index] + (endRoll[index] - startRoll[index]) * amount
            return (side: frame.side * cos(roll) + frame.normal * sin(roll),
                    normal: frame.normal * cos(roll) - frame.side * sin(roll))
        }
        let narrowFrames = transitionFrames(narrowStart, narrowEnd, amount: amount, faceForward: true)
        let neck = smooth(tieNeck)
        let collarAmount: Float = action == 6 ? amount : 0
        var result = [ribbon(id: "tie-wide-W", route: wide, width: 0.047, pointed: true, color: 1, moving: action < 6,
                             orientation: wideFrames, neckWidth: 0.018),
                      ribbon(id: "tie-narrow-N", route: narrow, width: 0.020, pointed: true, color: 2, moving: action == 6,
                             orientation: narrowFrames),
                      ribbon(id: "tie-neck-loop", route: neck, width: 0.016, pointed: false, color: 1, moving: false)]
        result += [collar(left: true, amount: collarAmount), collar(left: false, amount: collarAmount)]
        // The physical keeper sits on the back of W. It remains attached to the
        // same tail region as the blade moves; orbiting reveals the rear gap.
        // Keep the keeper on the hanging blade, below the knot. A fraction near
        // the knot mistakenly moved the narrow tail back into the front wrap.
        let index = Int(Float(wide.count - 1) * 0.91)
        let center = wide[index]
        let frame = wideFrames[index]
        // The keeper is sewn inside W's 47 mm blade. Its old 56 mm span
        // protruded as two dark ears even when viewed directly from the front.
        let localKeeper = smooth([Point(-0.019, -0.0035, 0), Point(-0.01425, -0.018, 0),
                                  Point(0.01425, -0.018, 0), Point(0.019, -0.0035, 0)], minimumHeight: nil)
        let along = simd_cross(frame.side, frame.normal)
        func transform(_ local: Point) -> Point {
            frame.side * local.x + frame.normal * local.y + along * local.z
        }
        // A sewn loop follows the blade's material frame, including its back
        // direction. World-Y offsets and separately interpolated loop frames
        // otherwise swing the keeper sideways during an intermediate tuck.
        let keeperRoute = localKeeper.map { center + transform($0) }
        let keeperFrames = frames(route: localKeeper).map {
            (side: transform($0.side), normal: transform($0.normal))
        }
        result.append(ribbon(id: "tie-rear-keeper", route: keeperRoute, width: 0.016,
                             pointed: false, color: 4, moving: action < 6,
                             orientation: keeperFrames))
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
                               point(202, 105, 0.06), point(224, 145, 0.145), point(209, 221, 0.082),
                               point(201, 275, 0.075), point(199, 305, 0.115), point(199, 350, 0.125)]
        default:
            // Dress the same crossing sequence near the collar. The descending
            // blade is between the rear wrap and front band, then emerges below
            // it. It must never be drawn on top of the band it passes through.
            return [point(155, 115, 0.075), point(176, 158, 0.075), point(194, 174, 0.084),
                    point(209, 177, 0.070), point(207, 181, 0.055), point(190, 181, 0.055),
                    point(186, 184, 0.078), point(192, 187, 0.105), point(207, 187, 0.105),
                    point(213, 183, 0.078), point(209, 180, 0.055), point(201, 176, 0.055),
                    point(200, 174, 0.060), point(204, 179, 0.085), point(201, 187, 0.077),
                    point(199, 204, 0.105), point(199, 350, 0.115)]
        }
    }

    private static func tieNarrow(state: Int) -> [Point] {
        if state < 7 {
            return [point(245, 115, 0.055), point(224, 222, 0.055), point(218, 325, 0.045)]
        }
        let wide = smooth(tieWide(state: 6))
        let insideGap = Point(0, -0.009, 0)
        let blade = wide.enumerated().filter { $0.offset > wide.count / 2 && $0.element.z >= point(199, 220, 0).z }
        // Follow the actual back of W through the keeper and stop before its
        // pointed tip; a single diagonal shortcut exposed an orange stripe.
        return [point(245, 115, 0.055), point(221, 149, 0.045), point(202, 195, 0.055)]
            + blade.filter { $0.offset < Int(Float(wide.count - 1) * 0.97) }.map { $0.element + insideGap }
    }

    /// In a dressed tie the front wrap is a band around the knot, not a flat
    /// ribbon that flips to face the camera on the back half of every turn.
    /// Keeping its width along the knot axis produces one continuous outside
    /// face. The open teaching poses retain their exaggerated readable routes.
    private static func tieWideRoll(state: Int) -> [Float] {
        guard state >= 6 else { return Array(repeating: 0, count: sampleCount) }
        let controls = tieWide(state: state), route = smooth(controls)
        let basis = frames(route: route, faceForward: true)
        var result = Array(repeating: Float(0), count: route.count)
        func closest(_ control: Int) -> Int {
            route.indices.min { simd_distance_squared(route[$0], controls[control]) <
                simd_distance_squared(route[$1], controls[control]) }!
        }
        let first = closest(3), last = closest(9)
        for index in max(0, first - 4)...min(route.count - 1, last + 4) {
            let tangent = simd_normalize(route[min(route.count - 1, index + 1)] - route[max(0, index - 1)])
            let axis = Point(0, 0, 1)
            let projected = axis - tangent * simd_dot(axis, tangent)
            guard simd_length_squared(projected) > 1e-8 else { continue }
            let side = simd_normalize(projected)
            let amount = min(1, Float(min(index - first + 4, last + 4 - index)) / 4)
            // A bounded material roll (zero outside the wrap) avoids adding a
            // whole quaternion turn to the free blade during knot tightening.
            result[index] = -acos(max(-1, min(1, simd_dot(basis[index].side, side)))) * amount
        }
        return result.indices.map { index in
            var angle: Float = 0, weight: Float = 0
            for offset in -4...4 {
                let w = Float(5 - abs(offset))
                angle += result[min(result.count - 1, max(0, index + offset))] * w
                weight += w
            }
            return angle / weight
        }
    }

    private static let tieNeck = [point(155, 115, 0.075), point(140, 84, 0.075), point(162, 52, 0.075),
                                  point(200, 42, 0.075), point(238, 52, 0.075), point(260, 84, 0.075),
                                  point(245, 115, 0.055)]

    private static func collar(left: Bool, amount: Float) -> EverydayMeshPart {
        let neck = smooth(tieNeck)
        let midpoint = (neck.count - 1) / 2
        let indices = left ? Array(0...midpoint) : Array(midpoint..<neck.count)
        let center = point(200, 90, 0)
        var positions: [Point] = [], triangles: [UInt32] = []
        for index in indices {
            let p = neck[index]
            let radial = simd_normalize(Point(p.x - center.x, 0, p.z - center.z))
            let hinge = p + radial * 0.032 + Point(0, 0.028, 0)
            // Raised panels pivot down over the neck band rather than turning
            // into the two edge-on triangles used by the earlier placeholder.
            let angle = amount * Float.pi / 2
            let edge = hinge - radial * (sin(angle) * 0.064) + Point(0, cos(angle) * 0.064, 0)
            positions += [hinge, edge]
        }
        for row in 0..<(indices.count - 1) {
            let i = UInt32(row * 2)
            triangles += [i, i + 2, i + 1, i + 1, i + 2, i + 3]
        }
        return EverydayMeshPart(id: left ? "tie-collar-left" : "tie-collar-right", positions: positions,
                                triangles: triangles, colorIndex: 3, isMoving: amount > 0, surfaceThickness: 0.0005)
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
    private static func smooth(_ controls: [Point], minimumHeight: Float? = 0.018) -> [Point] {
        guard controls.count >= 2 else { return Array(repeating: controls.first ?? .zero, count: sampleCount) }
        var dense: [Point] = []
        for i in 0..<(controls.count - 1) {
            let p0 = controls[max(0, i - 1)], p1 = controls[i]
            let p2 = controls[i + 1], p3 = controls[min(controls.count - 1, i + 2)]
            for j in 0..<10 {
                let t = Float(j) / 10, t2 = t * t, t3 = t2 * t
                let linear: Point = (p2 - p0) * t
                let q0: Point = p0 * 2
                let q1: Point = p1 * 5
                let q2: Point = p2 * 4
                let quadratic: Point = (q0 - q1 + q2 - p3) * t2
                let c1: Point = p1 * 3
                let c2: Point = p2 * 3
                let cubic: Point = (-p0 + c1 - c2 + p3) * t3
                let base: Point = p1 * 2
                var p: Point = (base + linear + quadratic + cubic) * 0.5
                if let minimumHeight { p.y = max(minimumHeight, p.y) }
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

    /// Parallel transport keeps a strand's cross-section continuous as it turns
    /// upright. Choosing a fresh world-up axis at each ring made the ribbon
    /// jump by its entire width when a tangent crossed the old 0.92 threshold.
    private static func frames(route: [Point], faceForward: Bool = false) -> [(side: Point, normal: Point)] {
        guard !route.isEmpty else { return [] }
        let tangents: [Point] = route.indices.map { index in
            let delta = route[min(route.count - 1, index + 1)] - route[max(0, index - 1)]
            return simd_length_squared(delta) > 1e-12 ? simd_normalize(delta) : Point(0, 0, 1)
        }
        let first = tangents[0]
        let reference = abs(first.y) < 0.999 ? Point(0, 1, 0) : Point(1, 0, 0)
        var side = simd_normalize(simd_cross(first, reference))
        var result = [(side: side, normal: simd_normalize(simd_cross(side, first)))]
        for index in 1..<route.count {
            let before = tangents[index - 1], after = tangents[index]
            let axis = simd_cross(before, after)
            let sine = simd_length(axis)
            let cosine = max(-1, min(1, simd_dot(before, after)))
            if sine > 1e-6 {
                let direction = axis / sine
                side = side * cosine + simd_cross(direction, side) * sine
                    + direction * simd_dot(direction, side) * (1 - cosine)
            }
            // A straight reversal can retain its side: a half-turn around that
            // side maps the previous tangent to the next without an axis guess.
            let projected = side - after * simd_dot(side, after)
            if simd_length_squared(projected) > 1e-12 { side = simd_normalize(projected) }
            result.append((side: side, normal: simd_normalize(simd_cross(side, after))))
        }
        guard faceForward else { return result }
        // Retain transported frames as the singularity fallback, but remove
        // accumulated roll for teaching ribbons. Otherwise the front band can
        // become edge-on and the hanging blade can twist over its narrow tail.
        let facing = zip(tangents, result).map { tangent, transported in
            let across = simd_cross(tangent, Point(0, 1, 0))
            guard simd_length_squared(across) > 1e-8 else { return transported }
            // Keep the same signed front-facing width in each authored pose.
            // Selecting its sign from the preceding ring can reverse the whole
            // free blade after a tuck, producing an unnecessary half-roll when
            // interpolating two otherwise broad, forward-facing endpoint poses.
            let side = simd_normalize(across)
            return (side: side, normal: simd_normalize(simd_cross(side, tangent)))
        }
        return smoothedFrames(facing)
    }

    private static func smoothedFrames(_ facing: [(side: Point, normal: Point)]) -> [(side: Point, normal: Point)] {
        // Spread the roll of a tight fabric turn across neighbouring sections.
        // This retains a broad face without concentrating a half-turn into one
        // narrow mesh strip when the route bends up and back down.
        var rotations: [SIMD4<Float>] = []
        for frame in facing {
            var q = simd_quatf(simd_float3x3(columns: (frame.side, frame.normal,
                                                     simd_cross(frame.side, frame.normal)))).vector
            if let before = rotations.last, simd_dot(before, q) < 0 { q = -q }
            rotations.append(q)
        }
        return rotations.indices.map { index in
            var total = SIMD4<Float>(repeating: 0)
            for offset in -3...3 {
                let other = min(rotations.count - 1, max(0, index + offset))
                total += rotations[other] * Float(4 - abs(offset))
            }
            let rotation = simd_quatf(vector: simd_normalize(total))
            return (side: rotation.act(Point(1, 0, 0)), normal: rotation.act(Point(0, 1, 0)))
        }
    }

    /// Interpolate authored frame orientations as well as positions. Rebuilding
    /// orientation from a temporarily collapsing intermediate curve can spin a
    /// whole ribbon even when its centreline moves by less than a millimetre.
    /// Quaternion interpolation preserves the endpoint poses and is reversible
    /// when the learner scrubs the timeline backwards.
    private static func transitionFrames(_ start: [Point], _ end: [Point], amount: Float, faceForward: Bool = false)
        -> [(side: Point, normal: Point)] {
        let a = frames(route: smooth(start), faceForward: faceForward), b = frames(route: smooth(end), faceForward: faceForward)
        if amount <= 0 { return a }
        if amount >= 1 { return b }
        func orientations(_ source: [(side: Point, normal: Point)]) -> [SIMD4<Float>] {
            var result: [SIMD4<Float>] = []
            for frame in source {
                var value = simd_quatf(simd_float3x3(columns:
                    (frame.side, frame.normal, simd_cross(frame.side, frame.normal)))).vector
                if let previous = result.last, simd_dot(previous, value) < 0 { value = -value }
                result.append(value)
            }
            return result
        }
        let first = orientations(a)
        var last = orientations(b)
        if simd_dot(first[0], last[0]) < 0 { last = last.map { -$0 } }
        return zip(first, last).map { start, finish in
            // Quaternion signs are unwrapped along each strand. Selecting the
            // shortest rotation separately at each ring creates a visible twist
            // seam where adjacent rings choose opposite interpolation arcs.
            let dot = max(-1, min(1, simd_dot(start, finish)))
            let mixed: SIMD4<Float>
            if dot > 0.9995 {
                mixed = simd_normalize(start + (finish - start) * amount)
            } else {
                let residual = finish - start * dot
                let perpendicular: SIMD4<Float>
                if simd_length_squared(residual) > 1e-12 {
                    perpendicular = simd_normalize(residual)
                } else {
                    // Exact antipodes have no unique arc. Keep a finite,
                    // deterministic half-circle rather than divide by zero.
                    let component = (0..<4).min { abs(start[$0]) < abs(start[$1]) }!
                    var axis = SIMD4<Float>(repeating: 0); axis[component] = 1
                    perpendicular = simd_normalize(axis - start * simd_dot(axis, start))
                }
                let angle = acos(dot) * amount
                mixed = start * cos(angle) + perpendicular * sin(angle)
            }
            let rotation = simd_quatf(vector: simd_normalize(mixed))
            return (side: rotation.act(Point(1, 0, 0)), normal: rotation.act(Point(0, 1, 0)))
        }
    }

    private static func tube(id: String, route: [Point], radius: Float, color: Int, moving: Bool,
                             orientation: [(side: Point, normal: Point)]? = nil) -> EverydayMeshPart {
        let sides = 10
        var positions: [Point] = [], triangles: [UInt32] = []
        let routeFrames = orientation ?? frames(route: route)
        for i in route.indices {
            let frame = routeFrames[i]
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

    private static func ribbon(id: String, route: [Point], width: Float, pointed: Bool, color: Int, moving: Bool,
                               orientation: [(side: Point, normal: Point)]? = nil,
                               neckWidth: Float? = nil) -> EverydayMeshPart {
        var positions: [Point] = [], triangles: [UInt32] = [], uvs: [SIMD2<Float>] = []
        let routeFrames = orientation ?? frames(route: route)
        let ribbonThickness: Float = 0.0026
        for i in route.indices {
            let frame = routeFrames[i]
            let t = Float(i) / Float(route.count - 1)
            let tip = pointed ? max(0.012, min(1, (1 - t) / 0.075)) : 1
            let sectionWidth = neckWidth.map { $0 + (width - $0) * min(1, t / 0.72) } ?? width
            let half = sectionWidth * tip / 2
            let thickness = ribbonThickness / 2
            let center: Point = route[i]
            let side: Point = frame.side * half
            let up: Point = frame.normal * thickness
            positions += [center - side - up,
                          center + side - up,
                          center + side + up,
                          center - side + up]
            // Material coordinates are authored in metres, independent of the
            // current folded route. Scrubbing and dressing cannot stretch or
            // restart the weave. Opposite faces share the same fabric sample.
            let materialLength: Float
            switch id {
            case "tie-wide-W": materialLength = 0.82
            case "tie-narrow-N": materialLength = 0.55
            case "tie-neck-loop": materialLength = 0.36
            default: materialLength = 0.075 // keeper sewn to the rear of W
            }
            uvs += [SIMD2(0, t * materialLength), SIMD2(sectionWidth * tip, t * materialLength),
                    SIMD2(sectionWidth * tip, t * materialLength), SIMD2(0, t * materialLength)]
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
        return EverydayMeshPart(id: id, positions: positions, triangles: triangles, colorIndex: color,
                                isMoving: moving, fabricUVs: uvs, closedRibbonThickness: ribbonThickness)
    }
}
