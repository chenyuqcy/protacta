import Foundation
import simd

/// An authored lucky-star lesson using one persistent strip coordinate system.
/// The overhand knot is a continuous ribbon bend/settling animation. Wrapping
/// uses clipped, rigid 180-degree hinges; pinching bends the same paper surface.
/// It is an explanatory model, not a cloth, contact, or force simulation.
enum StarGeometry {
    static let width: Float = 0.020
    static let length: Float = 0.260
    static let lastStep = 13
    static let stepCount = lastStep + 1
    private static let knotLength: Float = 0.105
    private static let shortLength: Float = 0.016
    private static let radius: Float = 0.0147
    private static let epsilon: Float = 0.0000001
    /// A display ordering interval, not a physical paper-thickness guarantee.
    /// Clearance tapers to zero at connected folds and the shared packet rim;
    /// this lesson therefore uses two-sided, zero-thickness rendered surfaces.
    private static let layerSpacing: Float = 0.00003

    private struct Edge {
        var a: SIMD3<Float>
        var b: SIMD3<Float>
        var outward: SIMD3<Float>
    }
    private struct Operation {
        var edge: Edge
        var part: Int
        var layer: Float
    }
    private struct Prepared {
        var knot: [PaperFace]
        var knotDisplay: [PaperFace]
        var shortOperations: [Operation]
        var shortStates: [[PaperFace]]
        var wrapOperations: [Operation]
        var wrapStates: [[PaperFace]]
        var pinchCells: [Int]
        var pinchSides: [Float]
        var pinchJoints: [[SIMD2<Int>]]
    }
    private struct Sector {
        var a: SIMD3<Float>
        var b: SIMD3<Float>
        var edgeIndex: Int
    }
    private struct GuideCell {
        var points: [SIMD3<Float>]
        var sector: Int
        var minimum: SIMD3<Float>
        var maximum: SIMD3<Float>
    }

    private static let pentagon: [SIMD3<Float>] = (0..<5).map { i in
        let angle = -.pi / 2 + Float(i) * 2 * .pi / 5
        return [radius * cos(angle), 0, radius * sin(angle)]
    }
    private static let edges: [Edge] = (0..<5).map { i in
        let a = pentagon[i], b = pentagon[(i + 1) % 5]
        let delta = b - a
        return Edge(a: a, b: b, outward: simd_normalize(SIMD3<Float>(delta.z, 0, -delta.x)))
    }
    private static let sectors: [Sector] = (0..<5).flatMap { i in
        let a = pentagon[i], b = pentagon[(i + 1) % 5], middle = (a + b) / 2
        return [Sector(a: a, b: middle, edgeIndex: i), Sector(a: middle, b: b, edgeIndex: i)]
    }
    private static let guideCells: [GuideCell] = {
        let divisions = 5
        var cells = [GuideCell]()
        for (index, sector) in sectors.enumerated() {
            func point(_ i: Int, _ j: Int) -> SIMD3<Float> {
                sector.a * Float(i) / Float(divisions) + sector.b * Float(j) / Float(divisions)
            }
            func add(_ points: [SIMD3<Float>]) {
                cells.append(GuideCell(points: points, sector: index,
                                       minimum: points.reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude), simd_min),
                                       maximum: points.reduce(SIMD3<Float>(repeating: -.greatestFiniteMagnitude), simd_max)))
            }
            for i in 0..<divisions {
                for j in 0..<(divisions - i) {
                    add([point(i, j), point(i + 1, j), point(i, j + 1)])
                    if i + j < divisions - 1 { add([point(i + 1, j), point(i + 1, j + 1), point(i, j + 1)]) }
                }
            }
        }
        return cells
    }()
    private static let prepared = prepare()

    static func frame(step requestedStep: Int, progress requestedProgress: Float) -> PaperFrame {
        let step = min(lastStep, max(0, requestedStep))
        let p = requestedProgress.isFinite ? min(1, max(0, requestedProgress)) : 0
        var faces = prepared.knotDisplay
        var crease: PaperCrease?
        var paths = [[SIMD3<Float>]]()

        if step <= 3 {
            // All four poses reuse the final knot's material partition, so the
            // paper does not disappear or get replaced while tightening.
            for i in faces.indices {
                for j in faces[i].vertices.indices {
                    var vertex = faces[i].vertices[j]
                    let s = vertex.source.x
                    let flat = SIMD3<Float>(s - length / 2, 0, vertex.source.y)
                    let loop = ribbonPoint(s: s, across: vertex.source.y, threaded: 0)
                    let threaded = ribbonPoint(s: s, across: vertex.source.y, threaded: 1)
                    switch step {
                    case 0:
                        vertex.position = flat; vertex.separation = .zero
                    case 1:
                        vertex.position = mix(flat, loop, smooth(p)); vertex.separation = .zero
                    case 2:
                        vertex.position = mix(loop, threaded, smooth(p)); vertex.separation = .zero
                    default:
                        vertex.position = mix(threaded, vertex.position, smooth(p))
                        vertex.separation *= smooth(p)
                    }
                    faces[i].vertices[j] = vertex
                }
                faces[i].isMoving = step > 0 && faces[i].originalSide < 0
            }
            if step == 1 {
                paths = [(0...24).map { i in
                    let angle = Float(i) / 24 * 1.6 * .pi
                    return SIMD3<Float>(-0.025 * sin(angle), 0.018, 0.022 * (1 - cos(angle)))
                }]
            } else if step == 2 {
                paths = [(0...24).map { i in
                    ribbonPoint(s: shortLength * 0.15, across: 0, threaded: Float(i) / 24) + [0, 0.010, 0]
                }]
            } else if step == 3 {
                paths = [[[-0.035, 0.014, 0.01], [-0.025, 0.011, 0.006], [-0.015, 0.008, 0.001]]]
            }
        } else if step == 4 {
            let result = animate(states: prepared.shortStates, operations: prepared.shortOperations, amount: p)
            faces = result.faces; crease = result.crease; paths = result.paths
        } else if step <= 8 {
            let count = prepared.wrapOperations.count
            let amount: Float
            switch step {
            case 5: amount = p
            case 6: amount = min(1, Float(count)) + p
            case 7: amount = 2 + p * Float(max(0, count - 3))
            default: amount = Float(max(0, count - 1)) + p
            }
            let result = animate(states: prepared.wrapStates, operations: prepared.wrapOperations,
                                 amount: min(Float(count), amount), normalized: false)
            faces = result.faces; crease = result.crease; paths = result.paths
        } else {
            faces = prepared.wrapStates.last ?? prepared.knot
            let pinches = Float(step - 9) + p
            faces = pinched(faces, amount: pinches, activeEdge: min(4, step - 9))
            let index = min(4, step - 9)
            let midpoint = (pentagon[index] + pentagon[(index + 1) % 5]) / 2
            let outward = simd_normalize(SIMD3<Float>(midpoint.x, 0, midpoint.z))
            paths = [(0...22).map { i in
                let t = Float(i) / 22
                return midpoint + outward * (0.013 - 0.018 * t) + SIMD3<Float>(0, 0.010, 0)
            }]
            if step == lastStep && p >= 0.999 { paths = [] }
        }

        if step >= 4 && step <= 8 && !(step == 8 && p == 1) {
            faces = renderPartition(faces)
        }
        if step <= 8 {
            for i in faces.indices {
                for j in faces[i].vertices.indices {
                    faces[i].vertices[j].separation *= rimWeight(faces[i].vertices[j].position)
                }
            }
        }
        if step >= 3 && step <= 8 {
            let joints = step == 8 && p == 1 ? prepared.pinchJoints : sourceJoints(faces)
            weldHeights(&faces, joints: joints)
        }
        setOutlines(&faces, step: step)
        let minY = faces.flatMap(\.vertices).map { ($0.position + $0.separation).y }.min() ?? 0
        let lift = max(0, -minY) + 0.001
        for i in faces.indices {
            for j in faces[i].vertices.indices { faces[i].vertices[j].position.y += lift }
        }
        if var c = crease { c.start.y += lift + 0.001; c.end.y += lift + 0.001; crease = c }
        paths = paths.map { path in
            let extra = max(lift, 0.009 - (path.map(\.y).min() ?? 0))
            return path.map { $0 + SIMD3<Float>(0, extra, 0) }
        }
        return PaperFrame(faces: faces, crease: crease, actionPaths: paths, tableLift: lift)
    }

    private static func initialFaces() -> [PaperFace] {
        // Small source-space panels support the curved loop and final puff.
        let sourceCuts = Array(Set((0...65).map { Float($0) * length / 65 } + [shortLength, knotLength])).sorted()
        var result = [PaperFace]()
        for i in 0..<(sourceCuts.count - 1) {
            let a = sourceCuts[i], b = sourceCuts[i + 1]
            let part = (a + b) / 2 < shortLength ? -2 : (a + b) / 2 < knotLength ? -1 : 1
            for row in 0..<4 {
                let v0 = -width / 2 + Float(row) * width / 4
                let v1 = v0 + width / 4
                let sources: [SIMD2<Float>] = [[a, v1], [b, v1], [b, v0], [a, v0]]
                let vertices = sources.map { PaperVertex(position: [$0.x - knotLength, 0, $0.y], source: $0) }
                result.append(PaperFace(vertices: vertices, originalSide: part))
            }
        }
        return result
    }

    private static func prepare() -> Prepared {
        var faces = initialFaces()
        // Lay out the compact flattened overhand knot. Source panels retain
        // their identity during the authored loop-to-knot settling animation.
        for _ in 0..<16 {
            guard let edge = nextEdge(faces: faces, part: -1) else { break }
            let operation = Operation(edge: edge, part: -3, layer: foldLayer(faces, edge: edge, part: -3, above: true))
            faces = apply(operation, faces: faces, amount: 1, moving: false)
        }
        let knot = faces
        var shortOperations = [Operation](), shortStates = [faces]
        for _ in 0..<8 {
            guard let edge = nextEdge(faces: faces, part: -2) else { break }
            let operation = Operation(edge: edge, part: -2, layer: foldLayer(faces, edge: edge, part: -2, above: false))
            shortOperations.append(operation)
            faces = apply(operation, faces: faces, amount: 1, moving: false)
            shortStates.append(faces)
        }
        var wrapOperations = [Operation](), wrapStates = [faces]
        for _ in 0..<20 {
            guard let edge = nextEdge(faces: faces, part: 1) else { break }
            var operation = Operation(edge: edge, part: 1, layer: foldLayer(faces, edge: edge, part: 1, above: true))
            var folded = apply(operation, faces: faces, amount: 1, moving: false)
            if nextEdge(faces: folded, part: 1) == nil {
                // The last short flap is tucked below the existing stack.
                operation.layer = foldLayer(faces, edge: edge, part: 1, above: false)
                folded = apply(operation, faces: faces, amount: 1, moving: false)
            }
            wrapOperations.append(operation)
            faces = folded
            wrapStates.append(faces)
        }
        let refined = refineForPinching(wrapStates.last ?? faces)
        wrapStates[wrapStates.count - 1] = refined.faces
        let joints = sourceJoints(refined.faces)
        let sides = contactSides(refined.faces, joints: joints)
        return Prepared(knot: knot, knotDisplay: renderPartition(knot), shortOperations: shortOperations, shortStates: shortStates,
                        wrapOperations: wrapOperations, wrapStates: wrapStates, pinchCells: refined.cells,
                        pinchSides: sides, pinchJoints: joints)
    }

    /// At a completed half-turn, the old offsets change sign. Compute the
    /// translation from the actual stack so the flap lands wholly above/below
    /// it. A fold-number multiplier can accidentally put different layers at
    /// exactly the same height, producing the observed white/ivory mosaic.
    private static func foldLayer(_ faces: [PaperFace], edge: Edge, part: Int, above: Bool) -> Float {
        var heights = [Float](), flapHeights = [Float]()
        for face in faces {
            guard face.originalSide == part || (part == -3 && face.originalSide < 0) else {
                heights += face.vertices.map { $0.separation.y }; continue
            }
            for moving in [false, true] {
                let vertices = clipped(face.vertices, edge: edge, positive: moving)
                guard vertices.count >= 3, PaperFace(vertices: vertices, originalSide: face.originalSide).area > 1e-12 else { continue }
                if moving { flapHeights += vertices.map { $0.separation.y } }
                else { heights += vertices.map { $0.separation.y } }
            }
        }
        if above { return (heights.max() ?? 0) + (flapHeights.max() ?? 0) + layerSpacing }
        return (heights.min() ?? 0) + (flapHeights.min() ?? 0) - layerSpacing
    }

    private static func nextEdge(faces: [PaperFace], part: Int) -> Edge? {
        let points = faces.filter { $0.originalSide == part }.flatMap { $0.vertices.map(\.position) }
        guard !points.isEmpty else { return nil }
        let candidate = edges.map { edge in (edge, points.map { simd_dot($0 - edge.a, edge.outward) }.max() ?? 0) }
            .max { $0.1 < $1.1 }
        guard let candidate, candidate.1 > 0.000001 else { return nil }
        return candidate.0
    }

    private static func animate(states: [[PaperFace]], operations: [Operation], amount: Float, normalized: Bool = true)
        -> (faces: [PaperFace], crease: PaperCrease?, paths: [[SIMD3<Float>]]) {
        guard !operations.isEmpty else { return (states.last ?? [], nil, []) }
        let value = normalized ? amount * Float(operations.count) : amount
        let index = min(operations.count - 1, max(0, Int(value)))
        let fraction = min(1, max(0, value - Float(index)))
        let operation = operations[index]
        let base = states[index]
        let faces: [PaperFace]
        if value >= Float(operations.count) { faces = states.last ?? base }
        else if fraction <= 0.000001 { faces = base }
        else { faces = apply(operation, faces: base, amount: smooth(fraction), moving: true) }
        let midpoint = (operation.edge.a + operation.edge.b) / 2
        let point = midpoint + operation.edge.outward * width * 0.9
        let axis = simd_normalize(operation.edge.b - operation.edge.a)
        let path = (0...26).map { i in
            rotate(point, origin: operation.edge.a, axis: axis, angle: .pi * Float(i) / 26) + [0, 0.006, 0]
        }
        return (faces, PaperCrease(start: operation.edge.a, end: operation.edge.b), [path])
    }

    private static func apply(_ operation: Operation, faces: [PaperFace], amount: Float, moving: Bool) -> [PaperFace] {
        let end = rawFold(operation, faces: faces, amount: 1, moving: false)
        var result = amount >= 1 ? end : rawFold(operation, faces: faces, amount: amount, moving: moving)
        // Settle unnecessary air gaps in the stack while keeping every layer in
        // its established order. This is a continuous render-offset correction,
        // not a scale of the strip or a last-frame replacement of its geometry.
        let levels = Array(Set(end.filter { $0.area > 1e-12 }.flatMap(\.vertices)
            .map { Int(($0.separation.y / epsilon).rounded()) })).sorted()
        let pivot = levels.enumerated().min { abs($0.element) < abs($1.element) }?.offset ?? 0
        let targets = Dictionary(uniqueKeysWithValues: levels.enumerated().map { ($0.element, Float($0.offset - pivot) * layerSpacing) })
        let amountToSettle = smooth(min(1, max(0, amount)))
        for i in result.indices {
            result[i].isMoving = moving && result[i].isMoving
            for j in result[i].vertices.indices {
                let oldHeight = end[i].vertices[j].separation.y
                let key = Int((oldHeight / epsilon).rounded())
                if let target = targets[key] {
                    result[i].vertices[j].separation.y += (target - oldHeight) * amountToSettle
                }
            }
        }
        return result.filter { $0.area > 1e-12 }
    }

    private static func rawFold(_ operation: Operation, faces: [PaperFace], amount: Float, moving: Bool) -> [PaperFace] {
        let axis = simd_normalize(operation.edge.b - operation.edge.a)
        var result = [PaperFace]()
        for face in faces {
            guard face.originalSide == operation.part || (operation.part == -3 && face.originalSide < 0) else {
                var fixed = face; fixed.isMoving = false; result.append(fixed); continue
            }
            let fixed = clipped(face.vertices, edge: operation.edge, positive: false)
            let flap = clipped(face.vertices, edge: operation.edge, positive: true)
            if fixed.count >= 3 { result.append(PaperFace(vertices: fixed, originalSide: face.originalSide)) }
            if flap.count >= 3 {
                let vertices = flap.map { original -> PaperVertex in
                    var v = original
                    v.position = rotate(v.position, origin: operation.edge.a, axis: axis, angle: .pi * amount)
                    v.separation = rotate(v.separation, origin: .zero, axis: axis, angle: .pi * amount)
                        + SIMD3<Float>(0, operation.layer * sin(.pi * amount / 2), 0)
                    return v
                }
                result.append(PaperFace(vertices: vertices, originalSide: face.originalSide, isMoving: moving))
            }
        }
        return result
    }

    private static func clipped(_ vertices: [PaperVertex], edge: Edge, positive: Bool, tolerance: Float = 0) -> [PaperVertex] {
        var result = [PaperVertex]()
        for i in vertices.indices {
            let a = vertices[i], b = vertices[(i + 1) % vertices.count]
            let da = simd_dot(a.position - edge.a, edge.outward), db = simd_dot(b.position - edge.a, edge.outward)
            let aInside = positive ? da >= -tolerance : da <= tolerance
            let bInside = positive ? db >= -tolerance : db <= tolerance
            if aInside { result.append(a) }
            if aInside != bInside && abs(da - db) > max(1e-15, tolerance) {
                result.append(.interpolate(a, b, min(1, max(0, da / (da - db)))))
            }
        }
        let cleanup = epsilon
        var clean = [PaperVertex]()
        for vertex in result where clean.last.map({ simd_distance($0.position, vertex.position) > cleanup }) ?? true { clean.append(vertex) }
        if clean.count > 1 && simd_distance(clean[0].position, clean[clean.count - 1].position) < cleanup { clean.removeLast() }
        return clean
    }

    private static func ribbonPoint(s: Float, across: Float, threaded: Float) -> SIMD3<Float> {
        func center(_ u: Float) -> SIMD3<Float> {
            if u >= knotLength { return [u - knotLength, 0, 0] }
            let arcLength = knotLength - shortLength
            let angle: Float = 1.80 * .pi
            let r = arcLength / angle
            let t = (knotLength - max(shortLength, u)) / arcLength
            let a = angle * t
            var c = SIMD3<Float>(-r * sin(a), 0.012 * sin(.pi * t), r * (1 - cos(a)))
            if u < shortLength {
                let delta = u - shortLength
                c += SIMD3<Float>(cos(angle), -0.012 * .pi / arcLength * cos(.pi), -sin(angle)) * delta
                let tip = (shortLength - u) / shortLength
                c += SIMD3<Float>(-0.027, -0.014, 0.012) * smooth(threaded) * tip
            }
            return c
        }
        let position = center(s)
        let tangent = center(min(length, s + 0.0001)) - center(max(0, s - 0.0001))
        let planar = SIMD3<Float>(-tangent.z, 0, tangent.x)
        let acrossDirection = simd_length_squared(planar) > 1e-12 ? simd_normalize(planar) : SIMD3<Float>(0, 0, 1)
        return position + acrossDirection * across
    }

    private static func pinched(_ faces: [PaperFace], amount: Float, activeEdge: Int) -> [PaperFace] {
        let total = min(5, max(0, amount))
        var result = faces.enumerated().map { index, face in
            var bent = face
            // Front/back winding denotes which colour of paper faces upward,
            // not whether a layer is at the top or bottom of the stack. Puff
            // layers in their actual height order and retain their clearances.
            let surfaceSide = prepared.pinchSides[index]
            let cell = guideCells[prepared.pinchCells[index]]
            let sector = sectors[cell.sector]
            let mapped = cell.points.map { targetPoint($0, sector: sector, pinches: total, side: surfaceSide) }
            bent.vertices = face.vertices.map { original in
                var v = original
                let point = original.position + original.separation
                let weights = barycentric(point, a: cell.points[0], b: cell.points[1], c: cell.points[2])
                v.position = mapped[0] * weights.x + mapped[1] * weights.y + mapped[2] * weights.z
                v.position.y += point.y * rimWeight(point)
                v.separation = .zero
                return v
            }
            let center = bent.vertices.reduce(SIMD3<Float>.zero) { $0 + $1.position } / Float(max(1, bent.vertices.count))
            let midpoint = (edges[activeEdge].a + edges[activeEdge].b) / 2
            bent.isMoving = simd_distance(SIMD2<Float>(center.x, center.z), SIMD2<Float>(midpoint.x, midpoint.z)) < radius * 0.70
            return bent
        }
        weldHeights(&result, joints: prepared.pinchJoints)
        for i in result.indices { for j in result[i].vertices.indices {
            result[i].vertices[j].position += result[i].vertices[j].separation
            result[i].vertices[j].separation = .zero
        }}
        return result
    }

    /// Smooth only the final inflation's tessellation, using neighbors that
    /// share original strip coordinates and a compatible oriented normal.
    /// Position, winding, material identity, fold guides and depth remain intact.
    /// The renderer uses these per-corner normals only during states 9...13.
    static func smoothPinchNormals(for frame: PaperFrame, step: Int, progress: Float) -> [[SIMD3<Float>]]? {
        guard (9...lastStep).contains(step), progress.isFinite,
              frame.faces.count == prepared.pinchCells.count else { return nil }
        let amount = smooth(min(1, max(0, Float(step - 9) + progress)))
        guard amount > 0 else { return nil }
        let faceNormals = frame.faces.map(\.normal)
        var result = frame.faces.enumerated().map { index, face in
            Array(repeating: faceNormals[index], count: face.vertices.count)
        }
        let cornerWeights = frame.faces.map { face in
            face.vertices.indices.map { i -> Float in
                let points = face.vertices
                let a = points[(i + points.count - 1) % points.count].position - points[i].position
                let b = points[(i + 1) % points.count].position - points[i].position
                return atan2(simd_length(simd_cross(a, b)), simd_dot(a, b))
            }
        }
        for joint in prepared.pinchJoints {
            for address in joint {
                let reference = faceNormals[address.x]
                let point = frame.faces[address.x].vertices[address.y].position
                var sum = SIMD3<Float>.zero
                for neighbor in joint {
                    let normal = faceNormals[neighbor.x]
                    guard simd_dot(reference, normal) > 0.35,
                          simd_distance(point, frame.faces[neighbor.x].vertices[neighbor.y].position) < 0.000002 else { continue }
                    sum += normal * cornerWeights[neighbor.x][neighbor.y]
                }
                if simd_length_squared(sum) > 1e-12 {
                    result[address.x][address.y] = simd_normalize(reference * (1 - amount) + simd_normalize(sum) * amount)
                }
            }
        }
        return result
    }

    /// Every overlapping layer uses the same small deformation cells. Without
    /// this common partition, independently triangulated curved layers can cut
    /// through each other even when all their vertices sample the same surface.
    private static func refineForPinching(_ faces: [PaperFace]) -> (faces: [PaperFace], cells: [Int]) {
        var refined = [PaperFace](), cellIDs = [Int]()
        for face in faces {
            let positions = face.vertices.map(\.position)
            let minimum = positions.reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude), simd_min)
            let maximum = positions.reduce(SIMD3<Float>(repeating: -.greatestFiniteMagnitude), simd_max)
            for (index, cell) in guideCells.enumerated() {
                guard minimum.x <= cell.maximum.x + epsilon && maximum.x >= cell.minimum.x - epsilon &&
                        minimum.z <= cell.maximum.z + epsilon && maximum.z >= cell.minimum.z - epsilon else { continue }
                var polygon = face.vertices
                for i in 0..<3 {
                    let a = cell.points[i], b = cell.points[(i + 1) % 3], delta = b - a
                    let outward = simd_normalize(SIMD3<Float>(delta.z, 0, -delta.x))
                    polygon = clipped(polygon, edge: Edge(a: a, b: b, outward: outward), positive: false, tolerance: 0)
                    if polygon.count < 3 { break }
                }
                if polygon.count >= 3 {
                    let fragment = PaperFace(vertices: polygon, originalSide: face.originalSide)
                    if fragment.area > 1e-12 {
                        for i in 1..<(polygon.count - 1) {
                            let triangle = PaperFace(vertices: [polygon[0], polygon[i], polygon[i + 1]], originalSide: face.originalSide, isMoving: face.isMoving)
                            if triangle.area > 1e-14 { refined.append(triangle); cellIDs.append(index) }
                        }
                    }
                }
            }
        }
        return (refined, cellIDs)
    }

    /// Use the same deformation cells during wrapping as during pinching.
    /// Independent coarse faces approximate a tapered layer differently and
    /// can cross; clipping each to a common affine field avoids that mosaic.
    /// The unwrapped tail is retained outside the pentagon, with no lost paper.
    private static func renderPartition(_ faces: [PaperFace]) -> [PaperFace] {
        var result = [PaperFace](), refinable = [PaperFace]()
        for face in faces {
            var projectedArea: Float = 0
            if face.vertices.count >= 3 {
                let a = face.vertices[0].position
                for i in 1..<(face.vertices.count - 1) {
                    let b = face.vertices[i].position - a, c = face.vertices[i + 1].position - a
                    projectedArea += abs(b.x * c.z - b.z * c.x) / 2
                }
            }
            // A vertical moving flap lies on several cell planes at once;
            // keep it once instead of duplicating its nonzero material area.
            guard projectedArea > 1e-10 else { result.append(face); continue }
            refinable.append(face)
            var inside = face.vertices
            for edge in edges {
                let outside = clipped(inside, edge: edge, positive: true, tolerance: 0)
                if outside.count >= 3 {
                    let fragment = PaperFace(vertices: outside, originalSide: face.originalSide, isMoving: face.isMoving)
                    if fragment.area > 1e-12 { result.append(fragment) }
                }
                inside = clipped(inside, edge: edge, positive: false, tolerance: 0)
                if inside.count < 3 { break }
            }
        }
        result += refineForPinching(refinable).faces
        return result
    }

    private static func targetPoint(_ point: SIMD3<Float>, sector: Sector, pinches: Float, side: Float) -> SIMD3<Float> {
        let weights = barycentric(point, a: .zero, b: sector.a, c: sector.b)
        let activation = smooth(min(1, max(0, pinches - Float(sector.edgeIndex))))
        let radial = min(1, max(0, weights.y + weights.z))
        var result = point
        if radial > 0.000001 {
            let rim = (sector.a * weights.y + sector.b * weights.z) / radial
            let direction = simd_normalize(rim)
            let angle = atan2(rim.z, rim.x) + Float.pi / 2
            // A real lucky star has short, broad points and gently curved
            // valleys. The old 5.1 mm V-shaped indentation made long spikes.
            // This shared radial field rounds both tips and valleys; every
            // layer still deforms through the same triangular guide cells.
            let inner = radius * cos(Float.pi / 5) - 0.0022
            let targetRadius = (radius + inner) / 2 + (radius - inner) / 2 * cos(5 * angle)
            let boundary = rim + (direction * targetRadius - rim) * activation
            result = boundary * radial
        }
        // A broad pillow profile rather than an apex. Sampling only the
        // shared grid preserves layer ordering and the already closed rim.
        let depth = min(1, max(0, weights.x))
        result.y = side * 0.0036 * pow(sin(depth * .pi / 2), 0.8) * pinches / 5
        return result
    }

    /// Folded layers join along the pentagon's boundary. An offset is a visual
    /// clearance inside the stack, not permission to pull those hinges apart.
    /// The transition occupies the outer guide-cell ring, so it is affine in
    /// each pinching cell and preserves shared material seams and flat facets.
    private static func rimWeight(_ point: SIMD3<Float>) -> Float {
        let inset = edges.map { -simd_dot(point - $0.a, $0.outward) }.min() ?? 0
        let apothem = radius * cos(Float.pi / 5)
        return min(1, max(0, inset / (apothem / 5)))
    }

    /// Material identity, not spatial overlap, defines a connected paper joint.
    private static func sourceJoints(_ faces: [PaperFace]) -> [[SIMD2<Int>]] {
        let bin: Float = 0.0000002
        let tolerance: Float = 0.00000005
        var lookup = [SIMD2<Int>: [Int]](), sources = [SIMD2<Float>]()
        var groups = [[SIMD2<Int>]]()
        for (i, face) in faces.enumerated() {
            for (j, vertex) in face.vertices.enumerated() {
                let key = SIMD2<Int>(Int(floor(vertex.source.x / bin)), Int(floor(vertex.source.y / bin)))
                var found: Int?
                search: for x in -1...1 {
                    for y in -1...1 {
                        for index in lookup[key &+ SIMD2<Int>(x, y)] ?? [] {
                            if simd_distance(sources[index], vertex.source) < tolerance { found = index; break search }
                        }
                    }
                }
                if let found { groups[found].append([i, j]) }
                else {
                    lookup[key, default: []].append(groups.count)
                    sources.append(vertex.source); groups.append([[i, j]])
                }
            }
        }
        return groups.filter { $0.count > 1 }
    }

    /// Interior fold connections belong to one side of the inflated packet.
    /// Keeping their puff weight equal avoids pulling a continuous hinge across
    /// the hollow center just because it straddles the global stack midpoint.
    private static func contactSides(_ faces: [PaperFace], joints: [[SIMD2<Int>]]) -> [Float] {
        let height = faces.map { face in
            face.vertices.reduce(Float(0)) { $0 + ($1.position + $1.separation).y } / Float(face.vertices.count)
        }
        let levels = Array(Set(height.map { Int(($0 / epsilon).rounded()) })).sorted()
        let levelIndex = Dictionary(uniqueKeysWithValues: levels.enumerated().map { ($0.element, $0.offset) })
        let indices = height.map { levelIndex[Int(($0 / epsilon).rounded())]! }
        var joined = Array(repeating: false, count: max(0, levels.count - 1))
        for joint in joints {
            let first = joint[0], point = faces[first.x].vertices[first.y].position
            guard rimWeight(point) > 0.005 else { continue }
            let ranks = joint.map { indices[$0.x] }
            if let low = ranks.min(), let high = ranks.max(), high > low {
                for rank in low..<high { joined[rank] = true }
            }
        }
        var weights = Array(repeating: Float(0), count: levels.count), start = 0
        while start < levels.count {
            var end = start
            while end < joined.count && joined[end] { end += 1 }
            let fraction = Float(start + end) / (2 * Float(max(1, levels.count - 1)))
            let weight = tanh((fraction - 0.5) * 20) / tanh(Float(10))
            for i in start...end { weights[i] = weight }
            start = end + 1
        }
        return indices.map { weights[$0] }
    }

    private static func weldHeights(_ faces: inout [PaperFace], joints: [[SIMD2<Int>]]) {
        for joint in joints {
            let height = joint.reduce(Float(0)) { value, address in
                let vertex = faces[address.x].vertices[address.y]
                return value + vertex.position.y + vertex.separation.y
            } / Float(joint.count)
            for address in joint {
                // Preserve X/Z exactly: very thin clipped triangles must not be
                // moved laterally or flipped by a source-quantization tolerance.
                faces[address.x].vertices[address.y].separation.y = height - faces[address.x].vertices[address.y].position.y
            }
        }
    }

    private static func barycentric(_ point: SIMD3<Float>, a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>) -> SIMD3<Float> {
        let v0 = SIMD2<Float>(b.x - a.x, b.z - a.z)
        let v1 = SIMD2<Float>(c.x - a.x, c.z - a.z)
        let v2 = SIMD2<Float>(point.x - a.x, point.z - a.z)
        let determinant = v0.x * v1.y - v0.y * v1.x
        guard abs(determinant) > 1e-16 else { return [1, 0, 0] }
        let y = (v2.x * v1.y - v2.y * v1.x) / determinant
        let z = (v0.x * v2.y - v0.y * v2.x) / determinant
        return [1 - y - z, y, z]
    }

    private static func setOutlines(_ faces: inout [PaperFace], step: Int) {
        for i in faces.indices {
            let vertices = faces[i].vertices
            faces[i].outlinedEdges = vertices.indices.map { index in
                // A wrapped star has no printed lines. Original strip edges
                // are buried in the stack; drawing tubes on them makes an
                // artificial black network poke through adjacent paper faces.
                // The compact form's visible silhouette comes from its mesh.
                if step >= 8 { return false }
                let a = vertices[index].source, b = vertices[(index + 1) % vertices.count].source
                let longEdge = abs(abs(a.y) - width / 2) < 1e-6 && abs(a.y - b.y) < 1e-6
                let shortEdge = (abs(a.x) < 1e-6 || abs(a.x - length) < 1e-6) && abs(a.x - b.x) < 1e-6
                if step >= 4 && !faces[i].isMoving {
                    let pa = vertices[index].position, pb = vertices[(index + 1) % vertices.count].position
                    let inside = edges.allSatisfy { edge in
                        simd_dot(pa - edge.a, edge.outward) <= epsilon && simd_dot(pb - edge.a, edge.outward) <= epsilon
                    }
                    if inside { return false }
                }
                return longEdge || shortEdge
            }
        }
    }

    private static func smooth(_ value: Float) -> Float { value * value * (3 - 2 * value) }
    private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }
    private static func rotate(_ point: SIMD3<Float>, origin: SIMD3<Float>, axis: SIMD3<Float>, angle: Float) -> SIMD3<Float> {
        let vector = point - origin
        let rawSine = sin(angle), rawCosine = cos(angle)
        let sine: Float = abs(rawSine) < 1e-6 ? 0 : rawSine
        let cosine: Float = abs(rawCosine) < 1e-6 ? 0 : rawCosine
        return origin + vector * cosine + simd_cross(axis, vector) * sine + axis * simd_dot(axis, vector) * (1 - cosine)
    }
}
