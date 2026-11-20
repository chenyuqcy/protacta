import Foundation
import simd

/// Towel teaching geometry with rounded, finite-width folds.
/// The authored bend preserves distance along each fold section; it is not a
/// cloth solver, force simulation, or a fit to a camera-observed towel.
/// The everyday lesson and catalogue share this same continuous surface.
enum EverydaySoftTowelGeometry {
    private static let bendSlices = 10

    static func parts(actionIndex: Int, progress: Double,
                      objectScale: SIMD3<Float> = SIMD3(repeating: 1)) -> [EverydayMeshPart] {
        let scale = EverydayMeshGeometry.validatedObjectScale(objectScale)
        let action = min(2, max(0, actionIndex))
        let amount = progress.isFinite ? Float(min(1, max(0, progress))) : 0
        let shape = Shape(scale: scale)
        let xs = shape.xSamples
        // Every column has the same row count. Its final-bend band follows that
        // layer's radius, so the outer layers get a longer arc than the inner.
        // These are fixed source points, calculated once from the unfolded size.
        let columns = xs.map { x in shape.zSamples(atX: x).map { SIMD3<Float>(x, 0, $0) } }
        let rows = columns[0].count
        let rest = columns.flatMap { $0 }
        let positions = rest.map { shape.position($0, action: action, progress: amount) }
        var triangles: [UInt32] = []
        var hemTriangles: [UInt32] = []
        triangles.reserveCapacity((xs.count - 1) * (rows - 1) * 6)
        for column in 0..<(xs.count - 1) {
            for row in 0..<(rows - 1) {
                let a = UInt32(column * rows + row)
                let b = a + 1
                let d = UInt32((column + 1) * rows + row)
                let c = d + 1
                triangles += [a, b, c, a, c, d]
                if column == 0 || column == xs.count - 2 || row == 0 || row == rows - 2 {
                    hemTriangles += [a, b, c, a, c, d]
                }
            }
        }
        let moving = amount > 0 && amount < 1
        let body = EverydayMeshPart(id: "towel_soft_body", positions: positions, triangles: triangles,
                                   colorIndex: 0, isMoving: moving, restPositions: rest,
                                   surfaceThickness: 0.0026 * scale.y,
                                   fabricUVs: rest.map { SIMD2<Float>($0.x, $0.z) })
        // The thicker woven binding follows only the four original outer edges.
        // It uses the same source grid and deformation, including every bend.
        var remap: [UInt32: UInt32] = [:]
        var hemRest: [SIMD3<Float>] = [], hemPositions: [SIMD3<Float>] = []
        let compactTriangles = hemTriangles.map { index -> UInt32 in
            if let existing = remap[index] { return existing }
            let compact = UInt32(hemRest.count)
            remap[index] = compact
            hemRest.append(rest[Int(index)])
            hemPositions.append(positions[Int(index)])
            return compact
        }
        let hem = EverydayMeshPart(id: "towel_hem", positions: hemPositions, triangles: compactTriangles,
                                  colorIndex: 0, isMoving: moving, restPositions: hemRest,
                                  surfaceThickness: 0.0032 * scale.y,
                                  fabricUVs: hemRest.map { SIMD2<Float>($0.x, $0.z) })
        return [body, hem]
    }

    private struct Shape {
        let scale: SIMD3<Float>
        var halfWidth: Float { 0.30 * scale.x }
        var halfLength: Float { 0.45 * scale.z }
        var hingeX: Float { 0.10 * scale.x }
        var baseHeight: Float { 0.004 * scale.y }
        // At the completed fold, the two centre lines sit 4 and 8 mm above
        // the base. Keep a feasible band even for an extreme object calibration.
        var leftRadius: Float { min(0.002 * scale.y, (halfWidth - hingeX) / (3 * .pi)) }
        var rightRadius: Float { min(0.004 * scale.y, (halfWidth - hingeX) / (3 * .pi)) }
        var packetPivotY: Float { baseHeight + 2 * rightRadius + 0.004 * scale.y }

        var xSamples: [Float] {
            var values: [Float] = [-0.30, -0.29, -0.25, -0.20, -0.15, -0.10,
                                   -0.05, 0, 0.05, 0.10, 0.15, 0.20, 0.25, 0.29, 0.30]
                .map { $0 * scale.x }
            let leftNarrow = Float.pi * leftRadius, rightNarrow = Float.pi * rightRadius
            let leftBroad = sideWidth(radius: leftRadius, angle: .pi / 2)
            let rightBroad = sideWidth(radius: rightRadius, angle: .pi / 2)
            // Do not superimpose two grids. Near-coincident rows make area-
            // weighted shell normals jump enough to pinch a millimetre skin.
            values.removeAll { x in
                (x < -hingeX && x >= -hingeX - leftBroad)
                    || (x > hingeX && x <= hingeX + rightBroad)
            }
            for index in 0...bendSlices {
                let fraction = Float(index) / Float(bendSlices)
                values.append(-hingeX - leftNarrow * fraction)
                values.append(hingeX + rightNarrow * fraction)
                values.append(-hingeX - leftNarrow - (leftBroad - leftNarrow) * fraction)
                values.append(hingeX + rightNarrow + (rightBroad - rightNarrow) * fraction)
            }
            let sorted = values.sorted()
            return sorted.reduce(into: []) { result, value in
                if result.last.map({ abs(value - $0) > 1e-7 }) ?? true { result.append(value) }
            }
        }

        func packetRadius(atX x: Float) -> Float {
            let folded = widthFold(x, action: 2, progress: 0)
            // Layers remain nested about the same bend axis in the normal
            // calibration range. Capping only protects impossible short/wide fits.
            return min(packetPivotY - folded.y, halfLength / (2 * .pi))
        }

        func zSamples(atX x: Float) -> [Float] {
            let width = .pi * packetRadius(atX: x)
            let broadWidth = min(width + 0.06 * scale.z, halfLength * 0.8)
            var values: [Float] = [-halfLength, -halfLength + 0.01 * scale.z,
                                   -halfLength * 2 / 3, -halfLength / 3, 0]
            values += (1...bendSlices).map { width * Float($0) / Float(bendSlices) }
            values += (1...bendSlices).map { width + (broadWidth - width) * Float($0) / Float(bendSlices) }
            values += [broadWidth + (halfLength - broadWidth) / 3,
                       broadWidth + (halfLength - broadWidth) * 2 / 3,
                       halfLength - 0.01 * scale.z, halfLength]
            return values
        }

        func widthFold(_ x: Float, action: Int, progress: Float) -> SIMD2<Float> {
            if x < -hingeX {
                let angle: Float = .pi * (action == 0 ? progress : 1)
                let fold = Self.arc(distance: -hingeX - x, width: sideWidth(radius: leftRadius, angle: angle), angle: angle)
                return [-hingeX - fold.outward, baseHeight + fold.height]
            }
            if x > hingeX {
                let fraction: Float = action == 0 ? 0 : action == 1 ? progress : 1
                let angle = Float.pi * fraction
                let fold = Self.arc(distance: x - hingeX, width: sideWidth(radius: rightRadius, angle: angle), angle: angle)
                return [hingeX + fold.outward, baseHeight + fold.height]
            }
            return [x, baseHeight]
        }

        func position(_ source: SIMD3<Float>, action: Int, progress: Float) -> SIMD3<Float> {
            let widthPoint = widthFold(source.x, action: action, progress: progress)
            guard action == 2, source.z > 0 else { return [widthPoint.x, widthPoint.y, source.z] }
            let angle = Float.pi * progress
            let fold = Self.arc(distance: source.z, width: packetWidth(atX: source.x, angle: angle), angle: angle)
            return [widthPoint.x, widthPoint.y + fold.height, fold.outward]
        }

        // A broader authored curl while lifting makes the towel read as soft
        // fabric. It settles into the physical layer radius at either endpoint.
        // The rest mesh already samples both bands; no vertex/UV is recreated.
        func sideWidth(radius: Float, angle: Float) -> Float {
            min(.pi * radius + 0.05 * scale.x * max(0, sin(angle)), (halfWidth - hingeX) * 0.8)
        }

        func packetWidth(atX x: Float, angle: Float) -> Float {
            // All layers must bend about one instantaneous axis. A fixed pi*R
            // band at intermediate angles changes each layer's axis and can
            // pinch the already-curved width folds. theta*R keeps the radial
            // separation exact while the common extra curl relaxes on landing.
            min(angle * packetRadius(atX: x) + 0.06 * scale.z * max(0, sin(angle)), halfLength * 0.8)
        }

        /// Integrate the tangent angle along source arc length. Within the band
        /// the curvature is constant; beyond it the free fabric continues along
        /// the endpoint tangent. At zero angle, use the exact flat limit.
        static func arc(distance: Float, width: Float, angle: Float) -> (outward: Float, height: Float) {
            guard angle > 1e-6 else { return (distance, 0) }
            let k = angle / width
            let bendDistance = min(distance, width)
            let phase = k * bendDistance
            let extra = max(0, distance - width)
            return (sin(phase) / k + extra * cos(angle),
                    (1 - cos(phase)) / k + extra * sin(angle))
        }
    }
}
