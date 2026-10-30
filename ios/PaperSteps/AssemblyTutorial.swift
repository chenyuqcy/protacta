import Foundation
import simd

/// Authored, model-specific structure walkthrough. Displacements use metres in
/// the studio's Y-up frame; imported assets keep their exporter conversion root.
/// A movement is not a repair instruction or a measurement of a real object.
struct AssemblyTutorial {
    struct Part: Identifiable {
        let id: String
        let entityName: String
        let title: String
        let detail: String
        let explodedOffset: SIMD3<Float>
    }
    struct Step: Identifiable {
        let id: String
        let title: String
        let instruction: String
        let focusID: String?
        /// Complete end pose. Omitted parts remain at their assembled origin.
        let offsets: [String: SIMD3<Float>]
    }
    let title: String
    let assetName: String
    let attribution: String
    let parts: [Part]
    let steps: [Step]
    var initialYaw: Float = 0.45
    var initialPitch: Float = 0.4

    func validate() throws {
        let ids = Set(parts.map(\.id))
        guard initialYaw.isFinite, initialPitch.isFinite, (0.15...1.48).contains(initialPitch),
              !parts.isEmpty, !steps.isEmpty, ids.count == parts.count,
              Set(parts.map(\.entityName)).count == parts.count,
              Set(steps.map(\.id)).count == steps.count,
              parts.allSatisfy({ !$0.id.isEmpty && !$0.entityName.isEmpty && $0.explodedOffset.isFiniteVector }),
              steps.allSatisfy({ !$0.id.isEmpty && ($0.focusID == nil || ids.contains($0.focusID!)) &&
                  Set($0.offsets.keys).isSubset(of: ids) && $0.offsets.values.allSatisfy(\.isFiniteVector) }) else {
            throw AssemblyTutorialError.invalidDefinition
        }
    }

    static let aeris = AssemblyTutorial(
        title: "AERIS · Parts in motion", assetName: "aeris-one",
        attribution: "Original AERIS concept model · Authored structure walkthrough",
        parts: [
            .init(id: "cover", entityName: "Rear_Cover", title: "Rear cover", detail: "The removable outer panel behind the filter compartment.", explodedOffset: [0, 0, -0.43]),
            .init(id: "filter", entityName: "Filter_Cartridge", title: "Filter cartridge", detail: "A cartridge containing the pleated media, seals and pull loop.", explodedOffset: [0, 0, -0.24]),
            .init(id: "top", entityName: "Top_Assembly", title: "Top assembly", detail: "The upper grille and controls, separated here to show the structure.", explodedOffset: [0, 0.10, 0]),
            .init(id: "base", entityName: "Base_Assembly", title: "Base assembly", detail: "The lower support, separated here to show its position below the housing.", explodedOffset: [0, -0.045, 0])
        ], steps: [
            .init(id: "cover_out", title: "Reveal the rear opening", instruction: "Watch the rear cover move outward. Rotate the model to see the opening from the side.", focusID: "cover", offsets: ["cover": [0, 0, -0.43]]),
            .init(id: "filter_out", title: "See the cartridge", instruction: "Watch the cartridge move away from the housing. Select a part to see its name and position.", focusID: "filter", offsets: ["cover": [0, 0, -0.43], "filter": [0, 0, -0.24]]),
            .init(id: "reassemble", title: "Bring the model together", instruction: "Replay the return movement to see how the cartridge and cover line up with the housing.", focusID: nil, offsets: [:])
        ], initialYaw: 2.35)
}

enum AssemblyTutorialError: LocalizedError {
    case invalidDefinition, missingOrAmbiguousPart(String), nestedParts, emptyPart(String), emptyModel
    var errorDescription: String? {
        switch self {
        case .invalidDefinition: "This walkthrough's part definitions need review."
        case .missingOrAmbiguousPart(let name): "A required model part is missing or ambiguous: \(name)."
        case .nestedParts: "Overlapping part groups need review before animation."
        case .emptyPart(let name): "A required model part has no visible geometry: \(name)."
        case .emptyModel: "The model has no usable visible bounds."
        }
    }
}

private extension SIMD3 where Scalar == Float {
    var isFiniteVector: Bool { x.isFinite && y.isFinite && z.isFinite }
}
