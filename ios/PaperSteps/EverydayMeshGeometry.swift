import Foundation
import simd

/// Original teaching surfaces in metres. These are authored references, not
/// a cloth/rope simulator and not a registration result for a physical object.
struct EverydayMeshPart: Equatable {
    let id: String
    let positions: [SIMD3<Float>]
    let triangles: [UInt32]
    let colorIndex: Int
    let isMoving: Bool
}

enum EverydayMeshGeometry {
    static func parts(courseID: EverydayTutorialID, actionIndex: Int, progress: Double) -> [EverydayMeshPart] {
        switch courseID {
        case .tShirt, .towel, .flatBedsheet:
            return EverydayClothGeometry.parts(courseID: courseID, actionIndex: actionIndex, progress: progress)
        case .squareKnot, .fourInHand:
            return EverydayKnotGeometry.parts(courseID: courseID, actionIndex: actionIndex, progress: progress)
        }
    }

    /// Use the whole course's motion envelope so folds never trigger a camera
    /// or AR scale jump. Placement is sized once, not against the current pose.
    static func envelope(courseID: EverydayTutorialID) -> (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for action in EverydayTutorialCourse.course(courseID).actions.indices {
            for sample in 0...8 {
                let progress = Double(sample) / 8
                for part in parts(courseID: courseID, actionIndex: action, progress: progress) {
                    for point in part.positions where point.x.isFinite && point.y.isFinite && point.z.isFinite {
                        minimum = simd_min(minimum, point); maximum = simd_max(maximum, point)
                    }
                }
            }
        }
        if !minimum.x.isFinite || maximum.x < minimum.x { return ([-0.4, 0, -0.4], [0.4, 0.4, 0.4]) }
        let padding = (maximum - minimum) * 0.025
        return (minimum - padding, maximum + padding)
    }
}
