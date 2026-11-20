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
    /// Stable undeformed coordinates identify shared cloth vertices. Current
    /// positions can overlap after a fold and must never define topology.
    var restPositions: [SIMD3<Float>]? = nil
    /// Zero preserves an already closed volume (rope/tie). Open cloth declares
    /// its teaching thickness, scaled with calibrated dimensions and layer gaps.
    var surfaceThickness: Float = 0
    /// Material coordinates follow the undeformed cloth, never world space.
    var fabricUVs: [SIMD2<Float>]? = nil
    /// Optional smooth front-face normals from a continuous deformation field.
    /// They must follow the mesh winding and retain one value per source vertex.
    /// Without these, the surface builder derives normals from triangle areas.
    var surfaceNormals: [SIMD3<Float>]? = nil
    /// A closed ribbon has four corners per ring (back-left, back-right,
    /// front-right, front-left). Its edge/cap UV charts need this authored
    /// thickness, independent of the animated pose; it does not add a shell.
    var closedRibbonThickness: Float? = nil
}

enum EverydayMeshGeometry {
    /// Flat-object calibration dimensions the undeformed fabric before folding.
    /// Knot/tie routes remain tabletop references and do not accept a cloth fit.
    static func parts(courseID: EverydayTutorialID, actionIndex: Int, progress: Double,
                      objectScale: SIMD3<Float> = SIMD3(repeating: 1)) -> [EverydayMeshPart] {
        switch courseID {
        case .tShirt, .towel, .flatBedsheet:
            return EverydayClothGeometry.parts(courseID: courseID, actionIndex: actionIndex, progress: progress, objectScale: objectScale)
        case .squareKnot, .fourInHand:
            return EverydayKnotGeometry.parts(courseID: courseID, actionIndex: actionIndex, progress: progress)
        }
    }

    static func validatedObjectScale(_ value: SIMD3<Float>) -> SIMD3<Float> {
        (0..<3).allSatisfy { value[$0].isFinite && value[$0] > 0 } ? value : SIMD3(repeating: 1)
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
