import Foundation
import simd

/// Render-only thickness for the authored teaching surfaces. Rest coordinates
/// identify seams: overlapping folded layers must never be welded by proximity.
/// This does not change the lesson's motion or represent a cloth simulation.
enum EverydaySurfaceMesh {
    struct Surface {
        let positions: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
        /// Undeformed material coordinates in metres. The material applies its
        /// physical tile size; the animation must never recompute these from a pose.
        let textureCoordinates: [SIMD2<Float>]
        let triangles: [UInt32]
    }

    enum MeshError: Error { case invalidGeometry }

    private struct RestKey: Hashable {
        let x: Int64, y: Int64, z: Int64
        init(_ p: SIMD3<Float>) {
            x = Int64((Double(p.x) * 1_000_000).rounded())
            y = Int64((Double(p.y) * 1_000_000).rounded())
            z = Int64((Double(p.z) * 1_000_000).rounded())
        }
    }

    private struct EdgeKey: Hashable {
        let low: Int, high: Int
        init(_ a: Int, _ b: Int) { low = min(a, b); high = max(a, b) }
    }
    private struct Edge { let a: Int, b: Int }

    static func make(part: EverydayMeshPart) throws -> Surface {
        let source = part.positions
        guard !source.isEmpty, part.triangles.count >= 3,
              part.triangles.count % 3 == 0,
              part.surfaceThickness.isFinite, part.surfaceThickness >= 0,
              source.allSatisfy(isFinite),
              part.triangles.allSatisfy({ Int($0) < source.count }) else {
            throw MeshError.invalidGeometry
        }
        if let rest = part.restPositions {
            guard rest.count == source.count, rest.allSatisfy(isFinite),
                  rest.allSatisfy({ simd_reduce_max(simd_abs($0)) < 1_000_000 }) else {
                throw MeshError.invalidGeometry
            }
        }
        if let uvs = part.fabricUVs {
            guard uvs.count == source.count, uvs.allSatisfy(isFinite) else {
                throw MeshError.invalidGeometry
            }
        }
        if let authored = part.surfaceNormals {
            guard authored.count == source.count, authored.allSatisfy(isFinite),
                  authored.allSatisfy({ simd_length_squared($0).isFinite && simd_length_squared($0) > 1e-12 }) else {
                throw MeshError.invalidGeometry
            }
        }
        if let thickness = part.closedRibbonThickness {
            guard thickness.isFinite, thickness > 0, part.surfaceThickness == 0,
                  source.count >= 8, source.count % 4 == 0, part.fabricUVs != nil else {
                throw MeshError.invalidGeometry
            }
        }
        let sourceUVs = part.fabricUVs ?? Array(repeating: .zero, count: source.count)

        var normals = Array(repeating: SIMD3<Float>.zero, count: source.count)
        var front: [UInt32] = []
        for i in stride(from: 0, to: part.triangles.count, by: 3) {
            let a = Int(part.triangles[i]), b = Int(part.triangles[i + 1]), c = Int(part.triangles[i + 2])
            let cross = simd_cross(source[b] - source[a], source[c] - source[a])
            guard isFinite(cross), simd_length_squared(cross).isFinite else { throw MeshError.invalidGeometry }
            guard simd_length_squared(cross) > 1e-18 else { continue }
            normals[a] += cross; normals[b] += cross; normals[c] += cross
            front += [UInt32(a), UInt32(b), UInt32(c)]
        }
        guard !front.isEmpty else { throw MeshError.invalidGeometry }
        if let authored = part.surfaceNormals {
            normals = authored.map { simd_normalize($0) }
        } else {
            normals = normals.map { simd_length_squared($0) > 1e-18 ? simd_normalize($0) : [0, 1, 0] }
        }
        guard normals.allSatisfy(isFinite) else { throw MeshError.invalidGeometry }

        // The producer explicitly marks closed volumes with zero shell width.
        // Cords and tie ribbons already have end caps and real thickness.
        guard part.surfaceThickness > 0 else {
            if let thickness = part.closedRibbonThickness {
                return try ribbonSurface(positions: source, normals: normals, uvs: sourceUVs,
                                         triangles: front, thickness: thickness)
            }
            return Surface(positions: source, normals: normals,
                           textureCoordinates: sourceUVs, triangles: front)
        }

        let half = part.surfaceThickness / 2
        var positions = zip(source, normals).map { $0 + $1 * half }
            + zip(source, normals).map { $0 - $1 * half }
        var surfaceNormals = normals + normals.map { -$0 }
        var textureCoordinates = sourceUVs + sourceUVs
        let count = UInt32(source.count)
        var triangles: [UInt32] = []
        func appendSkinFace(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
            // A valid source sliver can collapse after offsetting along a
            // curved normal field. Apply the same rendered-face tolerance as
            // the seam strips; never submit a near-zero tangent frame.
            let cross = simd_cross(positions[Int(b)] - positions[Int(a)],
                                   positions[Int(c)] - positions[Int(a)])
            if simd_length_squared(cross) > 1e-18 { triangles += [a, b, c] }
        }
        for i in stride(from: 0, to: front.count, by: 3) {
            appendSkinFace(front[i], front[i + 1], front[i + 2])
            appendSkinFace(front[i + 2] + count, front[i + 1] + count, front[i] + count)
        }

        // Indexed ribbons already express shared topology. Cloth producers
        // supply undeformed coordinates because clipped polygons duplicate it.
        var vertexIDs = Array(source.indices)
        if let rest = part.restPositions {
            var identities: [RestKey: Int] = [:]
            for (i, p) in rest.enumerated() {
                let key = RestKey(p)
                if let identity = identities[key] { vertexIDs[i] = identity }
                else { identities[key] = i; vertexIDs[i] = i }
            }
        }
        var edges: [EdgeKey: [Edge]] = [:]
        var edgeOrder: [EdgeKey] = []
        for i in stride(from: 0, to: front.count, by: 3) {
            let indices = (0..<3).map { Int(front[i + $0]) }
            for e in 0..<3 {
                let a = indices[e], b = indices[(e + 1) % 3]
                guard vertexIDs[a] != vertexIDs[b] else { throw MeshError.invalidGeometry }
                let key = EdgeKey(vertexIDs[a], vertexIDs[b])
                if edges[key] == nil { edgeOrder.append(key) }
                edges[key, default: []].append(Edge(a: a, b: b))
            }
        }

        func appendTriangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>,
                            _ uvA: SIMD2<Float>, _ uvB: SIMD2<Float>, _ uvC: SIMD2<Float>) {
            let cross = simd_cross(b - a, c - a)
            // A shared flat edge needs no seam bridge; skip its collapsed faces.
            guard simd_length_squared(cross) > 1e-18 else { return }
            let index = UInt32(positions.count)
            positions += [a, b, c]
            surfaceNormals += Array(repeating: simd_normalize(cross), count: 3)
            textureCoordinates += [uvA, uvB, uvC]
            triangles += [index, index + 1, index + 2]
        }
        func appendQuad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                        _ uvA: SIMD2<Float>, _ uvB: SIMD2<Float>, _ uvC: SIMD2<Float>, _ uvD: SIMD2<Float>) {
            appendTriangle(a, b, c, uvA, uvB, uvC)
            appendTriangle(a, c, d, uvA, uvC, uvD)
        }
        func edgeOffset(_ edge: Edge) throws -> SIMD2<Float> {
            guard part.fabricUVs != nil else { return .zero }
            let direction = sourceUVs[edge.b] - sourceUVs[edge.a]
            let length = simd_length(direction)
            guard length.isFinite, length > 1e-12 else { throw MeshError.invalidGeometry }
            // Unwrap the thin edge as a strip in the same metre units as the
            // face. A full 0...1 tile here would squash its weave into stripes.
            // Use authored width, not the animated crease gap, to prevent swim.
            return SIMD2<Float>(-direction.y, direction.x) * (part.surfaceThickness / length)
        }

        for key in edgeOrder {
            guard let owners = edges[key], let edge = owners.first else { continue }
            let uvA = sourceUVs[edge.a], uvB = sourceUVs[edge.b]
            let offset = try edgeOffset(edge)
            switch owners.count {
            case 1:
                // A crisp sidewall only at the panel's boundary, not along each
                // triangle in the clipped cloth tessellation.
                appendQuad(positions[edge.a], positions[edge.a + source.count],
                           positions[edge.b + source.count], positions[edge.b],
                           uvA, uvA + offset, uvB + offset, uvB)
            case 2:
                let other = owners[1]
                guard vertexIDs[edge.a] == vertexIDs[other.b],
                      vertexIDs[edge.b] == vertexIDs[other.a] else { throw MeshError.invalidGeometry }
                // Keep the crease sharp. Averaging opposite fold normals would
                // flip near 180 degrees. Close only the offset's tiny gap instead.
                appendQuad(positions[edge.b], positions[edge.a], positions[other.b], positions[other.a],
                           uvB, uvA, uvA + offset, uvB + offset)
                appendQuad(positions[edge.a + source.count], positions[edge.b + source.count],
                           positions[other.a + source.count], positions[other.b + source.count],
                           uvA, uvB, uvB + offset, uvA + offset)
            default:
                throw MeshError.invalidGeometry
            }
        }
        guard positions.allSatisfy(isFinite), surfaceNormals.allSatisfy(isFinite),
              textureCoordinates.count == positions.count, textureCoordinates.allSatisfy(isFinite) else {
            throw MeshError.invalidGeometry
        }
        return Surface(positions: positions, normals: surfaceNormals,
                       textureCoordinates: textureCoordinates, triangles: triangles)
    }

    /// Broad faces keep their authored material coordinates. Only thin sides
    /// and caps split their render vertices, so normal mapping has a valid
    /// thickness-sized chart rather than a zero-area UV triangle. The original
    /// closed geometry, averaged normals and winding remain unchanged.
    private static func ribbonSurface(positions source: [SIMD3<Float>], normals: [SIMD3<Float>],
                                      uvs: [SIMD2<Float>], triangles: [UInt32],
                                      thickness: Float) throws -> Surface {
        var positions = source, surfaceNormals = normals, coordinates = uvs
        var indices: [UInt32] = []
        indices.reserveCapacity(triangles.count)
        for offset in stride(from: 0, to: triangles.count, by: 3) {
            let face = (0..<3).map { Int(triangles[offset + $0]) }
            let corners = Set(face.map { $0 % 4 })
            let isCap = face.allSatisfy { $0 / 4 == face[0] / 4 }
            if !isCap && (corners == Set([0, 1]) || corners == Set([2, 3])) {
                indices += face.map(UInt32.init)
                continue
            }
            let rightSide = corners == Set([1, 2])
            let leftSide = corners == Set([0, 3])
            guard isCap || rightSide || leftSide else { throw MeshError.invalidGeometry }
            for index in face {
                let corner = index % 4
                let uv: SIMD2<Float>
                if isCap {
                    uv = [uvs[index].x, corner >= 2 ? thickness : 0]
                } else {
                    let across: Float = rightSide ? (corner == 2 ? thickness : 0)
                                                 : (corner == 0 ? thickness : 0)
                    uv = [across, uvs[index].y]
                }
                indices.append(UInt32(positions.count))
                positions.append(source[index])
                surfaceNormals.append(normals[index])
                coordinates.append(uv)
            }
        }
        return Surface(positions: positions, normals: surfaceNormals,
                       textureCoordinates: coordinates, triangles: indices)
    }

    private static func isFinite(_ p: SIMD3<Float>) -> Bool { p.x.isFinite && p.y.isFinite && p.z.isFinite }
    private static func isFinite(_ p: SIMD2<Float>) -> Bool { p.x.isFinite && p.y.isFinite }
}
