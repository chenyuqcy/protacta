import Foundation
import simd

/// Original hinged teaching surfaces, not a cloth solver or a camera check.
/// X is width, -Z is the far edge and Y is up; distances are schematic metres.
/// Crease subdivisions depend on the initial dimensions, never on playback progress.
enum EverydayClothGeometry {
    static func parts(courseID: EverydayTutorialID, actionIndex: Int, progress: Double,
                      objectScale: SIMD3<Float> = SIMD3(repeating: 1)) -> [EverydayMeshPart] {
        let scale = EverydayMeshGeometry.validatedObjectScale(objectScale)
        let p = progress.isFinite ? Float(min(1, max(0, progress))) : 0
        switch courseID {
        case .towel:
            return EverydaySoftTowelGeometry.parts(actionIndex: actionIndex, progress: progress, objectScale: scale)
        case .tShirt:
            let action = min(5, max(0, actionIndex))
            let usesStandardSize = scale == SIMD3<Float>(repeating: 1)
            let patches = usesStandardSize ? shirtPatches : makeShirtPatches(objectScale: scale)
            let transform: (Patch) -> ([SIMD3<Float>], Bool) = { patch in
                (patch.points.map { shirtPoint($0, patch: patch, action: action, progress: p, objectScale: scale) },
                 shirtMoves(patch, action: action))
            }
            let body = grouped(patches, prefix: "shirt", color: 1, thickness: 0.0007 * scale.y, uvScale: scale, transform: transform)
            // Default-size geometry is immutable: only the pose changes each
            // tick. Calibrated templates remain computed because the final
            // folded-space clipping depends on the exact measured dimensions.
            let collarPatches = usesStandardSize ? shirtCollarPatches : clippedDetails(patches, regions: collarBands)
            let cuffPatches = usesStandardSize ? shirtCuffPatches : clippedDetails(patches, regions: shirtCuffBands)
            let hemPatches = usesStandardSize ? shirtHemPatches : clippedDetails(patches, regions: shirtHemBands)
            let collar = details(collarPatches, id: "shirt_collar", color: 1,
                                 thickness: 0.0010 * scale.y, uvScale: scale, transform: transform)
            let cuffs = details(cuffPatches,
                                id: "shirt_cuffs", color: 1, thickness: 0.0010 * scale.y, uvScale: scale, transform: transform)
            let hem = details(hemPatches, id: "shirt_hem", color: 1,
                              thickness: 0.0010 * scale.y, uvScale: scale, transform: transform)
            return body + collar + cuffs + hem
        case .flatBedsheet:
            let action = min(3, max(0, actionIndex))
            let transform: (Patch) -> ([SIMD3<Float>], Bool) = { patch in
                (patch.points.map { sheetPoint($0, patch: patch, action: action, progress: p, objectScale: scale) },
                 [patch.side < 0, patch.nearHem, patch.outerSleeve, patch.nearPacket][action])
            }
            return grouped(sheetPatches, prefix: "sheet", color: 3, thickness: 0.0007 * scale.y, uvScale: scale, transform: transform)
                + details(sheetPatches, regions: rectangularHem(width: 0.72, length: 0.86, inset: 0.009),
                          id: "sheet_hem", color: 3, thickness: 0.0010 * scale.y, uvScale: scale, transform: transform)
        case .squareKnot, .fourInHand: return []
        }
    }

    private struct Patch {
        var points: [SIMD3<Float>]
        let side: Int
        let outerSleeve: Bool
        let nearHem: Bool
        let nearPacket: Bool
        let section: String
        var key: String { "\(section)_\(side)_\(outerSleeve ? 1 : 0)_\(nearHem ? 1 : 0)_\(nearPacket ? 1 : 0)" }

        func replacingPoints(_ value: [SIMD3<Float>]) -> Patch {
            Patch(points: value, side: side, outerSleeve: outerSleeve, nearHem: nearHem,
                  nearPacket: nearPacket, section: section)
        }
    }

    private static func amount(_ stage: Int, action: Int, progress: Float) -> Float {
        stage < action ? 1 : stage == action ? progress : 0
    }

    private static func rotate(_ point: SIMD3<Float>, about pivot: SIMD3<Float>,
                               axis: SIMD3<Float>, angle: Float) -> SIMD3<Float> {
        guard angle != 0 else { return point }
        let delta = point - pivot, direction = simd_normalize(axis)
        return pivot + delta * cos(angle) + simd_cross(direction, delta) * sin(angle)
            + direction * simd_dot(direction, delta) * (1 - cos(angle))
    }

    private static func shirtMoves(_ patch: Patch, action: Int) -> Bool {
        switch action {
        case 0: return patch.side < 0
        case 1: return patch.side < 0 && patch.outerSleeve
        case 2: return patch.side > 0
        case 3: return patch.side > 0 && patch.outerSleeve
        case 4: return patch.nearHem
        default: return patch.nearPacket
        }
    }

    private static func shirtPoint(_ source: SIMD3<Float>, patch: Patch,
                                   action: Int, progress: Float, objectScale: SIMD3<Float>) -> SIMD3<Float> {
        // Scaling an already-rotated flap makes it grow/shrink when raised.
        // Dimension source points, pivots and crease directions first instead.
        var point = source * objectScale
        if patch.side < 0 {
            let t = amount(0, action: action, progress: progress)
            point = rotate(point, about: SIMD3<Float>(-0.12, 0.001, 0) * objectScale, axis: SIMD3<Float>(0, 0, 1) * objectScale, angle: -.pi * t)
            point.y += 0.0015 * objectScale.y * t
            if patch.outerSleeve {
                let tuck = amount(1, action: action, progress: progress)
                // The diagonal seam turns a projecting sleeve inward and down.
                point = rotate(point, about: SIMD3<Float>(0.01, 0.0025, -0.24) * objectScale, axis: SIMD3<Float>(0.05, 0, 0.14) * objectScale, angle: .pi * tuck)
                point.y += 0.0015 * objectScale.y * tuck
            }
        } else if patch.side > 0 {
            let t = amount(2, action: action, progress: progress)
            point = rotate(point, about: SIMD3<Float>(0.12, 0.001, 0) * objectScale, axis: SIMD3<Float>(0, 0, 1) * objectScale, angle: .pi * t)
            point.y += 0.0045 * objectScale.y * t
            if patch.outerSleeve {
                let tuck = amount(3, action: action, progress: progress)
                point = rotate(point, about: SIMD3<Float>(-0.01, 0.0055, -0.24) * objectScale, axis: SIMD3<Float>(-0.05, 0, 0.14) * objectScale, angle: -.pi * tuck)
                point.y += 0.0015 * objectScale.y * tuck
            }
        }
        if patch.nearHem {
            point = rotate(point, about: SIMD3<Float>(0, 0.008, 0.01) * objectScale, axis: SIMD3<Float>(1, 0, 0) * objectScale,
                           angle: -.pi * amount(4, action: action, progress: progress))
        }
        if patch.nearPacket {
            point = rotate(point, about: SIMD3<Float>(0, 0.016, -0.155) * objectScale, axis: SIMD3<Float>(1, 0, 0) * objectScale,
                           angle: -.pi * amount(5, action: action, progress: progress))
        }
        return point
    }

    private static func sheetPoint(_ source: SIMD3<Float>, patch: Patch,
                                   action: Int, progress: Float, objectScale: SIMD3<Float>) -> SIMD3<Float> {
        // Scaling an already-rotated flap makes it grow/shrink when raised.
        // Dimension source points, pivots and crease directions first instead.
        var point = source * objectScale
        if patch.side < 0 {
            let t = amount(0, action: action, progress: progress)
            point = rotate(point, about: SIMD3<Float>(0, 0.001, 0) * objectScale, axis: SIMD3<Float>(0, 0, 1) * objectScale, angle: -.pi * t)
            point.y += 0.0015 * objectScale.y * t
        }
        if patch.nearHem {
            point = rotate(point, about: SIMD3<Float>(0, 0.004, 0) * objectScale, axis: SIMD3<Float>(1, 0, 0) * objectScale,
                           angle: -.pi * amount(1, action: action, progress: progress))
        }
        if patch.outerSleeve {
            point = rotate(point, about: SIMD3<Float>(0.18, 0.0085, 0) * objectScale, axis: SIMD3<Float>(0, 0, 1) * objectScale,
                           angle: -.pi * amount(2, action: action, progress: progress))
        }
        if patch.nearPacket {
            point = rotate(point, about: SIMD3<Float>(0, 0.0175, -0.215) * objectScale, axis: SIMD3<Float>(1, 0, 0) * objectScale,
                           angle: -.pi * amount(3, action: action, progress: progress))
        }
        return point
    }

    private static let sheetPatches: [Patch] = {
        let x: [Float] = [-0.36, -0.18, 0, 0.18, 0.36]
        let z: [Float] = [-0.43, -0.215, 0, 0.215, 0.43]
        return (0..<4).flatMap { column in
            (0..<4).map { row in
                let midpointX = (x[column] + x[column + 1]) / 2
                let midpointZ = (z[row] + z[row + 1]) / 2
                return Patch(points: [[x[column], 0.001, z[row]], [x[column], 0.001, z[row + 1]],
                                      [x[column + 1], 0.001, z[row + 1]], [x[column + 1], 0.001, z[row]]],
                             side: midpointX < 0 ? -1 : 1, outerSleeve: abs(midpointX) < 0.18,
                             nearHem: midpointZ > 0, nearPacket: abs(midpointZ) < 0.215, section: "linen")
            }
        }
    }()

    private static let shirtPatches = makeShirtPatches(objectScale: SIMD3(repeating: 1))

    private static func makeShirtPatches(objectScale: SIMD3<Float>) -> [Patch] {
        // A shaped neck opening and shoulder seams identify an actual T-shirt,
        // rather than relabeling a rectangle as a garment.
        let outline: [SIMD3<Float>] = [[-0.22, 0.001, -0.26]] + shirtNeckline
            + [[0.22, 0.001, -0.26], [0.22, 0.001, 0.34], [-0.22, 0.001, 0.34]]
        var seeds = triangulate(outline).map { $0.map { outline[$0] } }.map { ($0, false, "body") }
        let base: [SIMD3<Float>] = [[-0.22, 0.001, -0.26], [-0.25, 0.001, -0.24],
                                    [-0.30, 0.001, -0.10], [-0.22, 0.001, -0.06]]
        let outer: [SIMD3<Float>] = [[-0.25, 0.001, -0.24], [-0.37, 0.001, -0.22],
                                     [-0.37, 0.001, -0.10], [-0.30, 0.001, -0.10]]
        for mirror: Float in [1, -1] {
            seeds.append((base.map { [$0.x * mirror, $0.y, $0.z] }, false, "sleeve_base"))
            seeds.append((outer.map { [$0.x * mirror, $0.y, $0.z] }, true, "sleeve_tip"))
        }
        var patches: [Patch] = []
        for (polygon, sleeve, section) in seeds {
            var subdivisions = [polygon]
            for x: Float in [-0.12, 0.12] { subdivisions = subdivisions.flatMap { split($0) { $0.x - x } } }
            subdivisions = subdivisions.flatMap { split($0) { $0.z - 0.01 } }
            for polygon in subdivisions {
                let center = polygon.reduce(.zero, +) / Float(polygon.count)
                let side = center.x < -0.12 ? -1 : center.x > 0.12 ? 1 : 0
                let seed = Patch(points: polygon, side: side, outerSleeve: sleeve,
                                 nearHem: center.z > 0.01, nearPacket: false, section: section)
                // The final crease also crosses tucked sleeves. Split in the
                // already-folded state, interpolating the original vertices.
                for divided in split(polygon, value: { shirtPoint($0, patch: seed, action: 4, progress: 1, objectScale: objectScale).z + 0.155 * objectScale.z }) {
                    let center = divided.reduce(.zero, +) / Float(divided.count)
                    patches.append(Patch(points: divided, side: side, outerSleeve: sleeve,
                                         nearHem: seed.nearHem,
                                         nearPacket: shirtPoint(center, patch: seed, action: 4, progress: 1, objectScale: objectScale).z > -0.155 * objectScale.z,
                                         section: section))
                }
            }
        }
        return patches
    }

    /// Clips a convex polygon in source space. Prior crease subdivisions make
    /// each later folded-space clipping value affine within one polygon.
    private static func split(_ polygon: [SIMD3<Float>], value: (SIMD3<Float>) -> Float) -> [[SIMD3<Float>]] {
        let epsilon: Float = 0.0000001
        let values = polygon.map(value)
        guard values.contains(where: { $0 > epsilon }), values.contains(where: { $0 < -epsilon }) else { return [polygon] }
        return [true, false].compactMap { positive -> [SIMD3<Float>]? in
            var result: [SIMD3<Float>] = []
            for i in polygon.indices {
                let a = polygon[i], b = polygon[(i + 1) % polygon.count]
                let va = values[i], vb = values[(i + 1) % polygon.count]
                let aInside = positive ? va >= -epsilon : va <= epsilon
                let bInside = positive ? vb >= -epsilon : vb <= epsilon
                if aInside { result.append(a) }
                if aInside != bInside {
                    let amount = va / (va - vb)
                    result.append(a + (b - a) * amount)
                }
            }
            result = uniqueNeighbours(result)
            guard result.count >= 3, abs(signedArea(result)) > 1e-10 else { return nil }
            return result
        }
    }

    private static func uniqueNeighbours(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        var result: [SIMD3<Float>] = []
        for point in points where result.last.map({ simd_distance_squared($0, point) > 1e-12 }) ?? true { result.append(point) }
        if result.count > 1, simd_distance_squared(result[0], result[result.count - 1]) < 1e-12 { result.removeLast() }
        return result
    }

    private static func signedArea(_ polygon: [SIMD3<Float>]) -> Float {
        polygon.indices.reduce(0) { sum, i in
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            return sum + a.x * b.z - b.x * a.z
        } / 2
    }

    /// Ear clipping preserves the neck's concave outline. All later polygons
    /// are convex clips of these triangles and use a simple triangle fan.
    private static func triangulate(_ polygon: [SIMD3<Float>]) -> [[Int]] {
        let direction: Float = signedArea(polygon) >= 0 ? 1 : -1
        func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> Float {
            (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x)
        }
        var remaining = Array(polygon.indices), result: [[Int]] = []
        while remaining.count > 3 {
            var found = false
            for i in remaining.indices {
                let a = remaining[(i + remaining.count - 1) % remaining.count]
                let b = remaining[i], c = remaining[(i + 1) % remaining.count]
                guard cross(polygon[a], polygon[b], polygon[c]) * direction > 1e-10 else { continue }
                let containsPoint = remaining.contains { j in
                    guard j != a && j != b && j != c else { return false }
                    return cross(polygon[a], polygon[b], polygon[j]) * direction >= -1e-9
                        && cross(polygon[b], polygon[c], polygon[j]) * direction >= -1e-9
                        && cross(polygon[c], polygon[a], polygon[j]) * direction >= -1e-9
                }
                if containsPoint { continue }
                result.append([a, b, c]); remaining.remove(at: i); found = true; break
            }
            guard found else { return [] }
        }
        if remaining.count == 3 { result.append(remaining) }
        return result
    }

    private static let shirtNeckline: [SIMD3<Float>] = [
        [-0.085, 0.001, -0.32], [-0.070, 0.001, -0.29], [-0.055, 0.001, -0.266],
        [-0.030, 0.001, -0.253], [0, 0.001, -0.249], [0.030, 0.001, -0.253],
        [0.055, 0.001, -0.266], [0.070, 0.001, -0.29], [0.085, 0.001, -0.32]
    ]

    /// A mitered band follows the real neck opening into the garment. These are
    /// authored garment features, never borders around the lesson's fold panels.
    private static let collarBands: [[SIMD3<Float>]] = {
        let path = shirtNeckline
        let normals = (0..<(path.count - 1)).map { i -> SIMD3<Float> in
            let edge = path[i + 1] - path[i]
            return simd_normalize(SIMD3(-edge.z, 0, edge.x))
        }
        let inner = path.indices.map { i -> SIMD3<Float> in
            let previous = normals[max(0, i - 1)], next = normals[min(i, normals.count - 1)]
            let miter = simd_normalize(previous + next)
            return path[i] + miter * (0.009 / max(0.7, simd_dot(miter, next)))
        }
        return (0..<(path.count - 1)).map { [path[$0], path[$0 + 1], inner[$0 + 1], inner[$0]] }
    }()

    private static let shirtCuffBands = [rectangle(-0.37, -0.358, -0.24, -0.08),
                                        rectangle(0.358, 0.37, -0.24, -0.08)]
    private static let shirtHemBands = [rectangle(-0.22, 0.22, 0.328, 0.34)]
    private static let shirtCollarPatches = clippedDetails(shirtPatches, regions: collarBands)
    private static let shirtCuffPatches = clippedDetails(shirtPatches, regions: shirtCuffBands)
    private static let shirtHemPatches = clippedDetails(shirtPatches, regions: shirtHemBands)

    private static func rectangle(_ minX: Float, _ maxX: Float, _ minZ: Float, _ maxZ: Float,
                                  y: Float = 0.001) -> [SIMD3<Float>] {
        [[minX, y, minZ], [maxX, y, minZ], [maxX, y, maxZ], [minX, y, maxZ]]
    }

    private static func rectangularHem(width: Float, length: Float, inset: Float,
                                       y: Float = 0.001) -> [[SIMD3<Float>]] {
        let x = width / 2, z = length / 2
        // Nonoverlapping corner ownership avoids coincident top surfaces.
        return [rectangle(-x, -x + inset, -z, z, y: y), rectangle(x - inset, x, -z, z, y: y),
                rectangle(-x + inset, x - inset, -z, -z + inset, y: y),
                rectangle(-x + inset, x - inset, z - inset, z, y: y)]
    }

    /// Clip decorative material regions to the already classified source
    /// patches. Thus sleeve tucks and the final folded-space crease use exactly
    /// the body's classification, including under nonuniform AR calibration.
    private static func details(_ patches: [Patch], regions: [[SIMD3<Float>]], id: String,
                                color: Int, thickness: Float, uvScale: SIMD3<Float>,
                                transform: (Patch) -> ([SIMD3<Float>], Bool)) -> [EverydayMeshPart] {
        details(clippedDetails(patches, regions: regions), id: id, color: color,
                thickness: thickness, uvScale: uvScale, transform: transform)
    }

    private static func clippedDetails(_ patches: [Patch], regions: [[SIMD3<Float>]]) -> [Patch] {
        var decorated: [Patch] = []
        for region in regions {
            for patch in patches {
                let clipped = intersection(patch.points, with: region)
                guard clipped.count >= 3 else { continue }
                // Mirrored sleeve seeds have opposite winding. A single detail
                // mesh uses one source orientation so touching strips can weld.
                decorated.append(patch.replacingPoints(signedArea(clipped) < 0 ? Array(clipped.reversed()) : clipped))
            }
        }
        return decorated
    }

    private static func details(_ decorated: [Patch], id: String, color: Int, thickness: Float,
                                uvScale: SIMD3<Float>,
                                transform: (Patch) -> ([SIMD3<Float>], Bool)) -> [EverydayMeshPart] {
        guard !decorated.isEmpty else { return [] }
        let posed = decorated.map(transform)
        return [mesh(id: id, polygons: posed.map(\.0), topology: decorated.map(\.points), color: color,
                     moving: posed.contains { $0.1 }, thickness: thickness, uvScale: uvScale)]
    }

    private static func intersection(_ polygon: [SIMD3<Float>], with region: [SIMD3<Float>]) -> [SIMD3<Float>] {
        let sign: Float = signedArea(region) >= 0 ? 1 : -1
        var result = polygon
        for edge in region.indices {
            guard result.count >= 3 else { return [] }
            let origin = region[edge], direction = region[(edge + 1) % region.count] - origin
            func distance(_ point: SIMD3<Float>) -> Float {
                (direction.x * (point.z - origin.z) - direction.z * (point.x - origin.x)) * sign
            }
            var clipped: [SIMD3<Float>] = []
            for i in result.indices {
                let a = result[i], b = result[(i + 1) % result.count]
                let da = distance(a), db = distance(b)
                let aInside = da >= -1e-9, bInside = db >= -1e-9
                if aInside { clipped.append(a) }
                if aInside != bInside { clipped.append(a + (b - a) * (da / (da - db))) }
            }
            result = uniqueNeighbours(clipped)
        }
        return result.count >= 3 && abs(signedArea(result)) > 1e-10 ? result : []
    }

    private static func grouped(_ patches: [Patch], prefix: String, color: Int, thickness: Float, uvScale: SIMD3<Float>,
                                transform: (Patch) -> ([SIMD3<Float>], Bool)) -> [EverydayMeshPart] {
        let keys = Array(Set(patches.map(\.key))).sorted()
        return keys.map { key in
            let group = patches.filter { $0.key == key }
            let transformed = group.map(transform)
            return mesh(id: "\(prefix)_\(key)", polygons: transformed.map(\.0),
                        topology: group.map(\.points), color: color, moving: transformed.contains { $0.1 },
                        thickness: thickness, uvScale: uvScale)
        }
    }

    private static func mesh(id: String, polygons: [[SIMD3<Float>]], topology: [[SIMD3<Float>]]? = nil,
                             color: Int, moving: Bool, thickness: Float,
                             uvScale: SIMD3<Float> = SIMD3(repeating: 1)) -> EverydayMeshPart {
        var positions: [SIMD3<Float>] = [], restPositions: [SIMD3<Float>] = [], triangles: [UInt32] = []
        for (polygonIndex, polygon) in polygons.enumerated() {
            guard polygon.count >= 3 else { continue }
            let reference = topology?[polygonIndex] ?? polygon
            let offset = UInt32(positions.count)
            positions += polygon
            restPositions += reference
            for i in 1..<(polygon.count - 1) {
                let cross = simd_cross(reference[i] - reference[0], reference[i + 1] - reference[0])
                // Collinear clipping vertices are harmless but must not become
                // zero-area faces in the runtime RealityKit mesh.
                guard simd_length_squared(cross) > 1e-16 else { continue }
                triangles += [offset, offset + UInt32(i), offset + UInt32(i + 1)]
            }
        }
        return EverydayMeshPart(id: id, positions: positions, triangles: triangles,
                                colorIndex: color, isMoving: moving, restPositions: restPositions,
                                surfaceThickness: thickness,
                                fabricUVs: restPositions.map { SIMD2($0.x * uvScale.x, $0.z * uvScale.z) })
    }
}
