import Foundation
import simd

/// An original three-panel teaching diagram, not a real-time cloth solver.
/// X is width, -Z is the far edge and +Y is up. Units are schematic meters.
enum Towel3DGeometry {
    struct Panel {
        let column: Int
        let isMoving: Bool
        let quads: [[SIMD3<Float>]]
    }

    static func panels(actionIndex: Int, progress: Double) -> [Panel] {
        let action = min(2, max(0, actionIndex))
        let value = progress.isFinite ? Float(min(1, max(0, progress))) : 0
        let edges: [Float] = [-0.30, -0.10, 0.10, 0.30]
        let rows: [Float] = [-0.45, 0, 0.45]
        return (0..<3).map { column in
            let moving = action == 2 || (action == 0 && column == 0) || (action == 1 && column == 2)
            let quads = (0..<2).map { row in
                [SIMD3<Float>(edges[column], 0, rows[row]),
                 SIMD3<Float>(edges[column], 0, rows[row + 1]),
                 SIMD3<Float>(edges[column + 1], 0, rows[row + 1]),
                 SIMD3<Float>(edges[column + 1], 0, rows[row])].map {
                    position($0, column: column, action: action, progress: value)
                }
            }
            return Panel(column: column, isMoving: moving, quads: quads)
        }
    }

    private static func position(_ source: SIMD3<Float>, column: Int,
                                 action: Int, progress: Float) -> SIMD3<Float> {
        var point = source
        // Small visible layer spacing explains the stack; it is not a measured
        // fabric thickness. Left/right thirds use their own fixed hinge axes.
        if column == 0 {
            let amount: Float = action == 0 ? progress : 1
            let angle = Float.pi * amount
            let dx = source.x + 0.10
            point.x = -0.10 + dx * cos(angle)
            point.y = -dx * sin(angle) + 0.004 * (1 - cos(angle)) / 2
        } else if column == 2 {
            let amount: Float = action == 0 ? 0 : action == 1 ? progress : 1
            let angle = Float.pi * amount
            let dx = source.x - 0.10
            point.x = 0.10 + dx * cos(angle)
            point.y = dx * sin(angle) + 0.008 * (1 - cos(angle)) / 2
        }
        if action == 2 && source.z >= 0 {
            let angle = -Float.pi * progress
            let hingeHeight: Float = 0.012
            let dy = point.y - hingeHeight
            point.y = hingeHeight + dy * cos(angle) - source.z * sin(angle)
            point.z = dy * sin(angle) + source.z * cos(angle)
        }
        return point
    }

    static func bounds(of panels: [Panel]) -> (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        let points = panels.flatMap { $0.quads.flatMap { $0 } }
        return (points.reduce(SIMD3(repeating: .greatestFiniteMagnitude), simd_min),
                points.reduce(SIMD3(repeating: -.greatestFiniteMagnitude), simd_max))
    }
}
