import Foundation
import simd

/// Studio-only framing. An action is framed once over its complete movement,
/// so seeking never makes the camera chase a shrinking or rotating cloth.
/// Tabletop placement and calibrated physical dimensions use their own bounds.
enum EverydayStepFraming {
    struct Frame: Equatable {
        let minimum: SIMD3<Float>
        let maximum: SIMD3<Float>
        var center: SIMD3<Float> { (minimum + maximum) * 0.5 }
        var radius: Float { max(0.025, simd_length(maximum - minimum) * 0.5) }
    }

    static func action(courseID: EverydayTutorialID, actionIndex: Int,
                       objectScale: SIMD3<Float> = SIMD3(repeating: 1)) -> Frame {
        let last = EverydayTutorialCourse.course(courseID).actions.count - 1
        let index = min(last, max(0, actionIndex))
        return measure(courseID: courseID, actionIndex: index,
                       progress: (0...32).map { Double($0) / 32 }, objectScale: objectScale)
    }

    static func completed(courseID: EverydayTutorialID,
                          objectScale: SIMD3<Float> = SIMD3(repeating: 1)) -> Frame {
        pose(courseID: courseID,
             actionIndex: EverydayTutorialCourse.course(courseID).actions.count - 1,
             progress: 1, objectScale: objectScale)
    }

    /// Explicit paused inspection only. Restore action framing before playing
    /// or seeking again, otherwise a large unfolding movement could be cropped.
    static func pose(courseID: EverydayTutorialID, actionIndex: Int, progress: Double,
                     objectScale: SIMD3<Float> = SIMD3(repeating: 1)) -> Frame {
        let last = EverydayTutorialCourse.course(courseID).actions.count - 1
        let amount = progress.isFinite ? min(1, max(0, progress)) : 0
        return measure(courseID: courseID, actionIndex: min(last, max(0, actionIndex)),
                       progress: [amount], objectScale: objectScale)
    }

    private static func measure(courseID: EverydayTutorialID, actionIndex: Int,
                                progress: [Double], objectScale: SIMD3<Float>) -> Frame {
        let scale = EverydayMeshGeometry.validatedObjectScale(objectScale)
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for amount in progress {
            let parts = EverydayMeshGeometry.parts(courseID: courseID, actionIndex: actionIndex,
                                                    progress: amount, objectScale: scale)
            for part in parts {
                // All shell vertices are offset by half the declared thickness;
                // seam bridges are made from these same vertices. This expansion
                // encloses the actual render mesh without rebuilding its faces.
                let halfSkin = SIMD3<Float>(repeating: part.surfaceThickness * 0.5)
                for point in part.positions {
                    guard finite(point), finite(halfSkin) else { return fallback }
                    minimum = simd_min(minimum, point - halfSkin)
                    maximum = simd_max(maximum, point + halfSkin)
                }
            }
        }
        guard finite(minimum), finite(maximum), finite(maximum - minimum),
              simd_reduce_min(maximum - minimum) >= 0,
              simd_length(maximum - minimum).isFinite else { return fallback }
        // Sampling catches the fold arc; isotropic padding also covers extrema
        // between samples and leaves room around a nearly flat final packet.
        let span = simd_reduce_max(maximum - minimum)
        let padding = SIMD3<Float>(repeating: max(span * 0.015, 0.0005))
        return Frame(minimum: minimum - padding, maximum: maximum + padding)
    }

    private static var fallback: Frame { Frame(minimum: [-0.4, 0, -0.4], maximum: [0.4, 0.4, 0.4]) }
    private static func finite(_ p: SIMD3<Float>) -> Bool { p.x.isFinite && p.y.isFinite && p.z.isFinite }
}
