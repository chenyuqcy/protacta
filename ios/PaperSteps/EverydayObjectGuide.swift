import Foundation
import simd

/// Named points the learner identifies on a FLAT object. This records a manual
/// starting registration; it does not identify fabric or track its deformation.
struct EverydayObjectGuide {
    let footprint: EverydayObjectFootprint
    let pointNames: [String]
    let setup: String

    static func course(_ id: EverydayTutorialID) -> Self? {
        switch id {
        case .tShirt:
            // Calibrate the body rectangle, not the bounding box around empty
            // space below the sleeves. These are authored, visible seam points.
            guard let footprint = EverydayObjectFootprint(
                minimum: [-0.22, 0.001, -0.26], maximum: [0.22, 0.001, 0.34]) else { return nil }
            return Self(footprint: footprint,
                        pointNames: ["Left hem corner", "Right hem corner", "Left shoulder seam"],
                        setup: "Lay a short-sleeve T-shirt flat, neck away from you. Use the outer shoulder where the sleeve joins the body for point 3.")
        case .towel, .flatBedsheet:
            let points = EverydayMeshGeometry.parts(courseID: id, actionIndex: 0, progress: 0).flatMap(\.positions)
            guard !points.isEmpty,
                  let footprint = EverydayObjectFootprint(
                    minimum: points.reduce(SIMD3(repeating: .greatestFiniteMagnitude), simd_min),
                    maximum: points.reduce(SIMD3(repeating: -.greatestFiniteMagnitude), simd_max)) else { return nil }
            return Self(footprint: footprint,
                        pointNames: ["Near-left corner", "Near-right corner", "Far-left corner"],
                        setup: id == .towel
                            ? "Spread a rectangular towel flat, with its long edges running away from you."
                            : "Spread a flat bedsheet on a level surface, with its long edges running away from you. Fitted sheets need a different guide.")
        case .squareKnot, .fourInHand:
            // Flexible strands are taught with the tabletop model. Three planar
            // corners cannot register a rope knot or a tie around a neck.
            return nil
        }
    }
}
